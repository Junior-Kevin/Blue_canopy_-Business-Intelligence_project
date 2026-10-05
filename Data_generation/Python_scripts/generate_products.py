#!/usr/bin/env python3
"""
generate_products.py

Generates the products raw dataset (Type 2 SCD) for Blue Canopy Kenya.
Output: bronze/products/products_raw.csv

Depends on: bronze/suppliers/suppliers_raw.csv (if missing, creates placeholders)
Grain: one row per product version. Includes price changes and supplier changes.
"""

import os
import random
import csv
import numpy as np
import pandas as pd
from faker import Faker
from datetime import datetime, date, timedelta

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
fake = Faker('en_KE')
Faker.seed(42)
np.random.seed(42)
random.seed(42)

START_DATE = date(2016, 1, 1)
END_DATE = date(2026, 2, 28)

# ------------------------------------------------------------
# Kenyan counties and towns (unused but kept for consistency)
# ------------------------------------------------------------
KENYA_COUNTY_TOWNS = {
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
COUNTIES = list(KENYA_COUNTY_TOWNS.keys())
COUNTY_LOOKUP = {k.lower(): k for k in KENYA_COUNTY_TOWNS}

def random_town(county):
    """Return a random town for the given county (case‑insensitive)."""
    proper = COUNTY_LOOKUP.get(county.lower(), county)
    return random.choice(KENYA_COUNTY_TOWNS[proper])

# ------------------------------------------------------------
# Kenyan product categories, brands, and suppliers
# ------------------------------------------------------------
PRODUCT_CATEGORIES = {
    'FMCG': {
        'Food & Beverages': ['Unga wa Ngano', 'Mahindi Flour', 'Sukari', 'Chumvi', 'Mafuta ya Kupikia', 'Maziwa Fresh', 'Chai Leaves', 'Kahawa'],
        'Snacks & Confectionery': ['Biscuits', 'Chocolate Bars', 'Candy', 'Crisps', 'Nuts', 'Popcorn', 'Cookies', 'Sweets'],
        'Beverages': ['Soda', 'Juice', 'Water', 'Energy Drinks', 'Tea Bags', 'Coffee', 'Malt Drinks', 'Flavored Milk'],
        'Personal Care': ['Soap', 'Shampoo', 'Toothpaste', 'Deodorant', 'Sanitary Pads', 'Razors', 'Lotion', 'Perfume'],
        'Household': ['Washing Powder', 'Dish Soap', 'Toilet Cleaner', 'Air Freshener', 'Bleach', 'Hand Wash', 'Fabric Softener'],
        'Cooking Essentials': ['Cooking Oil', 'Salt', 'Sugar', 'Rice', 'Beans', 'Maize Flour', 'Wheat Flour', 'Spices']
    },
    'Fresh': {
        'Fruits & Vegetables': ['Sukuma Wiki', 'Spinach', 'Cabbage', 'Tomatoes', 'Onions', 'Potatoes', 'Carrots', 'Bananas', 'Oranges', 'Mangoes'],
        'Meat & Poultry': ['Beef', 'Chicken', 'Mutton', 'Pork', 'Fish', 'Sausages', 'Minced Meat', 'Goat Meat'],
        'Dairy': ['Milk', 'Yogurt', 'Cheese', 'Butter', 'Cream', 'Margarine', 'Eggs'],
        'Bakery': ['Bread', 'Buns', 'Cakes', 'Pastries', 'Donuts', 'Cookies', 'Rusk']
    },
    'Non-Food': {
        'Electronics': ['Mobile Phones', 'Chargers', 'Headphones', 'Power Banks', 'USB Cables', 'Batteries'],
        'Clothing': ['T-Shirts', 'Trousers', 'Dresses', 'Shirts', 'Skirts', 'Socks', 'Underwear'],
        'Footwear': ['Shoes', 'Sandals', 'Slippers', 'Boots', 'Sports Shoes'],
        'Home Appliances': ['Kettles', 'Toasters', 'Blenders', 'Irons', 'Fans', 'Heaters'],
        'Stationery': ['Notebooks', 'Pens', 'Pencils', 'Files', 'Staplers', 'Calculators']
    },
    'Health & Wellness': {
        'Pharmacy': ['Painkillers', 'Antibiotics', 'Vitamins', 'First Aid', 'Thermometers', 'Bandages'],
        'Supplements': ['Protein Powder', 'Vitamins', 'Minerals', 'Herbal Supplements', 'Energy Boosters'],
        'Fitness': ['Sports Equipment', 'Yoga Mats', 'Dumbbells', 'Exercise Bands', 'Sports Drinks']
    },
    'Beauty & Fashion': {
        'Cosmetics': ['Lipstick', 'Foundation', 'Mascara', 'Nail Polish', 'Makeup Brushes', 'Eyeliner'],
        'Perfumes': ['Men\'s Fragrances', 'Women\'s Fragrances', 'Unisex Scents', 'Body Sprays'],
        'Jewelry': ['Necklaces', 'Earrings', 'Bracelets', 'Watches', 'Rings']
    },
    'Home & Living': {
        'Furniture': ['Chairs', 'Tables', 'Shelves', 'Beds', 'Cabinets', 'Sofas'],
        'Home Décor': ['Curtains', 'Cushions', 'Wall Art', 'Vases', 'Lamps', 'Rugs'],
        'Kitchenware': ['Pots', 'Pans', 'Utensils', 'Cutlery', 'Plates', 'Glasses'],
        'Gardening': ['Seeds', 'Tools', 'Fertilizers', 'Pots', 'Watering Cans', 'Gloves']
    },
    'Automotive': {
        'Car Accessories': ['Car Mats', 'Seat Covers', 'Phone Holders', 'Air Fresheners', 'Cleaning Kits'],
        'Motorbike': ['Helmets', 'Gloves', 'Raincoats', 'Locks', 'Maintenance Kits'],
        'Lubricants': ['Engine Oil', 'Brake Fluid', 'Coolant', 'Transmission Fluid', 'Grease']
    },
    'Services': {
        'Financial': ['Airtime', 'Data Bundles', 'Bill Payments', 'Money Transfer', 'Gift Cards'],
        'Lottery': ['Lottery Tickets', 'Betting Slips', 'Scratch Cards'],
        'Other': ['Printing Services', 'Photocopying', 'Laminating', 'Passport Photos']
    }
}

KENYAN_BRANDS = {
    'FMCG': ['Bidco', 'KCC', 'Brookside', 'Tusker', 'Kericho Gold', 'Dormans', 'Eveready', 'Kimbo', 'Cowboy', 'Sunlight'],
    'Fresh': ['Farmers Choice', 'Kenfresh', 'Mukwano', 'Local Farm', 'Fresh Produce Kenya', 'Zucchini', 'Uchumi Fresh'],
    'Non-Food': ['Samsung', 'Tecno', 'Infinix', 'Nokia', 'Mango', 'H&M', 'Bata', 'SafariCom', 'Airtel'],
    'Health & Wellness': ['GlaxoSmithKline', 'Bayer', 'Pfizer', 'GSK', 'Local Pharma', 'HealthyU', 'Wellness Kenya'],
    'Beauty & Fashion': ['MAC', 'Maybelline', 'L\'Oréal', 'Nivea', 'Vaseline', 'Ponds', 'Local Beauty'],
    'Home & Living': ['Mabati', 'Chandaria', 'Mwananchi', 'Home Essentials', 'Kenya Furniture', 'Decor Kenya'],
    'Automotive': ['Castrol', 'Shell', 'Total', 'Mobil', 'Kenya Auto', 'Ride Safe', 'Boda Boda Pro'],
    'Services': ['Safaricom', 'Airtel', 'Telkom', 'Equitel', 'M-Pesa', 'Airtel Money', 'T-Kash', 'Betika', 'SportPesa']
}

# ------------------------------------------------------------
# Helper to inject data quality issues (same as before)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Load suppliers (create placeholders if missing)
# ------------------------------------------------------------
def load_suppliers():
    suppliers_file = os.path.join('bronze', 'suppliers', 'suppliers_raw.csv')
    if os.path.exists(suppliers_file):
        suppliers_df = pd.read_csv(suppliers_file)
        # Get distinct supplier IDs (current version only)
        # For simplicity, we'll use the first occurrence of each supplier_id
        suppliers = suppliers_df.groupby('supplier_id').first().reset_index()
        supplier_ids = suppliers['supplier_id'].tolist()
        print(f"Loaded {len(supplier_ids)} suppliers from {suppliers_file}")
        return supplier_ids
    else:
        print("Warning: suppliers_raw.csv not found. Generating placeholder supplier IDs.")
        # Generate 200 placeholder supplier IDs (matching the expected number)
        supplier_ids = [f"SUP-{i+1:04d}" for i in range(200)]
        return supplier_ids

# ------------------------------------------------------------
# Main generation function
# ------------------------------------------------------------
def generate_products():
    print("Generating Products...")
    out_dir = os.path.join('bronze', 'products')
    os.makedirs(out_dir, exist_ok=True)

    supplier_ids = load_suppliers()
    total_base_products = 5000   # target base products (not counting versions)
    rows = []
    product_counter = 1

    for category, subcats in PRODUCT_CATEGORIES.items():
        for subcategory, product_names in subcats.items():
            # Number of base products per subcategory: roughly proportional
            # We'll allocate to reach total_base_products
            # For simplicity, we'll just loop until we have enough, but better to distribute.
            pass

    # Better: iterate through categories/subcategories and assign a portion
    # We'll calculate total slots needed per subcategory based on its number of names
    # and the total desired base products.
    # First, build a list of all (category, subcategory, product_name) combinations.
    combos = []
    for cat, subcats in PRODUCT_CATEGORIES.items():
        for subcat, names in subcats.items():
            for name in names:
                combos.append((cat, subcat, name))

    # We need 5000 base products. Each combo can generate multiple products
    # by adding brand/size variations. We'll assign a random number between 1 and 5 per combo.
    # There are about 120 combos; that would give ~120*3 = 360, not enough. So we need more combos.
    # Actually the product names list per subcategory is limited; we should generate many variants.
    # We'll treat each combo as a base, and for each we create several products with different brands/sizes.
    # To reach 5000, we can generate products by iterating over combos repeatedly with different suffixes.

    # Let's instead generate base products by iterating over a range and randomly picking category/subcat/product.
    # We'll keep a set to avoid exact duplicates (but duplicates are allowed with different IDs).
    # We'll just generate 5000 base products randomly from the available categories.

    base_products = []
    for i in range(total_base_products):
        cat = random.choice(list(PRODUCT_CATEGORIES.keys()))
        subcat = random.choice(list(PRODUCT_CATEGORIES[cat].keys()))
        product_base = random.choice(PRODUCT_CATEGORIES[cat][subcat])
        brand = random.choice(KENYAN_BRANDS.get(cat, ['Generic']))
        size = random.choice(['Regular','Large','Small','Family Pack','Economy','Premium'])
        product_name = f"{brand} {product_base} {size}"
        # Avoid exact same name? Not necessary; duplicates reflect reality.
        base_products.append({
            'category': cat,
            'subcategory': subcat,
            'product_base': product_base,
            'brand': brand,
            'product_name': product_name
        })

    # Now generate versions for each base product
    for idx, base in enumerate(base_products):
        product_id = f"PROD-{idx+1:04d}"

        # Version 1: introduced sometime between 2010 and START_DATE? Actually must be >= START_DATE.
        # We'll set introduction_date between 2010 and 2025, but if before START_DATE, clamp to START_DATE.
        intro_year = random.randint(2010, 2025)
        intro_month = random.randint(1,12)
        intro_day = random.randint(1,28)
        intro_date = date(intro_year, intro_month, intro_day)
        if intro_date < START_DATE:
            intro_date = START_DATE
        if intro_date > END_DATE:
            intro_date = END_DATE

        # Determine if product is active (90% active)
        is_active = random.random() < 0.9
        discontinued_date = None
        if not is_active:
            # discontinued after some time
            discontinue_offset = random.randint(30, 1000)
            discontinue_date = intro_date + timedelta(days=discontinue_offset)
            if discontinue_date > END_DATE:
                discontinue_date = END_DATE
            discontinued_date = discontinue_date
            # valid_to for the last version will be set to discontinued_date
        else:
            discontinued_date = None

        # Choose supplier
        supplier_id = random.choice(supplier_ids)

        # Cost and price based on category (realistic pricing for Kenya)
        category = base['category']
        
        # Define realistic price ranges by category
        if category == 'FMCG':
            cost = round(np.random.uniform(10, 300), 2)  # Flour, sugar, oil, etc
            margin = np.random.uniform(0.20, 0.40)  # 20-40% margin on groceries
        elif category == 'Fresh':
            cost = round(np.random.uniform(20, 400), 2)  # Vegetables, fruit, meat
            margin = np.random.uniform(0.25, 0.45)  # 25-45% margin
        elif category == 'Non-Food':
            # Split between cheaper clothes/stationery and expensive electronics
            if base['subcategory'] in ['Electronics', 'Home Appliances']:
                cost = round(np.random.uniform(5000, 50000), 2)  # Expensive electronics
                margin = np.random.uniform(0.15, 0.35)  # Lower margin on expensive items
            elif base['subcategory'] in ['Clothing', 'Footwear']:
                cost = round(np.random.uniform(200, 2500), 2)
                margin = np.random.uniform(0.40, 0.60)  # Higher margin on apparel
            else:  # Stationery, etc
                cost = round(np.random.uniform(20, 500), 2)
                margin = np.random.uniform(0.30, 0.50)
        elif category == 'Health & Wellness':
            cost = round(np.random.uniform(50, 2500), 2)  # Pharmacy, supplements
            margin = np.random.uniform(0.25, 0.45)
        elif category == 'Beauty & Fashion':
            cost = round(np.random.uniform(100, 5000), 2)  # Cosmetics, perfume
            margin = np.random.uniform(0.35, 0.55)
        elif category == 'Home & Living':
            cost = round(np.random.uniform(200, 15000), 2)  # Furniture, décor
            margin = np.random.uniform(0.30, 0.50)
        elif category == 'Automotive':
            cost = round(np.random.uniform(500, 10000), 2)  # Car/bike products
            margin = np.random.uniform(0.20, 0.40)
        else:  # Services, Lottery, etc
            cost = round(np.random.uniform(10, 2000), 2)
            margin = np.random.uniform(0.10, 0.30)  # Lower margin on services
        
        price = round(cost * (1 + margin), 2)
        margin_pct = round(margin * 100, 1)

        # Version 1 row
        valid_from = intro_date
        valid_to = None  # will be updated if changes occur

        rows.append([
            product_id,
            valid_from.isoformat(),
            None,
            base['product_name'],
            base['category'],
            base['subcategory'],
            base['brand'],
            supplier_id,
            cost,
            price,
            margin_pct,
            intro_date.isoformat(),
            discontinued_date.isoformat() if discontinued_date else None,
            is_active
        ])

        # Simulate changes: ~30% of products have at least one change (price, supplier, margin)
        num_changes = 0
        if random.random() < 0.3:
            num_changes = random.randint(1, 3)  # up to 3 changes over time

        current_valid_from = valid_from
        current_cost = cost
        current_price = price
        current_margin = margin_pct
        current_supplier = supplier_id
        current_is_active = is_active

        for change_num in range(num_changes):
            # Change date must be after current_valid_from and before END_DATE
            earliest_change = current_valid_from + timedelta(days=60)
            latest_change = END_DATE - timedelta(days=1)
            
            if earliest_change >= latest_change:
                break
            
            change_date = fake.date_between(
                start_date=earliest_change,
                end_date=latest_change
            )
            # Close previous version
            rows[-1][2] = change_date.isoformat()

            # Decide what changes: maybe price, maybe supplier, maybe margin (implied by price/cost change)
            change_type = random.choice(['price', 'supplier', 'both'])
            if change_type in ['price', 'both']:
                # Change price (and possibly cost)
                cost_change = np.random.uniform(0.8, 1.2)  # ±20%
                current_cost = round(current_cost * cost_change, 2)
                price_change = np.random.uniform(0.85, 1.25)
                current_price = round(current_price * price_change, 2)
                current_margin = round(((current_price - current_cost) / current_cost) * 100, 1) if current_cost > 0 else 0
            if change_type in ['supplier', 'both']:
                current_supplier = random.choice(supplier_ids)

            # If product becomes inactive mid-way, we need to handle that.
            # We'll keep is_active as originally set unless we decide to discontinue later.
            # But if the product was already inactive, we shouldn't add more versions after discontinuation.
            # We'll enforce that changes stop when the product is discontinued.
            # So check if current date is after discontinued_date (if any)
            if discontinued_date and change_date >= discontinued_date:
                # This change would be after discontinuation – skip and stop
                break

            # Add new version
            rows.append([
                product_id,
                change_date.isoformat(),
                None,
                base['product_name'],
                base['category'],
                base['subcategory'],
                base['brand'],
                current_supplier,
                current_cost,
                current_price,
                current_margin,
                intro_date.isoformat(),  # introduction date never changes
                discontinued_date.isoformat() if discontinued_date else None,
                current_is_active
            ])
            current_valid_from = change_date

        # After all changes, if product is inactive, set the final valid_to to discontinued_date
        if not is_active and discontinued_date:
            # The last version should have valid_to = discontinued_date
            # But we already set discontinued_date in the row, and valid_to is None.
            # We should set valid_to of the final version to discontinued_date.
            # The last added row has valid_to None; we need to update it.
            rows[-1][2] = discontinued_date.isoformat()
        # else final version valid_to remains None

    # Build DataFrame
    columns = [
        'product_id', 'valid_from', 'valid_to', 'product_name',
        'category', 'subcategory', 'brand', 'supplier_id',
        'unit_cost_kes', 'retail_price_kes', 'margin_percentage',
        'introduction_date', 'discontinued_date', 'is_active'
    ]
    df = pd.DataFrame(rows, columns=columns)

    # Inject data quality issues
    df = inject_issues(
        df,
        frac_missing=0.02,
        frac_duplicate=0.01,
        missing_cols=['supplier_id', 'brand', 'category'],
        date_cols=['valid_from', 'valid_to', 'introduction_date', 'discontinued_date'],
        int_cols=['unit_cost_kes', 'retail_price_kes']  # allow negative prices
    )

    # Save
    out_file = os.path.join(out_dir, 'products_raw.csv')
    df.to_csv(out_file, index=False)
    print(f"  -> {len(df):,} rows written to {out_file}")

if __name__ == '__main__':
    generate_products()