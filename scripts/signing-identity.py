"""Select a local development identity without disclosing certificate subject names."""
import re
import subprocess
result = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True, text=True, check=False)
rows = re.findall(r'([0-9A-F]{40}) "(Apple Development:[^"]+)"', result.stdout)
print(rows[0][0] if rows else '-')
