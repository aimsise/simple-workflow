# Phase auto-detection rule details

This reference documents the full per-rule logic for `### 4. Phase Auto-Detection and Guidance` in `skills/catchup/SKILL.md`. The SKILL.md body keeps the numbered list of rules with one-line trigger summaries + recommended command mentions; this file holds the detailed conditions, mapping tables, precedence prose, and per-ticket guidance variants.

## Evaluation order and precedence

Detect the current development phase by checking these conditions **in order**. Check both `.simple-workflow/docs/` and `.simple-workflow/backlog/active/` for artifacts. Use the **first matching** phase.

**Rule precedence note**: `phase-state.yaml` is the authoritative lifecycle state source. Rule 0 below therefore evaluates `phase_state_records` (from Step 1-pre) **strictly before** the legacy compact-state rule (now Rule 0-legacy). The legacy rule only fires when Rule 0 did not match (typically on repositories that have no `phase-state.yaml` yet, or where every record has `overall_status != in-progress`).

## Rule 0. `phase-state.yaml` indicates an in-progress ticket with a completed phase

Suggest `next_recommended` command based on `last_completed_phase` mapping.

- **Precedence**: this rule is evaluated **strictly before Rule 0-legacy** and before Rule 1. `phase-state.yaml` is the authoritative state source; only when it yields no match do the legacy compact-state / artifact-discovery rules apply.
- **Fire condition**: at least one record in `phase_state_records` (from Step 1-pre) has `overall_status: in-progress` AND `last_completed_phase != ship` AND `last_completed_phase != null`. If none match, fall through to Rule 0-legacy.
- **Mapping from `last_completed_phase` to next recommended command**:

  | `last_completed_phase` | ticket location | next command |
  |---|---|---|
  | `create_ticket` | `.simple-workflow/backlog/active/` or `.simple-workflow/backlog/product_backlog/` | `/scout {ticket-dir}` |
  | `scout` | `.simple-workflow/backlog/active/` | `/impl {plan-path}` |
  | `impl` | `.simple-workflow/backlog/active/` | `/ship` |

  (`last_completed_phase == ship` means the ticket should have moved to `.simple-workflow/backlog/done/`; skip.)

  The `{ticket-dir}` carries its full location prefix — for a product_backlog ticket use the full path (e.g. `.simple-workflow/backlog/product_backlog/001-foo`), not just the bare directory name. Step 1-pre records the `location` field per record specifically so this mapping can emit the correct prefix.

- **Single in-progress ticket**: recommend the mapped command using that ticket's `{ticket-dir}` (and `plan.md` path for the `scout → /impl` case).
- **Multiple in-progress tickets** (AC 4.3): list ALL matching tickets in the guidance, then recommend resuming the one with the **most recent `latest_started_at`** (computed in Step 1-pre as the max `phases.{phase}.started_at` across that ticket's phase sections, with `created` as fallback). Ties are broken by lexicographic `{ticket-dir}` order. Name the selected ticket in the recommendation line so the user can see which one was chosen.

- **Inconsistency warning (Rule 0 vs Rule 0-legacy)**: If Rule 0 fires AND a YAML-frontmatter compact-state was also parsed in Step 1 AND the compact-state's aggregate suggestion (from Rule 0-legacy below) would recommend a different action than Rule 0 AND `phase-state.yaml` mtime (from Step 1-pre) is newer than the compact-state's `date` field, emit a single warning line **before** the Rule 0 guidance:

  ```
  Inconsistency detected between phase-state.yaml and older compact-state. Preferring phase-state.yaml (newer).
  ```

  Then proceed with the Rule 0 recommendation. This surfaces — rather than silently hides — state drift between the two files, so users can investigate whether the compact-state snapshot is stale.

## Rule 0-legacy. Compact-state indicates an in-progress `/impl` loop

Suggest **resume `/impl`** *(only when Rule 0 did not fire)*.

- Check: a YAML-frontmatter compact-state file was parsed in Step 1 AND `in_progress_phase == impl-loop` (aggregate field)
- Check: no new git commit has been made since the compact-state's `date` (compare against `git log -1 --format=%cI` for the most recent commit). If a newer commit exists, the user has already moved on — skip Rule 0-legacy and fall through to the rules below.
- **Per-ticket guidance** (when `tickets:` array is present): identify ticket(s) with `in_progress_phase == impl-loop` from the per-ticket array. For each such ticket, include its directory, round number, and outcome in the guidance.
  - Single impl-loop ticket: "You were in the middle of `/impl` for `{dir}` (round `{latest_eval_round}` evaluated, last outcome: `{last_round_outcome}`). Re-run `/impl` to resume."
  - Multiple impl-loop tickets: List all looping tickets with their round/outcome, then recommend resuming the one with the highest `latest_eval_round`.
- **Fallback** (when `tickets:` array is absent — legacy compact-state): use the aggregate `latest_eval_round` and `last_round_outcome` as before. If `active_tickets` is non-empty, name the ticket directory in the guidance.

## Rule 1. No research files for current topic — suggest **investigate**

- Check: `.simple-workflow/docs/research/` is empty or has no files related to current branch
- Also check: `.simple-workflow/backlog/active/` has ticket directories but no `investigation.md` in any of them
- Guidance: Use `/investigate <topic>`. If a ticket exists in `.simple-workflow/backlog/active/`, mention its directory.

## Rule 2. Research exists, no plans — suggest **plan**

- Check: `.simple-workflow/docs/research/` has files BUT `.simple-workflow/docs/plans/` has no related files
- Also check: `.simple-workflow/backlog/active/**/investigation.md` exists BUT `.simple-workflow/backlog/active/**/plan.md` does not (depth-agnostic; covers nested layouts)
- Guidance: Read the research first, then use `/plan2doc <feature>`. `/plan2doc` automatically uses sonnet for S-size and opus for M/L/XL.

## Rule 3. Plans exist, no code diff from default branch — suggest **implement**

- Check: `.simple-workflow/docs/plans/` has files BUT `git diff <default-branch> --name-only` shows no changes outside `.simple-workflow/`
- Also check: `.simple-workflow/backlog/active/**/plan.md` exists BUT no code changes outside `.simple-workflow/` (depth-agnostic)
- Guidance: Read the plan first, then use `/impl`.

## Rule 4. Code diff exists, no test changes — suggest **test**

- Check: `git diff <default-branch> --name-only` shows source changes BUT no test file changes
- Guidance: Use `/test <changed files>`.

## Rule 5. Tests exist, no review files — suggest **review**

- Check: Both source and test changes exist BUT no recent review in `.simple-workflow/docs/reviews/` or `.simple-workflow/backlog/active/**/quality-round-*.md` (depth-agnostic)
- Guidance: Use `/audit` to check all changes (code quality + security).

## Rule 6. Review done, uncommitted changes — suggest **commit**

- Check: Review files exist AND `git status --porcelain` shows uncommitted changes
- Guidance: Use `/ship` to commit and create PR.

## Closing note

Present the detection result with reasoning, including any ticket directory information from `.simple-workflow/backlog/active/`. If the user specified a phase via `$ARGUMENTS`, skip detection and go directly to the guidance for that phase.
