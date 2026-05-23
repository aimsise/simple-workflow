---
name: tune
description: >-
  Analyzes evaluation logs (eval-round, quality-round, security-scan,
  audit-round, autopilot-log) by spawning the tune-analyzer subagent and
  maintains the project knowledge base under `.simple-workflow/kb/`
  (entries.yaml, index.yaml, candidates.yaml) with confidence-based
  three-tier promotion (Tier 1 >= 0.8 auto-promote, Tier 2 0.5-0.8
  propose, Tier 3 < 0.5 accumulate). Use when (1) the user runs `/tune
  TICKET-DIR` to mine one ticket's logs, (2) the user runs `/tune all`
  to mine every ticket under `.simple-workflow/backlog/done/` and
  `active/`, or (3) `/ship` Phase 1 step 6 chain-calls `/tune` via the
  Skill tool after moving a ticket to `done/` so the next `/impl`
  Generator receives updated `index.yaml` pattern hints. Caps candidates
  at 30 with a 90-day TTL and entries at 50. Triggers on "/tune",
  "tune the knowledge base", "extract patterns", "analyze evaluation
  logs", "update the kb", "promote candidates", "knowledge base
  extraction", "mine evaluation logs".
disable-model-invocation: false
allowed-tools:
  - Agent
  - Read
  - Write
  - Glob
  - Grep
argument-hint: "[ticket-dir name or 'all']"
---

Analyze evaluation logs and maintain the project knowledge base.
User arguments: $ARGUMENTS

## Pre-computed Context

Active tickets:
!`ls -d .simple-workflow/backlog/active/*/ 2>/dev/null | head -10`

Done tickets:
!`ls -d .simple-workflow/backlog/done/*/ 2>/dev/null | head -10`

Knowledge base status:
!`ls .simple-workflow/kb/*.yaml 2>/dev/null || echo "KB not initialized"`

Available user skills: !`( ls -1 ~/.claude/skills 2>/dev/null ; ls -1 .claude/skills 2>/dev/null ) | sort -u | grep . | tr "\n" "," | sed "s/,$//" | grep . || echo "(none)"`

## YAML Schema Reference

### entries.yaml

```yaml
entries:
  - id: "entry-001"
    pattern: "description"
    category: "error-handling|security|performance|convention|testing|decision"
    scope: "bash|typescript|python|general"
    roles: ["implementer"]
    confidence: 0.92
    evidence_count: 4
    sources:
      - ticket: "slug"
        round: 1
        type: "eval-round"
        observed_at: "2026-04-01"
    promoted_at: "2026-04-10"
```

### index.yaml

```yaml
implementer:
  - id: "entry-001"
    summary: "one-line summary"
    confidence: 0.92
```

### candidates.yaml

```yaml
candidates:
  - id: "cand-001"
    pattern: "description"
    category: "category"
    scope: "scope"
    roles: ["role1"]
    confidence: 0.3
    evidence_count: 1
    sources:
      - ticket: "slug"
        round: 1
        type: "eval-round"
        observed_at: "2026-04-10"
```

Invocation policy: Do not auto-invoke. Only invoke when explicitly called by name by the user or by another skill (e.g. `/ship` Phase 1 step 6). `disable-model-invocation: false` is intentional because this skill is chain-called from `/ship` by name via the Skill tool; flipping to `true` breaks the chain-call surface for `/ship` and any direct `/tune {ticket-dir}` / `/tune all` user invocation.

## Mandatory Skill Invocations

The following agent invocation is **contractual** — `/tune` MUST delegate to the `tune-analyzer` agent via the Agent tool. `/tune` itself extracts no patterns; its entire role is argument parsing, directory existence checks, log-path enumeration, candidate pruning, promotion judgment, and reading/writing the three knowledge-base YAML files. The `tune-analyzer` agent is the sole pattern-extraction author.

| Invocation Target | When | Skip consequence |
|---|---|---|
| `tune-analyzer` agent (Agent tool) | Step 3 — always, after the evaluation log paths have been collected in Step 2 | No new candidates written to `.simple-workflow/kb/candidates.yaml`; Step 4..7 have nothing to prune or promote; downstream `/impl` Generator KB injection (`.simple-workflow/kb/index.yaml`) receives no fresh patterns. Detected by absence of `candidates.yaml` mtime change after a `/tune` run that found logs. |

**Binding rules**:
- `MUST invoke the tune-analyzer agent via the Agent tool` in Step 3 after the log paths are enumerated. The orchestrator MUST NOT extract patterns by reading the log files itself.
- `NEVER bypass tune-analyzer` by writing directly to `.simple-workflow/kb/candidates.yaml` from `/tune` (orchestrator-side YAML writes are restricted to pruning in Step 5 and promotion bookkeeping in Step 7).
- `Fail the /tune invocation immediately` when the tune-analyzer agent cannot be invoked at all. Print the failure reason and the resolved knowledge-base directory path. Do NOT touch any of the three KB YAML files.

## Instructions

### Step 0: Parse Arguments

Parse `$ARGUMENTS`:
- If a ticket-dir name is provided, scope log analysis to that ticket only (`.simple-workflow/backlog/active/{ticket-dir}/` or `.simple-workflow/backlog/done/{ticket-dir}/`)
- If `all` is provided, analyze all tickets in `.simple-workflow/backlog/done/` and `.simple-workflow/backlog/active/`
- If no argument, default to the most recently completed ticket in `.simple-workflow/backlog/done/` (by modification time)

### Step 1: Initialize Knowledge Base

Check if `.simple-workflow/kb/` directory exists. If not:
1. Create the directory: `.simple-workflow/kb/`
2. Create `entries.yaml` with content: `entries: []\n`
3. Create `index.yaml` with content: `# Role-based pattern index\n`
4. Create `candidates.yaml` with content: `candidates: []\n`

If the directory exists, verify all three YAML files exist. Create any missing ones with the defaults above.

### Step 2: Collect Evaluation Logs

Gather evaluation log file paths from the target ticket(s):
- `eval-round-*.md` (AC evaluator feedback)
- `quality-round-*.md` (code quality feedback)
- `security-scan-*.md` (security scanner findings)
- `audit-round-*.md` (audit summaries)
- `autopilot-log.md` (autopilot decision log — category `decision`)

Use Glob to find these files. If `autopilot-log.md` does not exist in the ticket directory, skip it (do not error). If no logs are found at all, print "No evaluation logs found for the specified scope." and stop.

### Step 3: Spawn tune-analyzer Agent

Invoke the `tune-analyzer` agent via the Agent tool. The agent owns the fork — the orchestrator does NOT read the evaluation log contents itself; only the file path list and the knowledge base directory are passed across the boundary, and the orchestrator resumes once the agent returns its 5-field envelope.

- Provide the list of evaluation log file paths collected in Step 2
- Provide the knowledge base path: `.simple-workflow/kb/`
- Instruct it to write new candidate patterns to `.simple-workflow/kb/candidates.yaml`
- Receive the agent's return value (patterns found/updated counts)

If the agent returns **Status: failed**, print the error and stop.

**Return contract**: The `tune-analyzer` agent MUST return a 5-field envelope per its `## Context Conservation Protocol` (`agents/tune-analyzer.md`), under 500 tokens: **Status**: `success | partial | failed`, **Output**: `[path to written candidates file]`, **Patterns Found**: `[count of new patterns extracted]`, **Patterns Updated**: `[count of existing patterns with increased evidence]`, **Next Steps**: `[recommended actions]`. The orchestrator parses these fields to drive Step 4 (read updated candidates), Step 5 (pruning), and Step 8 (summary line items).

### Step 4: Read Updated Candidates

Read `.simple-workflow/kb/candidates.yaml` to see the current candidate list.

### Step 5: Pruning — Enforce Limits

Apply pruning rules to `candidates.yaml`:
- **Maximum 30 candidates**: If more than 30, remove the lowest-confidence candidates until 30 remain
- **TTL 90 days**: Remove any candidate whose most recent `observed_at` date in `sources` is older than 90 days from today

Write the pruned `candidates.yaml` back.

### Step 6: Promotion Judgment

For each candidate in `candidates.yaml`, evaluate promotion eligibility based on confidence:

**Tier 1 — Auto-promote** (confidence >= 0.8):
- Promote to `entries.yaml` automatically (proceed to Step 7)

**Tier 2 — Propose** (0.5 <= confidence < 0.8):
- Print the candidate pattern and confidence to the user
- Note: "This pattern may be worth promoting. Run `/tune` again after more evidence accumulates, or manually increase confidence."

**Tier 3 — Accumulate only** (confidence < 0.5):
- No action. The candidate remains in `candidates.yaml` for future evidence accumulation.

### Step 7: Auto-Promotion (for Tier 1 candidates)

For each candidate with confidence >= 0.8:

1. **Add to entries.yaml**:
   - Generate a new entry ID (`entry-NNN` where NNN is the next sequential number)
   - Copy all fields from the candidate
   - Add `promoted_at` field with today's date
   - Append to the `entries` list
   - **Entry limit: maximum 50 entries** in `entries.yaml`. If adding would exceed 50, remove the entry with the lowest confidence first.

2. **Update index.yaml**:
   - For each role in the entry's `roles` list, add an index record:
     ```yaml
     {role}:
       - id: "{entry-id}"
         summary: "1-line summary of the pattern"
         confidence: {confidence}
     ```
   - If the role key already exists, append to its list

3. **Remove from candidates.yaml**:
   - Delete the promoted candidate from the `candidates` list

Write all three files after processing all promotions.

### Step 8: Summary

Print a summary:
- Logs analyzed: [count]
- New patterns extracted: [count]
- Existing patterns updated: [count]
- Candidates promoted to entries: [count]
- Candidates proposed (Tier 2): [count]
- Candidates pruned: [count]
- Current totals: entries=[count], candidates=[count]

## Error Handling

- **No evaluation logs**: Print "No evaluation logs found for the specified scope." and stop.
- **tune-analyzer failure**: Print the agent's error output and stop. Do not modify the knowledge base.
- **YAML parse error**: If any YAML file is malformed, print the error and stop. Do not overwrite malformed files without user confirmation.
- **KB directory missing files**: Re-create only the missing files with defaults (Step 1).
- **Promotion write failure**: Report which file failed to write. The knowledge base may be in an inconsistent state; advise the user to check `.simple-workflow/kb/` manually.

## Subagent Skill-Access Handoff

When you spawn a subagent via the Agent tool, consult the `Available user skills:` line in the Pre-computed Context above. If a listed utility skill is relevant to that subagent's task, name it in the Agent prompt and instruct the subagent to use it via the Skill tool when it materially helps.

- Do NOT hand skill references to `security-scanner` or `ticket-evaluator`. These subagents are intentionally hermetic and do not carry the Skill tool; referencing skills to them only adds noise.
- Never present a pipeline skill (`/scout`, `/impl`, `/audit`, `/ship`, `/autopilot`, `/brief`, `/catchup`, `/create-ticket`, `/investigate`, `/plan2doc`, `/refactor`, `/test`, `/tune`) as a utility for a subagent.
- When a ticket's `### Capabilities` section exists (resolve via `{ticket-dir}/ticket.md` or the autopilot state file's `paths.ticket`), `Read` it before constructing any subagent spawn prompt and inline the bound capabilities verbatim into every spawn prompt under the heading `## Bound capabilities (per AC)`. For per-AC spawns (one spawn per AC, e.g. `/impl` Steps 13/15), include only the rows whose `Bound AC(s)` column lists the active AC. For tip / whole-deliverable spawns (the rest), include the full table. The upstream binding is authoritative — do NOT re-derive relevance from the AC text or re-scan `Available user skills:` for plausible matches. When the ticket lacks `### Capabilities` (older ticket pre-dating Gate 6), emit `## Bound capabilities (per AC): (none recorded — ticket pre-dates Gate 6)` in the spawn prompt and let the subagent fall back to its in-house capability-selection path.
- If the `Available user skills:` probe reports `(none)`, hand off nothing and let the subagent proceed with its in-house capabilities.
