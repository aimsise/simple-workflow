# KB Policy Integration

This reference holds the Phase 4 knowledge-base integration logic for `/brief`. It defines how `.simple-workflow/kb/index.yaml` `autopilot` entries are read, the confidence-based 3-tier judgment (`>= 0.7` / `0.5-0.7` / `< 0.5`), the `# kb-suggested` comment annotation, and the size-scoped pattern priority rule. `/brief` Phase 4 links here for the load-bearing logic.

## KB integration logic

1. Read `.simple-workflow/kb/index.yaml` if it exists.
   - Filter entries under the `autopilot` section. These are historical decision patterns (from `/tune` analysis of autopilot-log.md) that inform default policy values.
   - For each gate in the policy template, search the `autopilot` section for patterns whose `summary` matches the gate name (e.g., `ac_eval_fail`, `ship_review_gate`).
2. Determine default policy values based on:
   - User's risk tolerance answers from Phase 2 (maps to conservative/moderate/aggressive). If Phase 2 was skipped (`interview_complete: false`), default to **conservative** and emit default gates.
   - KB autopilot patterns (if any), applying confidence-based 3-tier judgment per gate:
     - confidence >= 0.7 → use the pattern's action as recommended default; append `# kb-suggested` comment to the gate line
     - confidence 0.5-0.7 → use the pattern's action but append `# [low confidence]` comment
     - confidence < 0.5 → use conservative default (stop)
   - **Size-scoped pattern priority**: If the `autopilot` section contains patterns with a `scope` matching the current brief's `estimated_size` (S/M/L/XL), prefer those over patterns with `scope=general`. Fall back to `scope=general` only when no size-specific pattern exists for a gate.
   - If `.simple-workflow/kb/index.yaml` does not exist or has no `autopilot` section (first run), use conservative defaults for all gates and add `# KB patterns: none` comment to the generated policy file.
