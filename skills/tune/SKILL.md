---
name: tune
description: >-
  Analyze evaluation logs, extract reusable patterns, and maintain the
  project knowledge base. Run after /ship or manually to tune agent behavior.
disable-model-invocation: true
allowed-tools:
  # Claude Code
  - Agent
  - Read
  - Write
  - Glob
  - Grep
  # Copilot CLI
  - task
  - view
  - create
  - glob
  - grep
argument-hint: "[ticket-dir name or 'all']"
---

Analyze evaluation logs and maintain the project knowledge base.
User arguments: $ARGUMENTS

## Pre-computed Context

Active tickets:
!`ls -d .backlog/active/*/ 2>/dev/null | head -10`

Done tickets:
!`ls -d .backlog/done/*/ 2>/dev/null | head -10`

Knowledge base status:
!`ls .simple-wf-knowledge/*.yaml 2>/dev/null || echo "KB not initialized"`

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
    summary: "1行の要約"
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

## Instructions

### Step 0: Parse Arguments

Parse `$ARGUMENTS`:
- If a ticket-dir name is provided, scope log analysis to that ticket only (`.backlog/active/{ticket-dir}/` or `.backlog/done/{ticket-dir}/`)
- If `all` is provided, analyze all tickets in `.backlog/done/` and `.backlog/active/`
- If no argument, default to the most recently completed ticket in `.backlog/done/` (by modification time)

### Step 1: Initialize Knowledge Base

Check if `.simple-wf-knowledge/` directory exists. If not:
1. Create the directory: `.simple-wf-knowledge/`
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

Invoke the `tune-analyzer` agent via the Agent tool:
- Provide the list of evaluation log file paths collected in Step 2
- Provide the knowledge base path: `.simple-wf-knowledge/`
- Instruct it to write new candidate patterns to `.simple-wf-knowledge/candidates.yaml`
- Receive the agent's return value (patterns found/updated counts)

If the agent returns **Status: failed**, print the error and stop.

### Step 4: Read Updated Candidates

Read `.simple-wf-knowledge/candidates.yaml` to see the current candidate list.

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
- **Promotion write failure**: Report which file failed to write. The knowledge base may be in an inconsistent state; advise the user to check `.simple-wf-knowledge/` manually.
