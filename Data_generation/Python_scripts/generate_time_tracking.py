#!/usr/bin/env python3
"""
generate_time_tracking.py

Generates time tracking (clock in/out) events for Blue Canopy Kenya.
Output: bronze/hr/time_tracking_raw.csv

Depends on: bronze/hr/hr_raw.csv, bronze/stores/stores_raw.csv

Grain: One row per clock event (in/out/break), multiple per employee per day.
Volume: ~10M rows (more granular than shifts).
"""

import os
import random
import numpy as np
import pandas as pd
from faker import Faker
from datetime import date, time, datetime, timedelta

fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

def load_employees():
    """Load current employees."""
    hr_file = os.path.join('bronze', 'hr', 'hr_raw.csv')
    if os.path.exists(hr_file):
        df = pd.read_csv(hr_file)
        df['valid_to'] = df['valid_to'].fillna('2099-12-31')
        current = df[df['valid_to'] >= '2099-12-31'].copy()
        employees = current.groupby('employee_id').first().reset_index()
        result = employees[['employee_id', 'store_id', 'shift_pattern']].to_dict('records')
        print(f"Loaded {len(result)} current employees from HR")
        return result
    else:
        print("Warning: hr_raw.csv not found. Using placeholder employees.")
        return [{'employee_id': f"EMP-{i+1:06d}", 'store_id': f"STOR-{random.randint(1,150):04d}", 
                 'shift_pattern': random.choice(['Day', 'Night', 'Off'])} for i in range(3000)]

def inject_issues(df, frac_missing=0.02, frac_duplicate=0.01,
                  missing_cols=None, date_cols=None):
    """Add data quality issues."""
    if missing_cols:
        for col in missing_cols:
            if col in df.columns:
                mask = np.random.random(len(df)) < frac_missing
                df.loc[mask, col] = np.nan
    if frac_duplicate > 0:
        dup = df.sample(frac=frac_duplicate, random_state=42).copy()
        key_col = df.columns[0]
        dup[key_col] = dup[key_col] + '-DUP'
        df = pd.concat([df, dup], ignore_index=True)
    if date_cols:
        bad_mask = np.random.random(len(df)) < 0.02
        for col in date_cols:
            if col in df.columns:
                df.loc[bad_mask, col] = '2023-13-45'
    return df

def generate_time_tracking():
    print("Generating Time Tracking Events...")
    out_dir = os.path.join('bronze', 'hr')
    os.makedirs(out_dir, exist_ok=True)

    employees = load_employees()
    
    rows = []
    event_id = 1
    batch_size = 10_000
    
    current_date = START_DATE
    while current_date <= END_DATE:
        for emp in employees:
            emp_id = emp['employee_id']
            store_id = emp['store_id']
            shift_pattern = emp['shift_pattern']
            
            if shift_pattern == 'Off':
                continue  # No clock events on off days
            
            # Random absence: 2%
            if random.random() < 0.02:
                continue
            
            # Generate clock in
            shift_start_hour = 6 if shift_pattern == 'Day' else 14
            clock_in_offset = random.randint(-30, 30)  # ±30 min
            clock_in_time = datetime.combine(
                current_date, 
                time(hour=shift_start_hour, minute=random.randint(0, 59))
            ) + timedelta(minutes=clock_in_offset)
            
            rows.append([
                f"TTE-{event_id:08d}",
                emp_id,
                store_id,
                clock_in_time.isoformat(),
                'clock_in'
            ])
            event_id += 1
            
            # Break start (after 4-5 hours)
            break_start_offset = random.randint(240, 300)  # 4-5 hours
            break_start = clock_in_time + timedelta(minutes=break_start_offset)
            rows.append([
                f"TTE-{event_id:08d}",
                emp_id,
                store_id,
                break_start.isoformat(),
                'break_start'
            ])
            event_id += 1
            
            # Break end (30-60 min break)
            break_duration = random.randint(30, 60)
            break_end = break_start + timedelta(minutes=break_duration)
            rows.append([
                f"TTE-{event_id:08d}",
                emp_id,
                store_id,
                break_end.isoformat(),
                'break_end'
            ])
            event_id += 1
            
            # Clock out (8 hours later)
            clock_out_offset = random.randint(-30, 30)
            clock_out_time = datetime.combine(
                current_date, 
                time(hour=shift_start_hour + 8, minute=random.randint(0, 59))
            ) + timedelta(minutes=clock_out_offset)
            
            rows.append([
                f"TTE-{event_id:08d}",
                emp_id,
                store_id,
                clock_out_time.isoformat(),
                'clock_out'
            ])
            event_id += 1
            
            if len(rows) >= batch_size:
                pass  # Could batch write here
        
        current_date += timedelta(days=1)
    
    columns = [
        'event_id', 'employee_id', 'store_id', 'timestamp', 'event_type'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=[],
        date_cols=['timestamp']
    )
    
    out_file = os.path.join(out_dir, 'time_tracking_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_time_tracking()
