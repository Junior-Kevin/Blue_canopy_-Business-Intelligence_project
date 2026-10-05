#!/usr/bin/env python3
"""
generate_inventory_snapshots.py – Optimised for ~12.8 million rows.

Generates weekly inventory snapshots for Blue Canopy Kenya.
Output: bronze/inventory/inventory_snapshots_raw.csv

Grain: one row per store / product / snapshot date.
Uses vectorised operations and incremental writes to handle large volumes.
"""

import os
import random
from datetime import date, timedelta

import numpy as np
import pandas as pd
from faker import Faker

fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

# Configuration – adjust these to change output volume
TARGET_ROWS = 12_800_000          # desired approximate row count
START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)      # ~10 years
DEFAULT_STORES = 150               # used if stores_raw.csv missing
DEFAULT_PRODUCTS = 500              # <-- reduced from 5000 to hit target

def load_stores():
    """Load store IDs from file, or generate default count."""
    stores_file = os.path.join('bronze', 'stores', 'stores_raw.csv')
    if os.path.exists(stores_file):
        df = pd.read_csv(stores_file)
        store_ids = df['store_id'].unique().tolist()
        print(f"Loaded {len(store_ids)} stores from file")
        return store_ids
    else:
        print(f"Stores file not found. Generating {DEFAULT_STORES} placeholder stores.")
        return [f"STOR-{i+1:04d}" for i in range(DEFAULT_STORES)]

def load_products():
    """Load product IDs from file, or generate default count."""
    prod_file = os.path.join('bronze', 'products', 'products_raw.csv')
    if os.path.exists(prod_file):
        df = pd.read_csv(prod_file)
        product_ids = df['product_id'].unique().tolist()
        print(f"Loaded {len(product_ids)} products from file")
        return product_ids
    else:
        print(f"Products file not found. Generating {DEFAULT_PRODUCTS} placeholder products.")
        return [f"PROD-{i+1:04d}" for i in range(DEFAULT_PRODUCTS)]

def inject_issues(df, frac_missing=0.02, frac_duplicate=0.01,
                  missing_cols=None, date_cols=None, int_cols=None):
    """
    Add data quality issues to a DataFrame chunk.
    (Same logic as original, but works on any DataFrame.)
    """
    df = df.copy()   # avoid modifying original chunk
    if missing_cols:
        for col in missing_cols:
            if col in df.columns:
                mask = np.random.random(len(df)) < frac_missing
                df.loc[mask, col] = np.nan

    if frac_duplicate > 0 and len(df) > 0:
        dup = df.sample(frac=min(frac_duplicate, 0.1), random_state=42).copy()
        # Modify the first column (snapshot_date) to simulate a duplicate key
        key_col = df.columns[0]
        if key_col in dup.columns:
            dup[key_col] = dup[key_col].astype(str) + '-DUP'
        df = pd.concat([df, dup], ignore_index=True)

    if date_cols and len(df) > 0:
        bad_mask = np.random.random(len(df)) < 0.02
        for col in date_cols:
            if col in df.columns:
                # Replace with an invalid date string
                df.loc[bad_mask, col] = '2023-13-45'

    if int_cols and len(df) > 0:
        neg_mask = np.random.random(len(df)) < 0.005
        for col in int_cols:
            if col in df.columns and pd.api.types.is_numeric_dtype(df[col]):
                df.loc[neg_mask, col] = df.loc[neg_mask, col] * -1

    return df

def generate_weekly_chunk(snapshot_date, store_ids, product_ids):
    """
    Create a DataFrame for one snapshot date containing all store–product combinations.
    Uses vectorised NumPy operations.
    """
    n_stores = len(store_ids)
    n_products = len(product_ids)
    total = n_stores * n_products

    # Create arrays for each column
    dates = np.full(total, snapshot_date.isoformat(), dtype='datetime64[D]')
    stores = np.repeat(store_ids, n_products)
    products = np.tile(product_ids, n_stores)

    # Inventory metrics – all random, but you can replace with realistic logic
    on_hand = np.random.randint(0, 1001, size=total, dtype=np.int32)
    reorder_point = np.random.randint(10, 201, size=total, dtype=np.int32)
    safety_stock = np.random.randint(5, 101, size=total, dtype=np.int32)

    df = pd.DataFrame({
        'snapshot_date': dates,
        'store_id': stores,
        'product_id': products,
        'on_hand_quantity': on_hand,
        'reorder_point': reorder_point,
        'safety_stock': safety_stock
    })
    return df

def generate_inventory_snapshots():
    print("Generating Inventory Snapshots (optimised, weekly)...")
    out_dir = os.path.join('bronze', 'inventory')
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, 'inventory_snapshots_raw.csv')

    store_ids = load_stores()
    product_ids = load_products()

    n_stores = len(store_ids)
    n_products = len(product_ids)
    combos_per_week = n_stores * n_products

    # Calculate number of weeks in the full date range
    start = pd.Timestamp(START_DATE)
    end = pd.Timestamp(END_DATE)
    total_weeks = (end - start).days // 7 + 1   # inclusive of both ends
    estimated_rows = total_weeks * combos_per_week

    print(f"Stores: {n_stores}, Products: {n_products}, Combos/week: {combos_per_week:,}")
    print(f"Date range: {START_DATE} to {END_DATE} → {total_weeks} weeks")
    print(f"Estimated rows (full range): {estimated_rows:,}")

    # If estimated rows greatly exceed TARGET_ROWS, we adjust by limiting weeks
    if estimated_rows > TARGET_ROWS * 1.05:   # allow 5% tolerance
        # Reduce number of weeks to hit target
        weeks_to_use = int(TARGET_ROWS // combos_per_week)
        if weeks_to_use < 1:
            weeks_to_use = 1
        end_date_limited = start + pd.Timedelta(weeks=weeks_to_use - 1)
        print(f"Target rows {TARGET_ROWS:,} is smaller; limiting to first {weeks_to_use} weeks "
              f"(up to {end_date_limited.date()})")
        weeks_iter = range(weeks_to_use)
        actual_weeks = weeks_to_use
    else:
        # Use full range
        weeks_iter = range(total_weeks)
        actual_weeks = total_weeks

    actual_rows = actual_weeks * combos_per_week
    print(f"Will generate ~{actual_rows:,} rows (approx. {actual_weeks} weeks)")

    # Write header
    header = ['snapshot_date', 'store_id', 'product_id', 'on_hand_quantity',
              'reorder_point', 'safety_stock']
    pd.DataFrame(columns=header).to_csv(out_file, index=False)

    # Generate week by week
    current_date = start
    for week_idx in weeks_iter:
        # Create the raw chunk for this week
        chunk = generate_weekly_chunk(current_date.date(), store_ids, product_ids)

        # Inject data quality issues (same as original, but on chunk)
        chunk = inject_issues(
            chunk,
            frac_missing=0.02,
            frac_duplicate=0.01,
            missing_cols=['reorder_point'],
            date_cols=['snapshot_date'],
            int_cols=['on_hand_quantity', 'reorder_point', 'safety_stock']
        )

        # Append chunk to CSV
        chunk.to_csv(out_file, mode='a', header=False, index=False)

        if (week_idx + 1) % 10 == 0:
            print(f"  ... wrote week {week_idx+1} ({current_date.date()})")
        current_date += timedelta(days=7)

    print(f"Done. Output written to {out_file}")
    # Optionally verify row count
    final_count = sum(1 for _ in open(out_file)) - 1  # subtract header
    print(f"Final row count (excluding header): {final_count:,}")

if __name__ == '__main__':
    generate_inventory_snapshots()