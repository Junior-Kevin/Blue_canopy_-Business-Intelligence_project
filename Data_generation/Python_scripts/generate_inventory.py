#!/usr/bin/env python3
"""
generate_inventory.py

Generates inventory movement records for Blue Canopy Kenya.
Output: bronze/inventory/inventory_movements_raw.csv

Depends on: bronze/goods_receipts/goods_receipts_raw.csv, 
            bronze/products/products_raw.csv,
            bronze/stores/stores_raw.csv

Grain: One row per inventory movement.
Movement types: RECEIPT, SALE, ADJUSTMENT, TRANSFER_OUT/IN, RETURN
Volume: ~5M rows
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

def load_stores():
    """Load store IDs."""
    stores_file = os.path.join('bronze', 'stores', 'stores_raw.csv')
    if os.path.exists(stores_file):
        df = pd.read_csv(stores_file)
        store_ids = df['store_id'].unique().tolist()
        print(f"Loaded {len(store_ids)} stores")
        return store_ids
    else:
        print("Warning: stores_raw.csv not found.")
        return [f"STOR-{i+1:04d}" for i in range(150)]

def load_products():
    """Load product info."""
    prod_file = os.path.join('bronze', 'products', 'products_raw.csv')
    if os.path.exists(prod_file):
        df = pd.read_csv(prod_file)
        latest = df.sort_values('valid_from').groupby('product_id').tail(1)
        prods = latest[['product_id', 'unit_cost_kes']].to_dict('records')
        print(f"Loaded {len(prods)} products")
        return prods
    else:
        print("Warning: products_raw.csv not found.")
        return [{'product_id': f"PROD-{i+1:04d}", 'unit_cost_kes': 5000.0} for i in range(5000)]

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

def generate_inventory():
    print("Generating Inventory Movements...")
    out_dir = os.path.join('bronze', 'inventory')
    os.makedirs(out_dir, exist_ok=True)

    stores = load_stores()
    products = load_products()
    product_dict = {p['product_id']: p for p in products}
    
    rows = []
    movement_id = 1
    batch_size = 100_000
    
    # Generate ~5M movements directly (not store-by-store per day)
    num_movements = 5_000_000
    total_days = (END_DATE - START_DATE).days
    
    print(f"  Generating {num_movements:,} inventory movements...")
    
    for i in range(num_movements):
        if (i + 1) % 500_000 == 0:
            print(f"    Progress: {i + 1:,} / {num_movements:,}")
        
        movement_date = START_DATE + timedelta(days=random.randint(0, total_days - 1))
        store_id = random.choice(stores)
        product_id = random.choice(list(product_dict.keys()))
        
        movement_type = random.choices(
            ['RECEIPT', 'SALE', 'ADJUSTMENT', 'TRANSFER_OUT', 'TRANSFER_IN', 'RETURN'],
            weights=[15, 70, 5, 3, 3, 4]
        )[0]
        
        if movement_type in ['RECEIPT', 'ADJUSTMENT']:
            quantity = random.randint(10, 500)
        elif movement_type == 'SALE':
            quantity = -random.randint(1, 50)
        elif movement_type == 'RETURN':
            quantity = -random.randint(1, 20)
        elif movement_type == 'TRANSFER_OUT':
            quantity = -random.randint(10, 100)
        else:  # TRANSFER_IN
            quantity = random.randint(10, 100)
        
        unit_cost = product_dict[product_id].get('unit_cost_kes', 1000)
        
        rows.append([
            f"MOV-{movement_id:08d}",
            movement_date.isoformat(),
            store_id,
            product_id,
            movement_type,
            quantity,
            unit_cost
        ])
        
        movement_id += 1
    
    columns = [
        'movement_id', 'movement_date', 'store_id', 'product_id',
        'movement_type', 'quantity', 'unit_cost_kes'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=[],
        date_cols=['movement_date'],
        int_cols=['quantity', 'unit_cost_kes']
    )
    
    out_file = os.path.join(out_dir, 'inventory_movements_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_inventory()
