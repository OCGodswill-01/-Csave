/**
 * Atomic balance changes. RULE: never do  doc.balance = x; doc.save()  on money.
 * That read-modify-write overwrites any change made between the read and the save
 * (a withdrawal, a deposit, a spend), which can bring spent money back or lose a credit.
 * Every function here changes the balance in ONE database operation.
 * Models are passed in so these can be tested without a database.
 */
const round2 = n => Math.round(n * 100) / 100;

// Add money to a member's wallet (creates the wallet if needed). Returns the updated wallet.
async function creditWallet(Wallet, userId, amount) {
  const opts = { upsert: true, new: true, setDefaultsOnInsert: true };
  const run = () => Wallet.findOneAndUpdate({ user: userId }, { $inc: { balance: amount } }, opts);
  try { return await run(); }
  catch (e) { if (e && e.code === 11000) return run(); throw e; }   // two first-time credits raced: the wallet now exists, retry once
}

// Idempotent credit: the same key (a Flutterwave payment id, say) can only ever be applied once.
// The key is stored on the wallet document itself, so "check" and "credit" are ONE atomic operation.
// Returns { wallet, duplicate }. Safe to call again after a crash or a retried webhook.
const KEEP_KEYS = 500;
async function creditWalletOnce(Wallet, userId, amount, key) {
  const upd = { $inc: { balance: amount }, $push: { processed: { $each: [key], $slice: -KEEP_KEYS } } };
  try {
    const w = await Wallet.findOneAndUpdate({ user: userId, processed: { $ne: key } }, upd, { upsert: true, new: true, setDefaultsOnInsert: true });
    return { wallet: w, duplicate: false };
  } catch (e) {
    if (!e || e.code !== 11000) throw e;
    // The wallet exists but the filter did not match (key already applied), or two first credits raced.
    const w = await Wallet.findOneAndUpdate({ user: userId, processed: { $ne: key } }, upd, { new: true });
    return w ? { wallet: w, duplicate: false } : { wallet: null, duplicate: true };
  }
}

// Same idea for a plan. Returns the updated plan, or null (already applied, paused, or not found).
const creditPlanOnce = (Plan, planId, amount, key) =>
  Plan.findOneAndUpdate({ _id: planId, paused: { $ne: true }, processed: { $ne: key } },
    { $inc: { balance: amount }, $push: { processed: { $each: [key], $slice: -KEEP_KEYS } } }, { new: true });

// Take money from a wallet only if enough is there. Returns the updated wallet, or null if not enough.
const debitWallet = (Wallet, userId, amount) =>
  Wallet.findOneAndUpdate({ user: userId, balance: { $gte: amount } }, { $inc: { balance: -amount } }, { new: true });

// Add money to a member's own plan, unless it is paused. Returns the updated plan, or null.
const creditPlan = (Plan, planId, userId, amount) =>
  Plan.findOneAndUpdate({ _id: planId, user: userId, paused: { $ne: true } }, { $inc: { balance: amount } }, { new: true });

/**
 * Pay one day of interest on one plan.
 * Compare-and-set: the update only lands if the balance is STILL what we read. If a
 * withdrawal or deposit slipped in, we re-read and try again, so interest is never
 * calculated on, or written back over, a stale balance. $set (not $inc) keeps the
 * balance rounded to 2 decimals. Returns { interest, balanceAfter } or null if nothing was paid.
 */
async function payInterest(Plan, plan, dailyRate, maxTries = 4, dateKey = null) {
  let cur = plan;
  for (let i = 0; i < maxTries; i++) {
    if (!cur || cur.paused || !(cur.balance > 0)) return null;
    if (dateKey && cur.lastInterestOn === dateKey) return null;      // already paid for this day (job re-run or second server)
    const interest = round2(cur.balance * dailyRate);
    if (interest < 0.01) return null;
    const next = round2(cur.balance + interest);
    const upd = await Plan.findOneAndUpdate({ _id: cur._id, balance: cur.balance, paused: { $ne: true }, ...(dateKey ? { lastInterestOn: { $ne: dateKey } } : {}) }, { $set: { balance: next, ...(dateKey ? { lastInterestOn: dateKey } : {}) } }, { new: true });
    if (upd) return { interest, balanceAfter: upd.balance };
    cur = await Plan.findById(cur._id);                               // balance changed under us: re-read and retry
  }
  return null;                                                        // still busy: skip today, never overwrite
}

module.exports = { round2, creditWallet, creditWalletOnce, creditPlanOnce, debitWallet, creditPlan, payInterest };
