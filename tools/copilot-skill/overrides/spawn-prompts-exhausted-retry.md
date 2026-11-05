target: references/agent-spawn-prompts.md
heading: ### Autopilot-policy escalation (gates.ticket_quality_fail)
mode: replace
---
### Exhausted-retry escalation

After max 2 rounds (initial + 1 revision) of FAIL, there is no policy file to consult; escalate to the user:

- Interactive flow:
  - Ask with the ask-user tool: "The ticket has unresolved quality issues: [list]. Proceed anyway or stop to revise manually?"
  - Proceed → Delivery with the ticket's verdict `FAIL (user-accepted)` (its `Quality` cell says exactly that) and the remaining issues noted in the Final summary.
  - Stop → print the issues, then `ERROR: unresolved FAIL gates; the user declined to proceed (draft saved under {scratch})`, and stop.
- **Non-interactive fallback**: a denied, erroring or unavailable ask-user tool (a host with no tool that returns the user's answer within the run, or a run where asking is treated as deny) means **stop**, exactly as for the remote-delivery confirmation in `references/destinations.md`. Print `ERROR: cannot resolve FAIL gates non-interactively; re-run interactively (draft saved under {scratch})` and stop. Do NOT hang.
