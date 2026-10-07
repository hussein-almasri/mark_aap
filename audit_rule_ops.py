import re

with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

match = re.search(r"data\.type in \[(.*?)\]", content)
if match:
    types_str = match.group(1)
    types = [t.strip().strip('"').strip("'") for t in types_str.split(',')]
    print("=== firestore.rules validOperationFields type list ===")
    for t in sorted(set(types)):
        print(f"  {t}")
else:
    print("Could not find type list")
PYEOF