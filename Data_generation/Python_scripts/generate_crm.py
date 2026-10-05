#!/usr/bin/env python3
"""
generate_crm.py

Generates the CRM raw dataset (Type 2 SCD) for Blue Canopy Kenya.
Output: bronze/crm/crm_raw.csv

Grain: One row per customer version, capturing changes in loyalty tier and segment.
Type 2 SCD: ~20% of customers undergo changes (tier upgrades/downgrades, segment shifts).
Volume: ~150k customers, ~180k rows accounting for version changes.
"""

import os
import random
import numpy as np
import pandas as pd
from faker import Faker
from datetime import date, timedelta

# Configuration
fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

LOYALTY_TIERS = ['Bronze', 'Silver', 'Gold', 'Platinum']
CUSTOMER_SEGMENTS = ['Budget Conscious', 'Regular', 'Premium', 'Value Seeker', 'Family']
ACQUISITION_CHANNELS = ['In-Store', 'Online', 'Mobile App', 'Referral', 'Staff', 'Event']

KENYA_COUNTY_TOWNS = {
    "Nairobi": ["CBD", "Westlands", "Kilimani", "Kasarani", "Embakasi"],
    "Mombasa": ["Mvita", "Nyali", "Bamburi", "Likoni"],
    "Kisumu": ["Kisumu CBD", "Milimani", "Manyatta"],
    "Nakuru": ["Nakuru CBD", "Naivasha", "Gilgil"],
    "Kiambu": ["Thika", "Ruiru", "Juja"],
    "Eldoret": ["Eldoret CBD", "Turbo", "Burnt Forest"],
    "Meru": ["Meru Town", "Nkubu", "Timau"],
    "Machakos": ["Machakos Town", "Athi River", "Kangundo"],
}

def inject_issues(df, frac_missing=0.02, frac_duplicate=0.01,
                  missing_cols=None, date_cols=None):
    """Add data quality issues to DataFrame."""
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
    return df

def generate_crm():
    print("Generating CRM (Customers)...")
    out_dir = os.path.join('bronze', 'crm')
    os.makedirs(out_dir, exist_ok=True)

    num_customers = 150_000
    rows = []
    
    for i in range(num_customers):
        customer_id = f"CUST-{i+1:06d}"
        
        first_name = fake.first_name()
        last_name = fake.last_name()
        gender = random.choice(['Male', 'Female', 'Other', np.nan])
        birth_date = fake.date_of_birth(minimum_age=18, maximum_age=80)
        phone = f"+254{random.choice(['70','71','72','73'])}{random.randint(1000000,9999999)}"
        email = f"{first_name.lower()}.{last_name.lower()}@example.com"
        
        county = random.choice(list(KENYA_COUNTY_TOWNS.keys()))
        town = random.choice(KENYA_COUNTY_TOWNS[county])
        
        # Registration date
        reg_year = random.randint(2016, 2025)
        reg_date = date(reg_year, random.randint(1, 12), random.randint(1, 28))
        if reg_date < START_DATE:
            reg_date = START_DATE
        
        # Churn: ~10% of customers churn
        is_churned = random.random() < 0.10
        churn_date = None
        if is_churned:
            churn_offset = random.randint(60, 1000)
            churn_date = reg_date + timedelta(days=churn_offset)
            if churn_date > END_DATE:
                churn_date = END_DATE
        
        # Initial loyalty tier and segment
        loyalty_tier = random.choice(LOYALTY_TIERS[:3])  # Start lower
        segment = random.choice(CUSTOMER_SEGMENTS)
        acquisition_channel = random.choice(ACQUISITION_CHANNELS)
        communication_pref = random.choice(['Email', 'SMS', 'Phone', 'None'])
        feedback_score = round(np.random.uniform(1, 5), 1) if random.random() < 0.7 else np.nan
        
        # Version 1
        valid_from = reg_date
        rows.append([
            customer_id,
            valid_from.isoformat(),
            None,
            first_name,
            last_name,
            gender,
            birth_date.isoformat(),
            phone,
            email,
            county,
            town,
            segment,
            acquisition_channel,
            reg_date.isoformat(),
            churn_date.isoformat() if churn_date else None,
            loyalty_tier,
            communication_pref,
            feedback_score
        ])
        
        # Simulate changes: ~20% of customers change tier/segment
        if random.random() < 0.2 and not is_churned:
            num_changes = random.randint(1, 3)
            current_valid_from = valid_from
            current_tier = loyalty_tier
            current_segment = segment
            
            for _ in range(num_changes):
                earliest_change = current_valid_from + timedelta(days=90)
                latest_change = END_DATE - timedelta(days=30)
                
                if earliest_change >= latest_change:
                    break
                
                change_date = fake.date_between(
                    start_date=earliest_change,
                    end_date=latest_change
                )
                
                # Skip if past churn date
                if churn_date and change_date >= churn_date:
                    break
                
                # Close previous version
                rows[-1][2] = change_date.isoformat()
                
                # Change tier (usually upgrade)
                if random.random() < 0.7:
                    tier_idx = LOYALTY_TIERS.index(current_tier)
                    current_tier = LOYALTY_TIERS[min(tier_idx + 1, len(LOYALTY_TIERS) - 1)]
                
                # Sometimes change segment
                if random.random() < 0.3:
                    current_segment = random.choice(CUSTOMER_SEGMENTS)
                
                feedback_score = round(np.random.uniform(1, 5), 1) if random.random() < 0.7 else np.nan
                
                rows.append([
                    customer_id,
                    change_date.isoformat(),
                    None,
                    first_name,
                    last_name,
                    gender,
                    birth_date.isoformat(),
                    phone,
                    email,
                    county,
                    town,
                    current_segment,
                    acquisition_channel,
                    reg_date.isoformat(),
                    churn_date.isoformat() if churn_date else None,
                    current_tier,
                    communication_pref,
                    feedback_score
                ])
                current_valid_from = change_date
    
    columns = [
        'customer_id', 'valid_from', 'valid_to', 'first_name', 'last_name',
        'gender', 'birth_date', 'phone', 'email', 'county', 'town',
        'customer_segment', 'acquisition_channel', 'registration_date',
        'churn_date', 'loyalty_tier', 'communication_preferences', 'feedback_score'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject data quality issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['email', 'phone', 'town'],
        date_cols=['valid_from', 'valid_to', 'birth_date', 'registration_date', 'churn_date']
    )
    
    out_file = os.path.join(out_dir, 'crm_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_crm()
