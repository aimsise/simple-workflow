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
```
