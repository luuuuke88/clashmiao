#!/usr/bin/env python3
# Reads /tmp/uidump.xml and taps the first Allow/OK button found.
# Exit 0 on successful tap, 1 if no button found.
import re
import subprocess
import sys

try:
    xml = open('/tmp/uidump.xml').read()
except FileNotFoundError:
    sys.exit(1)

for pat in [
    r'resource-id="com\.android\.permissioncontroller:id/permission_allow_button"',
    r'resource-id="android:id/button1"',
    r'text="Allow"',
    r'text="OK"',
]:
    m = re.search(pat + r'[^/]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
    if m:
        x1, y1, x2, y2 = map(int, m.groups())
        cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
        print(f'[grant-vpn] tap ({cx},{cy})')
        subprocess.run(['adb', 'shell', 'input', 'tap', str(cx), str(cy)], check=True)
        sys.exit(0)

sys.exit(1)
