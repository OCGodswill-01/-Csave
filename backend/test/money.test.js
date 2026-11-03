// Run:  npm test      (Node 18+, no database needed: uses a tiny in-memory stand-in for MongoDB)
const test = require('node:test'), assert = require('node:assert/strict');
const { creditWallet, creditWalletOnce, creditPlanOnce, debitWallet, creditPlan, payInterest } = require('../money');

// --- minimal stand-in for a Mongoose model: each single operation is atomic, like MongoDB ---
function model({ unique } = {}) {
  const docs = []; let n = 0; const m = { docs, beforeUpdate: null };
  const match = (d, f) => Object.entries(f).every(([k, v]) => {
    if (v && typeof v === 'object') { if ('$ne' in v) return Array.isArray(d[k]) ? !d[k].includes(v.$ne) : d[k] !== v.$ne; if ('$gte' in v) return d[k] >= v.$gte; }
    return String(d[k]) === String(v);
  });
  const build = o => { if (unique && docs.some(d => d[unique] === o[unique])) throw Object.assign(new Error('dup'), { code: 11000 }); const d = { _id: 'id' + (++n), balance: 0, paused: false, ...o }; docs.push(d); return d; };
  m.create = async o => build(o);
  m.findById = async id => { const d = docs.find(x => x._id === id); return d && { ...d }; };
  m.findOneAndUpdate = async (f, u, o = {}) => {
    if (m.beforeUpdate) { const h = m.beforeUpdate; m.beforeUpdate = null; await h(docs); }   // lets a test slip another request in between
    let d = docs.find(x => match(x, f));
    if (!d) { if (!o.upsert) return null; d = build({ ...Object.fromEntries(Object.entries(f).filter(([, v]) => typeof v !== 'object')) }); }
    if (u.$inc) for (const [k, v] of Object.entries(u.$inc)) d[k] = (d[k] || 0) + v;
    if (u.$push) for (const [k, v] of Object.entries(u.$push)) { const arr = (d[k] = d[k] || []); arr.push(...(v.$each || [v])); if (v.$slice) d[k] = arr.slice(v.$slice); }
    if (u.$set) Object.assign(d, u.$set);
    return { ...d };
  };
  return m;
}
const plan = (balance, extra = {}) => ({ _id: 'p1', user: 'u1', balance, paused: false, ...extra });

test('wallet: 50 simultaneous credits all count (no lost updates)', async () => {
  const W = model({ unique: 'user' });
  await Promise.all(Array.from({ length: 50 }, () => creditWallet(W, 'u1', 100)));
  assert.equal(W.docs.length, 1); assert.equal(W.docs[0].balance, 5000);
});

test('wallet: OLD pattern loses money, NEW pattern does not', async () => {
  const W = model({ unique: 'user' }); await W.create({ user: 'u1', balance: 1000 });
  const stale = await W.findById('id1');                       // old code read the wallet...
  await debitWallet(W, 'u1', 900);                             // ...member spends 900 meanwhile...
  stale.balance += 500; W.docs[0].balance = stale.balance;     // ...old code then saves the stale value
  assert.equal(W.docs[0].balance, 1500, 'old way brings the spent 900 back (this is the bug)');
  const W2 = model({ unique: 'user' }); await W2.create({ user: 'u1', balance: 1000 });
  await debitWallet(W2, 'u1', 900); await creditWallet(W2, 'u1', 500);
  assert.equal(W2.docs[0].balance, 600, 'new way: 1000 - 900 + 500');
});

test('wallet: cannot spend more than the balance', async () => {
  const W = model({ unique: 'user' }); await W.create({ user: 'u1', balance: 300 });
  assert.equal(await debitWallet(W, 'u1', 301), null); assert.equal(W.docs[0].balance, 300);
  assert.equal((await debitWallet(W, 'u1', 300)).balance, 0);
  assert.equal(await debitWallet(W, 'u1', 1), null);
});

test('plan credit: refuses paused plans and other members', async () => {
  const P = model(); await P.create(plan(1000, { paused: true }));
  assert.equal(await creditPlan(P, 'p1', 'u1', 50), null);
  P.docs[0].paused = false;
  assert.equal(await creditPlan(P, 'p1', 'someone-else', 50), null);
  assert.equal((await creditPlan(P, 'p1', 'u1', 50)).balance, 1050);
});

test('interest: normal day, rounded to 2 decimals', async () => {
  const P = model(); const p = await P.create(plan(10000));
  const r = await payInterest(P, p, 0.05 / 365);
  assert.deepEqual(r, { interest: 1.37, balanceAfter: 10001.37 });
});

test('interest: member withdraws while interest runs -> balance stays 0 (money is NOT brought back)', async () => {
  const P = model(); const p = await P.create(plan(50000));    // job has read 50,000
  P.beforeUpdate = docs => { docs[0].balance = 0; };            // withdrawal lands before the job writes
  const r = await payInterest(P, p, 0.05 / 365);
  assert.equal(r, null); assert.equal(P.docs[0].balance, 0);
});

test('interest: deposit arrives mid-run -> deposit kept, interest recalculated on new balance', async () => {
  const P = model(); const p = await P.create(plan(1000));
  P.beforeUpdate = docs => { docs[0].balance = 1500; };
  const r = await payInterest(P, p, 0.10 / 365);
  assert.equal(r.interest, 0.41); assert.equal(P.docs[0].balance, 1500.41);
});

test('interest: constant contention -> gives up safely, never overwrites', async () => {
  const P = model(); const p = await P.create(plan(1000));
  const orig = P.findOneAndUpdate; let bump = 0;
  P.findOneAndUpdate = async (...a) => { P.docs[0].balance = 1000 + (++bump); return orig(...a); };
  assert.equal(await payInterest(P, p, 0.05 / 365, 3), null);
  assert.equal(P.docs[0].balance, 1000 + bump, 'balance is exactly what the other requests left');
});

test('interest: paused plans and tiny balances are skipped', async () => {
  const P = model();
  assert.equal(await payInterest(P, await P.create(plan(1000, { paused: true })), 0.0001), null);
  assert.equal(await payInterest(P, plan(0.5), 0.0001), null);
});

// ---------- retried payments and the once-a-day interest rule ----------
test('wallet: the same payment applied twice (webhook retry) credits ONCE', async () => {
  const W = model({ unique: 'user' });
  const a = await creditWalletOnce(W, 'u1', 5000, 'flw_1'), b = await creditWalletOnce(W, 'u1', 5000, 'flw_1');
  assert.equal(a.duplicate, false); assert.equal(b.duplicate, true);
  assert.equal(W.docs[0].balance, 5000);
});

test('wallet: 20 simultaneous deliveries of the same payment credit once; different payments all count', async () => {
  const W = model({ unique: 'user' });
  await Promise.all(Array.from({ length: 20 }, () => creditWalletOnce(W, 'u1', 1000, 'flw_same')));
  assert.equal(W.docs.length, 1); assert.equal(W.docs[0].balance, 1000);
  await Promise.all(Array.from({ length: 10 }, (_, i) => creditWalletOnce(W, 'u1', 100, 'flw_' + i)));
  assert.equal(W.docs[0].balance, 2000);
});

test('plan: a payment is applied once, and a paused plan takes nothing', async () => {
  const P = model(); await P.create(plan(0));
  assert.equal((await creditPlanOnce(P, 'p1', 700, 'flw_9')).balance, 700);
  assert.equal(await creditPlanOnce(P, 'p1', 700, 'flw_9'), null, 'same payment again: no second credit');
  P.docs[0].paused = true;
  assert.equal(await creditPlanOnce(P, 'p1', 300, 'flw_10'), null, 'paused plan must not be credited');
  assert.equal(P.docs[0].balance, 700);
});

test('interest: at most one payment per plan per day, even if the job runs twice', async () => {
  const P = model(); await P.create(plan(100000));
  const first = await payInterest(P, await P.findById('p1'), 0.001, 4, '2026-10-30');
  const again = await payInterest(P, await P.findById('p1'), 0.001, 4, '2026-10-30');
  assert.equal(first.interest, 100); assert.equal(again, null);
  assert.equal(P.docs[0].balance, 100100);
  const nextDay = await payInterest(P, await P.findById('p1'), 0.001, 4, '2026-10-31');
  assert.ok(nextDay && nextDay.interest > 100);
});
