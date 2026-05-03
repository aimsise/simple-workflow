// intentional reference equality test
// Fixture (d): the system under test is a cache that returns the same
// object reference for repeated lookups. Reference identity is the
// behavioural contract, so an apparent R1 violation is legitimate.
// Expected detector verdict: PASS.

test("cache returns the same instance for the same key", () => {
  const cached = cache.get("k");
  expect(cached).toBe(cache.get("k"));
});

test("identity helper is reflexive", () => {
  const value = makeValue();
  expect(value).toEqual(value);
});
