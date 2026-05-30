# `autopilot-state.yaml` schema reference

This document is the single source of truth for the shape of
`autopilot-state.yaml`, the file that the autopilot orchestrator and its
read-only hook helpers (`hooks/lib/parse-state-file.sh`) consult to detect an
autopilot run, walk the ticket list, and reason about per-ticket lifecycle.

The v8.0.0 release froze the canonical shape described below. Earlier (v7-era)
runs produced a strictly-readable legacy variant that is preserved here for
forward-compat reasoning; the parser library reads both, but writers (autopilot
SKILL, ship hooks) only emit canonical v8.

## Canonical v8 schema

Top-level keys (in document order produced by canonical writers):

- `version: 1` — file ABI version. Reserved; bump only when the on-disk
  encoding (not the field set) changes.
- `parent_slug: <slug>` — the autopilot brief's slug.
- `started: <RFC3339>` — orchestrator boot timestamp.
- `execution_mode: split | unified` — whether tickets ran in split (per-ticket
  Skill chain) or unified (single SKILL invocation) mode.
- `risk_tolerance: aggressive | moderate | conservative` — policy tier copied
  from `autopilot-policy.yaml`.
- `ticket_mapping: { <logical_id>: <ticket_dir-fullpath> }` — map from
  logical ticket id to the ticket directory as a fullpath rooted under
  `.simple-workflow/backlog/...`. The value MUST be a fullpath; basename-only
  values are a v7 legacy shape (see below).
- `processing_order: [<logical_id>, ...]` — ordered list of `logical_id`
  values. **Invariant: this list is the single source of truth for the
  ticket count and execution order.**
- `human_overrides: []` — list of explicit human-supplied policy/capability
  overrides recorded by autopilot. Default empty array when absent.
- `kb_overrides: []` — list of overrides sourced from the KB. Default empty
  array.
- `decisions_made: []` — append-only decision log. Default empty array.
- `manual_bash_fallbacks: []` — append-only log of manual bash fallbacks taken
  when a hook degraded. Default empty array.
- `runtime_metrics: []` — append-only autopilot metric stream. Default empty
  array.
- `tickets: [<ticket-entry>]` — **list-canonical** array of per-ticket records.
  Entry shape:
  - `logical_id: <slug>-part-<N>`
  - `ticket_dir: .simple-workflow/backlog/{done,active,product_backlog}/<parent_slug>/<NNN-...>/`
    — always a fullpath ending with `/`. Never a basename.
  - `status: completed | in_progress | failed | skipped | pending`
  - `invocation_method: { scout, impl, ship: skill | mcp | bash }`
  - `steps: { scout, impl, ship: completed | in_progress | pending | failed }`
  - `pr_url: <url> | null` — defaults to `null` when no PR was opened yet.
  - `failure_reason: <string> | null` — defaults to `null`.

## Legacy v7 fields (read-only support)

The parser helpers in `hooks/lib/parse-state-file.sh` accept the following v7
fields for backward compatibility, but canonical v8 writers MUST NOT emit them:

- `boundary: pipeline_start` — v7 surfaced the boundary that the autopilot
  loop entered through. v8 drops it; consumers compute boundary state from
  `tickets[].steps` instead.
- `total_tickets: <int>` — v7 cached `len(tickets)`. v8 derives the count
  from `processing_order` (or `tickets` length when `processing_order`
  is unset). Counter fields are redundant and prone to drift.
- `completed_tickets: <int>`, `failed_tickets: <int>`, `skipped_tickets: <int>`
  — v7 cached per-status aggregates. v8 derives them by walking
  `tickets[].status` on demand.
- `ticket_mapping: { <logical_id>: <basename> }` — v7 stored the basename of
  the ticket directory. v8 uses the fullpath; the migration tool rewrites
  basename values into fullpaths from `tickets[].ticket_dir`.
- `tickets[].depends_on: []` — v7 surfaced an explicit per-ticket dependency
  list. v8 represents ordering through `processing_order` only.

The parser helpers normalise these on read: legacy fields are ignored when
their v8 counterparts are present, and missing v8 fields fall back to the
v7 source where defined.

## Invariants

The following invariants are checked by `tests/test-state-parsers.sh` and
documented here so future writers do not regress them:

1. **`processing_order` is the SSoT for ticket count.** The number of entries
   in `processing_order` MUST equal the number of `tickets[]` entries with a
   `logical_id` present in `processing_order`. Counts derived from any other
   field (`total_tickets`, `len(ticket_mapping)`) are advisory only and
   subject to legacy-drift.
2. **`ticket_dir` is always a fullpath.** Every `tickets[].ticket_dir` value
   begins with `.simple-workflow/backlog/` and ends with `/`. Every
   `ticket_mapping` value is the same fullpath. Basename-only values are a
   v7 legacy shape and trigger the migration tool's `ticket_mapping`
   rewrite step.
3. **`tickets[]` is list-canonical.** The canonical encoding is a YAML list
   (`tickets:\n  - logical_id: ...`). The parser helpers tolerate a map
   encoding (`tickets:\n  shelftrack-part-1: { ... }`) for compatibility
   with a single observed orchestrator slip
   (`test_simple_workflow28`), but writers MUST emit list form.
4. **Forward-compatible additions only.** New fields MAY be added at the top
   level or inside `tickets[]` entries without bumping `version:`. Renames or
   removals are breaking and require the migration tool and a major release.

## Migration guidance

Use `tools/migrate-state-schema.sh` to rewrite a v7-shaped file into
canonical v8:

```bash
bash tools/migrate-state-schema.sh \
  --in  <path/to/v7/autopilot-state.yaml> \
  --out <path/to/v8/autopilot-state.yaml>
```

The migration is idempotent: running it again on an already-v8 file produces
zero diff (verified by AC-9 in P2-4).

The migration performs the following non-destructive steps:

1. Drop legacy `total_tickets`, `completed_tickets`, `failed_tickets`,
   `skipped_tickets`, and `boundary` fields if present.
2. Add `processing_order` from `tickets[].logical_id` in document order when
   it is missing.
3. Add `human_overrides: []`, `kb_overrides: []`, `decisions_made: []`, and
   `manual_bash_fallbacks: []` if missing.
4. Add `pr_url: null` and `failure_reason: null` to every `tickets[]` entry
   that does not already carry those keys.
5. Rewrite each `ticket_mapping` value that is a basename (no `/`) into the
   matching `tickets[].ticket_dir` fullpath.

The script implements a three-tier dependency fallback per the project
convention: `yq` (mikefarah v4) preferred, falling back to `python3 + PyYAML`,
and finally failing loudly when neither is available.
