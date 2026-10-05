#!/usr/bin/env python3
"""
generate_gis.py

Generates GIS (Geographic Information System) data.
Output:
  - bronze/gis/gis_counties_raw.csv
  - bronze/gis/gis_locations_raw.csv

Grain:
  - Counties: County profiles
  - Locations: Points of interest with accessibility
Volume: 47 counties, ~500 locations
"""

import os
import random
import numpy as np
import pandas as pd
from faker import Faker

fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

KENYA_COUNTIES = {
    "Nairobi": (1166054, 700000, -1.2921, 36.8219),
    "Mombasa": (939370, 80000, -4.0435, 39.6682),
    "Kisumu": (968909, 35000, -0.0917, 34.7680),
    "Nakuru": (1603325, 35000, -0.3031, 36.0800),
    "Kiambu": (1623282, 30000, -1.1714, 36.7844),
    "Uasin Gishu": (876000, 25000, 0.5167, 35.2667),
    "Meru": (700000, 20000, 0.0478, 37.6493),
    "Machakos": (1097000, 15000, -1.5177, 37.2617),
    "Kakamega": (1660651, 25000, 0.2833, 34.7500),
    "Bungoma": (1670570, 20000, 0.5690, 34.5600),
    "Kisii": (1152382, 25000, -0.6761, 34.7681),
    "Nyamira": (596268, 20000, -0.5739, 34.9500),
    "Nyandarua": (560000, 20000, -0.0315, 36.3667),
    "Nyeri": (730000, 22000, -0.4167, 36.9500),
    "Kirinyaga": (550000, 18000, -0.4417, 37.4411),
    "Murang'a": (917000, 20000, -0.7167, 37.1500),
    "Laikipia": (406600, 15000, 0.4167, 36.9500),
    "Nandi": (750000, 20000, 0.1000, 35.0000),
    "Kericho": (750000, 22000, -0.3670, 35.2830),
    "Bomet": (850000, 20000, -0.7667, 35.3333),
    "Kilifi": (1453787, 15000, -3.6333, 39.8500),
    "Kwale": (649931, 12000, -4.1766, 39.4590),
    "Lamu": (80000, 5000, -2.2711, 40.9000),
    "Taita Taveta": (344062, 10000, -3.3969, 38.3561),
    "Garissa": (623060, 8000, -0.4526, 39.6470),
    "Wajir": (661143, 8000, 1.7485, 40.0576),
    "Mandera": (425647, 8000, 3.9379, 41.8561),
    "Marsabit": (291904, 8000, 2.3333, 37.9833),
    "Isiolo": (181904, 10000, 0.3527, 37.5822),
    "Kitui": (1012000, 12000, -1.3667, 38.0167),
    "Makueni": (884527, 12000, -1.7833, 37.7333),
    "Embu": (546487, 15000, -0.5333, 37.4500),
    "Tharaka Nithi": (410189, 8000, -0.2167, 37.6500),
    "Busia": (701037, 10000, 0.4542, 34.1100),
    "Siaya": (748048, 12000, 0.0597, 34.2883),
    "Homa Bay": (963794, 15000, -0.5263, 34.4580),
    "Migori": (796436, 12000, -1.0658, 34.4739),
    "Vihiga": (554622, 15000, 0.0908, 34.7420),
    "Baringo": (625537, 8000, 0.5000, 36.1167),
    "Elgeyo Marakwet": (432815, 8000, 0.5167, 35.5333),
    "Samburu": (278656, 8000, 0.5333, 37.5167),
    "Trans Nzoia": (818000, 15000, 1.0167, 35.0000),
    "Turkana": (855399, 10000, 3.4140, 35.5670),
    "West Pokot": (512533, 8000, 1.2167, 35.0920),
    "Narok": (909186, 12000, -1.0833, 35.8833),
    "Kajiado": (687312, 15000, -1.8500, 36.7833),
    "Tana River": (315954, 8000, -1.4667, 39.8167)
}

def generate_gis():
    print("Generating GIS Data...")
    out_dir = os.path.join('bronze', 'gis')
    os.makedirs(out_dir, exist_ok=True)

    # Counties
    county_rows = []
    for county, (population, income_kes, lat, lon) in KENYA_COUNTIES.items():
        county_rows.append([
            county,
            population,
            income_kes,
            lat,
            lon
        ])
    
    county_df = pd.DataFrame(county_rows, columns=['county', 'population', 
                                                    'avg_income_kes', 'latitude', 'longitude'])
    
    # Locations (POI)
    location_rows = []
    location_id = 1
    for county, (_, _, lat, lon) in KENYA_COUNTIES.items():
        # 8-12 locations per county
        num_locations = random.randint(8, 12)
        for _ in range(num_locations):
            location_type = random.choice(['Market', 'Shopping Center', 'Residential', 'Industrial', 'Transport Hub'])
            accessibility_score = round(np.random.uniform(1, 10), 1)
            
            location_rows.append([
                f"LOC-{location_id:06d}",
                county,
                f"{fake.word().title()} {location_type}",
                location_type,
                round(lat + np.random.normal(0, 0.08), 4),
                round(lon + np.random.normal(0, 0.08), 4),
                accessibility_score
            ])
            location_id += 1
    
    location_df = pd.DataFrame(location_rows, columns=['location_id', 'county', 'location_name',
                                                        'location_type', 'latitude', 'longitude', 
                                                        'accessibility_score'])
    
    county_file = os.path.join(out_dir, 'gis_counties_raw.csv')
    location_file = os.path.join(out_dir, 'gis_locations_raw.csv')
    
    county_df.to_csv(county_file, index=False)
    location_df.to_csv(location_file, index=False)
    
    print(f"  -> {len(county_df):,} counties")
    print(f"  -> {len(location_df):,} locations")

if __name__ == '__main__':
    generate_gis()
