const { test } = require('node:test');
const assert = require('node:assert/strict');
const { namesMatch, isoDate, matchBvn, readBvnResponse, lookupBvn } = require('../bvn');

test('same person in any word order, with or without a middle name', () => {
  assert.equal(namesMatch('Kelvin Goswell', 'KELVIN', 'CHIDI', 'GOSWELL'), true);
  assert.equal(namesMatch('Kelvin Chidi Goswell', 'KELVIN', '', 'GOSWELL'), true);
  assert.equal(namesMatch('Goswell Kelvin', 'Kelvin', 'Chidi', 'Goswell'), true);
});

test('a different person is refused, even with the same surname', () => {
  assert.equal(namesMatch('Helen Goswell', 'KELVIN', '', 'GOSWELL'), false);
});

test('accents and apostrophes do not break the match', () => {
  assert.equal(namesMatch('Adé O\'Brien', 'ADE', '', "O'BRIEN"), true);
});

test('a single word name is never matched on its own', () => {
  assert.equal(namesMatch('Kelvin', 'KELVIN', '', 'GOSWELL'), false);
});

test('dates are read from the common formats', () => {
  assert.equal(isoDate('1997-05-16'), '1997-05-16');
  assert.equal(isoDate('1997-05-16T00:00:00.000Z'), '1997-05-16');
  assert.equal(isoDate('16/05/1997'), '1997-05-16');
  assert.equal(isoDate('not a date'), null);
  assert.equal(isoDate(null), null);
});

test('matchBvn reports a name mismatch, a date mismatch, or a match', () => {
  const rec = { first: 'KELVIN', middle: 'CHIDI', last: 'GOSWELL', dob: '1997-05-16' };
  assert.deepEqual(matchBvn(rec, 'Kelvin Goswell', '1997-05-16'), { result: 'match' });
  assert.deepEqual(matchBvn(rec, 'Helen Goswell', '1997-05-16'), { result: 'mismatch', reason: 'name' });
  assert.deepEqual(matchBvn(rec, 'Kelvin Goswell', '1998-01-01'), { result: 'mismatch', reason: 'dob' });
});

test('a date we cannot read does not block a member whose name matches', () => {
  const rec = { first: 'KELVIN', last: 'GOSWELL', dob: '21-Mar-1997' };
  assert.deepEqual(matchBvn(rec, 'Kelvin Goswell', '1997-05-16'), { result: 'match' });
});

test('Dojah answers: a record, no record, or an outage', () => {
  assert.deepEqual(readBvnResponse(200, { entity: { first_name: 'A', last_name: 'B', date_of_birth: '1990-01-01' } }),
    { found: true, first: 'A', middle: undefined, last: 'B', dob: '1990-01-01' });
  assert.deepEqual(readBvnResponse(200, { entity: null }), { found: false });
  assert.deepEqual(readBvnResponse(400, { error: 'not found' }), { found: false });
  assert.throws(() => readBvnResponse(401, {}), /unavailable/);
  assert.throws(() => readBvnResponse(429, {}), /unavailable/);
  assert.throws(() => readBvnResponse(503, {}), /unavailable/);
});

test('lookupBvn sends the number with both Dojah headers and no "Bearer"', async () => {
  let seen;
  const fakeFetch = async (url, opts) => {
    seen = { url, opts };
    return { status: 200, json: async () => ({ entity: { first_name: 'A', last_name: 'B' } }) };
  };
  const env = { DOJAH_APP_ID: 'app123', DOJAH_SECRET_KEY: 'sk_test' };
  const r = await lookupBvn('22222222222', { env, fetchImpl: fakeFetch });
  assert.equal(r.found, true);
  assert.equal(seen.url, 'https://api.dojah.io/api/v1/kyc/bvn/full?bvn=22222222222');
  assert.equal(seen.opts.headers.AppId, 'app123');
  assert.equal(seen.opts.headers.Authorization, 'sk_test');
});

test('lookupBvn refuses to run without keys', async () => {
  await assert.rejects(() => lookupBvn('22222222222', { env: {}, fetchImpl: async () => { throw new Error('should not call'); } }), /not configured/);
});
