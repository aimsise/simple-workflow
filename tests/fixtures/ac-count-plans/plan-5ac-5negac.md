# Plan: Fixture — 5 positive AC + 5 Negative AC stop-condition test

## Overview

Fixture plan with 5 positive Acceptance Criteria and 5 Negative Acceptance
Criteria under a level-4 heading. Used to verify the Negative-AC stop
condition (Negative AC-6): the AC-counting algorithm MUST stop counting at
the `#### Negative Acceptance Criteria` heading and return AC_COUNT = 5,
not 10. If the algorithm counts items below the stop heading, this fixture
will return AC_COUNT = 10, which is the regression.

## Affected files

| File | Change |
|------|--------|
| `tests/fixtures/ac-count-plans/plan-5ac-5negac.md` | fixture — no source changes |

## Acceptance Criteria

1. **AC-1**: Stub positive criterion 1 for the negative-AC stop-condition fixture.
2. **AC-2**: Stub positive criterion 2 for the negative-AC stop-condition fixture.
3. **AC-3**: Stub positive criterion 3 for the negative-AC stop-condition fixture.
4. **AC-4**: Stub positive criterion 4 for the negative-AC stop-condition fixture.
5. **AC-5**: Stub positive criterion 5 for the negative-AC stop-condition fixture.

#### Negative Acceptance Criteria

1. **Negative AC-1**: Stub negative criterion 1. MUST NOT be counted by the AC-counting algorithm.
2. **Negative AC-2**: Stub negative criterion 2. MUST NOT be counted by the AC-counting algorithm.
3. **Negative AC-3**: Stub negative criterion 3. MUST NOT be counted by the AC-counting algorithm.
4. **Negative AC-4**: Stub negative criterion 4. MUST NOT be counted by the AC-counting algorithm.
5. **Negative AC-5**: Stub negative criterion 5. MUST NOT be counted by the AC-counting algorithm.
