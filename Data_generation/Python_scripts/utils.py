# utils.py (optional – can be copied into each script)
import random
import numpy as np
import pandas as pd
from datetime import datetime, date

# Kenyan counties and towns (case‑insensitive lookup)
COUNTY_TOWNS = {
    "Nairobi": ["CBD", "Westlands", "Kilimani", "Kasarani", "Embakasi", "Lang'ata", "Karen", "Runda", "Lavington", "Parklands"],
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
COUNTIES = list(COUNTY_TOWNS.keys())
COUNTY_LOOKUP = {k.lower(): k for k in COUNTY_TOWNS}

def random_town(county):
    """Return a random town for the given county (case‑insensitive)."""
    proper = COUNTY_LOOKUP.get(county.lower(), county)
    return random.choice(COUNTY_TOWNS[proper])

def weighted_town(county):
    """Return a weighted random town for the given county (case‑insensitive)."""
    proper = COUNTY_LOOKUP.get(county.lower(), county)
    towns = COUNTY_TOWNS[proper]
    weights = [3 if i < 2 else 1 for i in range(len(towns))]
    return random.choices(towns, weights=weights, k=1)[0]

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
        key_col = df.columns[0]  # assume first column is primary key
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

def append_to_csv(file_path, rows):
    """Append rows (list of lists) to CSV file."""
    with open(file_path, 'a', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerows(rows)