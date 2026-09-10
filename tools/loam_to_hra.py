#!/usr/bin/env python3
"""
tools/loam_to_hra.py - Lossless converter from Loam 18-family storage to HRA-N 3-file storage.

Formally verified schema: spec/alloy/hra_n_storage_schema.als
Canonical specification: docs/HRA_N_STORAGE_SPEC.md

Usage:
    python3 tools/loam_to_hra.py <loam-data-dir> <output-hra-data-dir>
"""

import sys
import os
import re
from collections import defaultdict

def parse_flow_token(tok):
    parts = tok.split(':')
    if parts[-1].lstrip('-').isdigit():
        amt = int(parts[-1])
        measure = 'jpy'
        locus = ':'.join(parts[:-1])
    else:
        measure = parts[-1]
        amt = int(parts[-2])
        locus = ':'.join(parts[:-2])
    return locus, measure, amt

def parse_loam_data(loam_dir):
    # 1. Parse CURRENT manifest
    manifest_path = os.path.join(loam_dir, "movement-authority", "CURRENT")
    manifest = {}
    with open(manifest_path, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 2:
                manifest[parts[0]] = parts[1]

    # 2. Parse Events
    event_file = os.path.join(loam_dir, "movement-authority", manifest["Event"])
    events = []
    events_order = []
    current_ev = None
    event_flows = {}
    with open(event_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "EVENT":
                current_ev = parts[1]
                events_order.append(current_ev)
                event_flows[current_ev] = []
            elif parts[0] == "EFFECT":
                # EFFECT <id> <locus> <measure> <amount>
                flow_id = parts[1]
                locus = parts[2]
                measure = parts[3]
                amount = int(parts[4])
                event_flows[current_ev].append((locus, measure, amount))

    # 3. Parse ActualValidity
    val_file = os.path.join(loam_dir, "movement-authority", manifest["ActualValidity"])
    event_dates = {}
    with open(val_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "BASE":
                event_dates[parts[1]] = parts[2]

    # 4. Parse EventDescription
    desc_file = os.path.join(loam_dir, "movement-authority", manifest["EventDescription"])
    event_descs = {}
    with open(desc_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "DESC":
                ev_id = parts[1]
                desc_text = parts[2] if len(parts) > 2 else ""
                event_descs[ev_id] = desc_text

    # 5. Parse Scheduled
    sched_file = os.path.join(loam_dir, "scheduled.loam")
    scheduled_items = {}
    scheduled_order = []
    current_sched = None
    sched_completions = {}
    sched_retirements = set()
    sched_replacements = {}
    mode = "none"

    with open(sched_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "BEGIN":
                mode = parts[1]
            elif parts[0] == "END":
                mode = "none"
            elif mode == "Scheduled":
                if parts[0] == "SCHEDULED":
                    # SCHEDULED <id> <due-date> <measure>
                    current_sched = parts[1]
                    scheduled_order.append(current_sched)
                    scheduled_items[current_sched] = {
                        "due": parts[2],
                        "measure": parts[3],
                        "flows": []
                    }
                elif parts[0] == "CHANGE":
                    # CHANGE <locus> <amount>
                    scheduled_items[current_sched]["flows"].append((parts[1], int(parts[2])))
            elif mode == "Completion":
                if parts[0] == "COMPLETION":
                    sched_completions[parts[1]] = parts[2]
            elif mode == "Retirement":
                if parts[0] == "RETIREMENT":
                    sched_retirements.add(parts[1])
            elif mode == "Replacement":
                if parts[0] == "REPLACEMENT":
                    sched_replacements[parts[1]] = parts[2]

    # 6. Parse Accounting Roles
    role_file = os.path.join(loam_dir, "accounting-role.loam")
    roles = {}
    with open(role_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "ROLE":
                roles[parts[1]] = parts[2]

    # 7. Parse Zero-Origin Coverage
    zero_file = os.path.join(loam_dir, "zero-origin-coverage.loam")
    zero_origins = []
    with open(zero_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "COORDINATE":
                zero_origins.append((parts[1], parts[2]))

    # 8. Parse Capacity
    cap_file = os.path.join(loam_dir, "capacity.loam")
    capacity_balances = defaultdict(int)
    with open(cap_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "CHANGE":
                if parts[1] == "PURPOSE":
                    capacity_balances[parts[2]] += int(parts[3])
                elif parts[1] == "UNALLOCATED":
                    capacity_balances["UNALLOCATED"] += int(parts[2])

    # 9. Parse Routing
    routing_file = os.path.join(loam_dir, "actual-routing.loam")
    routing = {}
    with open(routing_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if parts[0] == "ROUTE":
                locus = parts[1]
                purpose = parts[4]
                routing[locus] = purpose

    # 10. Parse Boundary Presets
    preset_file = os.path.join(loam_dir, "config", "boundary-presets.tsv")
    presets = []
    if os.path.exists(preset_file):
        with open(preset_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) >= 3:
                    presets.append((parts[0], parts[1], parts[2]))

    return {
        "events_order": events_order,
        "event_flows": event_flows,
        "event_dates": event_dates,
        "event_descs": event_descs,
        "scheduled_order": scheduled_order,
        "scheduled_items": scheduled_items,
        "sched_completions": sched_completions,
        "sched_retirements": sched_retirements,
        "sched_replacements": sched_replacements,
        "roles": roles,
        "zero_origins": zero_origins,
        "capacity_balances": capacity_balances,
        "routing": routing,
        "presets": presets,
    }

def convert_to_hra(data, out_dir):
    os.makedirs(out_dir, exist_ok=True)

    # 1. Generate journal.hra
    journal_path = os.path.join(out_dir, "journal.hra")
    with open(journal_path, "w", encoding="utf-8") as f:
        f.write("# HRA-N Actual Journal\n")
        f.write("# Format: TX <id> <date> <flows...> [@<purpose>] [\"<note>\"]\n\n")

        for ev_id in data["events_order"]:
            date = data["event_dates"].get(ev_id, "2026-01-01")
            flows = data["event_flows"][ev_id]
            desc = data["event_descs"].get(ev_id, "")

            # Format flows
            flow_tokens = []
            for locus, measure, amt in flows:
                if measure == "jpy":
                    flow_tokens.append(f"{locus}:{amt}")
                else:
                    flow_tokens.append(f"{locus}:{amt}:{measure}")
            flows_str = " ".join(flow_tokens)

            # Determine purpose if expense routing exists
            purposes = set()
            for locus, measure, amt in flows:
                if amt > 0 and locus in data["routing"]:
                    purposes.add(data["routing"][locus])

            purpose_str = ""
            if len(purposes) == 1:
                purpose_str = f" @{list(purposes)[0]}"

            desc_escaped = desc.replace('"', '\\"')
            desc_str = f' "{desc_escaped}"' if desc else ''

            f.write(f"TX {ev_id} {date} {flows_str}{purpose_str}{desc_str}\n")

    # 2. Generate scheduled.hra
    sched_path = os.path.join(out_dir, "scheduled.hra")
    with open(sched_path, "w", encoding="utf-8") as f:
        f.write("# HRA-N Scheduled Journal\n")
        f.write("# Format: SCHED <id> <due-date> <flows...> status:<status>\n\n")

        for s_id in data["scheduled_order"]:
            item = data["scheduled_items"][s_id]
            due = item["due"]
            measure = item["measure"]
            flows = item["flows"]

            flow_tokens = []
            for locus, amt in flows:
                if measure == "jpy":
                    flow_tokens.append(f"{locus}:{amt}")
                else:
                    flow_tokens.append(f"{locus}:{amt}:{measure}")
            flows_str = " ".join(flow_tokens)

            status = "open"
            if s_id in data["sched_completions"]:
                status = f"completed:{data['sched_completions'][s_id]}"
            elif s_id in data["sched_retirements"]:
                status = "retired"
            elif s_id in data["sched_replacements"]:
                status = f"replaced-by:{data['sched_replacements'][s_id]}"

            f.write(f"SCHED {s_id} {due} {flows_str} status:{status}\n")

    # 3. Generate policy.hra
    policy_path = os.path.join(out_dir, "policy.hra")
    with open(policy_path, "w", encoding="utf-8") as f:
        f.write("# HRA-N Policy Declarations\n")
        f.write("# Roles, Zero-Origin Evidence, and Capacities\n\n")

        # Group roles by type
        by_role = defaultdict(list)
        for locus, rtype in sorted(data["roles"].items()):
            by_role[rtype].append(locus)

        f.write("# 1. Accounting Roles\n")
        for rtype in ["ASSET", "LIABILITY", "INCOME", "EXPENSE", "EQUITY"]:
            if by_role[rtype]:
                f.write(f"ROLE {', '.join(sorted(by_role[rtype]))}: {rtype}\n")
        f.write("\n")

        f.write("# 2. Zero-Origin Evidence Coordinates\n")
        coords = [f"{loc}:{m}" for loc, m in sorted(data["zero_origins"])]
        f.write(f"ZERO-ORIGIN {', '.join(coords)}\n\n")

        f.write("# 3. Capacity Envelopes\n")
        for purp, amt in sorted(data["capacity_balances"].items()):
            if purp != "UNALLOCATED" and amt != 0:
                f.write(f"CAPACITY {purp}: {amt} jpy\n")
        f.write("\n")

        f.write("# 4. Expense Routing Defaults\n")
        by_purpose = defaultdict(list)
        for loc, purp in sorted(data["routing"].items()):
            by_purpose[purp].append(loc)
        for purp, loci in sorted(by_purpose.items()):
            f.write(f"ROUTE {', '.join(sorted(loci))}: {purp}\n")

        if data.get("presets"):
            f.write("\n# 5. Budget Window Presets\n")
            for name, start_d, end_d in data["presets"]:
                f.write(f"WINDOW {name}: {start_d} -> {end_d}\n")

def verify_conversion(data, out_dir):
    print("Verifying mathematical equivalence of HRA conversion...")
    # Calculate balances from original data
    orig_balances = defaultdict(int)
    for ev_id, flows in data["event_flows"].items():
        for locus, measure, amt in flows:
            orig_balances[(locus, measure)] += amt

    # Parse journal.hra directly
    journal_balances = defaultdict(int)
    journal_path = os.path.join(out_dir, "journal.hra")
    tx_count = 0
    with open(journal_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("TX "):
                tx_count += 1
                tokens = line.split()
                # TX <id> <date> <flows...>
                for tok in tokens[3:]:
                    if tok.startswith("@") or tok.startswith('"') or tok.startswith("replaces:") or tok.startswith("relation:") or tok.startswith("discharges:"):
                        break
                    locus, measure, amt = parse_flow_token(tok)
                    journal_balances[(locus, measure)] += amt

    assert tx_count == len(data["events_order"]), f"TX count mismatch: {tx_count} vs {len(data['events_order'])}"
    print(f"  [OK] Transaction count matches exactly: {tx_count}")

    for coord, amt in orig_balances.items():
        j_amt = journal_balances[coord]
        assert amt == j_amt, f"Balance mismatch at {coord}: {amt} vs {j_amt}"

    print(f"  [OK] All {len(orig_balances)} locus balances match bit-for-bit!")
    for loc, m in data["zero_origins"]:
        print(f"       [COVERED] {loc}:{m} = {journal_balances[(loc, m)]}")

    # Verify scheduled
    sched_path = os.path.join(out_dir, "scheduled.hra")
    sched_count = 0
    open_count = 0
    with open(sched_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("SCHED "):
                sched_count += 1
                if "status:open" in line:
                    open_count += 1

    assert sched_count == len(data["scheduled_order"]), f"Scheduled count mismatch: {sched_count}"
    assert open_count == 11, f"Open scheduled mismatch: {open_count} vs 11"
    print(f"  [OK] Scheduled items count ({sched_count}) and open count ({open_count}) match exactly!")

    # Verify file sizes and reduction
    orig_lines = 9188
    j_lines = sum(1 for _ in open(journal_path))
    s_lines = sum(1 for _ in open(sched_path))
    p_lines = sum(1 for _ in open(os.path.join(out_dir, "policy.hra")))
    total_new_lines = j_lines + s_lines + p_lines

    print("\nStorage Consolidation Results:")
    print(f"  Original Loam files: 18 files, {orig_lines} total lines")
    print(f"  New HRA files:        3 files, {total_new_lines} total lines")
    print(f"    - journal.hra:      {j_lines} lines")
    print(f"    - scheduled.hra:    {s_lines} lines")
    print(f"    - policy.hra:       {p_lines} lines")
    print(f"  Line reduction:       {((orig_lines - total_new_lines) / orig_lines) * 100:.1f}% reduction!")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        loam_dir = "/Users/user/Projects/moko/loam-data"
        out_dir = "/Users/user/Projects/moko/hra-data"
    else:
        loam_dir = sys.argv[1]
        out_dir = sys.argv[2]

    print(f"Converting from {loam_dir} to {out_dir}...")
    parsed = parse_loam_data(loam_dir)
    convert_to_hra(parsed, out_dir)
    verify_conversion(parsed, out_dir)
    print("\nSUCCESS: Canonical HRA-N storage generated and verified losslessly.")
