#!/usr/bin/env python3
"""
run_all_generators.py

Master script to execute all data generation scripts in the correct dependency order.

Execution Order:
1. Base/Independent: suppliers, stores, campaigns, competitors, economic, gis
2. CRM & Loyalty: crm, loyalty
3. HR & Operations: hr, shifts, time_tracking
4. Products: products (depends on suppliers)
5. Procurement: purchase_orders, goods_receipts, inventory, inventory_snapshots
6. Sales: pos, ecommerce, returns, gift_cards
7. Marketing: promotions
8. Customer Service: customer_service, feedback
9. Finance: financials

This ensures all dependencies are satisfied.
"""

import os
import subprocess
import sys
from datetime import datetime

# Define execution order
GENERATORS = [
    # Stage 1: Independent generators
    ('generate_suppliers.py', 'Suppliers (Type 2 SCD)'),
    ('generate_stores.py', 'Stores (Type 2 SCD)'),
    ('generate_campaigns.py', 'Marketing Campaigns'),
    ('generate_competitors.py', 'Competitor Intelligence'),
    ('generate_economic.py', 'Economic Indicators'),
    ('generate_gis.py', 'GIS Data'),
    
    # Stage 2: CRM & Loyalty
    ('generate_crm.py', 'CRM/Customers (Type 2 SCD)'),
    ('generate_loyalty.py', 'Loyalty Program (depends on CRM)'),
    
    # Stage 3: HR & Operations
    ('generate_hr.py', 'HR/Employees (Type 2 SCD, depends on Stores)'),
    ('generate_shifts.py', 'Employee Shifts (depends on HR)'),
    ('generate_time_tracking.py', 'Time Tracking (depends on HR)'),
    
    # Stage 4: Products
    ('generate_products.py', 'Products (Type 2 SCD, depends on Suppliers)'),
    
    # Stage 5: Procurement
    ('generate_purchase_orders.py', 'Purchase Orders (depends on Suppliers, Products)'),
    ('generate_goods_receipts.py', 'Goods Receipts (depends on POs)'),
    ('generate_inventory.py', 'Inventory Movements (depends on all above)'),
    ('generate_inventory_snapshots.py', 'Inventory Snapshots (depends on Inventory)'),
    
    # Stage 6: Sales
    ('generate_pos.py', 'POS Transactions (depends on Stores, Products, CRM, HR)'),
    ('generate_ecommerce.py', 'E-commerce Orders (depends on Products, CRM)'),
    ('generate_returns.py', 'Returns (depends on POS, E-commerce)'),
    ('generate_gift_cards.py', 'Gift Cards'),
    
    # Stage 7: Marketing
    ('generate_promotions.py', 'Promotions'),
    
    # Stage 8: Customer Service
    ('generate_customer_service.py', 'Customer Service (depends on CRM)'),
    ('generate_feedback.py', 'Customer Feedback (depends on CRM)'),
    
    # Stage 9: Finance
    ('generate_financials.py', 'Financials (depends on Stores)'),
]

def run_generator(script_name):
    """Run a single generator script."""
    try:
        print(f"\n{'='*70}")
        print(f"  Running: {script_name}")
        print(f"{'='*70}")
        
        result = subprocess.run(
            [sys.executable, script_name],
            cwd=os.path.dirname(__file__),
            capture_output=False,
            text=True
        )
        
        if result.returncode != 0:
            print(f"ERROR: {script_name} failed with return code {result.returncode}")
            return False
        
        print(f"✓ {script_name} completed successfully")
        return True
        
    except Exception as e:
        print(f"ERROR running {script_name}: {str(e)}")
        return False

def main():
    """Execute all generators in order."""
    print("\n" + "="*70)
    print("  BLUE CANOPY KENYA DATA WAREHOUSE - SYNTHETIC DATA GENERATION")
    print("  Start Time:", datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    print("="*70)
    
    successful = []
    failed = []
    
    for script_name, description in GENERATORS:
        print(f"\n[{len(successful) + len(failed) + 1}/{len(GENERATORS)}] {description}")
        
        if run_generator(script_name):
            successful.append(script_name)
        else:
            failed.append(script_name)
            print(f"❌ Stopping due to failure in {script_name}")
            break
    
    # Summary
    print("\n" + "="*70)
    print("  SUMMARY")
    print("="*70)
    print(f"Successful: {len(successful)}/{len(GENERATORS)}")
    print(f"Failed: {len(failed)}/{len(GENERATORS)}")
    
    if successful:
        print("\n✓ Generated:")
        for script in successful:
            print(f"  - {script}")
    
    if failed:
        print("\n❌ Failed to generate:")
        for script in failed:
            print(f"  - {script}")
        return 1
    
    print("\nEnd Time:", datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    print("="*70)
    print("\n✓ All generators completed successfully!")
    print("Bronze layer data is ready in: bronze/")
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
