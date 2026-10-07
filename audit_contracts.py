import re
import os

files = {
    'customer_model': r'C:\mark app\mark_aap\lib/data/models/customer_model.dart',
    'customer_transaction_model': r'C:\mark app\mark_aap\lib/data/models/customer_transaction_model.dart',
    'customer_repository': r'C:\mark app\mark_aap\lib/data/repositories/customer_repository.dart',
    'customer_transaction_repository': r'C:\mark app\mark_aap\lib/data/repositories/customer_transaction_repository.dart',
}

for name, path in files.items():
    print("=" * 70)
    print(f"LAYER: {name.upper()}")
    print("=" * 70)
    with open(path) as f:
        content = f.read()
    
    # Find final field declarations
    pattern = r'final (\w+) (\w+);'
    fields = re.findall(pattern, content)
    
    for field in fields:
        print(f"  {field[0]:8s} {field[1]}")
    print()
PYEOF