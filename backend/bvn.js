// BVN checks through Dojah (https://dojah.io).
// Keys live only in the server environment: DOJAH_APP_ID and DOJAH_SECRET_KEY. Optional DOJAH_BASE_URL (default https://api.dojah.io).
// The rules below are pure functions, so they can be tested without a network or a database.

const plain = s => String(s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

/** Lower-case name words without punctuation or one-letter words ("A.", "O'" are ignored). */
function nameWords(s) {
  return [...new Set(plain(s).replace(/[^a-z\s]/g, ' ').split(/\s+/).filter(w => w.length > 1))];
}

/**
 * True when the name on the member's CSave account and the name on the BVN belong to the same person.
 * Word order does not matter ("Kelvin Goswell" = "Goswell Kelvin"). A middle name may be missing on one side:
 * the shorter name must be wholly inside the longer one and must have at least two words,
 * so "Helen Goswell" never matches "Kelvin Goswell".
 */
function namesMatch(accountName, bvnFirst, bvnMiddle, bvnLast) {
  const a = nameWords(accountName);
  const b = nameWords([bvnFirst, bvnMiddle, bvnLast].filter(Boolean).join(' '));
  if (a.length < 2 || b.length < 2) return false;
  const [small, big] = a.length <= b.length ? [a, b] : [b, a];
  const bigSet = new Set(big);
  return small.every(w => bigSet.has(w));
}

/** Returns yyyy-mm-dd from "1997-05-16", "1997-05-16T00:00:00.000Z" or "16/05/1997". Null when unreadable. */
function isoDate(v) {
  const s = String(v ?? '').trim();
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
  m = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/);
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  return null;
}

/**
 * Compares a BVN record with what the member entered.
 * Returns { result: 'match' } or { result: 'mismatch', reason: 'name' | 'dob' }.
 * The date is only compared when both sides can be read, so a format we do not understand never blocks a member.
 */
function matchBvn(record, accountName, enteredDob) {
  if (!namesMatch(accountName, record.first, record.middle, record.last)) return { result: 'mismatch', reason: 'name' };
  const theirs = isoDate(record.dob), ours = isoDate(enteredDob);
  if (theirs && ours && theirs !== ours) return { result: 'mismatch', reason: 'dob' };
  return { result: 'match' };
}

/**
 * Reads a Dojah BVN response. Returns { found: false } when Dojah has no record for the number.
 * Throws when the service is unavailable or refuses us (bad keys, rate limit, server error),
 * so the caller can tell "this BVN does not exist" apart from "we could not check right now".
 */
function readBvnResponse(status, json) {
  if (status === 401 || status === 403 || status === 429 || status >= 500) throw new Error(`BVN service unavailable (HTTP ${status})`);
  const e = json && json.entity;
  if (!e || typeof e !== 'object') return { found: false };
  return { found: true, first: e.first_name, middle: e.middle_name, last: e.last_name, dob: e.date_of_birth };
}

/** Looks up a BVN with Dojah. Never logs the response (it contains personal data). */
async function lookupBvn(bvn, { env = process.env, fetchImpl = fetch, timeoutMs = 15000 } = {}) {
  if (!env.DOJAH_APP_ID || !env.DOJAH_SECRET_KEY) throw new Error('BVN service is not configured');
  const base = (env.DOJAH_BASE_URL || 'https://api.dojah.io').replace(/\/$/, '');
  const res = await fetchImpl(`${base}/api/v1/kyc/bvn/full?bvn=${encodeURIComponent(bvn)}`, {
    headers: { AppId: env.DOJAH_APP_ID, Authorization: env.DOJAH_SECRET_KEY },   // Dojah wants the raw key, not "Bearer <key>"
    signal: AbortSignal.timeout(timeoutMs),
  });
  const json = await res.json().catch(() => null);
  return readBvnResponse(res.status, json);
}

module.exports = { nameWords, namesMatch, isoDate, matchBvn, readBvnResponse, lookupBvn };
