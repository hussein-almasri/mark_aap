with open(r'C:\mark app\mark_aap\lib/data/repositories/customer_repository.dart') as f:
    content = f.read()

# Find strings that look like operation types
import re
ops = re.findall(r"'[A-Z][A-Z_]*'", content)
print('customer_repository.dart - unique operation strings:')
for op in sorted(set(ops)):
    print(f'  {op}')

print()

with open(r'C:\mark app\mark_aap\lib/data/repositories/customer_transaction_repository.dart') as f:
    content = f.read()
ops = re.findall(r"'[A-Z][A-Z_]*'", content)
print('customer_transaction_repository.dart - unique operation strings:')
for op in sorted(set(ops)):
    print(f'  {op}')