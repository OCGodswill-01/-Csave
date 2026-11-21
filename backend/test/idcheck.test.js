const test = require('node:test');
const assert = require('node:assert/strict');
const { readNinResponse, matchId, checkKycId } = require('../idcheck');

const keys = { DOJAH_APP_ID: 'app-1', DOJAH_SECRET_KEY: 'secret-1' };
const reply = (status, entity) => async () => ({ status, json: async () => (entity === undefined ? null : { entity }) });
const ada = { first_name: 'Ada', last_name: 'Obi', date_of_birth: '1990-05-16' };
const base = { idType: 'NIN', idNo: '12345678901', accountName: 'Ada Obi', dob: '1990-05-16' };

test('no Dojah keys: the check is simply off, so staff verify by hand', async () => {
  assert.deepEqual(await checkKycId(base, { env: {} }), { result: 'off' });
});

test('other ID types are checked by hand', async () => {
  assert.deepEqual(await checkKycId({ ...base, idType: 'Voter card' }, { env: keys }), { result: 'manual' });
});

test('a matching NIN record is a match, and the request carries the keys and the number', async () => {
  let seen;
  const fetchImpl = async (url, opts) => { seen = { url, opts }; return reply(200, ada)(); };
  assert.deepEqual(await checkKycId(base, { env: keys, fetchImpl }), { result: 'match' });
  assert.match(seen.url, /\/api\/v1\/kyc\/nin\?nin=12345678901$/);
  assert.equal(seen.opts.headers.AppId, 'app-1');
  assert.equal(seen.opts.headers.Authorization, 'secret-1');
});

test('other spellings of the field names are understood', async () => {
  const r = await checkKycId(base, { env: keys, fetchImpl: reply(200, { firstname: 'Ada', surname: 'Obi', birthdate: '16-05-1990' }) });
  assert.equal(r.result, 'match');
});

test('a different name or date of birth is a mismatch with the reason', async () => {
  assert.deepEqual(await checkKycId(base, { env: keys, fetchImpl: reply(200, { ...ada, first_name: 'Helen', last_name: 'Obi' }) }), { result: 'mismatch', reason: 'name' });
  assert.deepEqual(await checkKycId(base, { env: keys, fetchImpl: reply(200, { ...ada, date_of_birth: '1991-01-01' }) }), { result: 'mismatch', reason: 'dob' });
});

test('a number Dojah does not know is notfound (404 or empty record)', async () => {
  assert.equal((await checkKycId(base, { env: keys, fetchImpl: reply(404) })).result, 'notfound');
  assert.equal((await checkKycId(base, { env: keys, fetchImpl: reply(200, null) })).result, 'notfound');
});

test('Dojah trouble (bad keys, no balance, rate limit, server error) is unchecked and flagged as a failure, never a rejection', async () => {
  for (const status of [400, 401, 403, 429, 500, 503]) {
    const r = await checkKycId(base, { env: keys, fetchImpl: reply(status) });
    assert.equal(r.result, 'unchecked', String(status)); assert.equal(r.failed, true, String(status));
  }
  const down = async () => { throw new Error('network down'); };
  assert.equal((await checkKycId(base, { env: keys, fetchImpl: down })).result, 'unchecked');
});

test('a record whose name we cannot read is unchecked, not a mismatch', async () => {
  const r = await checkKycId(base, { env: keys, fetchImpl: reply(200, { something_else: 'x' }) });
  assert.equal(r.result, 'unchecked'); assert.notEqual(r.failed, true);
  assert.equal(matchId({ first: 'Ada' }, 'Ada Obi', '1990-05-16').result, 'unchecked');
});

test('readNinResponse treats only 200 as an answer', () => {
  assert.equal(readNinResponse(404, null).found, false);
  assert.throws(() => readNinResponse(500, null));
  assert.equal(readNinResponse(200, { entity: ada }).found, true);
});
