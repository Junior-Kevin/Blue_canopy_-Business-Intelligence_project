#!/usr/bin/env python3
"""
generate_purchase_orders.py

Generates purchase orders and lines for Blue Canopy Kenya.
Output: 
  - bronze/procurement/purchase_orders_raw.csv
  - bronze/procurement/purchase_order_lines_raw.csv

Depends on: bronze/suppliers/suppliers_raw.csv, bronze/products/products_raw.csv

Grain: 
  - Header: One per PO
  - Lines: One per line item in PO
Volume: ~20k POs, ~150k lines
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

def load_suppliers():
    """Load supplier IDs."""
    sup_file = os.path.join('bronze', 'suppliers', 'suppliers_raw.csv')
    if os.path.exists(sup_file):
        df = pd.read_csv(sup_file)
        sup_ids = df['supplier_id'].unique().tolist()
        print(f"Loaded {len(sup_ids)} suppliers")
        return sup_ids
    else:
        print("Warning: suppliers_raw.csv not found.")
        return [f"SUP-{i+1:04d}" for i in range(200)]

def load_products():
    """Load product IDs and their costs."""
    prod_file = os.path.join('bronze', 'products', 'products_raw.csv')
    if os.path.exists(prod_file):
        df = pd.read_csv(prod_file)
        # Get latest version of each product
        latest = df.sort_values('valid_from').groupby('product_id').tail(1)
        prods = latest[['product_id', 'unit_cost_kes', 'supplier_id']].to_dict('records')
        print(f"Loaded {len(prods)} products")
        return prods
    else:
        print("Warning: products_raw.csv not found.")
        return [{'product_id': f"PROD-{i+1:04d}", 'unit_cost_kes': 5000.0, 
                 'supplier_id': f"SUP-{random.randint(1,200):04d}"} for i in range(5000)]

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

def generate_purchase_orders():
    print("Generating Purchase Orders...")
    out_dir = os.path.join('bronze', 'procurement')
    os.makedirs(out_dir, exist_ok=True)

    suppliers = load_suppliers()
    products = load_products()
    # Build supplier -> products mapping to ensure purchase orders match product suppliers
    supplier_products = {}
    for p in products:
        if p['supplier_id']:
            supplier_products.setdefault(p['supplier_id'], []).append(p)

    active_suppliers = [s for s in suppliers if s in supplier_products]
    if not active_suppliers:
        active_suppliers = suppliers

    po_rows = []
    line_rows = []
    
    num_pos = 20_000
    po_number = 1
    line_number = 1
    
    current_date = START_DATE
    days_span = (END_DATE - START_DATE).days
    pos_per_day = num_pos // days_span
    
    while current_date <= END_DATE:
        # Generate ~pos_per_day POs on this date
        daily_pos = random.randint(max(1, pos_per_day - 2), pos_per_day + 2)
        
        for _ in range(daily_pos):
            supplier_id = random.choice(active_suppliers)
            order_date = current_date
            
            # Expected delivery: 5-30 days from order
            delivery_offset = random.randint(5, 30)
            expected_delivery = order_date + timedelta(days=delivery_offset)
            
            # PO status: 70% closed, 30% still open
            po_status = random.choice(['Closed', 'Closed', 'Closed', 'Open', 'Cancelled'])
            
            # Generate 1-20 line items from products supplied by this supplier
            supplier_prods = supplier_products.get(supplier_id, [])
            if not supplier_prods:
                supplier_prods = products
            num_lines = random.randint(1, 20)
            total_po_amount = 0
            line_items = []
            
            for ln in range(1, num_lines + 1):
                prod = random.choice(supplier_prods)
                qty = random.randint(10, 500)
                unit_price = prod['unit_cost_kes'] * random.uniform(0.9, 1.1)
                line_total = qty * unit_price
                total_po_amount += line_total
                
                line_items.append({
                    'po_number': f"PO-{po_number:08d}",
                    'line_number': ln,
                    'product_id': prod['product_id'],
                    'quantity_ordered': qty,
                    'unit_price': unit_price,
                    'line_total': line_total
                })
            
            # PO header
            po_rows.append([
                f"PO-{po_number:08d}",
                order_date.isoformat(),
                supplier_id,
                expected_delivery.isoformat(),
                po_status,
                round(total_po_amount, 2)
            ])
            
            # Add lines
            for item in line_items:
                line_rows.append(list(item.values()))
            
            po_number += 1
        
        current_date += timedelta(days=1)
    
    # Create PO header DataFrame
    po_columns = [
        'po_number', 'order_date', 'supplier_id', 'expected_delivery_date',
        'status', 'total_amount'
    ]
    po_df = pd.DataFrame(po_rows, columns=po_columns)
    
    # Create PO lines DataFrame
    line_columns = [
        'po_number', 'line_number', 'product_id', 'quantity_ordered',
        'unit_price', 'line_total'
    ]
    line_df = pd.DataFrame(line_rows, columns=line_columns)
    
    # Inject issues
    po_df = inject_issues(
        po_df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['supplier_id'],
        date_cols=['order_date', 'expected_delivery_date'],
        int_cols=['total_amount']
    )
    
    line_df = inject_issues(
        line_df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=[],
        date_cols=[],
        int_cols=['quantity_ordered', 'unit_price', 'line_total']
    )
    
    # Save
    po_file = os.path.join(out_dir, 'purchase_orders_raw.csv')
    line_file = os.path.join(out_dir, 'purchase_order_lines_raw.csv')
    
    po_df.to_csv(po_file, index=False)
    line_df.to_csv(line_file, index=False)
    
    print(f"  -> {len(po_df):,} PO headers written to {po_file}")
    print(f"  -> {len(line_df):,} PO lines written to {line_file}")

if __name__ == '__main__':
    generate_purchase_orders()
