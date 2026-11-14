"""VT-107 mutation run: apply one temporary mutant at a time to the export module,
run the whole test suite, record KILLED / SURVIVED, and always restore the original files.

Usage (from the repository root, any OS):
    python docs/vt107/evidence/mutation_vt107.py --godot "<path to Godot 4.7.2 console exe>"
    python docs/vt107/evidence/mutation_vt107.py --godot "<exe>" --out docs/vt107/evidence/12_mutation_win.log
    python docs/vt107/evidence/mutation_vt107.py --godot "<exe>" --only P1,S1   (subset)

The GODOT environment variable is used when --godot is not given.
Only run it on a clean working tree (untracked .uid files are fine): it edits
scripts/run_management/*.gd in place and puts the original bytes back in a finally block.
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "procedural-dungeon"
SVC = "scripts/run_management/run_export_service.gd"
REPO = "scripts/run_management/run_record_repository.gd"

# (id, group, description, file, [(old, new), ...], runs)
# `old` must occur exactly once in the file, otherwise the script stops (no silent skips).
MUTANTS = [
    # --- permission checks (authorize) ---
    ("P1", "permission", "role check removed: any string role is accepted (unknown role gets maintainer rights)",
     SVC, [('typeof(role) != TYPE_STRING or (role != ROLE_PLAYER and role != ROLE_MAINTAINER)',
            'typeof(role) != TYPE_STRING')], 1),
    ("P2", "permission", "empty requester id accepted",
     SVC, [('typeof(id) != TYPE_STRING or id == ""', 'typeof(id) != TYPE_STRING')], 1),
    ("P3", "permission", "requester type check removed",
     SVC, [('\tif not (requester is Dictionary):\n\t\treturn _denied(ERR_NOT_AUTHORIZED)\n', '')], 1),
    ("P4", "permission", "player may name another owner in scope (Forbidden check removed)",
     SVC, [('if named_owner != "" and named_owner != id:', 'if false:')], 1),
    ("P5", "permission", "player export is not limited to own records (any_owner true)",
     SVC, [('return {"error": "", "owner_id": id, "any_owner": false}',
            'return {"error": "", "owner_id": id, "any_owner": true}')], 1),
    ("P6", "permission", "scope type check removed",
     SVC, [('\tif not (scope is Dictionary):\n\t\treturn _denied(ERR_INVALID_SCOPE)\n', '')], 1),
    # --- owner scope filter ---
    ("S1", "scope", "owner filter removed: every record is returned",
     SVC, [('if not access["any_owner"] and record.get("owner_id", "") != access["owner_id"]:', 'if false:')], 1),
    ("S2", "scope", "maintainer naming an owner gets all owners",
     SVC, [('return {"error": "", "owner_id": named_owner, "any_owner": false}',
            'return {"error": "", "owner_id": named_owner, "any_owner": true}')], 1),
    ("S3", "scope", "maintainer without owner gets nothing",
     SVC, [('return {"error": "", "owner_id": "", "any_owner": true}',
            'return {"error": "", "owner_id": "", "any_owner": false}')], 1),
    # --- projection, order, expiry, result shape ---
    ("F1", "projection", "expires_at leaves the module",
     SVC, [('"created_at", "status", "won", "reason", "owner_id",',
            '"created_at", "status", "won", "reason", "owner_id", "expires_at",')], 1),
    ("F2", "projection", "config is no longer deep-copied",
     SVC, [('record[field].duplicate(true) if record[field] is Dictionary else record[field]', 'record[field]')], 1),
    ("O1", "order", "no run_id tie-break (equal created_at)",
     SVC, [('return str(a.get("run_id", "")) < str(b.get("run_id", ""))', 'return false')], 1),
    ("O2", "order", "created_at order reversed",
     SVC, [('return a_time < b_time', 'return a_time > b_time')], 1),
    ("E1", "expiry", "expiry filter removed",
     SVC, [('if expires_at <= now:', 'if false:')], 1),
    ("E2", "expiry", "records without numeric expires_at are not dropped",
     SVC, [('if typeof(expires_at) != TYPE_INT and typeof(expires_at) != TYPE_FLOAT:', 'if false:')], 1),
    ("X1", "result", "skipped count always 0 in the export result",
     SVC, [('"skipped": listing["skipped"]}', '"skipped": 0}')], 1),
    # --- repository read path ---
    ("R1", "repository", "whole-number floats are not turned back into ints",
     REPO, [('if value == floorf(value) and absf(value) < 9007199254740992.0:', 'if false:')], 1),
    ("R2", "repository", "ints are not restored inside nested config",
     REPO, [('restored[key] = _restore_ints(value[key])', 'restored[key] = value[key]')], 1),
    ("R3", "repository", "any non-null JSON value is accepted as a record",
     REPO, [('if parsed is Dictionary:', 'if parsed != null:')], 1),
    # --- slice 3 mutants (same as redcheck_slice3.py) ---
    ("M1", "slice3", "empty owner_id accepted in scope",
     SVC, [('typeof(scope["owner_id"]) != TYPE_STRING or scope["owner_id"] == ""',
            'typeof(scope["owner_id"]) != TYPE_STRING')], 1),
    ("M2", "slice3", "last_run.json listed as a record",
     REPO, [('if not file_name.ends_with(".json") or file_name == LAST_RUN_FILE:\n\t\t\tcontinue\n\t\tvar parsed',
             'if not file_name.ends_with(".json"):\n\t\t\tcontinue\n\t\tvar parsed')], 1),
    ("M3", "slice3", "corrupt files not counted",
     REPO, [('\t\t\tskipped += 1', '\t\t\tskipped += 0')], 1),
    ("M4", "slice3", "records without owner_id visible to players",
     SVC, [('record.get("owner_id", "") != access["owner_id"]',
             'record.has("owner_id") and record["owner_id"] != access["owner_id"]')], 1),
    ("M5", "slice3", "export prunes expired files",
     SVC, [('\tvar listing := RunRecordRepository.new(records_dir).list_records()',
            '\tvar repo := RunRecordRepository.new(records_dir)\n\trepo.prune_expired(clock.call())\n\tvar listing := repo.list_records()')], 1),
    ("M6", "slice3", "export creates the records directory",
     REPO, [('\tvar dir := DirAccess.open(records_dir)\n\tif dir == null:\n\t\treturn {"records": records, "skipped": skipped}',
             '\tDirAccess.make_dir_recursive_absolute(records_dir)\n\tvar dir := DirAccess.open(records_dir)\n\tif dir == null:\n\t\treturn {"records": records, "skipped": skipped}')], 1),
    ("M7", "slice3", "expiry boundary off by one (< instead of <=)",
     SVC, [('if expires_at <= now:', 'if expires_at < now:')], 1),
    # --- slice 4 mutant (same as redcheck_slice4.py), several runs because it is a concurrency mutant ---
    ("C1", "concurrency", "export_runs keeps the access decision in a member variable (state shared between calls)",
     SVC, [('\tvar access := authorize(requester, scope)\n\tif access["error"] != "":\n\t\treturn {"ok": false, "error": access["error"], "records": [], "skipped": 0}\n\tvar listing := RunRecordRepository.new(records_dir).list_records()\n\tvar records := select_records(listing["records"], access, clock.call())',
            '\t_access = authorize(requester, scope)\n\tif _access["error"] != "":\n\t\treturn {"ok": false, "error": _access["error"], "records": [], "skipped": 0}\n\tvar listing := RunRecordRepository.new(records_dir).list_records()\n\tvar records := select_records(listing["records"], _access, clock.call())'),
           ('var records_dir: String\n', 'var records_dir: String\nvar _access := {}\n')], 3),
]


def read_bytes(path):
    return path.read_bytes()


def apply_edits(raw, edits, mutant_id):
    text = raw.decode("utf-8")
    crlf = "\r\n" in text
    for old, new in edits:
        if crlf:
            old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
        count = text.count(old)
        if count != 1:
            sys.exit("%s: expected exactly 1 match, found %d for: %r" % (mutant_id, count, old[:80]))
        text = text.replace(old, new, 1)
    return text.encode("utf-8")


def run_suite(godot, timeout):
    started = time.time()
    try:
        proc = subprocess.run(
            [godot, "--headless", "--path", str(PROJECT), "-s", "res://tests/run_tests.gd"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
        code, out = proc.returncode, proc.stdout + proc.stderr
    except subprocess.TimeoutExpired:
        return {"exit": "timeout", "summary": "timeout after %ds" % timeout, "failed": [], "secs": time.time() - started}
    lines = out.splitlines()
    summary = [l.strip() for l in lines if " tests, " in l and " passed" in l]
    failed = [l.split("::", 1)[1].strip() for l in lines if l.startswith("FAIL") and "::" in l]
    return {"exit": code, "summary": summary[-1] if summary else "no summary line (crash?)",
            "failed": failed, "secs": time.time() - started}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT", ""))
    parser.add_argument("--out", default=str(ROOT / "docs/vt107/evidence/12_mutation.log"))
    parser.add_argument("--only", default="", help="comma-separated mutant ids")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    godot = args.godot.strip('"')
    if not godot or not Path(godot).exists():
        sys.exit("Godot executable not found: %r (use --godot or the GODOT variable)" % godot)
    only = {x.strip() for x in args.only.split(",") if x.strip()}
    chosen = [m for m in MUTANTS if not only or m[0] in only]

    log = []

    def say(line=""):
        print(line, flush=True)
        log.append(line)

    version = subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip()
    head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    say("VT-107 mutation run | commit %s | Godot %s | %s, %d logical CPU(s)" % (head, version, sys.platform, os.cpu_count() or 0))

    baseline = run_suite(godot, args.timeout)
    say("baseline (no mutant): exit=%s  %s" % (baseline["exit"], baseline["summary"]))
    if baseline["exit"] != 0 or baseline["failed"]:
        sys.exit("Baseline is not green; fix that before running mutants.")
    say()

    originals = {}
    results = []
    try:
        for mutant_id, group, desc, rel, edits, runs in chosen:
            path = PROJECT / rel
            originals.setdefault(path, read_bytes(path))
            path.write_bytes(apply_edits(originals[path], edits, mutant_id))
            killers = {}
            summaries = []
            survived_runs = 0
            for _ in range(runs):
                result = run_suite(godot, args.timeout)
                summaries.append("exit=%s %s" % (result["exit"], result["summary"]))
                detected = result["exit"] != 0 or bool(result["failed"])
                if not detected:
                    survived_runs += 1
                for name in result["failed"]:
                    killers[name] = killers.get(name, 0) + 1
                if result["exit"] != 0 and not result["failed"]:
                    killers["(runner exit %s, no FAIL line)" % result["exit"]] = killers.get("(runner exit %s, no FAIL line)" % result["exit"], 0) + 1
            path.write_bytes(originals[path])
            status = "SURVIVED" if survived_runs == runs else "KILLED"
            if 0 < survived_runs < runs:
                status = "KILLED %d/%d runs" % (runs - survived_runs, runs)
            results.append((mutant_id, group, desc, status, killers))
            say("%s [%s] %s" % (mutant_id, group, desc))
            say("  %s" % status)
            for summary in summaries[:1]:
                say("  %s" % summary)
            say("  failing tests: %s" % (", ".join("%s%s" % (n, " x%d" % c if runs > 1 else "") for n, c in killers.items()) or "NONE"))
    finally:
        for path, raw in originals.items():
            path.write_bytes(raw)

    killed = sum(1 for r in results if r[3].startswith("KILLED"))
    say()
    say("Mutation score: %d killed of %d mutants (%.0f%%)" % (killed, len(results), 100.0 * killed / max(1, len(results))))
    survivors = [r for r in results if not r[3].startswith("KILLED")]
    say("Survivors: %s" % (", ".join("%s (%s)" % (r[0], r[2]) for r in survivors) or "none"))
    say()
    say("| id | group | mutant | result | killed by |")
    say("|---|---|---|---|---|")
    for mutant_id, group, desc, status, killers in results:
        say("| %s | %s | %s | %s | %s |" % (mutant_id, group, desc, status, ", ".join(killers) or "-"))

    diff = subprocess.run(["git", "-C", str(ROOT), "diff", "--stat", "--", "procedural-dungeon/scripts"], capture_output=True, text=True).stdout.strip()
    say()
    say("git diff of procedural-dungeon/scripts after the run (must be empty): %s" % (diff or "empty"))
    Path(args.out).write_text("\n".join(log) + "\n", encoding="utf-8")
    print("log written to %s" % args.out)


if __name__ == "__main__":
    main()
