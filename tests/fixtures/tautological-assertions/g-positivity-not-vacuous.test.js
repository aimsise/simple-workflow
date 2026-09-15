// Fixture (g): strict positivity / negativity bounds against a literal are
// MEANINGFUL (they are not the type extremum for the operator) and must NOT be
// reported as R2. Expected detector verdict: PASS.

test("throughput is strictly positive and drift is negative", () => {
  const throughput = measureThroughput();
  const drift = measureDrift();
  expect(throughput).toBeGreaterThan(0);
  expect(throughput).toBeGreaterThanOrEqual(Number.MIN_VALUE);
  expect(drift).toBeLessThan(0);
});
