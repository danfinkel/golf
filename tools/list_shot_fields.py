"""Lists every field TrackMan can return for a shot's measurement, so the
deep dive can request impact location and other numbers. Read-only.

Usage:
    python3 tools/list_shot_fields.py path/to/token
"""
import sys

from find_handicap_field import base_type, describe, token


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    auth = token(sys.argv[1])
    stroke = describe(auth, "Stroke")
    if not stroke:
        sys.exit("No Stroke type found.")
    for field in stroke.get("fields") or []:
        inner = base_type(field["type"])
        print(f"stroke.{field['name']}  ({inner.get('name')})")
        if inner.get("kind") == "OBJECT" and field["name"] in ("measurement", "clubData", "normalizedMeasurement"):
            for sub in describe(auth, inner["name"]).get("fields") or []:
                print(f"  {field['name']}.{sub['name']}  ({base_type(sub['type']).get('name')})")


if __name__ == "__main__":
    main()
