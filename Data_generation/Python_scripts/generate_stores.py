#!/usr/bin/env python3
"""
generate_stores.py

Generates the stores raw dataset (Type 2 SCD) for Blue Canopy Kenya.
Output: bronze/stores/stores_raw.csv

Grain: One row per store version. Includes store format/size changes over time.
Type 2 SCD: Changes in format or size trigger new rows with valid_from/valid_to.
Volume: ~150 stores, ~180 rows (accounting for ~20% with changes)
"""

import os
import random
import csv
import numpy as np
import pandas as pd
from faker import Faker
from datetime import datetime, date, timedelta

# Configuration
fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

KENYA_COUNTY_TOWNS = {
    "Nairobi": ["CBD", "Westlands", "Kilimani", "Kasarani", "Embakasi", "Lang'ata", "Karen", "Runda", "Lavington"],
    "Mombasa": ["Mvita", "Nyali", "Bamburi", "Likoni", "Changamwe", "Kisauni", "Shanzu"],
    "Kisumu": ["Kisumu CBD", "Milimani", "Manyatta", "Nyamasaria", "Nyalenda", "Kondele"],
    "Nakuru": ["Nakuru CBD", "Naivasha", "Gilgil", "Molo", "Njoro", "Bahati"],
    "Kiambu": ["Thika", "Ruiru", "Juja", "Kiambu Town", "Githurai", "Limuru"],
    "Uasin Gishu": ["Eldoret CBD", "Turbo", "Burnt Forest", "Ziwa", "Moiben"],
    "Meru": ["Meru Town", "Nkubu", "Timau", "Maua", "Laare"],
    "Machakos": ["Machakos Town", "Athi River", "Kangundo", "Mwala", "Masinga"],
    "Kakamega": ["Kakamega Town", "Mumias", "Malava", "Butere", "Shinyalu"],
    "Bungoma": ["Bungoma Town", "Webuye", "Kimilili", "Chwele", "Sirisia"],
    "Kisii": ["Kisii Town", "Ogembo", "Suneka", "Mosocho"],
    "Nyamira": ["Nyamira Town", "Keroka", "Nyansiongo", "Rigoma"],
    "Nyandarua": ["Ol Kalou", "Engineer", "Njabini", "Kinangop"],
    "Nyeri": ["Nyeri Town", "Karatina", "Othaya", "Mathira"],
    "Kirinyaga": ["Kerugoya", "Kutus", "Sagana", "Wang'uru"],
    "Murang'a": ["Murang'a Town", "Kangema", "Maragua", "Gatanga"],
    "Laikipia": ["Nanyuki", "Nyahururu", "Rumuruti"],
    "Nandi": ["Kapsabet", "Mosoriot", "Lessos"],
    "Kericho": ["Kericho Town", "Litein", "Ainamoi"],
    "Bomet": ["Bomet Town", "Sotik", "Longisa"],
    "Kilifi": ["Kilifi Town", "Malindi", "Watamu", "Mariakani"],
    "Kwale": ["Kwale Town", "Ukunda", "Msambweni"],
    "Lamu": ["Lamu Town", "Mpeketoni"],
    "Taita Taveta": ["Voi", "Taveta", "Wundanyi"],
    "Garissa": ["Garissa Town", "Dadaab"],
    "Wajir": ["Wajir Town", "Habaswein"],
    "Mandera": ["Mandera Town", "El Wak"],
    "Marsabit": ["Marsabit Town", "Moyale"],
    "Isiolo": ["Isiolo Town", "Merti"],
    "Kitui": ["Kitui Town", "Mwingi", "Mutomo"],
    "Makueni": ["Wote", "Makindu", "Mtito Andei"],
    "Embu": ["Embu Town", "Runyenjes", "Siakago"],
    "Tharaka Nithi": ["Chuka", "Kathwana"],
    "Busia": ["Busia Town", "Malaba", "Nambale"],
    "Siaya": ["Siaya Town", "Bondo", "Ugunja"],
    "Homa Bay": ["Homa Bay Town", "Mbita", "Ndhiwa", "Oyugis"],
    "Migori": ["Migori Town", "Awendo", "Rongo"],
    "Vihiga": ["Mbale", "Luanda"],
    "Baringo": ["Kabarnet", "Eldama Ravine"],
    "Elgeyo Marakwet": ["Iten", "Chepkorio"],
    "Samburu": ["Maralal", "Baragoi"],
    "Trans Nzoia": ["Kitale", "Kiminini"],
    "Turkana": ["Lodwar", "Lokichoggio"],
    "West Pokot": ["Kapenguria", "Sigor"],
    "Narok": ["Narok Town", "Kilgoris"],
    "Kajiado": ["Kajiado Town", "Ngong", "Kitengela", "Ongata Rongai"],
    "Tana River": ["Hola Town", "Bura", "Garsen", "Madogo"]
}

def inject_issues(df, frac_missing=0.02, frac_duplicate=0.01,
                  missing_cols=None, date_cols=None, int_cols=None):
    """Add missing values, duplicates, and bad dates to a DataFrame."""
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

def generate_stores():
    print("Generating Stores...")
    out_dir = os.path.join('bronze', 'stores')
    os.makedirs(out_dir, exist_ok=True)

    STORE_FORMATS = ['Supermarket', 'Mini-mart', 'Express', 'Hypermarket']
    counties = list(KENYA_COUNTY_TOWNS.keys())
    
    rows = []
    num_stores = 150
    
    for i in range(num_stores):
        store_id = f"STOR-{i+1:04d}"
        county = random.choice(counties)
        town = random.choice(KENYA_COUNTY_TOWNS[county])
        store_name = f"Blue Canopy {town}"
        
        # Opening date: between 2010 and 2023 (but clamp to START_DATE for data range)
        open_year = random.randint(2010, 2023)
        open_date = date(open_year, random.randint(1, 12), random.randint(1, 28))
        if open_date < START_DATE:
            open_date = START_DATE
        
        # Determine if store is active
        is_active = random.random() < 0.95  # 95% active
        closing_date = None
        if not is_active:
            close_offset = random.randint(30, 1000)
            closing_date = open_date + timedelta(days=close_offset)
            if closing_date > END_DATE:
                closing_date = END_DATE
        
        # Store format and size
        store_format = random.choice(STORE_FORMATS)
        if store_format == 'Hypermarket':
            size_sqm = random.randint(8000, 15000)
        elif store_format == 'Supermarket':
            size_sqm = random.randint(3000, 8000)
        elif store_format == 'Mini-mart':
            size_sqm = random.randint(500, 2000)
        else:  # Express
            size_sqm = random.randint(100, 500)
        
        # Version 1
        valid_from = open_date
        rows.append([
            store_id,
            valid_from.isoformat(),
            None,
            store_name,
            county,
            town,
            store_format,
            size_sqm,
            open_date.isoformat(),
            closing_date.isoformat() if closing_date else None,
            is_active
        ])
        
        # Simulate changes: ~20% of stores have format/size changes
        if random.random() < 0.2 and is_active:
            num_changes = random.randint(1, 2)
            current_valid_from = valid_from
            current_format = store_format
            current_size = size_sqm
            
            for _ in range(num_changes):
                earliest_change = current_valid_from + timedelta(days=180)
                latest_change = END_DATE - timedelta(days=100)
                
                # Skip if date range is invalid
                if earliest_change >= latest_change:
                    break
                
                change_date = fake.date_between(
                    start_date=earliest_change,
                    end_date=latest_change
                )
                
                # Close previous version
                rows[-1][2] = change_date.isoformat()
                
                # Change format or size
                if random.random() < 0.6:
                    current_format = random.choice(STORE_FORMATS)
                if random.random() < 0.4:
                    if current_format == 'Hypermarket':
                        current_size = random.randint(8000, 15000)
                    elif current_format == 'Supermarket':
                        current_size = random.randint(3000, 8000)
                    elif current_format == 'Mini-mart':
                        current_size = random.randint(500, 2000)
                    else:
                        current_size = random.randint(100, 500)
                
                rows.append([
                    store_id,
                    change_date.isoformat(),
                    None,
                    store_name,
                    county,
                    town,
                    current_format,
                    current_size,
                    open_date.isoformat(),
                    closing_date.isoformat() if closing_date else None,
                    is_active
                ])
                current_valid_from = change_date
    
    columns = [
        'store_id', 'valid_from', 'valid_to', 'store_name', 'county', 'town',
        'format', 'size_sqm', 'opening_date', 'closing_date', 'is_active'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    # Inject data quality issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['town', 'format'],
        date_cols=['valid_from', 'valid_to', 'opening_date', 'closing_date'],
        int_cols=['size_sqm']
    )
    
    out_file = os.path.join(out_dir, 'stores_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_stores()
