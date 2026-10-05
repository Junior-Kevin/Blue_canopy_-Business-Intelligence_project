#!/usr/bin/env python3
"""
generate_ecommerce.py

Generates e-commerce orders for Blue Canopy Kenya.
Output:
  - bronze/sales/ecommerce_orders_raw.csv
  - bronze/sales/ecommerce_order_lines_raw.csv

Depends on: bronze/crm/crm_raw.csv, bronze/products/products_raw.csv

Grain: Similar to POS but with online-specific fields.
Volume: ~10% of POS volume (~6M line items)
"""

import os
import random
import numpy as np
import pandas as pd
from faker import Faker
from datetime import date, datetime, time, timedelta

fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

PAYMENT_METHODS = ['Card', 'Mobile Money', 'Bank Transfer']
ORDER_STATUSES = ['Pending', 'Shipped', 'Delivered', 'Returned', 'Cancelled']

def load_products():
    """Load product IDs and prices."""
    prod_file = os.path.join('bronze', 'products', 'products_raw.csv')
    if os.path.exists(prod_file):
        df = pd.read_csv(prod_file)
        latest = df.sort_values('valid_from').groupby('product_id').tail(1)
        prods = latest[['product_id', 'retail_price_kes']].to_dict('records')
        return prods
    else:
        return [{'product_id': f"PROD-{i+1:04d}", 'retail_price_kes': 500.0} for i in range(5000)]

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
    raise RuntimeError('crm_raw.csv is required for e-commerce generation. Generate CRM first.')
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

def generate_ecommerce():
    print("Generating E-commerce Orders...")
    out_dir = os.path.join('bronze', 'sales')
    os.makedirs(out_dir, exist_ok=True)

    products = load_products()
    product_dict = {p['product_id']: p['retail_price_kes'] for p in products}
    customers = load_customers()
    
    orders_file = os.path.join(out_dir, 'ecommerce_orders_raw.csv')
    lines_file = os.path.join(out_dir, 'ecommerce_order_lines_raw.csv')
    
    # Clear files if they exist
    if os.path.exists(orders_file):
        os.remove(orders_file)
    if os.path.exists(lines_file):
        os.remove(lines_file)
    
    # Write headers
    with open(orders_file, 'w') as f:
        f.write('order_id,order_date,customer_id,delivery_address,delivery_fee,payment_method,status,total_amount\n')
    with open(lines_file, 'w') as f:
        f.write('order_id,line_number,product_id,quantity,unit_price,discount_rate,line_total\n')
    
    # E-commerce is ~10% of POS volume
    # ~780k orders (3-7 per day × 365 days × 10 years)
    num_orders = 780_000
    total_days = (END_DATE - START_DATE).days
    
    order_rows = []
    line_rows = []
    order_id = 1
    batch_size = 10_000
    
    print(f"  Generating {num_orders:,} e-commerce orders...")
    
    for i in range(num_orders):
        if (i + 1) % 100_000 == 0:
            print(f"    Progress: {(i + 1):,} orders generated...")
        
        # Random date within range
        order_date = START_DATE + timedelta(days=random.randint(0, total_days - 1))
        order_time = datetime.combine(
            order_date,
            time(hour=random.randint(0, 23), minute=random.randint(0, 59))
        )
        
        customer_id = random.choice(customers)
        payment_method = random.choice(PAYMENT_METHODS)
        order_status = random.choices(
            ORDER_STATUSES,
            weights=[0.10, 0.30, 0.50, 0.05, 0.05]
        )[0]
        
        # Delivery fee
        delivery_fee = random.choice([0, 200, 300, 500]) if random.random() < 0.95 else 0
        
        # Generate 1-15 line items (fewer than retail)
        num_items = np.random.choice(
            range(1, 16),
            p=[0.40, 0.25, 0.15, 0.10, 0.05, 0.02, 0.01, 0.01, 0, 0, 0, 0, 0, 0, 0.01]
        )
        
        total_amount = delivery_fee
        
        for line_no in range(1, int(num_items) + 1):
            product_id = random.choice(list(product_dict.keys()))
            unit_price = product_dict[product_id]
            qty = random.randint(1, 5)
            discount_rate = 0.05 if random.random() < 0.1 else 0
            line_total = qty * unit_price * (1 - discount_rate)
            total_amount += line_total
            
            line_rows.append([
                f"ECORD-{order_id:08d}",
                line_no,
                product_id,
                qty,
                round(unit_price, 2),
                round(discount_rate, 2),
                round(line_total, 2)
            ])
        
        # Generate delivery address
        delivery_address = fake.address().replace('\n', ', ')
        
        order_rows.append([
            f"ECORD-{order_id:08d}",
            order_time.isoformat(),
            customer_id,
            delivery_address,
            delivery_fee,
            payment_method,
            order_status,
            round(total_amount, 2)
        ])
        
        order_id += 1
        
        # Batch write
        if len(order_rows) >= batch_size:
            df_orders = pd.DataFrame(order_rows, columns=[
                'order_id', 'order_date', 'customer_id', 'delivery_address',
                'delivery_fee', 'payment_method', 'status', 'total_amount'
            ])
            df_orders.to_csv(orders_file, mode='a', header=False, index=False)
            order_rows = []
        
        if len(line_rows) >= batch_size:
            df_lines = pd.DataFrame(line_rows, columns=[
                'order_id', 'line_number', 'product_id', 'quantity',
                'unit_price', 'discount_rate', 'line_total'
            ])
            df_lines.to_csv(lines_file, mode='a', header=False, index=False)
            line_rows = []
    
    # Flush remaining
    if order_rows:
        df_orders = pd.DataFrame(order_rows, columns=[
            'order_id', 'order_date', 'customer_id', 'delivery_address',
            'delivery_fee', 'payment_method', 'status', 'total_amount'
        ])
        df_orders.to_csv(orders_file, mode='a', header=False, index=False)
    
    if line_rows:
        df_lines = pd.DataFrame(line_rows, columns=[
            'order_id', 'line_number', 'product_id', 'quantity',
            'unit_price', 'discount_rate', 'line_total'
        ])
        df_lines.to_csv(lines_file, mode='a', header=False, index=False)
    
    # Count results
    orders_df = pd.read_csv(orders_file)
    lines_df = pd.read_csv(lines_file)
    
    print(f"  -> {len(orders_df):,} orders written to {orders_file}")
    print(f"  -> {len(lines_df):,} line items written to {lines_file}")

if __name__ == '__main__':
    generate_ecommerce()
