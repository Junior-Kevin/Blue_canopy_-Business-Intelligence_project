#!/usr/bin/env python3
"""
Generate suppliers raw data (Type 2 SCD) for Blue Canopy Kenya.
Output: bronze/suppliers/suppliers_raw.csv
"""
import os, random, csv
import numpy as np
import pandas as pd
from faker import Faker
from datetime import datetime, date, timedelta
from utils import *   # or copy functions

fake = Faker('en_KE') 
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

def generate_suppliers():
    out_dir = os.path.join('bronze', 'suppliers')
    os.makedirs(out_dir, exist_ok=True)

    # Base supplier names
    base_names = [
        'Nairobi Wholesalers Ltd', 'Mombasa Distributors', 'Kisumu Suppliers', 'Nakuru Merchants',
        'Eldoret Traders', 'Thika Distributors', 'Kenya Imports Ltd', 'Local Producers Co-op',
        'Fresh Farms Kenya', 'Manufacturers Direct', 'Regional Wholesalers', 'County Suppliers',
        'Coast Beverages', 'Highlands Produce', 'Rift Valley Millers', 'Eastern Cereals',
        'Western Dairies', 'North Rift Grains', 'Athi River Logistics', 'Industrial Area Packers'
    ]
    
    # Generate 200 unique supplier names
    supplier_names = base_names.copy()
    counties = ['Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Kiambu', 'Eldoret', 'Meru', 'Machakos']
    while len(supplier_names) < 200:
        county = random.choice(counties)
        suffix = f"Suppliers {random.randint(1, 999)}"
        supplier_names.append(f"{county} {suffix}")
    
    supplier_names = supplier_names[:200]
    
    categories = ['Local', 'International']
    payment_terms = ['Net30', 'Net60', 'Net15']

    rows = []
    for i, name in enumerate(supplier_names):  # we need 200
        supplier_id = f"SUP-{i+1:04d}"
        # version 1
        valid_from = START_DATE
        valid_to = None  # will be set if changes occur
        contact = fake.name()
        phone = f"+254{random.choice(['070','071','072','073'])}{random.randint(1000000,9999999)}"
        email = f"contact@{name.lower().replace(' ','')}.co.ke"
        terms = random.choice(payment_terms)
        lead_time = random.randint(2, 30)
        category = random.choice(categories)
        tax_id = f"P{random.randint(10000000,99999999)}"

        rows.append([supplier_id, valid_from.isoformat(), None, name, contact, phone, email,
                     terms, lead_time, category, tax_id])

        # possible change: 30% get a second version
        if random.random() < 0.3:
            change_date = fake.date_between(start_date=valid_from + timedelta(days=180), end_date=END_DATE - timedelta(days=1))
            # update previous row's valid_to
            rows[-1][2] = change_date.isoformat()
            # new version
            contact = fake.name() if random.random() < 0.5 else contact
            phone = f"+254{random.choice(['070','071','072','073'])}{random.randint(1000000,9999999)}" if random.random() < 0.5 else phone
            email = f"contact@{name.lower().replace(' ','')}.co.ke" if random.random() < 0.5 else email
            terms = random.choice(payment_terms) if random.random() < 0.5 else terms
            lead_time = random.randint(2,30) if random.random() < 0.5 else lead_time
            category = random.choice(categories) if random.random() < 0.1 else category
            rows.append([supplier_id, change_date.isoformat(), None, name, contact, phone, email,
                         terms, lead_time, category, tax_id])

    columns = ['supplier_id', 'valid_from', 'valid_to', 'supplier_name', 'contact_person',
               'phone', 'email', 'payment_terms', 'lead_time_days', 'category', 'tax_id']
    df = pd.DataFrame(rows, columns=columns)
    df = inject_issues(df, missing_cols=['contact_person','email'], date_cols=['valid_from','valid_to'])
    df.to_csv(os.path.join(out_dir, 'suppliers_raw.csv'), index=False)
    print(f"Suppliers: {len(df)} rows")

if __name__ == '__main__':
    generate_suppliers()