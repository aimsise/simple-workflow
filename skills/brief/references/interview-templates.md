# Interview Templates for /brief

## 1. Business Context
- Why is this needed now? What triggered this work?
- Who are the primary users or stakeholders?
- Is there a deadline or target release date?

## 2. Technical Requirements
- What specific API endpoints, data models, or interfaces are needed?
- Are there performance requirements (latency, throughput, etc.)?
- What programming languages, frameworks, or libraries should be used?

## 3. Scope Boundary
- What is explicitly OUT of scope for this work?
- Can this be delivered incrementally, or must it be all-at-once?
- Are there related features that should NOT be changed?

## 4. Edge Cases
- What should happen when invalid input is provided?
- Are there concurrent access or race condition concerns?
- How should the system behave under failure conditions?

## 5. Quality Expectations
- What level of test coverage is expected?
- Are there specific code review or security review requirements?
- Should this follow any particular coding standards beyond the project default?

## 6. Risk Tolerance
- Are breaking changes to existing APIs acceptable?
- Is experimental or unproven technology acceptable?
- How critical is this feature — can it be rolled back easily?

## 7. Autonomous Decision Policy
- If the implementation encounters an unexpected technical blocker, should the agent stop and ask, or attempt a workaround?
- If automated tests fail after implementation, how many retry rounds are acceptable?
- Should the agent proceed with shipping if code quality review finds only warnings (no critical issues)?
