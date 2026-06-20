// Standalone plain-Node unit test for the eval-panel merge pure-function.
//
// Run: node tests/test-eval-panel-merge.mjs   (exit 0 on success, 1 on failure)
//
// This test has NO access to the Workflow sandbox globals (agent/parallel/log/
// phase/args), so it pastes a VERBATIM copy of mergeAcVerdicts (and the two
// severity-ladder helpers it depends on) below.
//
// MIRROR of skills/impl/workflows/eval-panel.mjs - keep in sync. Any edit to
// mergeAcVerdicts (or VERDICT_RANK / statusRank) in the product Workflow MUST be
// applied identically here, and vice versa.

// ----- BEGIN VERBATIM MIRROR (from skills/impl/workflows/eval-panel.mjs) -----

// --- Severity ladder helpers (shared by both merge modes) ---
// Ladder: FAIL_CRITICAL > FAIL > PASS_WITH_CAVEATS > PASS.
const VERDICT_RANK = {
  PASS: 0,
  PASS_WITH_CAVEATS: 1,
  FAIL: 2,
  CRITICAL: 3, // per-AC critical verdict
  FAIL_CRITICAL: 3, // round-level critical status
};

function statusRank(s) {
  return VERDICT_RANK[s] === undefined ? 0 : VERDICT_RANK[s];
}

function mergeAcVerdicts(verifiers, { refuteMerge } = {}) {
  const mode = refuteMerge === "off" ? "majority" : "refute";

  // 1. Drop invalid envelopes (null, or no usable acs array).
  const valid = (Array.isArray(verifiers) ? verifiers : []).filter(
    (v) => v && Array.isArray(v.acs),
  );

  // 2. Quorum: fewer than two independent envelopes is FAIL_CRITICAL.
  if (valid.length < 2) {
    return {
      status: "FAIL_CRITICAL",
      acs: [],
      issues: [
        `[quorum] only ${valid.length} valid verifier envelope(s); >=2 required for independent verification`,
      ],
      mergeMode: mode,
    };
  }

  // 3. Index each valid verifier's per-AC verdicts by AC id.
  //    Build the ordered set of AC ids in first-seen order across verifiers.
  const order = [];
  const seen = new Set();
  const byVerifier = valid.map((v) => {
    const m = new Map();
    for (const ac of v.acs) {
      if (!ac || ac.id === undefined || ac.id === null) continue;
      const id = String(ac.id);
      m.set(id, ac);
      if (!seen.has(id)) {
        seen.add(id);
        order.push(id);
      }
    }
    return m;
  });

  // 4. Merge each AC.
  const mergedAcs = [];
  for (const id of order) {
    // Verdicts actually rendered on this AC (silence is excluded).
    const rendered = byVerifier
      .map((m) => m.get(id))
      .filter((ac) => ac && ac.verdict !== undefined && ac.verdict !== null);

    // Carry a representative AC object forward for its metadata fields, but the
    // merged verdict is recomputed below.
    const repr = rendered[0] || { id };

    const verdicts = rendered.map((ac) => String(ac.verdict));

    // 4a. CRITICAL is not voted away (both modes).
    if (verdicts.includes("CRITICAL")) {
      mergedAcs.push({ ...repr, id, verdict: "CRITICAL" });
      continue;
    }

    const failers = rendered.filter((ac) => String(ac.verdict) === "FAIL");
    const refuters = rendered.filter((ac) => {
      const vd = String(ac.verdict);
      return vd === "PASS" || vd === "PASS_WITH_CAVEATS";
    });

    let verdict;
    if (failers.length === 0) {
      // No FAIL at all: PASS, upgraded to PASS_WITH_CAVEATS only when >=2
      // valid verifiers rendered PASS_WITH_CAVEATS.
      const caveats = rendered.filter(
        (ac) => String(ac.verdict) === "PASS_WITH_CAVEATS",
      );
      verdict = caveats.length >= 2 ? "PASS_WITH_CAVEATS" : "PASS";
    } else if (mode === "majority") {
      // Majority-merge: FAIL only with >=2 non-critical failers; lone FAIL
      // demoted to PASS.
      verdict = failers.length >= 2 ? "FAIL" : "PASS";
    } else {
      // Refute-merge: a non-critical FAIL is merged FAIL UNLESS every OTHER
      // valid verifier refutes it (affirmative non-FAIL on the SAME AC).
      // Two independent FAILs corroborate - neither refutes the other - so a
      // refutation can clear the failure ONLY when there is exactly ONE failer
      // and every other valid verifier rendered an affirmative non-FAIL on this
      // AC (silence is NOT refutation, so the refuter count must cover every
      // non-failing valid verifier: valid - 1).
      const everyOtherRefutes =
        failers.length === 1 && refuters.length === valid.length - 1;
      verdict = everyOtherRefutes ? "PASS" : "FAIL";
    }

    mergedAcs.push({ ...repr, id, verdict });
  }

  // 5. Overall status = worst merged per-AC verdict on the ladder.
  let worst = "PASS";
  for (const ac of mergedAcs) {
    const v = String(ac.verdict);
    if (statusRank(v) > statusRank(worst)) worst = v;
  }
  // Normalize per-AC CRITICAL up to the round-level FAIL_CRITICAL status.
  const status = worst === "CRITICAL" ? "FAIL_CRITICAL" : worst;

  // 6. Concatenate issues across valid verifiers, tagged by source verifier.
  const issues = [];
  valid.forEach((v, i) => {
    if (!Array.isArray(v.issues)) return;
    for (const issue of v.issues) {
      if (typeof issue === "string") {
        issues.push(`[v${i + 1}] ${issue}`);
      } else if (issue && typeof issue === "object") {
        issues.push({ verifier: `v${i + 1}`, ...issue });
      }
    }
  });

  return { status, acs: mergedAcs, issues, mergeMode: mode };
}

// ----- END VERBATIM MIRROR -----

// --- Tiny assert helper + table-driven runner ---

let passes = 0;
let failures = 0;

function assertEq(actual, expected, label) {
  if (actual === expected) {
    passes += 1;
  } else {
    failures += 1;
    console.error(
      `  FAIL: ${label}\n    expected: ${JSON.stringify(expected)}\n    actual:   ${JSON.stringify(actual)}`,
    );
  }
}

// Convenience: build a verifier envelope from a list of [acId, verdict] pairs.
function v(...pairs) {
  return { status: "PASS", acs: pairs.map(([id, verdict]) => ({ id, verdict })), issues: [] };
}

// Pull the merged verdict for a given AC id out of a merge result.
function verdictOf(result, id) {
  const ac = result.acs.find((x) => x.id === id);
  return ac ? ac.verdict : undefined;
}

// Each case: name, verifiers, opts, and a check(result) callback.
const cases = [
  {
    name: "1. one CRITICAL anywhere => CRITICAL (refute mode)",
    verifiers: [
      v(["AC-1", "PASS"]),
      v(["AC-1", "CRITICAL"]),
      v(["AC-1", "PASS"]),
    ],
    opts: {},
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "CRITICAL", "AC-1 verdict");
      assertEq(r.status, "FAIL_CRITICAL", "round status");
    },
  },
  {
    name: "1b. one CRITICAL anywhere => CRITICAL (majority mode too)",
    verifiers: [
      v(["AC-1", "CRITICAL"]),
      v(["AC-1", "PASS"]),
      v(["AC-1", "PASS"]),
    ],
    opts: { refuteMerge: "off" },
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "CRITICAL", "AC-1 verdict");
      assertEq(r.status, "FAIL_CRITICAL", "round status");
    },
  },
  {
    // The task's case (2): a lone non-critical FAIL that SURVIVES under
    // refute-merge but is DEMOTED under majority-merge. Per the authority
    // (ac-evaluator-orchestration.md L164-175) two affirmative refuters would
    // CLEAR the failure to PASS even under refute-merge, so the scenario that
    // genuinely diverges between the two modes is a lone FAIL with one
    // affirmative refuter and one SILENT sibling: silence is not refutation, so
    // not-every-other-refutes => survives FAIL under refute; only one failer =>
    // demoted to PASS under majority.
    name: "2a. lone non-critical FAIL, one refuter + one SILENT sibling => survives as FAIL under refute-merge",
    verifiers: [
      v(["AC-1", "FAIL"]),
      v(["AC-1", "PASS"]),
      v(["AC-2", "PASS"]), // silent on AC-1
    ],
    opts: {}, // refute (default)
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "FAIL", "AC-1 survives as FAIL (silence != refutation)");
      assertEq(r.status, "FAIL", "round status");
    },
  },
  {
    name: "2b. same lone non-critical FAIL => DEMOTED to PASS under majority-merge (only 1 failer)",
    verifiers: [
      v(["AC-1", "FAIL"]),
      v(["AC-1", "PASS"]),
      v(["AC-2", "PASS"]), // silent on AC-1
    ],
    opts: { refuteMerge: "off" },
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "PASS", "AC-1 demoted to PASS (<2 failers)");
    },
  },
  {
    // Corroboration of a refutation: a lone FAIL that EVERY other valid verifier
    // affirmatively refutes IS cleared to PASS under refute-merge (authority
    // L167-168: "A FAIL that every other valid verifier explicitly refutes is
    // merged PASS"). Same PASS under majority. Pinned so a future code change
    // that stops clearing fully-refuted failures is caught.
    name: "2c. lone FAIL, BOTH others affirmatively refute (PASS) => cleared to PASS (both modes)",
    verifiers: [
      v(["AC-1", "FAIL"]),
      v(["AC-1", "PASS"]),
      v(["AC-1", "PASS"]),
    ],
    opts: {},
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "PASS", "AC-1 cleared (every other refutes), refute-merge");
      const maj = mergeAcVerdicts(
        [v(["AC-1", "FAIL"]), v(["AC-1", "PASS"]), v(["AC-1", "PASS"])],
        { refuteMerge: "off" },
      );
      assertEq(verdictOf(maj, "AC-1"), "PASS", "AC-1 PASS under majority too");
    },
  },
  {
    name: "3a. lone FAIL but a sibling is SILENT (no verdict) => NOT refuted, survives FAIL (refute)",
    verifiers: [
      v(["AC-1", "FAIL"]),
      v(["AC-1", "PASS"]),
      v(["AC-2", "PASS"]), // silent on AC-1
    ],
    opts: {},
    check: (r) => {
      // Only one refuter (v2); v3 is silent on AC-1, so silence != refutation.
      assertEq(verdictOf(r, "AC-1"), "FAIL", "AC-1 survives (silence not refutation)");
    },
  },
  {
    name: "3b. two FAIL, one also FAIL => FAIL under refute-merge",
    verifiers: [
      v(["AC-1", "FAIL"]),
      v(["AC-1", "FAIL"]),
      v(["AC-1", "PASS"]),
    ],
    opts: {},
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "FAIL", "AC-1 FAIL (not every other refutes)");
      assertEq(r.status, "FAIL", "round status");
    },
  },
  {
    name: "3c. two FAIL => FAIL under majority-merge as well",
    verifiers: [
      v(["AC-1", "FAIL"]),
      v(["AC-1", "FAIL"]),
      v(["AC-1", "PASS"]),
    ],
    opts: { refuteMerge: "off" },
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "FAIL", "AC-1 FAIL (>=2 failers)");
      assertEq(r.status, "FAIL", "round status");
    },
  },
  {
    name: "4a. quorum < 2 (only 1 valid envelope, others null) => FAIL_CRITICAL",
    verifiers: [v(["AC-1", "PASS"]), null, null],
    opts: {},
    check: (r) => {
      assertEq(r.status, "FAIL_CRITICAL", "round status");
      assertEq(r.acs.length, 0, "no merged acs on quorum failure");
    },
  },
  {
    name: "4b. quorum < 2 (one valid + one malformed envelope) => FAIL_CRITICAL",
    verifiers: [v(["AC-1", "PASS"]), { status: "PASS" /* no acs */ }, null],
    opts: { refuteMerge: "off" },
    check: (r) => {
      assertEq(r.status, "FAIL_CRITICAL", "round status (majority mode quorum)");
    },
  },
  {
    name: "5. all PASS => PASS",
    verifiers: [
      v(["AC-1", "PASS"], ["AC-2", "PASS"]),
      v(["AC-1", "PASS"], ["AC-2", "PASS"]),
      v(["AC-1", "PASS"], ["AC-2", "PASS"]),
    ],
    opts: {},
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "PASS", "AC-1 PASS");
      assertEq(verdictOf(r, "AC-2"), "PASS", "AC-2 PASS");
      assertEq(r.status, "PASS", "round status");
    },
  },
  {
    name: "6. >=2 PASS_WITH_CAVEATS => merged PASS_WITH_CAVEATS",
    verifiers: [
      v(["AC-1", "PASS_WITH_CAVEATS"]),
      v(["AC-1", "PASS_WITH_CAVEATS"]),
      v(["AC-1", "PASS"]),
    ],
    opts: {},
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "PASS_WITH_CAVEATS", "AC-1 caveats");
      assertEq(r.status, "PASS_WITH_CAVEATS", "round status");
    },
  },
  {
    name: "6b. lone PASS_WITH_CAVEATS does not downgrade a majority PASS",
    verifiers: [
      v(["AC-1", "PASS_WITH_CAVEATS"]),
      v(["AC-1", "PASS"]),
      v(["AC-1", "PASS"]),
    ],
    opts: {},
    check: (r) => {
      assertEq(verdictOf(r, "AC-1"), "PASS", "AC-1 stays PASS (single caveat)");
    },
  },
];

console.log("test-eval-panel-merge: running merge unit cases\n");
for (const c of cases) {
  console.log(`- ${c.name}`);
  c.check(mergeAcVerdicts(c.verifiers, c.opts));
}

const total = passes + failures;
console.log(`\nPASS ${passes}/${total}`);
if (failures > 0) {
  console.error(`FAILURES: ${failures}`);
}
process.exit(failures ? 1 : 0);
