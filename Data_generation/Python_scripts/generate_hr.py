#!/usr/bin/env python3
"""
generate_hr.py

Generates HR (employee) master data (Type 2 SCD) for Blue Canopy Kenya.
Output: bronze/hr/hr_raw.csv

Depends on: bronze/stores/stores_raw.csv

Grain: One row per employee version. Changes include promotions, salary updates, department changes.
Type 2 SCD: ~40% of employees undergo changes (promotions, relocations, salary increases).
Volume: ~3k employees, ~5k rows.
"""

import os
import random
import numpy as np
import pandas as pd
from faker import Faker
from datetime import date, timedelta

fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

DEPARTMENTS = ['Store Operations', 'Sales', 'Warehouse', 'Finance', 'HR', 'IT', 'Marketing', 'Supply Chain']
JOB_TITLES = {
    'Store Operations': ['Store Manager', 'Assistant Manager', 'Supervisor', 'Cashier', 'Security'],
    'Sales': ['Sales Associate', 'Promoter', 'Customer Care', 'Senior Sales'],
    'Warehouse': ['Warehouse Manager', 'Loader', 'Stock Keeper', 'Forklift Operator'],
    'Finance': ['Accountant', 'Finance Manager', 'Cashier', 'Auditor'],
    'HR': ['HR Manager', 'Recruiter', 'HR Officer'],
    'IT': ['IT Manager', 'Systems Admin', 'Developer', 'Support'],
    'Marketing': ['Marketing Manager', 'Brand Officer', 'Digital Officer'],
    'Supply Chain': ['Procurement Officer', 'Supply Chain Manager', 'Logistics Officer']
}
SHIFTS = ['Day', 'Night', 'Off']

def load_stores():
    """Load store IDs from stores."""
    stores_file = os.path.join('bronze', 'stores', 'stores_raw.csv')
    if os.path.exists(stores_file):
        df = pd.read_csv(stores_file)
        store_ids = df['store_id'].unique().tolist()
        print(f"Loaded {len(store_ids)} stores from stores_raw.csv")
        return store_ids
    else:
        print("Warning: stores_raw.csv not found. Using placeholder store IDs.")
        return [f"STOR-{i+1:04d}" for i in range(150)]

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

def generate_hr():
    print("Generating HR (Employees)...")
    out_dir = os.path.join('bronze', 'hr')
    os.makedirs(out_dir, exist_ok=True)

    store_ids = load_stores()
    rows = []
    employee_counter = 1
    
    # Phase 1: Create core store structure
    # Each store gets exactly 3 cashiers and 1 supervisor
    print(f"  Creating store structure: 3 cashiers + 1 supervisor per store...")
    supervisor_mapping = {}  # Maps supervisor_id to store_id
    
    for store_id in store_ids:
        # Create 3 cashiers for this store
        for cashier_num in range(3):
            employee_id = f"EMP-{employee_counter:06d}"
            employee_counter += 1
            
            first_name = fake.first_name()
            last_name = fake.last_name()
            gender = random.choice(['Male', 'Female'])
            birth_date = fake.date_of_birth(minimum_age=18, maximum_age=65)
            
            hire_year = random.randint(2010, 2025)
            hire_date = date(hire_year, random.randint(1, 12), random.randint(1, 28))
            if hire_date < START_DATE:
                hire_date = START_DATE
            if hire_date > END_DATE:
                hire_date = END_DATE - timedelta(days=30)
            
            salary_kes = random.randint(35_000, 50_000)  # Cashier range
            shift_pattern = random.choice(['Day', 'Night'])
            
            valid_from = hire_date
            rows.append([
                employee_id,
                valid_from.isoformat(),
                None,
                first_name,
                last_name,
                gender,
                birth_date.isoformat(),
                hire_date.isoformat(),
                'Store Operations',
                'Cashier',
                salary_kes,
                store_id,
                shift_pattern
            ])
            
            # Simulate some salary increases for existing cashiers
            if random.random() < 0.4:
                num_changes = random.randint(1, 2)
                current_valid_from = valid_from
                current_salary = salary_kes
                
                for _ in range(num_changes):
                    earliest_change = current_valid_from + timedelta(days=180)
                    latest_change = END_DATE - timedelta(days=30)
                    
                    if earliest_change >= latest_change:
                        break
                    
                    change_date = fake.date_between(
                        start_date=earliest_change,
                        end_date=latest_change
                    )
                    
                    rows[-1][2] = change_date.isoformat()
                    
                    salary_increase = np.random.uniform(1.05, 1.15)
                    current_salary = int(current_salary * salary_increase)
                    
                    rows.append([
                        employee_id,
                        change_date.isoformat(),
                        None,
                        first_name,
                        last_name,
                        gender,
                        birth_date.isoformat(),
                        hire_date.isoformat(),
                        'Store Operations',
                        'Cashier',
                        current_salary,
                        store_id,
                        shift_pattern
                    ])
                    current_valid_from = change_date
        
        # Create 1 supervisor for this store
        supervisor_id = f"EMP-{employee_counter:06d}"
        supervisor_mapping[supervisor_id] = store_id
        employee_counter += 1
        
        first_name = fake.first_name()
        last_name = fake.last_name()
        gender = random.choice(['Male', 'Female'])
        birth_date = fake.date_of_birth(minimum_age=18, maximum_age=65)
        
        hire_year = random.randint(2010, 2025)
        hire_date = date(hire_year, random.randint(1, 12), random.randint(1, 28))
        if hire_date < START_DATE:
            hire_date = START_DATE
        if hire_date > END_DATE:
            hire_date = END_DATE - timedelta(days=30)
        
        salary_kes = random.randint(60_000, 85_000)  # Supervisor range
        shift_pattern = 'Day'  # Supervisors work day shifts
        
        valid_from = hire_date
        rows.append([
            supervisor_id,
            valid_from.isoformat(),
            None,
            first_name,
            last_name,
            gender,
            birth_date.isoformat(),
            hire_date.isoformat(),
            'Store Operations',
            'Supervisor',
            salary_kes,
            store_id,
            shift_pattern
        ])
        
        # Simulate some promotions/transfers for supervisors
        if random.random() < 0.3:
            num_changes = random.randint(1, 2)
            current_valid_from = valid_from
            current_salary = salary_kes
            
            for _ in range(num_changes):
                earliest_change = current_valid_from + timedelta(days=180)
                latest_change = END_DATE - timedelta(days=30)
                
                if earliest_change >= latest_change:
                    break
                
                change_date = fake.date_between(
                    start_date=earliest_change,
                    end_date=latest_change
                )
                
                rows[-1][2] = change_date.isoformat()
                
                salary_increase = np.random.uniform(1.08, 1.20)
                current_salary = int(current_salary * salary_increase)
                
                rows.append([
                    supervisor_id,
                    change_date.isoformat(),
                    None,
                    first_name,
                    last_name,
                    gender,
                    birth_date.isoformat(),
                    hire_date.isoformat(),
                    'Store Operations',
                    'Supervisor',
                    current_salary,
                    store_id,
                    shift_pattern
                ])
                current_valid_from = change_date
    
    # Phase 2: Create 1 manager at HQ per supervisor
    print(f"  Creating {len(supervisor_mapping)} managers at HQ...")
    
    for supervisor_id, store_id in supervisor_mapping.items():
        manager_id = f"EMP-{employee_counter:06d}"
        employee_counter += 1
        
        first_name = fake.first_name()
        last_name = fake.last_name()
        gender = random.choice(['Male', 'Female'])
        birth_date = fake.date_of_birth(minimum_age=18, maximum_age=65)
        
        hire_year = random.randint(2010, 2025)
        hire_date = date(hire_year, random.randint(1, 12), random.randint(1, 28))
        if hire_date < START_DATE:
            hire_date = START_DATE
        if hire_date > END_DATE:
            hire_date = END_DATE - timedelta(days=30)
        
        salary_kes = random.randint(90_000, 130_000)  # Manager range
        shift_pattern = 'Day'
        
        valid_from = hire_date
        rows.append([
            manager_id,
            valid_from.isoformat(),
            None,
            first_name,
            last_name,
            gender,
            birth_date.isoformat(),
            hire_date.isoformat(),
            'Store Operations',
            'Store Manager',
            salary_kes,
            None,  # HQ-based, no store assignment
            shift_pattern
        ])
        
        # Simulate some promotions/salary increases for managers
        if random.random() < 0.3:
            num_changes = random.randint(1, 2)
            current_valid_from = valid_from
            current_salary = salary_kes
            
            for _ in range(num_changes):
                earliest_change = current_valid_from + timedelta(days=180)
                latest_change = END_DATE - timedelta(days=30)
                
                if earliest_change >= latest_change:
                    break
                
                change_date = fake.date_between(
                    start_date=earliest_change,
                    end_date=latest_change
                )
                
                rows[-1][2] = change_date.isoformat()
                
                salary_increase = np.random.uniform(1.10, 1.25)
                current_salary = int(current_salary * salary_increase)
                
                rows.append([
                    manager_id,
                    change_date.isoformat(),
                    None,
                    first_name,
                    last_name,
                    gender,
                    birth_date.isoformat(),
                    hire_date.isoformat(),
                    'Store Operations',
                    'Store Manager',
                    current_salary,
                    None,  # HQ-based
                    shift_pattern
                ])
                current_valid_from = change_date
    
    # Phase 3: Create remaining employees (other departments and HQ staff)
    print(f"  Creating additional support staff...")
    current_structure_count = employee_counter - 1
    num_additional_employees = max(500, 3_000 - current_structure_count)
    
    for i in range(num_additional_employees):
        employee_id = f"EMP-{employee_counter:06d}"
        employee_counter += 1
        
        first_name = fake.first_name()
        last_name = fake.last_name()
        gender = random.choice(['Male', 'Female'])
        birth_date = fake.date_of_birth(minimum_age=18, maximum_age=65)
        
        hire_year = random.randint(2010, 2025)
        hire_date = date(hire_year, random.randint(1, 12), random.randint(1, 28))
        if hire_date < START_DATE:
            hire_date = START_DATE
        if hire_date > END_DATE:
            hire_date = END_DATE - timedelta(days=30)
        
        department = random.choice([d for d in DEPARTMENTS if d != 'Store Operations'])
        job_title = random.choice(JOB_TITLES[department])
        salary_kes = random.randint(25_000, 120_000)
        
        # Warehouse, Finance, HR, IT, Marketing, Supply Chain mostly HQ-based
        store_id = None if random.random() < 0.85 else random.choice(store_ids)
        shift_pattern = random.choice(['Day', 'Night', 'Off'])
        
        # Version 1
        valid_from = hire_date
        rows.append([
            employee_id,
            valid_from.isoformat(),
            None,
            first_name,
            last_name,
            gender,
            birth_date.isoformat(),
            hire_date.isoformat(),
            department,
            job_title,
            salary_kes,
            store_id,
            shift_pattern
        ])
        
        # Simulate changes: ~30% have promotions/transfers/salary increases
        if random.random() < 0.3:
            num_changes = random.randint(1, 2)
            current_valid_from = valid_from
            current_dept = department
            current_title = job_title
            current_salary = salary_kes
            current_store = store_id
            
            for _ in range(num_changes):
                earliest_change = current_valid_from + timedelta(days=180)
                latest_change = END_DATE - timedelta(days=30)
                
                if earliest_change >= latest_change:
                    break
                
                change_date = fake.date_between(
                    start_date=earliest_change,
                    end_date=latest_change
                )
                
                rows[-1][2] = change_date.isoformat()
                
                # Change: promotion or salary increase (rarely transfer)
                change_type = random.choice(['salary', 'salary', 'promotion'])
                
                if change_type == 'promotion':
                    current_dept = random.choice([d for d in DEPARTMENTS if d != 'Store Operations'])
                    current_title = random.choice(JOB_TITLES[current_dept])
                
                if change_type == 'salary' or change_type == 'promotion':
                    salary_increase = np.random.uniform(1.05, 1.25)
                    current_salary = int(current_salary * salary_increase)
                
                rows.append([
                    employee_id,
                    change_date.isoformat(),
                    None,
                    first_name,
                    last_name,
                    gender,
                    birth_date.isoformat(),
                    hire_date.isoformat(),
                    current_dept,
                    current_title,
                    current_salary,
                    current_store,
                    shift_pattern
                ])
                current_valid_from = change_date
    
    columns = [
        'employee_id', 'valid_from', 'valid_to', 'first_name', 'last_name',
        'gender', 'birth_date', 'hire_date', 'department', 'job_title',
        'salary', 'store_id', 'shift_pattern'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['store_id', 'job_title'],
        date_cols=['valid_from', 'valid_to', 'birth_date', 'hire_date'],
        int_cols=['salary']
    )
    
    out_file = os.path.join(out_dir, 'hr_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_hr()
