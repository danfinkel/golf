"""Lists TrackMan GraphQL fields that look like a handicap, so the app can
query the right one. Read-only: it only asks the API to describe itself.

Usage (with a bearer token copied from the portal, as in the POC):
    python3 tools/find_handicap_field.py path/to/token
"""
import json
import re
import sys
import urllib.request

URL = "https://api.trackmangolf.com/graphql"
PATTERN = re.compile(r"hcp|handicap", re.IGNORECASE)

TYPE_QUERY = """
query Describe($name: String!) {
  __type(name: $name) { name fields { name type { name kind ofType { name kind ofType { name } } } } }
}
"""


def token(path):
    raw = open(path).read().strip()
    return raw if raw.lower().startswith("bearer ") else f"Bearer {raw}"


def describe(auth, name):
    body = json.dumps({"operationName": "Describe", "query": TYPE_QUERY, "variables": {"name": name}}).encode()
    request = urllib.request.Request(URL + "?fe_query=Describe", data=body, headers={
        "Authorization": auth,
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Origin": "https://portal.trackmangolf.com",
        "Referer": "https://portal.trackmangolf.com/",
    })
    payload = json.load(urllib.request.urlopen(request, timeout=30))
    if payload.get("errors"):
        sys.exit("TrackMan refused the schema query: " + json.dumps(payload["errors"])[:300])
    return (payload.get("data") or {}).get("__type") or {}


def base_type(t):
    while t and t.get("ofType"):
        t = t["ofType"]
    return t or {}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    auth = token(sys.argv[1])
    seen, queue, hits = set(), [("Me", "me")], []
    while queue and len(seen) < 40:
        type_name, path = queue.pop(0)
        if type_name in seen:
            continue
        seen.add(type_name)
        for field in describe(auth, type_name).get("fields") or []:
            inner = base_type(field["type"])
            where = f"{path}.{field['name']}"
            if PATTERN.search(field["name"]):
                hits.append(f"{where}  ({inner.get('name')})")
            if inner.get("kind") == "OBJECT" and path.count(".") < 2:
                queue.append((inner["name"], where))
    print("\n".join(hits) if hits else "No handicap-like fields found under me.")


if __name__ == "__main__":
    main()
