#!/usr/bin/env python3
"""
generate_promotions.py

Generates promotion records for Blue Canopy Kenya.
Output:
  - bronze/marketing/promotions_raw.csv
  - bronze/marketing/promotion_products_raw.csv

Grain:
  - Promotions: Campaign-level promotions
  - Products: Products included in each promotion
Volume: ~200 promotions, ~2000 product mappings
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

DISCOUNT_TYPES = ['percentage', 'fixed']

def load_products():
    """Load product IDs."""
    prod_file = os.path.join('bronze', 'products', 'products_raw.csv')
    if os.path.exists(prod_file):
        df = pd.read_csv(prod_file)
        return df['product_id'].unique().tolist()
    else:
        return [f"PROD-{i+1:04d}" for i in range(5000)]

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

def generate_promotions():
    print("Generating Promotions (Non-overlapping)...")
    out_dir = os.path.join('bronze', 'marketing')
    os.makedirs(out_dir, exist_ok=True)

    products = load_products()
    
    promo_rows = []
    product_rows = []
    
    # Create a timeline where promotions don't overlap
    # Divide the period into roughly equal segments
    num_promotions = 80  # Reduced from 200 to avoid overlaps
    total_days = (END_DATE - START_DATE).days
    segment_length = total_days // num_promotions
    
    current_date = START_DATE
    
    for i in range(num_promotions):
        promo_id = f"PROMO-{i+1:04d}"
        promo_name = f"Promotion_{fake.word().title()}_{random.randint(100, 999)}"
        
        # Each promotion gets a defined segment with some randomness
        # Start: somewhere in the current segment
        if i < num_promotions - 1:
            max_offset = min(segment_length - 10, 30)  # Don't use full segment to allow spacing
            start_offset = random.randint(0, max_offset) if max_offset > 0 else 0
            start_date = current_date + timedelta(days=start_offset)
            
            # Duration: 3-30 days (shorter promotions to ensure non-overlap)
            duration = random.randint(3, 30)
            end_date = start_date + timedelta(days=duration)
            
            # Move to next segment
            current_date = end_date + timedelta(days=random.randint(1, 5))  # Gap between promotions
        else:
            # Last promotion
            start_date = current_date
            duration = random.randint(3, 20)
            end_date = start_date + timedelta(days=duration)
        
        # Ensure dates stay within range
        if end_date > END_DATE:
            end_date = END_DATE
        if start_date > END_DATE:
            break
        
        discount_type = random.choice(DISCOUNT_TYPES)
        if discount_type == 'percentage':
            discount_value = random.choice([5, 10, 15, 20, 25])
        else:
            discount_value = random.choice([100, 200, 500, 1000])  # Fixed KES amounts
        
        promo_rows.append([
            promo_id,
            promo_name,
            start_date.isoformat(),
            end_date.isoformat(),
            discount_type,
            discount_value
        ])
        
        # Add 1-15 products to this promotion
        num_products = random.randint(1, 15)
        for _ in range(num_products):
            product_id = random.choice(products)
            product_rows.append([
                promo_id,
                product_id
            ])
    
    promo_columns = [
        'promotion_id', 'promotion_name', 'start_date', 'end_date',
        'discount_type', 'discount_value'
    ]
    
    product_columns = [
        'promotion_id', 'product_id'
    ]
    
    promo_df = pd.DataFrame(promo_rows, columns=promo_columns)
    product_df = pd.DataFrame(product_rows, columns=product_columns)
    
    # Inject issues (excluding critical date columns)
    promo_df = inject_issues(
        promo_df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=[]
    )
    
    product_df = inject_issues(
        product_df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['product_id']
    )
    
    promo_file = os.path.join(out_dir, 'promotions_raw.csv')
    product_file = os.path.join(out_dir, 'promotion_products_raw.csv')
    
    promo_df.to_csv(promo_file, index=False)
    product_df.to_csv(product_file, index=False)
    
    print(f"  -> {len(promo_df):,} promotions written to {promo_file}")
    print(f"  -> {len(product_df):,} promotion products written to {product_file}")

if __name__ == '__main__':
    generate_promotions()
