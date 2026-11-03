
## Keys (server .env only, never in the app)
DEEPSEEK_API_KEY  -> AI customer service (/api/ai/chat)
RESEND_API_KEY    -> emails. EMAIL_FROM must be a domain verified in Resend (onboarding@resend.dev only delivers to your own Resend account email while testing).

## Phase 4 and 5 (budget, coach, customer service)
- Budget: 10 tabs (Overview, Income, Categories, Expenses, Goals, Calendar, Tasks, Rules, History, Settings). Periods run from pay day, unspent money rolls over.
- Coach: Insights tab is a typing chat with its own AI persona (/api/coach/chat). It never handles account problems.
- Customer service: the ? Help button is a separate AI (/api/support/chat). It answers, staff confirm or correct every answer, and it hands over to a person when it cannot resolve.
- Staff dashboard: users with role "support" or "admin" see "Customer service dashboard" in Profile. Set the role in MongoDB.
- No new keys. Same DEEPSEEK_API_KEY in the server .env.
- Android alarms: see android_notes/README_ANDROID.txt.

## Phase 6 (staff console, roles, finance, operations, tech, audit, AI agent)
- Staff web console is served by the backend at  /admin  (file: backend/admin/index.html). Set ADMIN_WEB_URL in .env so invite links point to it.
- First administrator: register one account in the app, then in MongoDB set that user's  role  to "admin". Admin then invites everyone else from "Staff and invites".
- Staff always sign in with email + password + a 6-digit emailed code. Deactivating a staff member blocks them on their very next request.
- Roles: admin (sees all), finance, operations (includes analytics), support (customer service), tech. The server enforces this, not just the screens.
- Every staff request is recorded (who, what, when, IP). Request bodies are never stored. See Audit log.
- Accounting: deposits, withdrawals and membership fees post to a trial balance automatically. Finance can post manual journals and reconcile a pasted statement. Have a qualified accountant review the chart of accounts before you rely on it for reporting.
- Crash and security tools: the app reports crashes and session counts to /api/telemetry. The Technical tab shows crash rate, security checks and health.
- AI agent (admin only): ask what happened on the platform. It reads a fresh snapshot (no member emails) and answers with DeepSeek.
- New dependency: helmet  (run npm install again).
- Account analysis: the money coach now receives the member's plans, contribution history, budget periods and top spending categories, worked out by code, and explains them when asked.

## Announcement pictures, adding money, card auto-save
- Staff console > Operations > Announcements: pick up to 5 pictures. The console crops each to the banner shape (1000 x 319, about 3:1) and shrinks it. Members see them on Home and in Notifications; 2 or more slide by themselves every 4 seconds.
- Design banners at 2000 x 638 px (same shape). The app shows them small (about 340 px wide).
- Members can add money to the C Plan or Mission Plan any day (button on each plan, and Home > Add money).
- Auto-save is per plan, charged to the member's own card and saved straight into that plan (not a wallet). The member must tick the agreement. First charge = card setup; Flutterwave returns a token (your account must have tokenization turned on). Card numbers are never stored. The token is encrypted with TOKEN_KEY.
- Make the key once:  openssl rand -hex 32  and put it in TOKEN_KEY in backend/.env. Auto-save stays off until it is set.
- After 3 failed charges the auto-save pauses and the member is told.

## What's new (this snapshot)

- **Wallet** — `/api/wallet`, fund via Flutterwave, transfer-to-plan, admin credit. Flutter `wallet.dart` screen.
- **Ledger** — every money movement writes a Ledger row: plan deposits, wallet funding, wallet-to-plan, withdrawals, membership fees, interest, staff credits and reversals of failed payouts.
- **Plan extend / pause / resume** — C Plan unlock extension with history. A paused plan takes no money: card top-ups and auto-save are refused, wallet transfers are refused, and a payment that arrives after the pause is kept in the member's wallet instead.
- **Auth hardening** — `tokenVersion` invalidates JWTs on password change; 5 failed logins → 30 min lock + email; country check on every request using Cloudflare's `cf-ipcountry` (allowed list `ALLOWED_COUNTRIES`, default NG; the easy-to-fake `x-country` header is ignored unless `TRUST_X_COUNTRY=1`); fraudFlag blocks requests; PIN lockout NaN fixed.
- **Infrastructure** — `trust proxy`, CORS, helmet CSP off (custom CSP on `/admin`), startup assert on JWT_SECRET + DATABASE_URL, HTML escape in emails.
- **Interest** — node-cron at 01:05, Config `interest.ratePercent`, admin GET/POST.
- **Rates** — `/api/rates` proxies Flutterwave.
- **Webhook** — wrong `verif-hash` returns `401`. If crediting fails the webhook returns `500`, so Flutterwave sends it again. Crediting is idempotent (each payment id is stored with the balance change in one database step), so a retry can never credit twice. Payout results arrive as `transfer.completed`; a failed payout puts the money back.
- **Seed** — `npm run seed` creates admin@csave.demo / member@csave.demo with plans, wallet, budget, goal.
- See **DEMO.md** for the 10-minute walkthrough.

## Make an admin

1. Register in the app, or use the seeded `admin@csave.demo`.
2. Or in MongoDB: `db.users.updateOne({ email: "you@x.com" }, { $set: { role: "admin" } })`.
3. Admin invites other staff from the console (72-hour token link).

## Review fixes (this snapshot)

- **Lost payments**: every payment CSave starts is remembered (`PendingPay`). A job runs every 10 minutes and asks Flutterwave about payments that were never settled (webhook lost, server down, database hiccup), then credits them through the same safe path. The webhook now answers 500 on failure.
- **Withdrawals**: written to the Ledger and to the transaction list *before* the payout is sent. A payout stays "pending" until Flutterwave confirms. If the network fails while sending, the withdrawal is marked "review" and is NOT refunded automatically (the money may have gone out); finance checks it.
- **Ledger and accounts**: wallet top-ups now count as cash in; wallet-to-plan is an internal move (no cash entry); interest and staff credits post to the trial balance; failed payouts are left out. **An accountant must review these account choices**, especially staff credits.
- **"Money held for members"** now includes wallets, with a "Total held for members" card.
- **KYC**: the full ID number is stored encrypted (`KYC_KEY`, or `TOKEN_KEY` if you do not set one) and staff can view it in the console (every view is audited). Approval needs two *different* staff (`KYC_APPROVALS_REQUIRED`, default 2; use 1 only for a one-person demo). Rejection needs one. CSave does not check the number with NIMC/NIBSS: staff must compare it with the ID document, and you should confirm the exact KYC tier rules with your partner bank (MOUAU MFB).
- **AI and member data**: members must agree before the coach or Help chat sends data to the AI provider. `AI_ENABLED=0` switches AI off; `AI_BASE_URL` points to another provider. Have a lawyer check the privacy notice and the rules for sending data abroad under the Nigeria Data Protection Act.
- **Telemetry** needs the app key (`TELEMETRY_KEY`) and a device id, counts one session per device per hour, caps crashes per device, and crash rows delete after 30 days. The key is inside the app, so this stops casual abuse only.
- **Rate limits**: each route has its own limit (they used to share one counter). Counters live in server memory; with more than one server instance, move them to Redis.
- **Interest**: each plan is paid at most once per Lagos day, so a re-run or a second server cannot pay twice.
- **Server errors**: a failed database call in any route now returns a clean 500 instead of hanging the request.
- **Packages**: removed `multer`, `p-queue`, `uuid` and the AWS S3 packages (unused). Run `npm install` again.
- **App**: members without a fingerprint stay signed in when they leave the app (under 2 minutes: no prompt; longer: password only). Calls time out after 25 seconds with a clear message, and an expired session returns to the sign-in screen.
- **Wallet "method"**: the card / USSD / bank transfer choice now selects the Flutterwave payment option.
- **Admin console**: Members has **Credit wallet** and **View ID**; Finance → Summary shows the interest rate (admins can change it).

## Payment return page, BVN checks (Dojah), health monitor

- **Payment return page**: Flutterwave now sends members to `https://<your-server>/pay/return`. Set `PAYMENT_REDIRECT_URL` in Render to that address (or set `PUBLIC_BASE_URL` and the page is used automatically). The page asks Flutterwave whether the payment really went through, then uses the same safe, idempotent path as the webhook. Optional: `PAYMENT_BACK_URL` adds a "Back to CSave" button.
- **BVN checks through Dojah**: set `DOJAH_APP_ID` and `DOJAH_SECRET_KEY` (Dojah dashboard). When a member submits a BVN as their ID, the BVN record is checked: the name must match the CSave account name (word order and a missing middle name are allowed) and the date of birth must match when it can be read. A name or date mismatch is refused with a message. A BVN that Dojah cannot find is refused. If Dojah does not answer, the submission still goes to staff, marked **NOT CHECKED** in the View ID dialog, so an outage never blocks members. The BVN number is still stored encrypted, and only the outcome is kept, not the name Dojah returns.
- **Health monitor**: runs inside the server every 5 minutes, for as long as the server is live. Staff see it in **Technical → Health monitor**: an overall green, amber or red status, the open problems with what to do about each, and problems resolved in the last 7 days. It watches stuck payments, withdrawals that need a person, overdue KYC, auto-save failures, the payment re-check job, the crash rate, failed sign-ins, unused staff accounts, and missing settings. Critical problems also trigger an alert to ALERT_EMAIL or ALERT_WEBHOOK_URL (once per problem every 10 minutes). **Explain and prioritise with AI** sends only the problem list to DeepSeek (no names, emails or secrets) and asks for a ranked plan.
- **Tests**: `npm test` now also runs `test/bvn.test.js` and `test/health.test.js`.
- No Flutter changes are needed: the KYC screen already has a BVN option and shows the server's messages.
