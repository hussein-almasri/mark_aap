with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

# Check for amountFils > 0 and type in DEBT/PAYMENT
has_amount = 'amountFils > 0' in content
has_type = "\"type in ['DEBT', 'PAYMENT']\" in content" or "type in ['DEBT', 'PAYMENT']" in content

# Show the transaction create rule
idx = content.find('allow create: if isFinancialStoreMember(storeId)')
if idx >= 0:
    print('Transaction create rule (first 600 chars):')
    print(content[idx:idx+600])
    
print()
print('has_amountFils > 0:', has_amount)
print('has_type check:', has_type)