#!/usr/bin/env python3
import re

with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

checks = []

# 1. Check for customer rules
checks.append(('customers match block', 'match /customers' in content))

# 2. Check for customerNameKeys
checks.append(('customerNameKeys match block', 'match /customerNameKeys' in content))

# 3. Check transaction rules
checks.append(('customer transactions', 'match /customers' in content and 'transactions' in content))

# 4. Check operation types
operation_types = re.findall(r"'[A-Z_]+'", content)
checks.append(('operation types count', len(operation_types)))

# 5. Issue 1: Employee update via updatedBy
checks.append(('Issue 1: updatedBy == request.auth.uid', 'updatedBy == request.auth.uid' in content))

# 6. Issue 2: isActive references
checks.append(('Issue 2: isActive references', 'isActive' in content))

# 7. Issue 3: Transaction createdBy
checks.append(('Issue 3: resource.data.createdBy', 'resource.data.createdBy' in content))

# 8. Issue 4: companyId in customerNameKeys
checks.append(('Issue 4: companyId in customerNameKeys', 'companyId' in content))

# 9. Issue 5: Cancellation rules
checks.append(('Issue 5: cancellation rules', 'CANCELLED' in content and 'ACTIVE' in content))

# 10. Issue 6: Create validation
checks.append(('Issue 6: create validation', 'createdAt == request.time' in content))

# 11. Issue 7: Update validation
checks.append(('Issue 7: update validation', 'updatedAt' in content))

# 12. Issue 8: Transaction create
checks.append(('Issue 8: transaction create', 'amountFils' in content and 'type' in content))

# 13. Issue 9: Operations
checks.append(('Issue 9: operations block', 'match /operations' in content))

# 14. Issue 10: Tests
checks.append(('Issue 10: tests infrastructure', 'FirestoreRules' in content or 'firestore.rules' in content.lower()))

print("=" * 60)
print("FIRESTORE.RULES CURRENT STATE ANALYSIS")
print("=" * 60)
for name, result in checks:
    status = "PASS" if result else "FAIL/MISSING"
    print(f"  {name}: {status}")

print("=" * 60)

# Show which issues need fixing
missing = [name for name, result in checks if not result]
if missing:
    print(f"\nMissing/{'Need fixing':.{50}s} {len(missing)} issues")
    for m in missing:
        print(f"    - {m}")
else:
    print("\nAll checks passed!")