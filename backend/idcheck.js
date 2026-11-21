'use strict';
// Automatic ID check through Dojah (https://dojah.io). It starts working the moment DOJAH_APP_ID and DOJAH_SECRET_KEY are set in Render.
// Until then every submission simply goes to staff for a manual check. Staff approve in both cases: this only gives them a result to look at.
// Today only the NIN is looked up. The other ID types are checked by hand.
// The name and date rules are shared with bvn.js and are pure functions, so they are tested without a network.

const { namesMatch, isoDate } = require('./bvn');

const pick = (o, ...keys) => { for (const k of keys) if (o && o[k] != null && String(o[k]).trim() !== '') return o[k]; return undefined; };

// Reads a Dojah NIN response. Returns { found: false } when there is no record for that number.
// Throws when Dojah is unavailable or refuses us (bad keys, no balance, rate limit, server error), so "not found" is never confused with "could not check".
function readNinResponse(status, json) {
  if (status === 404) return { found: false };
  if (status !== 200) throw new Error(`ID service unavailable (HTTP ${status})`);
  const e = json && json.entity;
  if (!e || typeof e !== 'object') return { found: false };
  return {
    found: true,
    first: pick(e, 'first_name', 'firstname', 'firstName'),
    middle: pick(e, 'middle_name', 'middlename', 'middleName'),
    last: pick(e, 'last_name', 'surname', 'lastname', 'lastName'),
    dob: pick(e, 'date_of_birth', 'birthdate', 'dob'),
  };
}

// { result: 'match' } or { result: 'mismatch', reason: 'name' | 'dob' }.
// A record whose name we cannot read is 'unchecked', never a mismatch, so an unexpected reply format can never wrongly reject a member.
function matchId(rec, accountName, enteredDob) {
  if (!rec.first || !rec.last) return { result: 'unchecked' };
  if (!namesMatch(accountName, rec.first, rec.middle, rec.last)) return { result: 'mismatch', reason: 'name' };
  const theirs = isoDate(rec.dob), ours = isoDate(enteredDob);
  if (theirs && ours && theirs !== ours) return { result: 'mismatch', reason: 'dob' };
  return { result: 'match' };
}

async function lookupNin(nin, { env = process.env, fetchImpl = fetch, timeoutMs = 15000 } = {}) {
  const base = (env.DOJAH_BASE_URL || 'https://api.dojah.io').replace(/\/$/, '');
  const res = await fetchImpl(`${base}/api/v1/kyc/nin?nin=${encodeURIComponent(nin)}`, {
    headers: { AppId: env.DOJAH_APP_ID, Authorization: env.DOJAH_SECRET_KEY },   // Dojah wants the raw key, not "Bearer <key>"
    signal: AbortSignal.timeout(timeoutMs),
  });
  const json = await res.json().catch(() => null);
  return readNinResponse(res.status, json);
}

/**
 * result: 'match' | 'mismatch' | 'notfound' | 'unchecked' | 'off' (no keys yet) | 'manual' (ID type not checked automatically).
 * failed: true when Dojah itself did not answer properly (used by the health monitor). Never logs the response: it holds personal data.
 */
async function checkKycId({ idType, idNo, accountName, dob }, deps = {}) {
  const env = deps.env || process.env;
  if (idType !== 'NIN') return { result: 'manual' };
  if (!env.DOJAH_APP_ID || !env.DOJAH_SECRET_KEY) return { result: 'off' };
  try {
    const rec = await lookupNin(idNo, deps);
    if (!rec.found) return { result: 'notfound' };
    return matchId(rec, accountName, dob);
  } catch (e) {
    console.error('ID check unavailable:', e.message);
    return { result: 'unchecked', failed: true };
  }
}

module.exports = { readNinResponse, matchId, lookupNin, checkKycId };
