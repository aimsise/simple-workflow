# Interview Templates for /brief

## 1. Business Context
<!-- args-aware shrinkage hints (informational): deadline / target date / release date keywords; user persona names; competitor product names; "why now" rationale or trigger event explicitly named in the input. -->
- Why is this needed now? What triggered this work?
- Who are the primary users or stakeholders?
- Is there a deadline or target release date?

## 2. Technical Requirements
<!-- args-aware shrinkage hints (informational): named framework / language / library tokens (e.g. "Next.js 14 App Router", "Postgres", "TypeScript strict"); API endpoint paths (e.g. "/api/login"); explicit latency / throughput / req-s targets ("10k req/s", "200ms p95"); named data models or interfaces. -->
- What specific API endpoints, data models, or interfaces are needed?
- Are there performance requirements (latency, throughput, etc.)?
- What programming languages, frameworks, or libraries should be used?

## 3. Scope Boundary
<!-- args-aware shrinkage hints (informational): explicit "out of scope" / "do not change" / "no migration" phrases; "incremental" vs "all-at-once" delivery wording; named adjacent features the input promises not to touch. -->
- What is explicitly OUT of scope for this work?
- Can this be delivered incrementally, or must it be all-at-once?
- Are there related features that should NOT be changed?

## 4. Edge Cases
<!-- args-aware shrinkage hints (informational): explicit input-validation rules ("return 400 on invalid input"); named race / concurrency requirements ("optimistic locking", "idempotent"); failure-mode contracts ("retry 3 times", "fail closed"). -->
- What should happen when invalid input is provided?
- Are there concurrent access or race condition concerns?
- How should the system behave under failure conditions?

## 5. Quality Expectations
<!-- args-aware shrinkage hints (informational): explicit coverage targets ("test coverage 80%+"); explicit review requirements ("security review required", "WCAG AA"); explicit coding-standard pointers ("strict mode", "lint clean"). -->
- What level of test coverage is expected?
- Are there specific code review or security review requirements?
- Should this follow any particular coding standards beyond the project default?

## 6. Risk Tolerance
<!-- args-aware shrinkage hints (informational): explicit "breaking changes forbidden" / "breaking 禁止" / "no breaking" phrases; explicit experimental-tech bans ("stable libs only"); explicit rollback wording ("feature flag", "no DB migration", "easy rollback"). -->
- Are breaking changes to existing APIs acceptable?
- Is experimental or unproven technology acceptable?
- How critical is this feature — can it be rolled back easily?

## 7. Autonomous Decision Policy
<!-- args-aware shrinkage hints (informational): explicit "ask vs proceed" guidance ("stop and ask if blocked", "retry up to N times"); explicit autopilot-style policy tokens ("conservative", "moderate", "aggressive"); explicit warning-handling wording ("ship on warnings", "block on warnings"). -->
- If the implementation encounters an unexpected technical blocker, should the agent stop and ask, or attempt a workaround?
- If automated tests fail after implementation, how many retry rounds are acceptable?
- Should the agent proceed with shipping if code quality review finds only warnings (no critical issues)?
