import re

with open(r'C:\mark app\mark_aap\lib/data/repositories/customer_repository.dart') as f:
    cr = f.read()

with open(r'C:\mark app\mark_aap\lib/data/repositories/customer_transaction_repository.dart') as f:
    ctr = f.read()

cr_ops = re.findall(r"'[A-Z][A-Z_]*'", cr)
ctr_ops = re.findall(r"'[A-Z][A-Z_]*'", ctr)

print("=== customer_repository.dart ===")
for op in sorted(set(cr_ops)):
    print(f"  {op}")

print("\n=== customer_transaction_repository.dart ===")
for op in sorted(set(ctr_ops)):
    print(f"  {op}")