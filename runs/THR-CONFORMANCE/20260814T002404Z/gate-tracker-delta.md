# Gate tracker delta — THR-CONFORMANCE 20260814T002404Z (text only)

The governance tree is human-write-exclusive; this file is the delta an
operator applies by hand, expressed as the recount method rather than as
numbers to trust blindly (DONE is a measure, not a label).

After executing BOTH emitted commit sequences — yesterday's (THR-SUBAGENT,
in that run's FINDINGS.md) and this run's (COMMIT-SEQUENCE.md beside this
file):

1. WIR-1 (fixtures tracked), WIR-2 (fixtures on disk), WIR-6 (bypass_row
   register lines): re-run the gate and copy each fact's OBSERVED value
   into its expected. Counts at emission time on this tree: 51 fixtures on
   disk, 51 bypass_row register rows, 28 tracked (the gap is exactly the
   two sequences). WIR-5 counts lines by its own formula; take the gate's
   observed value after the commits land, same method.
2. GATE-3 clears on push (operator act), and STRUCTURE/status-done follows
   it.
3. New thread facts, if the operator seeds THR-CONFORMANCE into the
   tracker: the conformance machinery is six tracked files
   (scripts/conformance_record.py, conformance_verify.py,
   conformance_rule_v1.json, conformance_dump.py, conformance_narrow.py,
   conformance_watch.py), eight fixtures FT-20..FT-27, and ADR-024
   proposed -> accepted on the two-commit cycle.
