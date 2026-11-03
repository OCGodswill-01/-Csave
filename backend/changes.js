// Maker and checker for money settings (the interest rate and the referral rule). Pure rules, no database access.
//
// 1. Admin PROPOSES a change, with a reason.
// 2. A different admin APPROVES it.
// 3. A tech user (or an admin who is neither the proposer nor the approver) PUSHES it live.
// Nobody can both propose and approve, or propose and push, the same change.

const { normaliseRule } = require('./referral');

const KINDS = ['interest', 'referral'];
const STATUS = { PROPOSED: 'proposed', APPROVED: 'approved', PUSHING: 'pushing', APPLIED: 'applied', REJECTED: 'rejected' };

const same = (a, b) => !!a && !!b && String(a) === String(b);

/** Validates a proposed change and returns the clean payload. Throws a readable Error. */
function checkChange(kind, body) {
  if (!KINDS.includes(kind)) throw new Error('Unknown kind of change.');
  if (kind === 'interest') {
    const r = Number(body?.ratePercent);
    if (!(r >= 0 && r <= 100)) throw new Error('The interest rate must be between 0 and 100 percent a year.');
    return { ratePercent: r };
  }
  return { rule: normaliseRule(body?.rule) };
}

/** Null when [userId] may approve [change]. Otherwise the reason. */
function canApprove(change, userId) {
  if (change.status !== STATUS.PROPOSED) return 'Only a proposed change can be approved.';
  if (same(change.proposedBy, userId)) return 'The person who proposed a change cannot approve it. A second admin must.';
  return null;
}

/** Null when [userId] may reject [change]. A change that is already live cannot be rejected. */
function canReject(change) {
  if (change.status === STATUS.PROPOSED || change.status === STATUS.APPROVED) return null;
  return 'This change has already been pushed live or rejected.';
}

/** Null when [userId] may push [change] live. */
function canPush(change, userId) {
  if (change.status !== STATUS.APPROVED) return 'Only an approved change can be pushed live.';
  if (same(change.proposedBy, userId) || same(change.approvedBy, userId)) return 'Whoever proposed or approved a change cannot push it.';
  return null;
}

module.exports = { KINDS, STATUS, checkChange, canApprove, canReject, canPush };
