// Fixture (b): R2 violation — vacuous numeric boundary against literal 0.
// Expected detector verdict: FAIL with rule id R2.

test("final size is non-negative", () => {
  const finalSize = computeSize();
  expect(finalSize).toBeGreaterThanOrEqual(0);
});
