# Round 1 fixes (money bugs 1-7)

1. Plan extend can only move the unlock date LATER (server rule + app date picker). Max 10 years.
2. Membership payments are now tracked (PendingPay), so the 10-minute re-check job recovers them if the webhook is lost.
3. Double membership payment: an unsettled payment under 15 minutes old returns the SAME link. A second payment that still lands goes to the member's wallet (not booked as membership income) and the member is told.
4. Real alerts: set ALERT_EMAIL and/or ALERT_WEBHOOK_URL in Render. Used for uncertain withdrawals, failed wallet refunds, payments for missing plans, failed payments, escalated tickets. Same alert sent at most once per 10 minutes.
5. Interest rate documented as YEARLY percent (rate / 365 per day), in .env.example.
6. Fingerprint sign-in: a 401 clears the stored password and turns fingerprint off (one failed try, not five). Password reset also clears it.
7. `npm test` now runs all three test files (30 tests).

New Render variables: ALERT_EMAIL, ALERT_WEBHOOK_URL.
