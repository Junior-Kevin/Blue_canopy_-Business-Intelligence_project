#!/usr/bin/env python3
"""
generate_gift_cards.py

Generates gift card records.
Output:
  - bronze/sales/gift_cards_raw.csv
  - bronze/sales/gift_card_transactions_raw.csv

Grain:
  - Master: Card record
  - Transactions: Issuance, redemption, expiry
Volume: ~37k cards (1/4 of active customers), ~130k transactions
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

def generate_gift_cards():
    print("Generating Gift Cards...")
    out_dir = os.path.join('bronze', 'sales')
    os.makedirs(out_dir, exist_ok=True)

    # Try to load CRM customers so we can assign cards to customers and link transactions
    crm_file = os.path.join('bronze', 'crm', 'crm_raw.csv')
    customers = []
    if os.path.exists(crm_file):
        try:
            crm_df = pd.read_csv(crm_file)
            crm_df['valid_to'] = crm_df['valid_to'].fillna('2099-12-31')
            current = crm_df[crm_df['valid_to'] >= '2099-12-31']
            customers = current['customer_id'].unique().tolist()
        except Exception:
            customers = []

    card_rows = []
    txn_rows = []

    # Generate cards for ~1/4 of active customers
    num_cards = len(customers) // 4 if customers else 37_000
    txn_id = 1

    # Fixed parameters
    min_redeem = 100
    max_redeem = 5000
    min_topup = 100
    max_topup = 5000

    # Ensure we only assign cards to a random sample of customers (1/4 of total)
    if customers:
        customers_with_cards = random.sample(customers, num_cards)
    else:
        customers_with_cards = []

    for i in range(num_cards):
        card_number = f"GC{random.randint(1000000000000, 9999999999999)}"
        # Assign a customer from the pre-selected sample (1/4 of customers)
        customer_id = customers_with_cards[i] if i < len(customers_with_cards) else ''
        issue_date = START_DATE + timedelta(days=random.randint(0, (END_DATE - START_DATE).days))
        expiry_date = issue_date + timedelta(days=365)
        initial_balance = random.choice([1000, 2500, 5000, 10000, 25000])

        # Record the initial issuance as the first transaction
        txn_rows.append([
            f"GCT-{txn_id:08d}",
            card_number,
            issue_date.isoformat(),
            initial_balance,
            'issue',
            ''  # linked_transaction_id (none for issuance)
        ])
        txn_id += 1

        # Current balance after initial issue
        current_balance = initial_balance

        # Number of additional transactions (2-5)
        num_extra_txns = random.randint(2, 5)
        for _ in range(num_extra_txns):
            # Decide transaction type: 70% redemption, 30% top-up
            if random.random() < 0.7:          # redemption
                # Only redeem if balance is at least min_redeem
                if current_balance >= min_redeem:
                    max_allowed = min(max_redeem, current_balance)
                    amount = random.randint(min_redeem, max_allowed)
                    current_balance -= amount
                    txn_type = 'redeem'
                else:
                    # Not enough balance for redemption -> force a top-up
                    amount = random.randint(min_topup, max_topup)
                    current_balance += amount
                    txn_type = 'issue'
            else:                               # top-up (issue)
                amount = random.randint(min_topup, max_topup)
                current_balance += amount
                txn_type = 'issue'

            # Choose a transaction date between issue and expiry
            days_offset = random.randint(0, (expiry_date - issue_date).days)
            txn_date = issue_date + timedelta(days=days_offset)

            # Placeholder for linked transaction id (POS or EC order) to be filled if possible
            txn_rows.append([
                f"GCT-{txn_id:08d}",
                card_number,
                txn_date.isoformat(),
                amount,
                txn_type,
                ''
            ])
            txn_id += 1

        # Final current balance for the card master record
        card_rows.append([
            card_number,
            customer_id,
            issue_date.isoformat(),
            expiry_date.isoformat(),
            initial_balance,
            current_balance,
            ''  # transaction_ids (comma-separated)
        ])
    
    # Create DataFrames with new columns (including customer and linked transaction id)
    card_df = pd.DataFrame(card_rows, columns=[
        'card_number', 'customer_id', 'issue_date', 'expiry_date', 'initial_balance', 'current_balance', 'transaction_ids'
    ])

    txn_df = pd.DataFrame(txn_rows, columns=[
        'transaction_id', 'card_number', 'date', 'amount', 'type', 'linked_transaction_id'
    ])

    # Attempt to link redemption transactions to existing POS or e-commerce transactions
    pos_file = os.path.join('bronze', 'sales', 'pos_transactions_raw.csv')
    ec_file = os.path.join('bronze', 'sales', 'ecommerce_orders_raw.csv')
    pos_df = pd.DataFrame()
    ec_df = pd.DataFrame()
    try:
        if os.path.exists(pos_file):
            pos_df = pd.read_csv(pos_file, dtype=str)
    except Exception:
        pos_df = pd.DataFrame()
    try:
        if os.path.exists(ec_file):
            ec_df = pd.read_csv(ec_file, dtype=str)
    except Exception:
        ec_df = pd.DataFrame()

    # Build mapping of customer_id -> list of transaction ids (pos + ecommerce)
    cust_txn_map = {}
    if not pos_df.empty and 'customer_id' in pos_df.columns:
        for _, r in pos_df.iterrows():
            cid = r.get('customer_id', '')
            tid = r.get('transaction_id', '')
            if cid and pd.notna(cid):
                cust_txn_map.setdefault(cid, []).append(tid)
    if not ec_df.empty and 'customer_id' in ec_df.columns:
        for _, r in ec_df.iterrows():
            cid = r.get('customer_id', '')
            tid = r.get('order_id', '')
            if cid and pd.notna(cid):
                cust_txn_map.setdefault(cid, []).append(tid)

    # For each redemption txn, try to pick a transaction_id for the same customer and attach
    for idx, row in txn_df.iterrows():
        if row['type'] == 'redeem':
            card = row['card_number']
            cust_row = card_df[card_df['card_number'] == card]
            cust_id = cust_row['customer_id'].iloc[0] if not cust_row.empty else ''
            linked = ''
            if cust_id and cust_id in cust_txn_map and len(cust_txn_map[cust_id]) > 0:
                linked = random.choice(cust_txn_map[cust_id])
            txn_df.at[idx, 'linked_transaction_id'] = linked
            if linked:
                prev = card_df.loc[card_df['card_number'] == card, 'transaction_ids'].iloc[0]
                if not prev:
                    card_df.loc[card_df['card_number'] == card, 'transaction_ids'] = linked
                else:
                    card_df.loc[card_df['card_number'] == card, 'transaction_ids'] = prev + ',' + linked

    card_file = os.path.join(out_dir, 'gift_cards_raw.csv')
    txn_file = os.path.join(out_dir, 'gift_card_transactions_raw.csv')

    card_df.to_csv(card_file, index=False)
    txn_df.to_csv(txn_file, index=False)

    print(f"  -> {len(card_df):,} gift cards")
    print(f"  -> {len(txn_df):,} gift card transactions")

if __name__ == '__main__':
    generate_gift_cards()