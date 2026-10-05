#!/usr/bin/env python3
"""
generate_shifts.py

Generates employee shift assignments for Blue Canopy Kenya.
Output: bronze/hr/employee_shifts_raw.csv

Depends on: bronze/hr/hr_raw.csv, bronze/stores/stores_raw.csv

Grain: One row per employee per day with shift details.
Volume: ~5M rows (3k employees × 3650 days ≈ 11M; but sample to ~5M with random absences).
"""

import os
import random
import numpy as np
import pandas as pd
from faker import Faker
from datetime import date, time, timedelta

fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

SHIFT_TIMES = {
    'Day': {'start': '06:00', 'end': '14:00'},
    'Night': {'start': '14:00', 'end': '22:00'},
    'Off': {'start': None, 'end': None}
}

def load_employees():
    """Load current employee versions from HR."""
    hr_file = os.path.join('bronze', 'hr', 'hr_raw.csv')
    if os.path.exists(hr_file):
        df = pd.read_csv(hr_file)
        # Get current employees (valid_to is null or >= today)
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
                  missing_cols=None, date_cols=None, int_cols=None):
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
    if int_cols:
        neg_mask = np.random.random(len(df)) < 0.005
        for col in int_cols:
            if col in df.columns and pd.api.types.is_numeric_dtype(df[col]):
                df.loc[neg_mask, col] = df.loc[neg_mask, col] * -1
    return df

def generate_shifts():
    print("Generating Employee Shifts...")
    out_dir = os.path.join('bronze', 'hr')
    os.makedirs(out_dir, exist_ok=True)

    employees = load_employees()
    
    rows = []
    shift_id = 1
    batch_size = 10_000
    
    current_date = START_DATE
    while current_date <= END_DATE:
        for emp in employees:
            emp_id = emp['employee_id']
            store_id = emp['store_id']
            shift_pattern = emp['shift_pattern']
            
            # Random absence: 2% of shifts
            if random.random() < 0.02:
                shift_type = 'Absent'
                start_time = None
                end_time = None
                hours_worked = 0
                overtime = 0
            else:
                shift_type = shift_pattern
                if shift_type == 'Off':
                    start_time = None
                    end_time = None
                    hours_worked = 0
                    overtime = 0
                else:
                    shift_info = SHIFT_TIMES[shift_type]
                    start_time = shift_info['start']
                    end_time = shift_info['end']
                    hours_worked = 8  # Standard shift
                    overtime = np.random.choice([0, 0, 0, 0, 1, 2]) if random.random() < 0.05 else 0
            
            rows.append([
                f"SHF-{shift_id:08d}",
                emp_id,
                store_id,
                current_date.isoformat(),
                shift_type,
                start_time,
                end_time,
                hours_worked if hours_worked > 0 else np.nan,
                overtime if overtime > 0 else 0
            ])
            
            shift_id += 1
            
            if len(rows) >= batch_size:
                # Could batch write here
                pass
        
        current_date += timedelta(days=1)
    
    columns = [
        'shift_id', 'employee_id', 'store_id', 'shift_date', 'shift_type',
        'start_time', 'end_time', 'hours_worked', 'overtime_hours'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['start_time', 'end_time'],
        date_cols=['shift_date'],
        int_cols=['hours_worked', 'overtime_hours']
    )
    
    out_file = os.path.join(out_dir, 'employee_shifts_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_shifts()
