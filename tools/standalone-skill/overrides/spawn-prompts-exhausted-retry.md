target: references/agent-spawn-prompts.md
heading: ### Autopilot-policy escalation (gates.ticket_quality_fail)
mode: replace
---
### Exhausted-retry escalation

After max `rounds=` rounds (default 3: initial + 2 revisions) of FAIL, there is no policy file to consult; escalate to the user, unless `confirm=yes` is typed in the request or implied (a host with no ask-user tool and no `confirm=` token; SKILL.md Argument Parsing, `confirm=`). The escalation runs per ticket: a ticket whose escalation ended in "proceed" (`FAIL (user-accepted)` or `FAIL (unresolved)`) has a verdict and is delivered with the others; the run stops atomically, with nothing delivered, only when the escalation of at least one ticket ended in a stop (the user declined, or nobody could answer and `confirm=yes` was neither typed nor implied).

- **`confirm=yes` typed or implied** (interactive or not; implied only when this host has no ask-user tool and the request carries no `confirm=` token): the token pre-answers this question with "proceed", so it is NOT asked. Print the unresolved issues, then continue to Delivery with the ticket's verdict `FAIL (unresolved)` (its `Quality` cell says exactly that, so a ticket nobody reviewed stays distinguishable from `FAIL (user-accepted)`) and the remaining issues noted in the Final summary.
- Interactive flow (`confirm=yes` neither typed nor implied, the ask-user tool present):
  - Ask with the ask-user tool ONCE for every ticket still graded FAIL after its last round (in a split run, the evaluations finish concurrently, so the question waits until every ticket's last round is graded and lists each such ticket with its issues; one answer covers them all): "These tickets have unresolved quality issues: [ticket: list]. Proceed anyway or stop to revise manually?"
  - Proceed → Delivery with each such ticket's verdict `FAIL (user-accepted)` (its `Quality` cell says exactly that) and the remaining issues noted in the Final summary.
  - Stop → print the issues, then `ERROR: unresolved FAIL gates; the user declined to proceed (draft saved under {scratch})`, and stop.
- **Non-interactive fallback** (`confirm=yes` neither typed nor implied): an ask-user tool that is denied or errors, a run where asking is treated as deny, or a host with no ask-user tool when the request carries `confirm=no` means **stop**, exactly as for the remote-delivery confirmation in `references/destinations.md`. Print `ERROR: cannot resolve FAIL gates non-interactively; re-run interactively, or with confirm=yes to deliver as FAIL (unresolved) (draft saved under {scratch})` and stop. Do NOT hang.
