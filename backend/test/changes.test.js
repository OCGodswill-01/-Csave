const { test } = require('node:test');
const assert = require('node:assert/strict');
const { STATUS, checkChange, canApprove, canReject, canPush } = require('../changes');

const proposed = { status: STATUS.PROPOSED, proposedBy: 'A' };
const approved = { status: STATUS.APPROVED, proposedBy: 'A', approvedBy: 'B' };

test('interest rate must be 0 to 100', () => {
  assert.deepEqual(checkChange('interest', { ratePercent: 5 }), { ratePercent: 5 });
  assert.throws(() => checkChange('interest', { ratePercent: -1 }), /between 0 and 100/);
  assert.throws(() => checkChange('interest', { ratePercent: 101 }), /between 0 and 100/);
  assert.throws(() => checkChange('interest', {}), /between 0 and 100/);
});
test('referral change carries a validated rule', () => {
  assert.deepEqual(checkChange('referral', { rule: { type: 'percent', value: 5 } }), { rule: { type: 'percent', value: 5 } });
  assert.throws(() => checkChange('referral', { rule: { type: 'percent', value: 500 } }), /at most 100/);
});
test('unknown kind is refused', () => {
  assert.throws(() => checkChange('bonus', {}), /Unknown kind/);
});
test('the proposer cannot approve their own change', () => {
  assert.match(canApprove(proposed, 'A'), /cannot approve/);
});
test('a different admin can approve a proposed change', () => {
  assert.equal(canApprove(proposed, 'B'), null);
});
test('only a proposed change can be approved', () => {
  assert.match(canApprove(approved, 'C'), /Only a proposed/);
  assert.match(canApprove({ status: STATUS.APPLIED, proposedBy: 'A' }, 'B'), /Only a proposed/);
});
test('nobody can push a change they proposed or approved', () => {
  assert.match(canPush(approved, 'A'), /cannot push/);
  assert.match(canPush(approved, 'B'), /cannot push/);
  assert.equal(canPush(approved, 'T'), null);
});
test('push needs an approved change', () => {
  assert.match(canPush(proposed, 'T'), /Only an approved/);
});
test('reject is possible until the change is live', () => {
  assert.equal(canReject(proposed), null);
  assert.equal(canReject(approved), null);
  assert.match(canReject({ status: STATUS.APPLIED }), /already been pushed/);
  assert.match(canReject({ status: STATUS.REJECTED }), /already been pushed/);
});
