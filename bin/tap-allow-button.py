#!/usr/bin/env python3
# Reads /tmp/uidump.xml and taps the first Allow/OK/Connect button found.
# Uses proper XML parsing so attribute order doesn't matter.
# Exit 0 on successful tap, 1 if no button found.
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

try:
    tree = ET.parse('/tmp/uidump.xml')
except Exception:
    sys.exit(1)

TARGET_TEXTS = {'Allow', 'OK', 'Connect', 'Set up VPN', 'Accept'}
TARGET_IDS = {
    'com.android.permissioncontroller:id/permission_allow_button',
    'android:id/button1',
}

for node in tree.iter('node'):
    text = node.get('text', '')
    rid = node.get('resource-id', '')
    clickable = node.get('clickable', 'false')
    bounds = node.get('bounds', '')

    if (text in TARGET_TEXTS or rid in TARGET_IDS) and clickable == 'true' and bounds:
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
            print(f'[grant-vpn] tap ({cx},{cy}) text="{text}" id="{rid}"')
            subprocess.run(
                ['adb', 'shell', 'input', 'tap', str(cx), str(cy)], check=True
            )
            sys.exit(0)

sys.exit(1)
