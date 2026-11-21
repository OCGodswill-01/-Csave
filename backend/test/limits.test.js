const test = require('node:test');
const assert = require('node:assert/strict');
const { capFor, checkRoom, limitMessage, limitNotice } = require('../limits');

test('default cap is 300,000 and SAVINGS_CAP changes it', () => {
  assert.equal(capFor({}), 300000);
  assert.equal(capFor({ SAVINGS_CAP: '500000' }), 500000);
  assert.equal(capFor({ SAVINGS_CAP: 'abc' }), 300000);
  assert.equal(capFor({ SAVINGS_CAP: '0' }), 300000);
});

test('a payment that lands exactly on the cap is allowed, one naira over is not', () => {
  assert.equal(checkRoom({ held: 250000, incoming: 50000, cap: 300000 }).ok, true);
  assert.equal(checkRoom({ held: 250000, incoming: 50001, cap: 300000 }).ok, false);
  assert.equal(checkRoom({ held: 250000, incoming: 1, cap: 300000 }).room, 50000);
});

test('a member already over the cap has no room but nothing breaks', () => {
  const r = checkRoom({ held: 400000, incoming: 100, cap: 300000 });
  assert.equal(r.ok, false); assert.equal(r.room, 0);
});

test('messages name the cap and the room left', () => {
  assert.match(limitMessage(300000, 0), /₦300,000/);
  assert.match(limitMessage(300000, 0), /reached/);
  assert.match(limitMessage(300000, 50000), /₦50,000/);
  assert.match(limitNotice(300000), /₦300,000/);
});
