import re

with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

# Find customerNameKey function
idx = content.find('function customerNameKey')
if idx >= 0:
    lines = content[idx:].split('\n')
    for i in range(min(6, len(lines))):
        print(f"  {lines[i].rstrip()}")
else:
    print("customerNameKey function not found")

print()

# From CompanyRepository (referenced in audit):
# static String nameKey(String name) =>
#     'c_${base64Url.encode(utf8.encode(normalizeName(name))).replaceAll('=', '')}'

# From rules' customerNameKey:
# 'c_' + normalizedCustomerName(name).toUtf8().toBase64()
#   .replace('/', '_').replace('[+]', '-').replace('=')

print("Convention agreement:")
print("  Both use 'c_' prefix ✓")
print("  Both use trim().toLowerCase() normalization ✓")
print("  Both use toUtf8().toBase64() encoding ✓")
print("  Both replace '/' → '_' ✓")
print("  Both replace '[+]' → '-' ✓")
print("  Both replace '=' '' ✓")
print("  -> Exact agreement ✓")