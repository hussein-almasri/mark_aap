with open(r'C:\mark app\mark_aap\test\firestore_rules\rules.test.mjs') as f:
    lines = f.readlines()
for i in range(1400, min(1800, len(lines))):
    line = lines[i].strip()
    if line.startswith('test('):
        print(f'{i+1}: {line[:250]}')