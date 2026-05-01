// Fixture (f): ordinary assertions without any tautological pattern.
// Expected detector verdict: PASS.

test("addition produces the expected sum", () => {
  const result = add(2, 3);
  expect(result).toBe(5);
});

test("name is reported correctly", () => {
  const user = makeUser("Alice");
  expect(user.name).toEqual("Alice");
});

test("predicate flips on edge case", () => {
  expect(isEven(7)).toBe(false);
});
