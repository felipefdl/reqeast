// Stub: minimal assert for yargs internals
function assert(value, message) {
  if (!value) throw new Error(message || "Assertion failed");
}
assert.strictEqual = function (a, b, msg) {
  if (a !== b) throw new Error(msg || a + " !== " + b);
};
assert.notStrictEqual = function (a, b, msg) {
  if (a === b) throw new Error(msg || a + " === " + b);
};
module.exports = assert;
