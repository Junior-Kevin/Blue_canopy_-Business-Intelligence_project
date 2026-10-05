#!/usr/bin/env python3
"""
generate_financials.py

Generates financial records (store P&L and GL transactions).
Output:
  - bronze/finance/store_daily_financials_raw.csv
  - bronze/finance/gl_transactions_raw.csv

Depends on: bronze/stores/stores_raw.csv

Grain:
  - Store P&L: One row per store per day
  - GL: One row per transaction
Volume: 150 stores × 3650 days ≈ 547k rows; GL: ~5M rows
"""

import os
import random
import numpy as np
import pandas as pd
from datetime import date, timedelta

np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

GL_ACCOUNTS = [
    '1000-Cash', '1010-Accounts Receivable', '1020-Inventory', '2000-Accounts Payable',
    '3000-Owner Equity', '4000-Sales Revenue', '4100-Sales Returns', '5000-COGS',
    '6000-Rent Expense', '6100-Salary Expense', '6200-Utilities', '6300-Marketing'
]

def load_stores():
    """Load store IDs."""
    stores_file = os.path.join('bronze', 'stores', 'stores_raw.csv')
    if os.path.exists(stores_file):
        df = pd.read_csv(stores_file)
        return df['store_id'].unique().tolist()
    else:
        return [f"STOR-{i+1:04d}" for i in range(150)]

def generate_financials():
    print("Generating Financial Records...")
    out_dir = os.path.join('bronze', 'finance')
    os.makedirs(out_dir, exist_ok=True)

    stores = load_stores()
    
    # Store daily financials
    fin_rows = []
    current_date = START_DATE
    
    while current_date <= END_DATE:
        for store_id in stores:
            sales = round(np.random.uniform(100_000, 500_000), 2)
            cogs = round(sales * np.random.uniform(0.5, 0.7), 2)
            gross_margin = round(sales - cogs, 2)
            opex = round(np.random.uniform(30_000, 150_000), 2)
            net_profit = round(gross_margin - opex, 2)
            
            fin_rows.append([
                store_id,
                current_date.isoformat(),
                sales,
                cogs,
                gross_margin,
                opex,
                net_profit
            ])
        
        current_date += timedelta(days=1)
    
    # GL transactions
    gl_rows = []
    txn_id = 1
    current_date = START_DATE
    
    while current_date <= END_DATE:
        # ~10-20 GL transactions per day
        daily_txns = random.randint(10, 20)
        for _ in range(daily_txns):
            account = random.choice(GL_ACCOUNTS)
            store_id = random.choice(stores)
            amount = round(np.random.uniform(1000, 500_000), 2)
            txn_type = random.choice(['debit', 'credit'])
            
            gl_rows.append([
                f"GLT-{txn_id:08d}",
                account,
                current_date.isoformat(),
                amount,
                txn_type,
                store_id
            ])
            
            txn_id += 1
        
        current_date += timedelta(days=1)
    
    fin_df = pd.DataFrame(fin_rows, columns=[
        'store_id', 'date', 'sales_kes', 'cost_of_goods_sold',
        'gross_margin', 'operating_expenses', 'net_profit'
    ])
    
    gl_df = pd.DataFrame(gl_rows, columns=[
        'transaction_id', 'account_code', 'date', 'amount', 'type', 'store_id'
    ])
    
    fin_file = os.path.join(out_dir, 'store_daily_financials_raw.csv')
    gl_file = os.path.join(out_dir, 'gl_transactions_raw.csv')
    
    fin_df.to_csv(fin_file, index=False)
    gl_df.to_csv(gl_file, index=False)
    
    print(f"  -> {len(fin_df):,} store daily financials")
    print(f"  -> {len(gl_df):,} GL transactions")

if __name__ == '__main__':
    generate_financials()
