// Fixture (c): R3 violation — constant boolean on both sides.
// Expected detector verdict: FAIL with rule id R3.

test("truth is truth", () => {
  expect(true).toBe(true);
});
