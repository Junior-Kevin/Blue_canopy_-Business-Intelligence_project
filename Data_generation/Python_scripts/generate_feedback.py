#!/usr/bin/env python3
"""
generate_feedback.py

Generates customer feedback records.
Output: bronze/customer_service/feedback_raw.csv

Depends on: bronze/crm/crm_raw.csv

Grain: One row per feedback submission
Volume: ~100k rows
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

CATEGORIES = ['Product Quality', 'Service', 'Cleanliness', 'Pricing', 'Variety', 'Staff Behavior']

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
    raise RuntimeError('crm_raw.csv is required for feedback generation. Generate CRM first.')

def inject_issues(df, frac_missing=0.02, frac_duplicate=0.01,
                  missing_cols=None, date_cols=None):
    if missing_cols:
        for col in missing_cols:
            if col in df.columns:
                mask = np.random.random(len(df)) < frac_missing
                df.loc[mask, col] = np.nan
    if frac_duplicate > 0 and len(df) > 0:
        sample_size = max(1, int(len(df) * min(frac_duplicate, 0.05)))
        if sample_size > 0:
            dup = df.sample(n=sample_size, random_state=42).copy()
            key_col = df.columns[0]
            dup[key_col] = dup[key_col].astype(str) + '-DUP'
            df = pd.concat([df, dup], ignore_index=True)
    return df

def generate_feedback():
    print("Generating Customer Feedback...")
    out_dir = os.path.join('bronze', 'customer_service')
    os.makedirs(out_dir, exist_ok=True)

    customers = load_customers()
    
    rows = []
    feedback_id = 1
    
    num_feedbacks = 100_000
    
    for _ in range(num_feedbacks):
        customer_id = random.choice(customers)
        feedback_date = START_DATE + timedelta(days=random.randint(0, (END_DATE - START_DATE).days))
        rating = random.choices([1, 2, 3, 4, 5], weights=[0.05, 0.10, 0.20, 0.35, 0.30])[0]
        comment = fake.sentence(nb_words=10) if random.random() < 0.7 else None
        category = random.choice(CATEGORIES)
        
        rows.append([
            f"FB-{feedback_id:08d}",
            customer_id,
            feedback_date.isoformat(),
            rating,
            comment,
            category
        ])
        
        feedback_id += 1
    
    columns = [
        'feedback_id', 'customer_id', 'date', 'rating', 'comment', 'category'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['comment'],
        date_cols=['date']
    )
    
    out_file = os.path.join(out_dir, 'feedback_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} feedback records written")

if __name__ == '__main__':
    generate_feedback()
