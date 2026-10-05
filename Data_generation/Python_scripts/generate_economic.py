#!/usr/bin/env python3
"""
generate_economic.py

Generates macro-economic indicators by county.
Output: bronze/macroeconomic/economic_raw.csv

Grain: One row per county per month
Volume: 47 counties × 120 months = 5,640 rows
"""

import os
import random
import numpy as np
import pandas as pd
from datetime import date, timedelta
from dateutil.relativedelta import relativedelta

Faker_seed = 42
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

KENYA_COUNTIES = ["Nairobi", "Mombasa", "Kisumu", "Nakuru", "Kiambu", "Uasin Gishu", "Meru",
    "Machakos", "Kakamega", "Bungoma", "Kisii", "Nyamira", "Nyandarua", "Nyeri", "Kirinyaga",
    "Murang'a", "Laikipia", "Nandi", "Kericho", "Bomet", "Kilifi", "Kwale", "Lamu",
    "Taita Taveta", "Garissa", "Wajir", "Mandera", "Marsabit", "Isiolo", "Kitui", "Makueni",
    "Embu", "Tharaka Nithi", "Busia", "Siaya", "Homa Bay", "Migori", "Vihiga", "Baringo",
    "Elgeyo Marakwet", "Samburu", "Trans Nzoia", "Turkana", "West Pokot", "Narok", "Kajiado", "Tana River"]

def generate_economic():
    print("Generating Economic Indicators...")
    out_dir = os.path.join('bronze', 'macroeconomic')
    os.makedirs(out_dir, exist_ok=True)

    # Base offsets create county-level variation while preserving a shared national trend
    county_offsets = {
        county: {
            'gdp': np.random.uniform(-0.5, 0.5),
            'inflation': np.random.uniform(-0.8, 0.8),
            'unemployment': np.random.uniform(-1.0, 1.0),
            'confidence': np.random.uniform(-5, 5),
            'retail': np.random.uniform(-10, 10),
            'fuel': np.random.uniform(-5, 5)
        }
        for county in KENYA_COUNTIES
    }

    rows = []
    current_date = START_DATE
    month_index = 0

    while current_date <= END_DATE:
        year_month = current_date.strftime('%Y-%m')
        year_progress = month_index / max(1, ((END_DATE.year - START_DATE.year) * 12 + END_DATE.month - START_DATE.month))
        seasonal_factor = 1.0 + 0.05 * np.sin((current_date.month - 1) / 12 * 2 * np.pi)
        price_shock = 0

        # Add a global shock period for 2020-2021
        if current_date.year in [2020, 2021]:
            price_shock = 0.08

        for county in KENYA_COUNTIES:
            offsets = county_offsets[county]
            gdp_growth = round(np.random.normal(3.5 + offsets['gdp'] - 0.5 * price_shock + 0.2 * year_progress, 0.4), 2)
            inflation = round(np.random.normal(5.0 + offsets['inflation'] + 0.5 * price_shock + 0.3 * year_progress, 0.4), 2)
            unemployment = round(np.random.normal(6.0 + offsets['unemployment'] + 0.1 * price_shock, 0.5), 2)
            consumer_confidence = round(np.clip(50 + offsets['confidence'] - 0.8 * (inflation - 5) + 3 * year_progress, 20, 80), 1)
            retail_index = round(np.clip(90 + offsets['retail'] + 1.5 * month_index + 5 * year_progress + 5 * price_shock, 50, 220) * seasonal_factor, 1)
            fuel_price = round(np.clip(95 + offsets['fuel'] + 0.7 * month_index + 3 * price_shock + np.random.normal(0, 3), 70, 220), 2)
            usd_rate = round(np.clip(100 + 0.4 * month_index + np.random.normal(0, 1.5), 90, 180), 2)

            rows.append([
                county,
                year_month,
                gdp_growth,
                inflation,
                unemployment,
                consumer_confidence,
                retail_index,
                fuel_price,
                usd_rate
            ])

        current_date += relativedelta(months=1)
        month_index += 1
    
    columns = [
        'county', 'year_month', 'gdp_growth_pct', 'inflation_pct', 'unemployment_pct',
        'consumer_confidence', 'retail_sales_index', 'fuel_price_kes', 'usd_kes_rate'
    ]
    
    df = pd.DataFrame(rows, columns=columns)
    
    out_file = os.path.join(out_dir, 'economic_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} economic records written")

if __name__ == '__main__':
    generate_economic()
