#!/usr/bin/env python3
"""
generate_pos.py

Generates POS (in-store point of sale) transactions for Blue Canopy Kenya.
Output: 
  - bronze/sales/pos_transactions_raw.csv
  - bronze/sales/pos_line_items_raw.csv

Depends on: bronze/stores/stores_raw.csv, bronze/products/products_raw.csv,
            bronze/crm/crm_raw.csv, bronze/hr/hr_raw.csv

Grain:
  - Transactions: One per transaction
  - Line items: One per product in transaction
Volume: ~20M line items over 10 years (progressive: 9-18 per store/day at 2016 → 2026)
Performance: Batch writes to handle memory efficiently.
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

PAYMENT_METHODS = ['Cash', 'Card', 'Mobile Money', 'Cheque', 'Mixed']

def load_stores():
    """Load store IDs."""
    stores_file = os.path.join('bronze', 'stores', 'stores_raw.csv')
    if os.path.exists(stores_file):
        df = pd.read_csv(stores_file)
        store_ids = df['store_id'].unique().tolist()
        return store_ids
    else:
        return [f"STOR-{i+1:04d}" for i in range(150)]

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
    raise RuntimeError('crm_raw.csv is required for POS generation. Generate CRM first.')
def load_cashiers():
    """Load cashier assignments by store (store_id -> list of cashier_ids)."""
    hr_file = os.path.join('bronze', 'hr', 'hr_raw.csv')
    if not os.path.exists(hr_file):
        raise RuntimeError('hr_raw.csv is required for POS generation. Generate HR first.')

    df = pd.read_csv(hr_file)
    df['valid_to'] = df['valid_to'].fillna('2099-12-31')
    # Get current active employees
    current = df[df['valid_to'] >= '2099-12-31']
    # Filter for cashiers only
    cashiers = current[current['job_title'] == 'Cashier']

    # Create mapping: store_id -> list of cashier_ids
    cashier_mapping = {}
    for store_id in cashiers['store_id'].unique():
        if pd.notna(store_id) and store_id != '':
            store_cashiers = cashiers[cashiers['store_id'] == store_id]['employee_id'].tolist()
            if store_cashiers:
                cashier_mapping[store_id] = store_cashiers

    if not cashier_mapping:
        raise RuntimeError('No active cashiers found in HR for POS generation. Verify HR data.')
    return cashier_mapping

def load_promotions_and_campaigns():
    """Load active promotions and campaigns with their products and discounts by date."""
    promotions_map = {}  # date -> {product_id -> (discount_type, discount_value, promo_id)}
    campaigns_map = {}   # date -> (campaign_id, discount_rate)
    
    # Load promotions
    promo_file = os.path.join('bronze', 'marketing', 'promotions_raw.csv')
    prod_promo_file = os.path.join('bronze', 'marketing', 'promotion_products_raw.csv')
    
    if os.path.exists(promo_file) and os.path.exists(prod_promo_file):
        try:
            promos_df = pd.read_csv(promo_file)
            prod_promos_df = pd.read_csv(prod_promo_file)
            
            # Create a mapping of promo_id -> (start_date, end_date, discount_type, discount_value)
            promo_details = {}
            for _, row in promos_df.iterrows():
                promo_details[row['promotion_id']] = {
                    'start': pd.to_datetime(row['start_date']).date(),
                    'end': pd.to_datetime(row['end_date']).date(),
                    'type': row['discount_type'],
                    'value': row['discount_value']
                }
            
            # For each transaction date, build list of active promotions and their products
            for _, row in prod_promos_df.iterrows():
                promo_id = row['promotion_id']
                product_id = row['product_id']
                
                if promo_id not in promo_details:
                    continue
                
                details = promo_details[promo_id]
                # Add entry for each day in the promotion period
                current_date = details['start']
                while current_date <= details['end']:
                    if current_date not in promotions_map:
                        promotions_map[current_date] = {}
                    promotions_map[current_date][product_id] = (
                        details['type'], 
                        details['value'], 
                        promo_id
                    )
                    current_date += timedelta(days=1)
        except Exception as e:
            print(f"  Warning: Could not load promotions: {e}")
    
    # Load campaigns
    campaigns_file = os.path.join('bronze', 'marketing', 'campaigns_raw.csv')
    
    if os.path.exists(campaigns_file):
        try:
            campaigns_df = pd.read_csv(campaigns_file)
            
            for _, row in campaigns_df.iterrows():
                campaign_id = row['campaign_id']
                start_date = pd.to_datetime(row['start_date']).date()
                end_date = pd.to_datetime(row['end_date']).date()
                discount_rate = row['discount_rate'] if pd.notna(row['discount_rate']) else 0
                
                # Add entry for each day in the campaign period
                current_date = start_date
                while current_date <= end_date:
                    if current_date not in campaigns_map:
                        campaigns_map[current_date] = (campaign_id, discount_rate)
                    current_date += timedelta(days=1)
        except Exception as e:
            print(f"  Warning: Could not load campaigns: {e}")
    
    return promotions_map, campaigns_map

def get_applicable_discount(transaction_date, product_id, promotions_map, campaigns_map):
    """
    Get the applicable discount for a product on a given date.
    Promotions take precedence over campaigns.
    Returns: (discount_rate, discount_type, source_id)
    """
    txn_date = transaction_date.date() if isinstance(transaction_date, datetime) else transaction_date
    
    # Check if product is in an active promotion
    if txn_date in promotions_map and product_id in promotions_map[txn_date]:
        discount_type, discount_value, promo_id = promotions_map[txn_date][product_id]
        if discount_type == 'percentage':
            return float(discount_value) / 100.0, 'percentage', promo_id
        else:
            return float(discount_value), 'fixed', promo_id
    
    # Check if there's an active campaign
    if txn_date in campaigns_map:
        campaign_id, discount_rate = campaigns_map[txn_date]
        if discount_rate > 0:
            return discount_rate, 'campaign', campaign_id
    
    # No discount
    return 0, 'none', None

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

def generate_pos():
    print("Generating POS Transactions with Promotions/Campaigns...")
    out_dir = os.path.join('bronze', 'sales')
    os.makedirs(out_dir, exist_ok=True)

    stores = load_stores()
    products = load_products()
    product_dict = {p['product_id']: p['retail_price_kes'] for p in products}
    customers = load_customers()
    cashier_mapping = load_cashiers()
    
    # Load promotions and campaigns
    print("  Loading promotions and campaigns...")
    promotions_map, campaigns_map = load_promotions_and_campaigns()
    print(f"    Loaded {len(promotions_map)} active promotion dates")
    print(f"    Loaded {len(campaigns_map)} active campaign dates")
    
    trans_file = os.path.join(out_dir, 'pos_transactions_raw.csv')
    lines_file = os.path.join(out_dir, 'pos_line_items_raw.csv')
    
    # Clear files if they exist
    if os.path.exists(trans_file):
        os.remove(trans_file)
    if os.path.exists(lines_file):
        os.remove(lines_file)
    
    # Write headers
    with open(trans_file, 'w') as f:
        f.write('transaction_id,transaction_date,store_id,customer_id,cashier_id,payment_method,total_amount\n')
    with open(lines_file, 'w') as f:
        f.write('transaction_id,line_number,product_id,quantity,unit_price,discount_rate,discount_source,line_total\n')
    
    batch_size = 50_000
    trans_batch = []
    line_batch = []
    
    # Generate transactions with volume growth over time
    transaction_id = 1
    print(f"  Generating POS transactions with growth trend...")
    
    # Normalised probabilities for number of line items (1–20)
    p_raw = [0.30, 0.25, 0.15, 0.10, 0.08, 0.04, 0.03, 0.02, 0.01, 0.01,
             0.005, 0.005, 0, 0, 0, 0, 0, 0, 0, 0.005]
    p = np.array(p_raw) / np.sum(p_raw)
    
    total_days = (END_DATE - START_DATE).days + 1
    days = [START_DATE + timedelta(days=i) for i in range(total_days)]
    num_days = len(days)
    
    for day_index, txn_date in enumerate(days):
        if day_index % 365 == 0:
            print(f"    Progress: {day_index}/{num_days} days processed...")

        # Trend: 3 transactions/store/day in 2016, rising to 6 transactions/store/day in 2026
        year_progress = day_index / max(1, num_days - 1)
        avg_txns_per_store = 3 + 3 * year_progress
        weekday_factor = 1.0 + (0.05 if txn_date.weekday() in [4, 5] else -0.05)
        seasonal_factor = 1.0 + 0.08 * np.sin((txn_date.month - 1) / 12 * 2 * np.pi)
        daily_txns = int(round(len(stores) * avg_txns_per_store * weekday_factor * seasonal_factor))

        if daily_txns < 1:
            daily_txns = 1

        for _ in range(daily_txns):
            if transaction_id % 250_000 == 0:
                print(f"      Transactions generated: {transaction_id:,}")

            txn_time = datetime.combine(
                txn_date,
                time(hour=random.randint(6, 22), minute=random.randint(0, 59))
            )
            
            store_id = random.choice(stores)
            customer_id = random.choice(customers)
            
            # Use only cashiers assigned to this specific store
            if store_id in cashier_mapping and cashier_mapping[store_id]:
                cashier_id = random.choice(cashier_mapping[store_id])
            else:
                raise RuntimeError(f'No active cashier assignment found for store {store_id}. Verify HR store assignments.')
            
            payment_method = random.choice(PAYMENT_METHODS)
            
            # Generate 1-20 line items
            num_items = np.random.choice(range(1, 21), p=p)
            
            total_amount = 0
            
            for line_no in range(1, int(num_items) + 1):
                product_id = random.choice(list(product_dict.keys()))
                unit_price = product_dict[product_id]
                qty = random.randint(1, 10)
                
                # Get applicable discount for this product on this date
                discount_rate, discount_type, discount_source = get_applicable_discount(
                    txn_time, product_id, promotions_map, campaigns_map
                )
                
                # For fixed discounts, convert to discount rate
                if discount_type == 'fixed':
                    fixed_discount = discount_rate  # This is the fixed amount in KES
                    discount_after = max(0, unit_price - fixed_discount)
                    discount_rate = max(0, (unit_price - discount_after) / unit_price)
                else:
                    discount_after = unit_price * (1 - discount_rate)
                
                line_total = qty * unit_price * (1 - discount_rate)
                total_amount += line_total
                
                # Line item record with discount source
                line_batch.append([
                    f"TXN-{transaction_id:10d}",
                    line_no,
                    product_id,
                    qty,
                    round(unit_price, 2),
                    round(discount_rate, 2),
                    discount_source if discount_source else '',
                    round(line_total, 2)
                ])
            
            # Transaction header
            trans_batch.append([
                f"TXN-{transaction_id:10d}",
                txn_time.isoformat(),
                store_id,
                customer_id if customer_id else '',
                cashier_id,
                payment_method,
                round(total_amount, 2)
            ])
            
            transaction_id += 1
            
            # Batch write
            if len(trans_batch) >= batch_size:
                df_trans = pd.DataFrame(trans_batch, columns=[
                    'transaction_id', 'transaction_date', 'store_id', 'customer_id',
                    'cashier_id', 'payment_method', 'total_amount'
                ])
                df_trans.to_csv(trans_file, mode='a', header=False, index=False)
                trans_batch = []
            
            if len(line_batch) >= batch_size:
                df_lines = pd.DataFrame(line_batch, columns=[
                    'transaction_id', 'line_number', 'product_id', 'quantity',
                    'unit_price', 'discount_rate', 'discount_source', 'line_total'
                ])
                df_lines.to_csv(lines_file, mode='a', header=False, index=False)
                line_batch = []
    
    # Flush remaining batches
    if trans_batch:
        df_trans = pd.DataFrame(trans_batch, columns=[
            'transaction_id', 'transaction_date', 'store_id', 'customer_id',
            'cashier_id', 'payment_method', 'total_amount'
        ])
        df_trans.to_csv(trans_file, mode='a', header=False, index=False)
    
    if line_batch:
        df_lines = pd.DataFrame(line_batch, columns=[
            'transaction_id', 'line_number', 'product_id', 'quantity',
            'unit_price', 'discount_rate', 'discount_source', 'line_total'
        ])
        df_lines.to_csv(lines_file, mode='a', header=False, index=False)
    
    # Count results
    trans_df = pd.read_csv(trans_file)
    lines_df = pd.read_csv(lines_file)
    
    print(f"  -> {len(trans_df):,} transactions written to {trans_file}")
    print(f"  -> {len(lines_df):,} line items written to {lines_file}")

if __name__ == '__main__':
    generate_pos()