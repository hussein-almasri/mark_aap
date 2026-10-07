with open(r'C:\mark app\mark_aap\firestore.rules') as f:
    content = f.read()

# Find the validOperationFields function and the type list
import re
match = re.search(r"data\.type in \[(.*?)\]", content)
if match:
    types_str = match.group(1)
    print("Current type list:")
    print(types_str)
    print()
    
    # Add customer operation types
    customer_types = [", 'CREATE_CUSTOMER_DEBT'", ", 'CREATE_CUSTOMER_PAYMENT'", 
                      ", 'CANCEL_CUSTOMER_TRANSACTION'", ", 'ADMIN_CANCEL_CUSTOMER_TRANSACTION'"]
    new_types_str = types_str + ''.join(customer_types)
    print("\nNew type list:")
    print(new_types_str)
    
    # Replace in content
    new_content = content.replace(types_str, new_types_str)
    with open(r'C:\mark app\mark_aap\firestore.rules', 'w') as f:
        f.write(new_content)
    print("\nFile updated successfully")
else:
    print("Could not find type list")