target: SKILL.md
heading: ## Argument Parsing
mode: replace
---
## Argument Parsing

This host passes no argument variable: the input is the user's request text, that is, the text of the message that invoked this skill (everything after `/create-ticket` when it was typed as a command). Parse it into one mode: `findings=<path>` (scan `findings=`); `brief=<path>` (scan `brief=`); else bare-description free-text.

**Mutual exclusion**: BOTH `brief=` AND `findings=` → print `ERROR: brief= and findings= are mutually exclusive. Pass exactly one.` and exit non-zero. Do NOT read either file. Do NOT touch `.ticket-counter`. Do NOT create directories. (Literal `mutually exclusive` is load-bearing.)

**Empty arguments**: when the request carries no description and no `brief=` / `findings=` token, print `Usage: /create-ticket <ticket description> | brief=<path> | findings=<path>` and stop.
