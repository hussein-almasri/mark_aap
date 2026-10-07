#!/usr/bin/env python3
import sys

with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

checks = []

# Issue 1: Customer Update Authorization
checks.append(('Issue 1: Update has Admin check', 'isAdmin(storeId)' in content))

# Issue 2: Customer Read Visibility  
checks.append(('Issue 2: Customer read has Admin+Active', 'get(resource.path)' in content and 'isActive' in content))

# Issue 3: Transaction Read Access
checks.append(('Issue 3: Transaction read has isActive', 'get(/databases' in content and 'isActive' in content))

# Issue 4: Customer Name Claim - companyId vs customerId
cname_idx = content.find('match /customerNameKeys')
if cname_idx >= 0:
    snippet = content[cname_idx:cname_idx+500]
    checks.append(('Issue 4: customerNameKeys uses customerId', 'customerId' in snippet and 'companyId' not in snippet))
else:
    checks.append(('Issue 4: customerNameKeys exists', False))

# Issue 5: Customer Transaction Cancellation
checks.append(('Issue 5: Cancellation mentions CANCELLED', 'CANCELLED' in content))

# Issue 6: Customer Create Validation
checks.append(('Issue 6: Create validates fields', 'request.resource.data.keys().hasAll' in content and 'createdBy == request.auth.uid' in content))

# Issue 7: Customer Update Validation
checks.append(('Issue 7: Update prevents deleted', "'deleted' not in request.resource.data" in content))

# Issue 8: Transaction Create validation
checks.append(('Issue 8: Transaction create amount/type', 'amountFils > 0' in content and "\"type in ['DEBT', 'PAYMENT']\" in content)))

# Issue 9: Operation types
checks.append(('Issue 9: Operation types exist', "CREATE_CUSTOMER_DEBT" in content or "CREATE_CUSTOMER_PAYMENT" in content))

results = []
for name, result in checks:
    status = "PASS" if result else "FAIL/MISSING"
    results.append(f"  {name}: {status}")
    print(results[-1])

missing = [name for name, _ in checks if not _[1]]
print(f"\n{len(missing)} issues need attention out of {len(checks)} checks")