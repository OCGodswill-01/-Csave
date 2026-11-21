const test = require('node:test');
const assert = require('node:assert/strict');
const { deletionBlocker, erasedUser, deletePageHtml, ERASED_FIELDS } = require('../account-delete');

test('an empty account can be deleted', () => {
  assert.equal(deletionBlocker({}), null);
  assert.equal(deletionBlocker({ planBalance: 0, openPayouts: 0, openPayments: 0 }), null);
});

test('money still held blocks deletion and the message says how much', () => {
  assert.match(deletionBlocker({ planBalance: 1500 }), /₦1,500/);
  assert.match(deletionBlocker({ planBalance: 3000 }), /₦3,000/);
});

test('an unfinished withdrawal or payment blocks deletion', () => {
  assert.match(deletionBlocker({ openPayouts: 1 }), /withdrawal/i);
  assert.match(deletionBlocker({ openPayments: 1 }), /payment/i);
});

test('erasure removes personal data, closes the account and logs every phone out', () => {
  const u = erasedUser('64ABCDEF', 'random-hash', new Date('2026-11-18'));
  assert.equal(u.$set.name, 'Deleted member');
  assert.equal(u.$set.email, 'deleted-64abcdef@deleted.invalid');
  assert.equal(u.$set.active, false);
  assert.equal(u.$set.passwordHash, 'random-hash');
  assert.deepEqual(u.$inc, { tokenVersion: 1 });
  for (const f of ['pinHash', 'kyc', 'referralCode', 'resetCodeHash', 'otpHash']) assert.equal(u.$unset[f], 1, f);
  assert.ok(ERASED_FIELDS.includes('kyc'));
});

test('two different members never get the same deleted email (the email field is unique)', () => {
  assert.notEqual(erasedUser('a1', 'h').$set.email, erasedUser('a2', 'h').$set.email);
});

test('the public page names the app, both ways to delete, and what is kept', () => {
  const html = deletePageHtml({ support: 'help@example.ng' });
  assert.match(html, /Delete your C’SAVE account/);
  assert.match(html, /com\.abiacsave\.app/);
  assert.match(html, /Profile/);
  assert.match(html, /\/api\/account\/delete/);
  assert.match(html, /What we keep/);
  assert.match(html, /six years/);
  assert.match(html, /Delete my account/);
  assert.match(html, /help@example\.ng/);
});

test('the page works without a support email and escapes the one it is given', () => {
  assert.doesNotMatch(deletePageHtml({}), /mailto:/);
  assert.doesNotMatch(deletePageHtml({ support: '"><script>x</script>' }), /<script>x<\/script>/);
});
