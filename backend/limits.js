'use strict';
// Savings limit for now: a member can hold at most SAVINGS_CAP naira in total across their plans. Default 300,000.
// It is one number for everyone. To raise it later (for example once the partner bank gives each member their own account),
// change SAVINGS_CAP in Render. No new release is needed.
// Pure functions, so they are tested without a database.

const DEFAULT_CAP = 300000;

function capFor(env = process.env) {
  const base = Number(env.SAVINGS_CAP);
  return base > 0 ? Math.round(base) : DEFAULT_CAP;
}

// held = what the member already has in their plans. incoming = the new payment they are about to make.
function checkRoom({ held, incoming, cap }) {
  const h = Math.max(0, Number(held) || 0), add = Math.max(0, Number(incoming) || 0);
  return { ok: h + add <= cap, room: Math.max(0, cap - h), held: h, cap };
}

const naira = n => '₦' + Math.round(n).toLocaleString('en-NG');

function limitMessage(cap, room) {
  return `For now you can keep up to ${naira(cap)} in total in CSave. ` +
    (room > 0 ? `You can still add ${naira(room)}.` : 'You have reached that limit.') +
    ' This limit protects your money while we complete our partnership with our partner bank. It will be raised later.';
}

// The sentence members agree to. Shown at KYC, at membership payment, and inside the auto-save consent.
function limitNotice(cap) {
  return `Savings limit: for now you cannot keep more than ${naira(cap)} in total in CSave. ` +
    'CSave will not accept a payment that takes you above it. We will raise the limit once our partner bank arrangement is in place.';
}

module.exports = { DEFAULT_CAP, capFor, checkRoom, limitMessage, limitNotice };
