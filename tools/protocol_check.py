"""Validate agent-town protocol batches against protocol/schema/v1.schema.json.

Standard library only. Implements the JSON Schema keywords the v1 schema uses:
type, const, enum, required, properties, items, minLength, maxLength,
minimum, maximum, $ref (local), allOf, oneOf.

Usage:
    python3 tools/protocol_check.py protocol/fixtures/*.json
"""

import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCHEMA_PATH = os.path.join(ROOT, "protocol", "schema", "v1.schema.json")

_TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
}


def load_schema():
    with open(SCHEMA_PATH) as fh:
        return json.load(fh)


def _resolve(root, ref):
    if not ref.startswith("#/"):
        raise ValueError(f"only local refs are supported: {ref}")
    node = root
    for part in ref[2:].split("/"):
        node = node[part]
    return node


def _is_type(value, t):
    if t == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if t == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return isinstance(value, _TYPES[t])


def errors(value, schema, root, path="$"):
    """Return a list of error strings; empty when the value is valid."""
    errs = []
    if "$ref" in schema:
        errs += errors(value, _resolve(root, schema["$ref"]), root, path)
    if "allOf" in schema:
        for sub in schema["allOf"]:
            errs += errors(value, sub, root, path)
    if "oneOf" in schema:
        matches = [s for s in schema["oneOf"] if not errors(value, s, root, path)]
        if len(matches) != 1:
            hint = ""
            if isinstance(value, dict) and "type" in value:
                hint = f" (type {value['type']!r})"
                # Report the matching branch's errors to make failures readable.
                for s in schema["oneOf"]:
                    ref = s.get("$ref", "")
                    if ref.endswith("/" + str(value["type"])):
                        errs += errors(value, s, root, path)
                        return errs
            errs.append(f"{path}: matches {len(matches)} of oneOf, expected 1{hint}")
    if "type" in schema and not _is_type(value, schema["type"]):
        errs.append(f"{path}: expected {schema['type']}")
        return errs
    if "const" in schema and value != schema["const"]:
        errs.append(f"{path}: expected {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errs.append(f"{path}: {value!r} not in {schema['enum']}")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errs.append(f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errs.append(f"{path}: longer than {schema['maxLength']}")
    if _is_type(value, "number"):
        if "minimum" in schema and value < schema["minimum"]:
            errs.append(f"{path}: below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errs.append(f"{path}: above {schema['maximum']}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errs.append(f"{path}: missing {key!r}")
        for key, sub in schema.get("properties", {}).items():
            if key in value:
                errs += errors(value[key], sub, root, f"{path}.{key}")
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            errs += errors(item, schema["items"], root, f"{path}[{i}]")
    return errs


def check_batch(batch, schema=None):
    """Validate a batch and the per-session seq order. Returns error strings."""
    schema = schema or load_schema()
    errs = errors(batch, schema, schema)
    last = {}
    for i, ev in enumerate(batch.get("events", []) if isinstance(batch, dict) else []):
        sid, seq = ev.get("sessionId"), ev.get("seq")
        if isinstance(seq, int) and sid in last and seq != last[sid] + 1:
            errs.append(f"$.events[{i}]: seq {seq} after {last[sid]} for session {sid}")
        if isinstance(seq, int):
            last[sid] = seq
    return errs


def main(paths):
    schema = load_schema()
    failed = 0
    for p in paths:
        with open(p) as fh:
            errs = check_batch(json.load(fh), schema)
        status = "ok" if not errs else f"{len(errs)} error(s)"
        print(f"{p}: {status}")
        for e in errs:
            print(f"  {e}")
        failed += bool(errs)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
