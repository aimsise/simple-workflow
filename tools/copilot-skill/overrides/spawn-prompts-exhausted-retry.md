target: references/agent-spawn-prompts.md
heading: ### Autopilot-policy escalation (gates.ticket_quality_fail)
mode: replace
---
### Exhausted-retry escalation

After 2 rounds of FAIL, there is no policy file to consult; escalate to the user:

- Interactive flow:
  - `ask_user`: "The ticket has unresolved quality issues: [list]. Proceed anyway or stop to revise manually?"
  - Proceed → Common Write Path with issues noted.
  - Stop → print ticket path + issues.
- **Non-interactive fallback**: If `ask_user` is unavailable / errors (for example in the GitHub.com cloud agent or in autopilot mode, where asking is treated as deny), default to **stop**. Print "Stopped: /create-ticket cannot resolve FAIL gates non-interactively. Re-run interactively." and exit. Do NOT hang.
