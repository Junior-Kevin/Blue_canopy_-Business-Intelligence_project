#!/usr/bin/env python3
"""
generate_goods_receipts.py

Generates goods receipt records for Blue Canopy Kenya.
Output: bronze/procurement/goods_receipts_raw.csv

Depends on: bronze/procurement/purchase_orders_raw.csv

Grain: One row per receipt line (po_number, product_id).
Multiple receipts possible per PO line (partial receipts).
Volume: ~60k rows
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

def load_po_lines():
    """Load PO lines."""
    po_lines_file = os.path.join('bronze', 'procurement', 'purchase_order_lines_raw.csv')
    if os.path.exists(po_lines_file):
        df = pd.read_csv(po_lines_file)
        print(f"Loaded {len(df)} PO lines")
        return df.to_dict('records')
    else:
        print("Warning: purchase_order_lines_raw.csv not found.")
        return []

def load_po_headers():
    """Load PO headers."""
    po_file = os.path.join('bronze', 'procurement', 'purchase_orders_raw.csv')
    if os.path.exists(po_file):
        df = pd.read_csv(po_file)
        print(f"Loaded {len(df)} POs")
        return df.to_dict('records')
    else:
        print("Warning: purchase_orders_raw.csv not found.")
        return []

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

def generate_goods_receipts():
    print("Generating Goods Receipts...")
    out_dir = os.path.join('bronze', 'procurement')
    os.makedirs(out_dir, exist_ok=True)

    po_lines = load_po_lines()
    po_headers = load_po_headers()
    
    if not po_lines or not po_headers:
        print("Cannot generate goods receipts without PO data. Exiting.")
        return
    
    # Create lookup for PO dates and delivery dates
    po_lookup = {po['po_number']: po for po in po_headers}
    
    rows = []
    receipt_id = 1
    
    for line in po_lines:
        po_number = line['po_number']
        product_id = line['product_id']
        qty_ordered = line['quantity_ordered']
        
        if po_number not in po_lookup:
            continue
        
        po = po_lookup[po_number]
        try:
            order_date = pd.to_datetime(po['order_date']).date()
        except:
            continue  # Skip bad dates
        try:
            expected_delivery = pd.to_datetime(po['expected_delivery_date']).date()
        except:
            continue  # Skip bad dates
        
        # Simulate partial receipts: 70% receive full, 30% partial (1-3 receipts)
        if random.random() < 0.7:
            # Full receipt
            receipt_date = expected_delivery + timedelta(days=random.randint(-5, 10))
            if receipt_date < order_date:
                receipt_date = order_date
            
            rows.append([
                f"GR-{receipt_id:08d}",
                po_number,
                receipt_date.isoformat(),
                product_id,
                qty_ordered,
                random.choice([None, 'OK', 'Damaged in transit', 'Qty mismatch', 'Wrong items'])
            ])
            receipt_id += 1
        else:
            # Partial receipts
            num_receipts = random.randint(2, 4)
            received_so_far = 0
            for r in range(num_receipts):
                fraction = random.uniform(0.2, 0.6)
                qty_this = int(qty_ordered * fraction)
                received_so_far += qty_this
                
                receipt_date = expected_delivery + timedelta(days=random.randint(-5, 20))
                if receipt_date < order_date:
                    receipt_date = order_date
                
                rows.append([
                    f"GR-{receipt_id:08d}",
                    po_number,
                    receipt_date.isoformat(),
                    product_id,
                    qty_this,
                    random.choice([None, 'OK', 'Partial shipment'])
                ])
                receipt_id += 1
                
                if received_so_far >= qty_ordered:
                    break
    
    columns = [
        'receipt_id', 'po_number', 'receipt_date', 'product_id',
        'quantity_received', 'receiving_notes'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['receiving_notes'],
        date_cols=['receipt_date'],
        int_cols=['quantity_received']
    )
    
    out_file = os.path.join(out_dir, 'goods_receipts_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_goods_receipts()
