# Autopilot Policy Template

This reference holds the `autopilot-policy.yaml` template emitted by `/brief` Phase 4. The block lists every gate (`ticket_quality_fail`, `evaluator_dry_run_fail`, `ac_eval_fail`, `audit_infrastructure_fail`, `ship_review_gate`, `ship_ci_pending`, `unexpected_error`) and the `constraints:` block, with `conservative` / `moderate` / `aggressive` branches inlined as comments. `/brief` Phase 4 links here for the load-bearing YAML.

```yaml
version: 1
risk_tolerance: {conservative|moderate|aggressive}

gates:
  ticket_quality_fail:
    action: retry_with_feedback
    max_retries: 3
    allow_partial_split_commit: false  # opt-in: when true, successful sub-tickets in an N>1 split are committed even if one sub-ticket exhausts retries. Default false preserves the atomic all-or-nothing contract.
  evaluator_dry_run_fail:
    action: {proceed_without|stop}  # conservative=stop, moderate/aggressive=proceed_without
  ac_eval_fail:
    action: retry
    on_critical: stop
  audit_infrastructure_fail:
    action: {treat_as_fail|stop}  # conservative=stop, moderate/aggressive=treat_as_fail
  ship_review_gate:
    action: {proceed_if_eval_passed|stop}  # conservative=stop, moderate/aggressive=proceed_if_eval_passed
  ship_ci_pending:
    action: wait
    timeout_minutes: {30|60}  # conservative/moderate=30, aggressive=60
    on_timeout: stop
  unexpected_error:
    action: stop

constraints:
  max_total_rounds: {9|12}  # conservative/moderate=9, aggressive=12
  allow_breaking_changes: {false|true}  # conservative/moderate=false, aggressive=true
  verification_depth: auto  # auto (default, all tiers) derives a depth tier from ticket Size x risk_tolerance; standard|thorough|exhaustive force a tier; off restores pre-v8.1.0 behaviour (base rounds, single evaluator, no forced third-pass). See skills/impl/references/verification-depth.md
  oracle_verification: auto  # auto (default) enforces Gate 7 oracle independence for computational ACs + the criticality floor (thorough min for critical-domain computational ACs); off restores pre-v8.2.0 behaviour. See skills/impl/references/verification-depth.md and skills/create-ticket/references/ac-quality-criteria.md Gate 7
  irreversibility_floor: auto  # auto (default, M5/v8.3.0+) floors criticality=critical when an AC verifies an irreversible side-effect (data writes/network mutation/money movement/destructive ops/external-system calls), raising depth tier, bumping the evaluator model to opus (ac-evaluator-hi), and setting the red-team budget to full; off removes only this axis (the critical-domain oracle floor and matrix depth scaling are unaffected). See skills/impl/references/verification-depth.md
  independent_evidence: auto  # auto (default, M1/v8.3.0+) enforces Gate 8 independent evidence for behavioral ACs (each names >=1 channel independent of the implementation — EC-ORACLE/EC-DIFFERENTIAL/EC-PROPERTY/EC-RUNTIME — or is rewritten as structural EC-STATIC); the evidence_floor scales mandatory channels by tier (standard=natural only, thorough=+1, exhaustive=>=2); off grades Gate 8 n/a ticket-wide. See skills/impl/references/verification-depth.md, skills/create-ticket/references/ac-quality-criteria.md Gate 8, and skills/impl/references/evidence-channels.md
```
