#!/usr/bin/env python3
"""Release / CI check for the Wealth Compass CloudKit schema (TO_IMPROVE #24).

The Swift source is the single source of truth for the sync schema:
  * record TYPES   — the `CloudSyncRecordType` enum raw values (WCTransaction, …)
  * record FIELDS  — the CKRecord keys `CloudKitSyncService` reads/writes (`record["…"]`)
This script extracts both from `CloudKitSyncService.swift` and compares them to the
EXPECTED manifest embedded below.

Two jobs:
  1. CI drift gate — if the source adds/removes a record type or field that the manifest
     doesn't know about, exit non-zero. That forces a human to (a) update this manifest and
     (b) update the CloudKit Dashboard / deploy the schema to PRODUCTION before shipping —
     the exact "easy to ship with a schema mismatch" failure #24 is about.
  2. Release checklist — on success, print the record types + fields to verify exist in the
     production container.

What it CANNOT do here: hit the live CloudKit container (needs credentials + network). It
verifies the source-derived schema is self-consistent and hasn't drifted from the manifest;
the printed checklist is what you confirm against the production container by hand.

Usage:
    python3 scripts/check_cloudkit_schema.py          # checklist + drift gate (exit 0/1)
    python3 scripts/check_cloudkit_schema.py --json    # machine-readable manifest to stdout
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# ── EXPECTED manifest (update DELIBERATELY, together with the CloudKit Dashboard) ──────────
# Record types the production container must define.
EXPECTED_TYPES = {
    "WCTransaction",
    "WCRecurringTransaction",
    "WCInvestment",
    "WCCryptoHolding",
    "WCLiability",
    "WCNetWorthSnapshot",
}

# Custom fields present on EVERY record type (the entity itself is encoded into `payload`;
# CloudKit adds its own system fields — recordName, recordChangeTag, *Timestamp — on top).
# CloudKit field types: Data→BYTES, Date→TIMESTAMP(DATE_TIME), Bool/Int→INT64, String→STRING.
EXPECTED_FIELDS = {
    "payload": "BYTES",
    "createdAt": "TIMESTAMP",
    "updatedAt": "TIMESTAMP",
    "clientModifiedAt": "TIMESTAMP",
    "deletedAt": "TIMESTAMP",
    "isDeleted": "INT64",
    "revision": "STRING",
    "schemaVersion": "INT64",
}

SOURCE_REL = "Sources/Shared/Services/CloudKitSyncService.swift"


def source_path() -> Path:
    # scripts/ lives at apple/WealthCompass/scripts/ ; the source is a sibling of scripts/.
    candidate = Path(__file__).resolve().parent.parent / SOURCE_REL
    if not candidate.exists():
        sys.exit(f"ERROR: cannot find {SOURCE_REL} relative to this script (looked at {candidate}).")
    return candidate


def extract(source: str) -> dict:
    enum_match = re.search(r"enum CloudSyncRecordType.*?\n\}", source, re.DOTALL)
    if not enum_match:
        sys.exit("ERROR: could not locate the `CloudSyncRecordType` enum — did it move or get renamed?")
    types = set(re.findall(r'=\s*"(WC\w+)"', enum_match.group(0)))

    # CKRecord subscript usage on any var ending in `record`/`Record` (record, serverRecord, …).
    fields = set(re.findall(r'[Rr]ecord\["(\w+)"\]', source))

    def const(name: str, pattern: str) -> str:
        m = re.search(pattern, source)
        return m.group(1) if m else f"<{name}: not found>"

    return {
        "types": types,
        "fields": fields,
        "container": const("container", r'containerIdentifier\s*=\s*"([^"]+)"'),
        "zone": const("zone", r'zoneName\s*=\s*"([^"]+)"'),
        "schema_version": const("schemaVersion", r"schemaVersion:\s*Int64\s*=\s*(\d+)"),
    }


def diff(expected: set, actual: set) -> tuple[set, set]:
    """Returns (missing_from_source, added_in_source_but_not_expected)."""
    return expected - actual, actual - expected


def main() -> int:
    src = extract(source_path().read_text())

    if "--json" in sys.argv:
        print(json.dumps({
            "container": src["container"],
            "zone": src["zone"],
            "schemaVersion": src["schema_version"],
            "recordTypes": sorted(src["types"]),
            "fields": EXPECTED_FIELDS,
        }, indent=2))
        # Still apply the drift gate so `--json` is CI-safe.

    types_missing, types_extra = diff(EXPECTED_TYPES, src["types"])
    fields_missing, fields_extra = diff(set(EXPECTED_FIELDS), src["fields"])

    drift = []
    if types_missing:
        drift.append(f"record type(s) in the manifest but NOT in source (removed?): {sorted(types_missing)}")
    if types_extra:
        drift.append(f"record type(s) in source but NOT in the manifest (added?): {sorted(types_extra)}")
    if fields_missing:
        drift.append(f"field(s) in the manifest but NOT read/written by source (removed?): {sorted(fields_missing)}")
    if fields_extra:
        drift.append(f"field(s) used by source but NOT in the manifest (added?): {sorted(fields_extra)}")

    if drift:
        print("✗ SCHEMA DRIFT — source no longer matches the expected manifest:\n", file=sys.stderr)
        for line in drift:
            print(f"  • {line}", file=sys.stderr)
        print(
            "\nAction: update EXPECTED_TYPES/EXPECTED_FIELDS in this script to match, AND update the\n"
            "CloudKit Dashboard schema (Development → deploy to PRODUCTION) before shipping.",
            file=sys.stderr,
        )
        return 1

    if "--json" in sys.argv:
        return 0

    # ── Release checklist ──────────────────────────────────────────────────────────────────
    width = max(len(f) for f in EXPECTED_FIELDS)
    print("Wealth Compass — CloudKit schema checklist  (derived from CloudKitSyncService.swift)")
    print("=" * 84)
    print(f"Container        : {src['container']}")
    print(f"Custom zone      : {src['zone']}")
    print(f"schemaVersion    : {src['schema_version']}  (value written into each record's `schemaVersion` field)")
    print()
    print("Verify the PRODUCTION container (CloudKit Dashboard → Schema → Record Types) defines")
    print(f"all {len(EXPECTED_TYPES)} record types below, each with these {len(EXPECTED_FIELDS)} custom fields:")
    print()
    print("  Record types:")
    for t in sorted(EXPECTED_TYPES):
        print(f"    • {t}")
    print()
    print("  Fields (identical on every type — the entity itself is encoded into `payload`):")
    for name, kind in sorted(EXPECTED_FIELDS.items()):
        print(f"    • {name.ljust(width)}  {kind}")
    print()
    print("  Notes:")
    print("    - CloudKit adds system fields automatically (recordName, recordChangeTag, *Timestamp).")
    print("    - Bool→INT64, Date→TIMESTAMP, Data→BYTES.")
    print("    - Deploy the schema to PRODUCTION (not just Development) before submitting a build.")
    print()
    print(f"✓ Source matches the expected manifest — no drift ({len(src['types'])} record types, {len(src['fields'])} fields).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
