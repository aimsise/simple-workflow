target: references/agent-spawn-prompts.md
heading: ### Autopilot-policy escalation (gates.ticket_quality_fail)
mode: replace
---
### Exhausted-retry escalation

After max 2 rounds (initial + 1 revision) of FAIL, there is no policy file to consult; escalate to the user:

- Interactive flow:
  - `ask_user`: "The ticket has unresolved quality issues: [list]. Proceed anyway or stop to revise manually?"
  - Proceed → Delivery with the ticket's verdict `FAIL (user-accepted)` (its `Quality` cell says exactly that) and the remaining issues noted in the Final summary.
  - Stop → print the draft's path under `{scratch}` + issues.
- **Non-interactive fallback**: a denied, erroring or unavailable `ask_user` (for example in the GitHub.com cloud agent or in non-interactive mode, where asking is treated as deny) means **stop**, exactly as for the remote-delivery confirmation in `references/destinations.md`. Print "Stopped: /create-ticket cannot resolve FAIL gates non-interactively. Re-run interactively." and stop. Do NOT hang.
