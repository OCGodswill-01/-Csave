const { test } = require('node:test');
const assert = require('node:assert/strict');
const { MEMBERSHIP_FEE, normaliseRule, rewardFor, rewardBlocker } = require('../referral');

test('percent reward is a share of the membership fee', () => {
  assert.equal(rewardFor({ type: 'percent', value: 10 }), 500);
  assert.equal(rewardFor({ type: 'percent', value: 2.5 }), 125);
});
test('fixed amount reward is paid as typed', () => {
  assert.equal(rewardFor({ type: 'amount', value: 300 }), 300);
});
test('reward never exceeds the membership fee', () => {
  assert.equal(rewardFor({ type: 'percent', value: 100 }), MEMBERSHIP_FEE);
  assert.equal(rewardFor({ type: 'amount', value: 5000 }), 5000);
});
test('off or missing rule pays nothing', () => {
  assert.equal(rewardFor({ type: 'off', value: 0 }), 0);
  assert.equal(rewardFor(undefined), 0);
});
test('rounding is to kobo', () => {
  assert.equal(rewardFor({ type: 'percent', value: 3.333 }), 166.65);
});
test('rule validation rejects nonsense with a readable message', () => {
  assert.throws(() => normaliseRule({ type: 'percent', value: 0 }), /above 0/);
  assert.throws(() => normaliseRule({ type: 'percent', value: 101 }), /at most 100/);
  assert.throws(() => normaliseRule({ type: 'amount', value: 5001 }), /at most/);
  assert.throws(() => normaliseRule({ type: 'amount', value: 'abc' }), /number/);
  assert.throws(() => normaliseRule({ type: 'bonus', value: 5 }), /Choose off, percent or amount/);
});
test('rule validation accepts valid rules', () => {
  assert.deepEqual(normaliseRule({ type: 'off' }), { type: 'off', value: 0 });
  assert.deepEqual(normaliseRule({ type: 'percent', value: '10' }), { type: 'percent', value: 10 });
  assert.deepEqual(normaliseRule({ type: 'amount', value: 250 }), { type: 'amount', value: 250 });
});
test('blockers: self-referral, staff, unverified, inactive, flagged', () => {
  const id = 'a1';
  const good = { _id: 'r1', role: 'customer', membershipPaid: true, kycStatus: 'approved', active: true };
  const referee = { _id: 'e1' };
  assert.equal(rewardBlocker(good, referee), null);
  assert.match(rewardBlocker(good, { _id: 'r1' }), /Self-referral/);
  assert.match(rewardBlocker({ ...good, role: 'admin' }, referee), /staff/);
  assert.match(rewardBlocker({ ...good, membershipPaid: false }, referee), /verified, paid/);
  assert.match(rewardBlocker({ ...good, kycStatus: 'pending' }, referee), /verified, paid/);
  assert.match(rewardBlocker({ ...good, active: false }, referee), /inactive/);
  assert.match(rewardBlocker({ ...good }, { _id: 'e2', fraudFlag: true }), /flagged/);
  assert.match(rewardBlocker(null, referee), /no longer matches/);
  void id;
});
