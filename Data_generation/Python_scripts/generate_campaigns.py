#!/usr/bin/env python3
"""
generate_campaigns.py

Generates marketing campaign records for Blue Canopy Kenya.
Output: bronze/marketing/campaigns_raw.csv

Grain: One row per campaign.
Volume: ~500 rows
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

CAMPAIGN_TYPES = ['Loyalty', 'Seasonal', 'Promotion', 'Event', 'Holiday', 'Grand Opening']
CHANNELS = ['TV', 'Radio', 'Social Media', 'SMS', 'In-store', 'Digital', 'Email', 'Print']

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

def generate_campaigns():
    print("Generating Marketing Campaigns (Non-overlapping)...")
    out_dir = os.path.join('bronze', 'marketing')
    os.makedirs(out_dir, exist_ok=True)

    rows = []
    
    # Create a timeline where campaigns don't overlap with each other
    # Campaigns are typically larger scale, so we'll have fewer but longer-running campaigns
    num_campaigns = 150  # Reduced from 500 to ensure non-overlap
    total_days = (END_DATE - START_DATE).days
    segment_length = total_days // num_campaigns
    
    current_date = START_DATE
    campaign_id = 1
    
    for _ in range(num_campaigns):
        campaign_name = f"Campaign_{fake.word().title()}_{random.randint(1000, 9999)}"
        campaign_type = random.choice(CAMPAIGN_TYPES)
        channel = random.choice(CHANNELS)
        
        # Each campaign gets a defined segment with some randomness
        # Start: somewhere in the current segment
        if campaign_id < num_campaigns:
            max_offset = min(segment_length - 15, 20) if segment_length > 15 else 0
            start_offset = random.randint(0, max_offset) if max_offset > 0 else 0
            start_date = current_date + timedelta(days=start_offset)
            
            # Duration: 7-60 days (campaigns longer than promotions)
            duration = random.randint(7, 60)
            end_date = start_date + timedelta(days=duration)
            
            # Move to next segment
            current_date = end_date + timedelta(days=random.randint(1, 3))  # Small gap between campaigns
        else:
            # Last campaign
            start_date = current_date
            duration = random.randint(7, 45)
            end_date = start_date + timedelta(days=duration)
        
        # Ensure dates stay within range
        if end_date > END_DATE:
            end_date = END_DATE
        if start_date > END_DATE:
            break
        
        # Realistic budget allocation for Kenya
        budget = random.choice([5_000, 10_000, 25_000, 50_000, 100_000, 200_000])
        actual_spend = int(budget * np.random.uniform(0.7, 1.1))
        
        # Discount rate associated with campaign (if it's a promotional campaign)
        discount_rate = np.random.choice([0, 0.05, 0.10, 0.15, 0.20], p=[0.35, 0.25, 0.20, 0.15, 0.05])
        
        rows.append([
            f"CMP-{campaign_id:04d}",
            campaign_name,
            campaign_type,
            channel,
            start_date.isoformat(),
            end_date.isoformat(),
            budget,
            actual_spend,
            discount_rate
        ])
        
        campaign_id += 1
    
    columns = [
        'campaign_id', 'campaign_name', 'campaign_type', 'channel',
        'start_date', 'end_date', 'budget_kes', 'actual_spend_kes', 'discount_rate'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject issues (excluding critical date columns)
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['channel'],
        int_cols=['budget_kes', 'actual_spend_kes']
    )
    
    out_file = os.path.join(out_dir, 'campaigns_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} campaigns written to {out_file}")

if __name__ == '__main__':
    generate_campaigns()
