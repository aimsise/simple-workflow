# `phase-state.yaml` — Legacy migration reference

`/impl` is responsible for migrating legacy `impl-state.yaml` files that
predate the unified schema (see `phase-state-schema.md`). This document
is the authoritative source for the migration contract — rename table,
partial-state handling, `legacy_extras` preservation, `.bak` cleanup
convention, and the sunset timeline.

`/impl` §11a MUST read this file before applying a migration.

## 1. Branches

| State in `{ticket-dir}` | Branch |
|---|---|
| Only `impl-state.yaml` | §11a.1 — clean migration |
| Both `impl-state.yaml` AND `phase-state.yaml` with `phases.impl.*` populated | §11a.0 Sub-case A — migration already complete; skip to §11c resume |
| Both files, `phase-state.yaml.phases.impl.*` null | §11a.0 Sub-case B — partial migration; re-populate `phases.impl` from the legacy file |
| Neither file, `plan.md` only | §11b — bootstrap (not a migration) |

## 2. Legacy → unified field rename table

| Legacy (`impl-state.yaml`) | Unified (`phase-state.yaml`) |
|---|---|
| top-level `phase` | `phases.impl.phase_sub` |
| top-level `current_round` | `phases.impl.current_round` |
| top-level `max_rounds` | `phases.impl.max_rounds` |
| top-level `last_ac_status` | `phases.impl.last_ac_status` |
| top-level `last_audit_status` | `phases.impl.last_audit_status` |
| top-level `last_audit_critical` | `phases.impl.last_audit_critical` |
| top-level `next_action` | `phases.impl.next_action` |
| top-level `feedback_files.eval` | `phases.impl.feedback_files.eval` |
| top-level `feedback_files.quality` | `phases.impl.feedback_files.quality` |
| top-level `plan_file` | (dropped — derivable from `{ticket-dir}/plan.md`) |
| top-level `ticket_dir` | (dropped — the file path itself encodes location) |
| top-level `size` | top-level `size` |
| top-level `started` | `phases.impl.started_at` |

## 3. `legacy_extras` preservation rule

Before renaming the legacy file, `/impl` identifies any top-level keys in
`impl-state.yaml` that are NOT listed in section 2 above. Every such
unknown key is copied into `phases.impl.legacy_extras:` as a YAML map
(e.g. `legacy_extras: { custom_flag: true, experimental_mode: aggressive }`).
If no unknown keys are present, the `legacy_extras` field is omitted
entirely (no empty map).

This preserves forward-compatibility with experimental state from upstream
branches — nothing is silently dropped.

## 4. `.bak` cleanup convention

After the new `phase-state.yaml` has been written successfully, rename the
legacy file rather than deleting it:

```
mv {ticket-dir}/impl-state.yaml {ticket-dir}/impl-state.yaml.migrated-{YYYYMMDD}.bak
```

Never use `rm` on the legacy file. The `.bak` artifact is preserved for
audit and rollback and is removed by a later cleanup pass once the
migration is confirmed stable across a full release.

If the `phase-state.yaml` write failed, do NOT rename the legacy file —
the migration is all-or-nothing. A partial-migration state is recoverable
by §11a.0 Sub-case B on the next `/impl` run.

## 5. Sunset

Legacy `impl-state.yaml` migration support is retained through
**plugin v4.0 OR 2026-10-18 (6 months post-merge of the unified
schema), whichever comes later**. After that window, the migration
branch in `/impl` §11a MAY be removed and the legacy-rename table
above MAY be archived. Concretely:

- When all active tickets in a repository no longer contain
  `impl-state.yaml`, the §11a code path is dead for that repository.
- When every supported consumer of the plugin is past v4.0 AND the
  6-month window has elapsed, the §11a migration code may be deleted
  from `/impl`, and this document can be moved to an `archive/`
  subdirectory. `/impl` will then reject any remaining legacy files
  with an error pointing at the archived rename table.
