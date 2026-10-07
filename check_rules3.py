#!/usr/bin/env python3
import sys

with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

# Issue 1: Customer Update Authorization - should have Admin check
issue1 = 'isAdmin(storeId)' in content

# Issue 2: Customer Read Visibility - should have Admin + isActive check  
issue2 = 'get(resource.path)' in content and 'isActive' in content

# Issue 3: Transaction Read Access - should have isActive check
issue3 = 'get(/databases' in content and 'isActive' in content

# Issue 4: Customer Name Keys - should use customerId not companyId
cname_start = content.find('match /customerNameKeys')
if cname_start >= 0:
    snippet = content[cname_start:cname_start+500]
    issue4 = 'customerId' in snippet and 'companyId' not in snippet
else:
    issue4 = False

# Issue 5: Cancellation - should mention CANCELLED
issue5 = 'CANCELLED' in content

# Issue 6: Create validation - should have keys.hasAll and createdBy
issue6 = 'request.resource.data.keys().hasAll' in content and 'createdBy == request.auth.uid' in content

# Issue 7: Update validation - should prevent deleted field
issue7 = "'deleted' not in request.resource.data" in content

# Issue 8: Transaction create - should validate amount and type
issue8 = 'amountFils > 0' in content and "type in ['DEBT', 'PAYMENT']" in content

# Issue 9: Operation types
issue9 = "CREATE_CUSTOMER_DEBT" in content or "CREATE_CUSTOMER_PAYMENT" in content

results = [
    ("1. Update has Admin check", issue1),
    ("2. Customer read has Admin+Active", issue2),
    ("3. Transaction read has isActive", issue3),
    ("4. customerNameKeys uses customerId", issue4),
    ("5. Cancellation mentions CANCELLED", issue5),
    ("6. Create validates fields", issue6),
    ("7. Update prevents deleted", issue7),
    ("8. Transaction create amount/type", issue8),
    ("9. Operation types exist", issue9),
]

print("=" * 60)
for name, result in results:
    status = "PASS" if result else "FAIL/MISSING"
    print(f"  {name}: {status}")

missing = [name for name, r in results if not r]
print(f"\n{len(missing)} of 9 checks need attention")
for m in missing:
    print(f"  - {m}")