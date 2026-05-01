// Fixture (e): legitimate negative-bound assertion where the right-hand
// side is a non-constant variable threshold. The first-stage detector
// tolerates non-literal RHS expressions (false-negative tolerance is
// documented in the rules file's Limitations section).
// Expected detector verdict: PASS.

test("elapsed time stays under the configured threshold", () => {
  const threshold = config.timeoutMs;
  const elapsed = measureElapsed();
  expect(elapsed).toBeLessThan(threshold);
});
