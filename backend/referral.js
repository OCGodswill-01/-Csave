// Referral rules and rewards. Pure functions only: no database access here, so they can be tested on their own.
//
// A referral is paid once, when the referred person's membership fee is paid. The reward goes to the referrer's
// wallet, either as a percentage of the membership fee or as a fixed amount, and is never more than the fee itself.

const MEMBERSHIP_FEE = 5000;
const MAX_REFERRAL_AMOUNT = 5000;          // a fixed reward can never exceed the fee
const round2 = n => Math.round(n * 100) / 100;

/** Validates the rule an admin types. Returns { type, value }. Throws an Error whose message a person can read. */
function normaliseRule(input) {
  const type = String(input?.type || '');
  if (type === 'off') return { type: 'off', value: 0 };
  const value = Number(input?.value);
  if (!Number.isFinite(value)) throw new Error('Enter a number for the reward.');
  if (type === 'percent') {
    if (!(value > 0 && value <= 100)) throw new Error('A referral percentage must be above 0 and at most 100.');
    return { type, value: round2(value) };
  }
  if (type === 'amount') {
    if (!(value > 0 && value <= MAX_REFERRAL_AMOUNT)) throw new Error(`A referral amount must be above 0 and at most ₦${MAX_REFERRAL_AMOUNT.toLocaleString('en-US')}.`);
    return { type, value: round2(value) };
  }
  throw new Error('Choose off, percent or amount.');
}

/** What one paid referral is worth to the referrer, in naira. Zero when referrals are off. */
function rewardFor(rule, fee = MEMBERSHIP_FEE) {
  if (!rule || rule.type === 'off') return 0;
  const raw = rule.type === 'percent' ? fee * rule.value / 100 : rule.value;
  return round2(Math.min(raw, fee));
}

/** Null when the referral may be paid. Otherwise the reason it is skipped, shown to staff in the tracking list. */
function rewardBlocker(referrer, referee) {
  if (!referrer) return 'The referral code no longer matches a member.';
  if (String(referrer._id) === String(referee._id)) return 'Self-referral is not paid.';
  if (referrer.role !== 'customer') return 'The referrer is a staff account.';
  if (!referrer.membershipPaid || referrer.kycStatus !== 'approved') return 'The referrer is not a verified, paid member.';
  if (referrer.active === false) return 'The referrer account is inactive.';
  if (referrer.fraudFlag || referee.fraudFlag) return 'Held for review: an account is flagged.';
  return null;
}

module.exports = { MEMBERSHIP_FEE, MAX_REFERRAL_AMOUNT, normaliseRule, rewardFor, rewardBlocker };
