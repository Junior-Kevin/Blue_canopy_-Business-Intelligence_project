#!/usr/bin/env python3
"""
generate_customer_service.py

Generates customer service interaction records for Blue Canopy Kenya.
Output: bronze/customer_service/service_interactions_raw.csv

Depends on: bronze/crm/crm_raw.csv

Grain: One row per customer interaction.
Volume: ~50k rows
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

CHANNELS = ['Phone', 'Email', 'Chat', 'In-store', 'SMS']
ISSUE_TYPES = ['Product Quality', 'Delivery', 'Returns', 'Pricing', 'Stock Availability', 
               'Complaint', 'General Inquiry', 'Technical Issue']

def load_customers():
    """Load customer IDs from CRM only."""
    crm_file = os.path.join('bronze', 'crm', 'crm_raw.csv')
    if os.path.exists(crm_file):
        df = pd.read_csv(crm_file)
        df['valid_to'] = df['valid_to'].fillna('2099-12-31')
        current = df[df['valid_to'] >= '2099-12-31']
        customer_ids = current['customer_id'].unique().tolist()
        if not customer_ids:
            raise RuntimeError('No active customers found in CRM. Generate CRM first.')
        return customer_ids
    raise RuntimeError('crm_raw.csv is required for customer service generation. Generate CRM first.')

def inject_issues(df, frac_missing=0.02, frac_duplicate=0.01,
                  missing_cols=None, date_cols=None, int_cols=None):
    """Add data quality issues."""
    if len(df) == 0:
        return df
    
    if missing_cols:
        for col in missing_cols:
            if col in df.columns:
                mask = np.random.random(len(df)) < frac_missing
                df.loc[mask, col] = np.nan
    if frac_duplicate > 0:
        sample_size = max(1, int(len(df) * min(frac_duplicate, 0.05)))
        if sample_size > 0:
            dup = df.sample(n=sample_size, random_state=42).copy()
            key_col = df.columns[0]
            dup[key_col] = dup[key_col].astype(str) + '-DUP'
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

def generate_customer_service():
    print("Generating Customer Service Interactions...")
    out_dir = os.path.join('bronze', 'customer_service')
    os.makedirs(out_dir, exist_ok=True)

    customers = load_customers()
    
    rows = []
    interaction_id = 1
    
    # ~50k interactions over 10 years
    num_interactions = 50_000
    
    for _ in range(num_interactions):
        customer_id = random.choice(customers)
        interaction_date = START_DATE + timedelta(days=random.randint(0, (END_DATE - START_DATE).days))
        channel = random.choice(CHANNELS)
        issue_type = random.choice(ISSUE_TYPES)
        
        # Resolution time: 5-480 minutes, log-distributed
        resolution_time = int(np.random.exponential(scale=30) + 5)
        resolution_time = min(resolution_time, 480)
        
        # Satisfaction: mostly satisfied
        satisfaction_score = np.random.choice(
            [1, 2, 3, 4, 5],
            p=[0.05, 0.10, 0.15, 0.30, 0.40]
        )
        
        rows.append([
            f"INT-{interaction_id:08d}",
            customer_id,
            interaction_date.isoformat(),
            channel,
            issue_type,
            resolution_time,
            satisfaction_score
        ])
        
        interaction_id += 1
    
    columns = [
        'interaction_id', 'customer_id', 'interaction_date', 'channel',
        'issue_type', 'resolution_time_minutes', 'satisfaction_score'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['satisfaction_score'],
        date_cols=['interaction_date'],
        int_cols=['resolution_time_minutes', 'satisfaction_score']
    )
    
    out_file = os.path.join(out_dir, 'service_interactions_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} interactions written to {out_file}")

if __name__ == '__main__':
    generate_customer_service()
