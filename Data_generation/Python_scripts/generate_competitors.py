#!/usr/bin/env python3
"""
generate_competitors.py

Generates competitor and market intelligence data.
Output:
  - bronze/competitive_intelligence/competitors_raw.csv
  - bronze/competitive_intelligence/competitor_stores_raw.csv
  - bronze/competitive_intelligence/competitor_quarterly_raw.csv

Grain:
  - Competitors: Static master
  - Stores: Store locations
  - Quarterly: Q revenue and market share
Volume: ~10 competitors, ~200 stores, ~400 quarterly records
"""

import os
import random
import numpy as np
import pandas as pd
from faker import Faker
from datetime import date

fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

KENYA_COUNTIES = [
    "Nairobi", "Mombasa", "Kisumu", "Nakuru", "Kiambu", "Uasin Gishu", "Meru", "Machakos",
    "Kakamega", "Bungoma", "Kisii", "Nyamira", "Nyandarua", "Nyeri", "Kirinyaga", "Murang'a",
    "Laikipia", "Nandi", "Kericho", "Bomet", "Kilifi", "Kwale", "Lamu", "Taita Taveta",
    "Garissa", "Wajir", "Mandera", "Marsabit", "Isiolo", "Kitui", "Makueni", "Embu",
    "Tharaka Nithi", "Busia", "Siaya", "Homa Bay", "Migori", "Vihiga", "Baringo",
    "Elgeyo Marakwet", "Samburu", "Trans Nzoia", "Turkana", "West Pokot", "Narok",
    "Kajiado", "Tana River"
]

def inject_issues(df, frac_missing=0.02, frac_duplicate=0.01,
                  missing_cols=None, date_cols=None):
    if missing_cols:
        for col in missing_cols:
            if col in df.columns:
                mask = np.random.random(len(df)) < frac_missing
                df.loc[mask, col] = np.nan
    return df

def generate_competitors():
    print("Generating Competitor Intelligence...")
    out_dir = os.path.join('bronze', 'competitive_intelligence')
    os.makedirs(out_dir, exist_ok=True)

    competitor_names = [
        'Nakumatt Holdings', 'Quickmart', 'Carrefour Kenya', 'Tuskys Supermarket',
        'Naivas Ltd', 'Eastmatt', 'Machakos Kitchen', 'Jumia Fresh', 'Safaricom Retail',
        'Equity Group Retail'
    ]
    
    # Competitors
    comp_rows = []
    for i, name in enumerate(competitor_names):
        comp_rows.append([
            f"COMP-{i+1:03d}",
            name,
            fake.company(),
            random.randint(30, 220)  # estimated stores
        ])
    
    comp_df = pd.DataFrame(comp_rows, columns=['competitor_id', 'competitor_name', 'headquarters', 'estimated_stores'])
    
    # Competitor stores
    store_rows = []
    store_id = 1
    for comp in comp_rows:
        num_stores = comp[3]
        for _ in range(num_stores):
            county = random.choice(list(KENYA_COUNTIES))
            store_rows.append([
                f"CSTORE-{store_id:06d}",
                comp[0],
                f"{comp[1]} - {fake.city()}",
                county,
                random.choice(['Large', 'Medium', 'Small'])
            ])
            store_id += 1
    
    store_df = pd.DataFrame(store_rows, columns=['competitor_store_id', 'competitor_id', 'location', 'county', 'size_category'])
    
    # Quarterly financials (store-location grain)
    # Create stable competitor market weights and distribute quarterly performance across competitor store locations
    base_weights = np.random.uniform(0.05, 0.15, len(comp_rows))
    base_weights /= base_weights.sum()

    quarterly_rows = []
    for year in range(2016, 2027):
        year_progress = (year - 2016) / 10
        for quarter in range(1, 5):
            total_market = int(20_000_000_000 * (1 + 0.06 * year_progress) * (1 + np.random.normal(0, 0.02)))
            weights = base_weights + np.random.normal(0, 0.01, len(base_weights))
            weights = np.clip(weights, 0.01, None)
            weights /= weights.sum()
            for i, comp in enumerate(comp_rows):
                comp_id = comp[0]
                # competitor-level revenue for the quarter
                comp_revenue = int(total_market * weights[i])
                # get all stores for this competitor and split revenue across them
                comp_stores = store_df[store_df['competitor_id'] == comp_id]['competitor_store_id'].tolist()
                if len(comp_stores) == 0:
                    # if no stores found, attribute all revenue to a placeholder
                    quarterly_rows.append([
                        comp_id,
                        None,
                        f"{year}-Q{quarter}",
                        comp_revenue,
                        round(comp_revenue / total_market * 100, 1)
                    ])
                else:
                    # random but stable-ish split across stores using a Dirichlet draw
                    store_weights = np.random.dirichlet(np.ones(len(comp_stores)))
                    for j, store_id in enumerate(comp_stores):
                        store_rev = int(comp_revenue * store_weights[j])
                        quarterly_rows.append([
                            comp_id,
                            store_id,
                            f"{year}-Q{quarter}",
                            store_rev,
                            round(store_rev / total_market * 100, 1)
                        ])

    quarterly_df = pd.DataFrame(quarterly_rows, columns=['competitor_id', 'competitor_store_id', 'quarter', 'revenue_kes', 'market_share_pct'])
    
    comp_file = os.path.join(out_dir, 'competitors_raw.csv')
    store_file = os.path.join(out_dir, 'competitor_stores_raw.csv')
    quarterly_file = os.path.join(out_dir, 'competitor_quarterly_raw.csv')
    
    comp_df.to_csv(comp_file, index=False)
    store_df.to_csv(store_file, index=False)
    quarterly_df.to_csv(quarterly_file, index=False)
    
    print(f"  -> {len(comp_df):,} competitors")
    print(f"  -> {len(store_df):,} competitor stores")
    print(f"  -> {len(quarterly_df):,} quarterly records")

if __name__ == '__main__':
    generate_competitors()
