// Fixture (a): R1 violation — same identifier on both sides of toEqual.
// Expected detector verdict: FAIL with rule id R1.

const arr = [1, 2, 3];

test("snapshot of arr matches arr", () => {
  expect(arr).toEqual(arr);
});
