#!/usr/bin/env python3
"""Report semantic xcstrings keys (dotted identifiers) missing a ja translation."""
import json
import re
import sys

PATH = "SnapKei/Resources/Localizable.xcstrings"
SEMANTIC = re.compile(r"^[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$")

with open(PATH) as f:
    catalog = json.load(f)

missing = []
for key, value in sorted(catalog["strings"].items()):
    if not SEMANTIC.match(key):
        continue
    ja = value.get("localizations", {}).get("ja", {}).get("stringUnit", {})
    if ja.get("state") != "translated" or not ja.get("value"):
        missing.append(key)

if missing:
    print("Semantic keys missing ja translation:")
    for key in missing:
        print(f"  {key}")
    sys.exit(1)

print("OK: all semantic keys have ja translations.")
