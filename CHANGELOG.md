# Changelog

## Version 14 (1.3) — v21 (v17 full + v19 files + v21 changed files)

Built from: csave_v17_full_1.zip (base), csave_v19_CHANGED_FILES_only.zip (limits, account deletion, tests, README, package.json, .env.example),
and csave_v21_CHANGED_FILES_only.zip (backend/server.js, backend/admin/index.html, app/lib/screens.dart — these win over v17 and v19).

### Referrals
- A referral is recorded when the referred person pays the ₦5,000 membership fee.
- It is credited into the referrer's oldest ACTIVE savings plan only when the referred person's KYC is approved,
  they have paid the fee, they have made a first deposit, the referrer is in good standing, and the referrer has an active plan.
  An active plan is one that is not paused, a C Plan before its unlock date, or a Mission Plan below its target.
- Until then the referral stays "pending", with the reason shown.
- Once credited, the amount is frozen and stays in that plan. It leaves only when that plan is withdrawn,
  and the referral is then marked withdrawn with the date and withdrawal reference. A failed payout undoes the mark.
- Referral money does not count towards the savings limit.
- Member endpoint GET /api/me/referrals: current rule, balance, earned, withdrawn, each referral and withdrawal history.
  Other members' names are shortened.
- Staff members list shows each member's referral totals. Finance shows referral money still inside member plans.
  Operations referrals table shows referred, credited, earned, balance and waiting.

### Admin and members
- Admins can deactivate a member with a reason (admin role only). A deactivated member cannot sign in,
  their money is not moved, and their auto-saves are paused. Admins can reactivate them.
- Deleted accounts cannot be reactivated. A person who deleted their account opens a new one.

### App
- "My referrals" screen in Profile (read only).

### Not changed
- Payment method: members pay through Flutterwave payment links, matched by reference. Per-member bank accounts are not built.

## Testing
Run `npm test` in `backend/`. 76 tests cover money, referrals, changes, KYC, limits, account deletion and health rules.
Not yet tested against a live database or on a device: the Flutter screens, the admin console in a browser,
and the end-to-end referral flow (fee paid, KYC approved, first deposit, credit, withdrawal, failed payout).
