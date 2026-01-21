import re

def find_anomalous_zig_functions(functions_file, zig_file):
    # 1. Load function names from functions.txt
    try:
        with open(functions_file, 'r') as f:
            target_functions = [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        print(f"Error: {functions_file} not found.")
        return

    # 2. Read Zig file and strip comments
    code_content = []
    try:
        with open(zig_file, 'r') as f:
            for line in f:
                # Remove everything after // on a line
                clean_line = line.split('//')[0]
                code_content.append(clean_line)
        
        full_text = " ".join(code_content)
    except FileNotFoundError:
        print(f"Error: {zig_file} not found.")
        return

    # 3. Search for occurrences using Regex
    print(f"{'Function Name':<70} | {'Occurrences':<12} ({len(target_functions)})")
    print("-" * 45)

    missing = 0
    multiple = 0
    for func in target_functions:
        # \b ensures word boundaries (so 'foo' doesn't match 'foobar')
        pattern = rf"\b{re.escape(func)}\b"
        matches = re.findall(pattern, full_text)
        count = len(matches)

        if count == 0: missing += 1
        if count > 1: multiple += 1

        if count == 0 or count > 1:
            status = "MISSING" if count == 0 else "MULTIPLE"
            print(f"{func:<70} | {count:<12} ({status})")

    print(f"Missing: {missing}\nMultiple: {multiple}")

if __name__ == "__main__":
    find_anomalous_zig_functions('functions.list', 'root.zig')
