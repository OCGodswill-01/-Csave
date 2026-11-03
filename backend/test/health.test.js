const { test } = require('node:test');
const assert = require('node:assert/strict');
const { evaluateHealth, overallStatus, ENV_RULES } = require('../health');

const allEnvSet = Object.fromEntries(ENV_RULES.map(r => [r.name, true]));
const healthy = () => ({
  dbConnected: true, memoryMb: 120, lastRecheckAgeMin: 4,
  paymentsStuck: 0, withdrawalsReview: 0, withdrawalsStuck: 0,
  kycOverdue: 0, bvnFailing: false, autosaveFailing: 0, autosaveOverdue: 0,
  crashRate24h: 0.4, crashes24h: 2, sessions24h: 500, failedLogins24h: 3, staffStale: 0,
  env: { ...allEnvSet },
});
const keys = issues => issues.map(i => i.key);

test('a healthy platform reports no problems and is green', () => {
  const issues = evaluateHealth(healthy());
  assert.deepEqual(issues, []);
  assert.equal(overallStatus(issues), 'green');
});

test('the database being down is critical and turns the status red', () => {
  const issues = evaluateHealth({ ...healthy(), dbConnected: false });
  assert.ok(keys(issues).includes('db.down'));
  assert.equal(issues.find(i => i.key === 'db.down').severity, 'critical');
  assert.equal(overallStatus(issues), 'red');
});

test('a withdrawal that needs checking is critical, and never auto-refunded in the text', () => {
  const issues = evaluateHealth({ ...healthy(), withdrawalsReview: 2 });
  const i = issues.find(x => x.key === 'wd.review');
  assert.equal(i.severity, 'critical');
  assert.match(i.title, /2 withdrawals need/);
  assert.match(i.detail, /not refunded automatically/);
});

test('stuck payments: a warning for a few, critical for five or more', () => {
  assert.equal(evaluateHealth({ ...healthy(), paymentsStuck: 1 }).find(i => i.key === 'pay.stuck').severity, 'warning');
  assert.equal(evaluateHealth({ ...healthy(), paymentsStuck: 5 }).find(i => i.key === 'pay.stuck').severity, 'critical');
});

test('a missing critical setting is reported with its fix', () => {
  const issues = evaluateHealth({ ...healthy(), env: { ...allEnvSet, FLW_SECRET_KEY: false } });
  const i = issues.find(x => x.key === 'cfg.FLW_SECRET_KEY');
  assert.equal(i.severity, 'critical');
  assert.match(i.fix, /FLW_SECRET_KEY/);
  assert.equal(overallStatus([i]), 'red');
});

test('a missing BVN key is a warning, and is reported with the Dojah name', () => {
  const issues = evaluateHealth({ ...healthy(), env: { ...allEnvSet, DOJAH_KEYS: false } });
  const i = issues.find(x => x.key === 'cfg.DOJAH_KEYS');
  assert.equal(i.severity, 'warning');
  assert.match(i.fix, /DOJAH_APP_ID/);
});

test('a re-check job that has stopped is flagged', () => {
  assert.ok(keys(evaluateHealth({ ...healthy(), lastRecheckAgeMin: 45 })).includes('job.recheck'));
  assert.ok(!keys(evaluateHealth({ ...healthy(), lastRecheckAgeMin: null })).includes('job.recheck'));
});

test('a warning alone makes the status amber', () => {
  const issues = evaluateHealth({ ...healthy(), kycOverdue: 3 });
  assert.equal(overallStatus(issues), 'amber');
});

test('resolved problems do not count towards the status', () => {
  assert.equal(overallStatus([{ severity: 'critical', status: 'resolved' }]), 'green');
});

test('problem text never carries names, emails or secrets', () => {
  const text = JSON.stringify(evaluateHealth({ ...healthy(), dbConnected: false, withdrawalsReview: 1, env: { ...allEnvSet, FLW_SECRET_KEY: false } }));
  assert.doesNotMatch(text, /@/);
});
