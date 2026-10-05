#!/usr/bin/env python3
"""
generate_loyalty.py

Generates loyalty program transactions for Blue Canopy Kenya.
Output: bronze/loyalty/loyalty_transactions_raw.csv

Depends on: bronze/crm/crm_raw.csv

Grain: One row per loyalty points transaction (earn/redeem).
Volume: ~2M rows across 10-year period.
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

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def resolve_data_file(*relative_parts):
    """Resolve a data file from either the bronze folder or the csv_files folder."""
    candidates = [
        os.path.join(ROOT_DIR, *relative_parts),
        os.path.join(ROOT_DIR, 'csv_files', *relative_parts),
        os.path.join(ROOT_DIR, 'bronze', *relative_parts),
    ]

    for candidate in candidates:
        if os.path.exists(candidate):
            return candidate

    return candidates[0]


def load_sales_order_ids():
    """Load real order IDs from POS and e-commerce sales tables."""
    order_ids = []
    sales_sources = [
        ('sales', 'pos_transactions_raw.csv', 'transaction_id'),
        ('sales', 'ecommerce_orders_raw.csv', 'order_id')
    ]

    for folder, filename, order_col in sales_sources:
        sales_file = resolve_data_file(folder, filename)
        if not os.path.exists(sales_file):
            continue

        df = pd.read_csv(sales_file)
        if order_col not in df.columns:
            continue

        ids = df[order_col].dropna().astype(str).tolist()
        order_ids.extend(ids)

    if not order_ids:
        raise RuntimeError(
            'Sales data is required for loyalty generation. Generate POS or e-commerce sales first.'
        )

    print(f"Loaded {len(order_ids)} sales order IDs from POS/e-commerce")
    return order_ids

def load_customers():
    """Load customer IDs from CRM only."""
    crm_file = resolve_data_file('crm', 'crm_raw.csv')
    if os.path.exists(crm_file):
        df = pd.read_csv(crm_file)
        customer_ids = df['customer_id'].unique().tolist()
        if not customer_ids:
            raise RuntimeError('No active customers found in CRM. Generate CRM first.')
        print(f"Loaded {len(customer_ids)} customers from CRM")
        return customer_ids
    raise RuntimeError('crm_raw.csv is required for loyalty generation. Generate CRM first.')
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

def generate_loyalty():
    print("Generating Loyalty Program Transactions...")
    out_dir = os.path.join('bronze', 'loyalty')
    os.makedirs(out_dir, exist_ok=True)

    customer_ids = load_customers()
    sales_order_ids = load_sales_order_ids()
    
    rows = []
    transaction_id = 1
    
    # Generate ~2M transactions directly (not by iterating days)
    num_transactions = 2_000_000
    
    for _ in range(num_transactions):
        customer_id = random.choice(customer_ids)
        transaction_date = START_DATE + timedelta(days=random.randint(0, (END_DATE - START_DATE).days))
        transaction_type = random.choices(['earn', 'redeem'], weights=[0.75, 0.25])[0]
        order_id = random.choice(sales_order_ids) if transaction_type == 'earn' else None
        
        if transaction_type == 'earn':
            points_earned = random.randint(10, 500)
            points_redeemed = 0
        else:  # redeem
            points_earned = 0
            points_redeemed = random.randint(50, 2000)
        
        # Simple balance: earned - redeemed (not perfect tracking, but good enough for synthetic)
        points_balance = points_earned - points_redeemed if points_earned > points_redeemed else 0
        
        rows.append([
            f"LTXN-{transaction_id:08d}",
            customer_id,
            transaction_date.isoformat(),
            points_earned,
            points_redeemed,
            max(0, points_balance),
            transaction_type,
            order_id
        ])
        
        transaction_id += 1
        
        if len(rows) % 100_000 == 0:
            print(f"  Generated {len(rows):,} transactions...")
    
    columns = [
        'transaction_id', 'customer_id', 'date', 'points_earned',
        'points_redeemed', 'points_balance', 'transaction_type', 'order_id'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['order_id'],
        date_cols=['date'],
        int_cols=['points_earned', 'points_redeemed', 'points_balance']
    )
    
    out_file = os.path.join(out_dir, 'loyalty_transactions_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_loyalty()
