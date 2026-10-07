with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

# Find operation type strings in the validOperationFields function
# Look for the pattern: data.type in ['CREATE_PURCHASE_INVOICE', 'CANCEL_PURCHASE_INVOICE', ...]
import re

# Extract the type list from validOperationFields
match = re.search(r"data\.type in \[(.*?)\]", content)
if match:
    types_str = match.group(1)
    types = [t.strip().strip('\"').strip("'") for t in types_str.split(',')]
    print("Operation types in validOperationFields:")
    for t in sorted(set(types)):
        print(f"  {t}")
else:
    print("Could not find operation type list")
    
# Also check for customer operation types
print("\nChecking for customer operation types:")
for co in ['CREATE_CUSTOMER_DEBT', 'CREATE_CUSTOMER_PAYMENT', 'CANCEL_CUSTOMER_TRANSACTION', 'ADMIN_CANCEL_CUSTOMER_TRANSACTION']:
    if co in content:
        print(f"  {co}: FOUND")
    else:
        print(f"  {co}: MISSING")