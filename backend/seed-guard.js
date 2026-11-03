/**
 * Safety checks for seed-demo.js, which DELETES whole collections.
 * Two layers: (1) the connection string must look like a demo/dev/local database,
 * (2) once connected, the database must hold no real (non-demo) users.
 * Override (only if you truly mean it): SEED_FORCE_WIPE=I_UNDERSTAND_THIS_DELETES_EVERYTHING
 */
const FORCE_PHRASE = 'I_UNDERSTAND_THIS_DELETES_EVERYTHING';

function describeTarget(uri) {
  const m = /^mongodb(?:\+srv)?:\/\/(?:[^@/]*@)?([^/?]+)(?:\/([^?]*))?/i.exec(String(uri || '').trim());
  if (!m) return { host: '', db: '' };
  return { host: m[1].toLowerCase(), db: decodeURIComponent(m[2] || '').toLowerCase() };
}

function uriLooksSafe(uri) {
  const { host, db } = describeTarget(uri);
  if (!host) return { ok: false, host, db };
  const localHost = /^(localhost|127\.0\.0\.1|\[::1\]|mongo|mongodb|host\.docker\.internal)(:\d+)?$/.test(host.split(',')[0]);
  const demoName = /(^|[-_.])(demo|dev|test|local|sandbox|seed)([-_.]|$)/.test(db);
  return { ok: localHost || demoName, host, db };
}

function forced() { return process.env.SEED_FORCE_WIPE === FORCE_PHRASE; }

/** Step 1: call BEFORE connecting. Exits the process if the target looks real. */
function assertUriIsSafe(uri) {
  const t = uriLooksSafe(uri);
  if (t.ok) return;
  if (forced()) { console.warn(`WARNING: SEED_FORCE_WIPE set. Wiping ${t.host}/${t.db || '(default db)'}.`); return; }
  console.error(`REFUSING TO SEED: "${t.host}/${t.db || '(default db)'}" does not look like a demo or local database.
Seeding deletes users, plans, wallets, transactions and ledgers.
Use a database whose name contains "demo", "dev" or "test" (e.g. .../csave_demo), or run against localhost.`);
  process.exit(1);
}

/** Step 2: call AFTER connecting, BEFORE deleting. Exits if real members exist. */
async function assertNoRealUsers(db) {
  const names = (await db.listCollections().toArray()).map(c => c.name);
  if (!names.includes('users')) return;
  const real = await db.collection('users').countDocuments({ email: { $not: /@csave\.demo$/i } });
  if (real === 0) return;
  if (forced()) { console.warn(`WARNING: SEED_FORCE_WIPE set. Deleting ${real} real user(s).`); return; }
  console.error(`REFUSING TO SEED: this database already has ${real} non-demo user(s). Nothing was deleted.`);
  process.exit(1);
}

module.exports = { describeTarget, uriLooksSafe, assertUriIsSafe, assertNoRealUsers, FORCE_PHRASE };
