// PRODUCT-Workflow: high-assurance multi-verifier eval panel for /impl Step 15.
//
// This is the PRODUCT-Workflow (the committed script the shipped /impl Step 15
// invokes at runtime when uc=on AND verification_depth == exhaustive). It is
// DISTINCT from any DEV-Workflow (a meta-layer Workflow used to BUILD this
// feature, where agents edit tracked files). This file is product runtime code.
//
// It runs in the Claude Code Workflow sandbox. FORBIDDEN here: Date.now(),
// Math.random(), argless new Date(), the filesystem, any Node API, and importing
// local files. Because local imports are forbidden, the deterministic merge
// (mergeAcVerdicts) is INLINE below.
//
// SYNC CONTRACT: mergeAcVerdicts is MIRRORED VERBATIM in
//   tests/test-eval-panel-merge.mjs
// (a standalone plain-Node unit test that cannot reach the Workflow globals, so
// it pastes a copy). Any edit to mergeAcVerdicts here MUST be applied identically
// there, and vice versa. The unit test is the executable check on the merge
// algorithm; this file is the runtime that calls it.
//
// CONFIRMED-AT-DOGFOOD (not assumed): plugin-relative scriptPath resolution (how
// the caller passes ${CLAUDE_PLUGIN_ROOT}/skills/impl/workflows/eval-panel.mjs),
// whether the sandbox permits importing a sibling .mjs (it currently does not, so
// the merge is inlined + mirrored), and whether opts.model selects a distinct
// model (model is selected here by agentType / twin agent file, NOT by opts.model).

export const meta = {
  name: "eval-panel",
  description:
    "High-assurance 3-lens ac-evaluator fan-out over one rubric and one git diff, merged per AC by the deterministic refute-then-synthesize rule (mirrors skills/impl/references/ac-evaluator-orchestration.md). Invoked by /impl Step 15 when uc=on and verification_depth is exhaustive; persists three eval-round-{n}-v{i}.md reports and returns the merged typed verdict for Step 16.",
  phases: ["evaluate"],
};

// EVAL_SCHEMA - the forced StructuredOutput schema for each evaluator spawn.
// It is a FAITHFUL, LOOSE transcription of the prose return envelope: only
// `status` and `acs` are required (everything the prose treats as optional stays
// optional, so a legitimate report is never rejected for a missing field). The
// `accept_set_sweep` object mirrors the persisted `## Accept-set sweep` line
// fields for observability; it is NOT a substitute for persisting the report.
const EVAL_SCHEMA = {
  type: "object",
  additionalProperties: true,
  required: ["status", "acs"],
  properties: {
    status: {
      type: "string",
      enum: [
        "PASS",
        "PASS_WITH_CONCERNS",
        "FAIL",
        "FAIL_CRITICAL",
        "IN_PROGRESS",
      ],
    },
    acs: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: true,
        required: ["id", "verdict"],
        properties: {
          id: { type: "string" },
          verdict: {
            type: "string",
            enum: ["PASS", "PASS_WITH_CAVEATS", "FAIL", "CRITICAL"],
          },
          evidence_channel: { type: "string" },
          oracle_kind: { type: "string" },
          boundary_quantified: { type: "string" },
        },
      },
    },
    issues: {
      type: "array",
      items: {
        oneOf: [
          { type: "string" },
          {
            type: "object",
            additionalProperties: true,
            properties: {
              ac: { type: "string" },
              severity: { type: "string" },
              detail: { type: "string" },
            },
          },
        ],
      },
    },
    accept_set_sweep: {
      type: "object",
      additionalProperties: true,
      properties: {
        boundary: { type: "string" },
        triggered: { type: "string" },
        ran: { type: "string" },
        astral: { type: "string" },
        corpus_size: { type: "string" },
        divergences: { type: "string" },
        authoritative: { type: "string" },
        caveat: { type: "string" },
      },
    },
  },
};

// Per-lens directives (V1 / V2 / V3). These are the evidence-mode-diverse lenses
// from ac-evaluator-orchestration.md "## High-assurance multi-verifier branch":
// V1 EC-RUNTIME (real public boundary), V2 EC-DIFFERENTIAL or EC-PROPERTY
// (reference cross-check or seeded property sweep), V3 EC-ORACLE + targeted fuzz
// (independent oracle on the raw value + a parse-accepted-overflow vector).
const LENS_DIRECTIVES = [
  "--- lens: 1/3 runtime/EC-RUNTIME --- Gather evidence through the REAL public / protocol boundary only: drive the actual command-line entry point, the actual client over a transport, or the exported public API - never internal handlers reached by reflection or imports the real consumer cannot use. A green project suite is necessary but NOT sufficient: confirm the AC's behaviour is observable at the public boundary, and FAIL any AC whose only evidence is a white-box test that bypasses the schema / serialization / transport layer where real consumers fail.",
  "--- lens: 2/3 differential-or-property/EC-DIFFERENTIAL,EC-PROPERTY --- Establish evidence INDEPENDENT of the implementation's own output. When a reference implementation of the same contract exists, cross-check the implementation against it (EC-DIFFERENTIAL). Otherwise drive a seeded sweep over the input space (fixed seed, reproducible) and assert the invariants the output must hold - monotonicity, symmetry, idempotence, round-trip, range / containment (EC-PROPERTY). FAIL an AC whose tests assert only a handful of fixed points the code itself could have produced, with no reference cross-check and no property coverage across the distribution. Where a SECOND independent algorithm for the same contract exists, compare algorithm-vs-algorithm within tolerance, and require a committed, fixed-seed property-fuzz loop across the distribution.",
  "--- lens: 3/3 oracle-or-fuzz/EC-ORACLE --- For any computational AC, independently derive at least one expected value from an oracle that does NOT share the implementation's core (a third-party reference, a published formula applied from first principles, or a cited hand-computed constant) and compare against the implementation's RAW, pre-rounding output with an explicit tolerance. Additionally fuzz at least one parse-accepted-then-overflows vector (a value the parser ACCEPTS that yields a non-finite / out-of-range intermediate once arithmetic is applied) through the unit under a time-bounded watchdog; FAIL if it hangs or returns a non-error success carrying null / non-finite fields. A scratch oracle probe under the gitignored scratch directory is permitted. Derive two mutually-validated oracles where available (at least one first-principles), trusting a value only when they agree within tolerance, backed by a committed, fixed-seed seeded fuzz; degrade to one oracle plus a Caveat where no second oracle exists.",
];

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

// =====================================================================
// mergeAcVerdicts - the deterministic per-AC merge.
//
// MIRRORED VERBATIM in tests/test-eval-panel-merge.mjs (keep in sync).
//
// Implements the EXACT refute-then-synthesize merge from
// skills/impl/references/ac-evaluator-orchestration.md
// "### Refute-then-synthesize merge (after all three return)":
//
//   * Drop any verifier whose envelope is invalid (null / no acs). The
//     survivors are the `valid` set.
//   * Quorum: valid < 2  =>  round status FAIL_CRITICAL.
//   * Per AC over the valid set:
//       - CRITICAL is not voted away: any one valid verifier marking the AC
//         CRITICAL => merged CRITICAL.
//       - Non-critical FAIL survives unless refuted: when any one valid verifier
//         raises a non-critical FAIL on an AC, it is merged FAIL UNLESS every
//         OTHER valid verifier refutes it. A refuter is a verifier that
//         independently rendered PASS / PASS_WITH_CAVEATS on the SAME AC.
//         Silence is NOT refutation (a verifier that did not render a verdict on
//         the AC does not count). A lone FAIL that reproduces survives as FAIL;
//         a FAIL every other valid verifier refutes is merged PASS.
//       - Else PASS (PASS_WITH_CAVEATS when >=2 valid verifiers are
//         PASS_WITH_CAVEATS; a single caveat does not downgrade a majority PASS).
//   * Overall status = worst merged per-AC verdict on the ladder.
//
// When refuteMerge === 'off', the prior MAJORITY-merge is restored byte-for-byte:
// a non-critical FAIL is merged only when >=2 valid verifiers fail it; a lone
// non-critical FAIL against the rest is demoted to PASS. The CRITICAL-not-voted-
// away rule, the quorum rule, and the ladder are identical in both modes (the
// switch flips ONLY the lone-non-critical-FAIL disposition).
//
// `verifiers` is the array of returned envelopes (may contain nulls from dead
// agents). Returns { status, acs:[{id, verdict, ...}], issues, mergeMode }.
// =====================================================================
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

// =====================================================================
// Workflow body (runs in an async context; top-level await is allowed).
// =====================================================================

const a = args || {};

// agentType is selected by the evaluator model (twin agent files), NOT by
// opts.model: opus => the high-assurance twin, otherwise the default evaluator.
const agentType =
  a.evaluator_model === "opus"
    ? "simple-workflow:ac-evaluator-hi"
    : "simple-workflow:ac-evaluator";

const refuteMode = a.refute_merge === "off" ? "off" : "auto";

// Carried Step-3a resolution fields, surfaced verbatim into each spawn so the
// evaluator reads them from the prompt (not from disk), exactly as the
// Agent-tool path does.
const carried = [
  `Oracle verification: ${a.oracle_verification || "auto"}`,
  `Evidence floor: ${a.evidence_floor || ""}`,
  `Eval panel: ${a.eval_panel || "auto"}`,
  `Self-documentation verification: ${a.selfdoc_verification || "auto"}`,
  `Accept-set conformance: ${a.accept_set_conformance || "auto"}${
    a.accept_set_triggered_on ? ` triggered-on=${a.accept_set_triggered_on}` : ""
  }`,
]
  .filter(Boolean)
  .join("\n");

const evalRoundPaths = Array.isArray(a.eval_round_paths) ? a.eval_round_paths : [];

function buildPrompt(i) {
  const reportPath = evalRoundPaths[i] || `eval-round-${a.round || "n"}-v${i + 1}.md`;
  return [
    LENS_DIRECTIVES[i],
    "",
    "Acceptance Criteria (the fixed rubric - do NOT re-derive it):",
    a.ac_rubric || "",
    "",
    `git diff reference: ${a.git_diff_ref || ""}`,
    "Run `git diff` against that reference to inspect the changes, run lint / test independently, and verify each AC.",
    "",
    carried,
    "",
    `Persist your FULL evaluation report to: ${reportPath}`,
    "You MUST persist the full report to that file AND return the forced EVAL_SCHEMA object (status, acs, issues, accept_set_sweep). The persisted report is the durable artifact; the returned object is the handoff to the orchestrator.",
  ].join("\n");
}

phase("evaluate");
log(
  `eval-panel: spawning 3 lens-diverse evaluators (agentType=${agentType}, refute_merge=${refuteMode})`,
);

const verifiers = await parallel([
  () =>
    agent(buildPrompt(0), {
      agentType,
      schema: EVAL_SCHEMA,
      label: "ac-evaluator V1 runtime/EC-RUNTIME",
      phase: "evaluate",
    }),
  () =>
    agent(buildPrompt(1), {
      agentType,
      schema: EVAL_SCHEMA,
      label: "ac-evaluator V2 differential-or-property/EC-DIFFERENTIAL,EC-PROPERTY",
      phase: "evaluate",
    }),
  () =>
    agent(buildPrompt(2), {
      agentType,
      schema: EVAL_SCHEMA,
      label: "ac-evaluator V3 oracle-or-fuzz/EC-ORACLE",
      phase: "evaluate",
    }),
]);

const liveCount = verifiers.filter(Boolean).length;
log(`eval-panel: ${liveCount}/3 verifier envelopes returned`);

const merged = mergeAcVerdicts(verifiers, { refuteMerge: refuteMode });

log(
  `eval-panel: merged status=${merged.status} acs=${merged.acs.length} mode=${merged.mergeMode}`,
);

// The merged typed result is the effective Step 15 output for Step 16 to consume
// (no grep parse of a prose envelope). It is left as the module's trailing
// completion expression rather than a top-level `return` statement so that
// `node --check skills/impl/workflows/eval-panel.mjs` (the section 6 / section 12.3 green-gate)
// parses it as a plain ES module; the Workflow sandbox evaluates the body and
// reads this completion value as the script's result.
merged;
