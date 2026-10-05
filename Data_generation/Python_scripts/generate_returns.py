#!/usr/bin/env python3
"""
generate_returns.py

Generates product return records for Blue Canopy Kenya.
Output: bronze/sales/returns_raw.csv

Depends on: bronze/sales/pos_line_items_raw.csv, bronze/sales/ecommerce_order_lines_raw.csv

Grain: One row per returned item.
Volume: ~3% of line items are returned (~2M rows)
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

RETURN_REASONS = ['Damaged', 'Wrong Item', 'Not as Described', 'Defective', 'Changed Mind', 'Size/Fit Issue']

def load_pos_line_items():
    """Load POS line items."""
    lines_file = os.path.join('bronze', 'sales', 'pos_line_items_raw.csv')
    if os.path.exists(lines_file):
        df = pd.read_csv(lines_file)
        print(f"Loaded {len(df)} POS line items")
        return df.to_dict('records')
    else:
        print("Warning: pos_line_items_raw.csv not found.")
        return []

def load_ecommerce_line_items():
    """Load e-commerce line items."""
    lines_file = os.path.join('bronze', 'sales', 'ecommerce_order_lines_raw.csv')
    if os.path.exists(lines_file):
        df = pd.read_csv(lines_file)
        print(f"Loaded {len(df)} e-commerce line items")
        return df.to_dict('records')
    else:
        print("Warning: ecommerce_order_lines_raw.csv not found.")
        return []

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
    return df

def generate_returns():
    print("Generating Returns...")
    out_dir = os.path.join('bronze', 'sales')
    os.makedirs(out_dir, exist_ok=True)

    all_lines = []
    all_lines.extend(load_pos_line_items())
    all_lines.extend(load_ecommerce_line_items())
    
    if not all_lines:
        print("No line items found. Generating sample returns...")
        return
    
    rows = []
    return_id = 1
    
    # ~3% of all line items are returned
    for line in all_lines:
        if random.random() < 0.03:
            trans_id = line.get('transaction_id') or line.get('order_id')
            qty_returned = random.randint(1, line['quantity'])
            refund_amount = qty_returned * line['unit_price'] * (1 - line.get('discount_rate', 0))
            
            # Return date: 0-30 days after transaction
            # We'll use a random date (approximation)
            return_date = START_DATE + timedelta(days=random.randint(0, (END_DATE - START_DATE).days))
            
            rows.append([
                f"RET-{return_id:08d}",
                trans_id,
                return_date.isoformat(),
                line['product_id'],
                qty_returned,
                round(refund_amount, 2),
                random.choice(RETURN_REASONS)
            ])
            
            return_id += 1
    
    columns = [
        'return_id', 'original_transaction_id', 'return_date', 'product_id',
        'quantity_returned', 'refund_amount', 'return_reason'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['return_reason'],
        date_cols=['return_date'],
        int_cols=['quantity_returned', 'refund_amount']
    )
    
    out_file = os.path.join(out_dir, 'returns_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} returns written to {out_file}")

if __name__ == '__main__':
    generate_returns()
