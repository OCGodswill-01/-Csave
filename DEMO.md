# CSave 10-minute demo script

## Credentials

| Role   | Email              | Password  | Notes                          |
|--------|--------------------|-----------|--------------------------------|
| Admin  | admin@csave.demo   | admin123  | Staff OTP emailed (Resend)     |
| Member | member@csave.demo  | demo123   | PIN **1234**                   |

Membership ID: `CS-DEMO-001` · Referral: `ADA2026`

## Setup (once)

> **Warning:** `npm run seed` DELETES users, plans, wallets, transactions and ledgers. It now refuses to run unless `DATABASE_URL` points to localhost or a database whose name contains `demo`, `dev` or `test` (for example `.../csave_demo`), and it also refuses if any real (non-`@csave.demo`) user exists. **Never seed your live database.** Use a separate demo database.

```bash
cd backend
cp .env.example .env   # fill DATABASE_URL, JWT_SECRET (≥32), TOKEN_KEY (64 hex), etc.
npm install
npm run seed
npm start              # http://localhost:3000
```

```bash
cd app
# set API_BASE_URL in flutter_app.env (e.g. http://10.0.2.2:3000 for Android emulator)
flutter pub get
flutter run
```

## Admin console (http://localhost:3000/admin)

1. Sign in with admin@csave.demo / admin123 → enter the OTP from email. (KYC approval needs two different staff. For a one-person demo set `KYC_APPROVALS_REQUIRED=1` in `.env`.)
2. **Members** — demo member appears; use **Credit wallet** (admin or finance), or **View ID** on a pending KYC.
3. **Finance → Summary** — interest rate card visible (admins can tap **Change interest rate**); "Money held for members" lists plans and wallets.
4. **Audit** — rows from seed / prior actions.
5. **AI agent** — ask “How many customers do we have?” and get a real reply.

## Flutter member app

1. Sign in as member@csave.demo / demo123.
2. **Home** — Wallet action; open it → balance ₦ 12500.
3. **Budget** — income ₦150,000, four expenses in current period.
4. **Savings** — C Plan tile has **Extend** and **Pause**; Extend opens date picker without crash.
5. Background the app → lock appears. Pull notification shade → does **not** lock.
6. **Coach** — ask a question; get a real AI reply (needs DEEPSEEK_API_KEY).

## Webhook check

```bash
curl -s -X POST http://localhost:3000/api/webhooks/flutterwave \
  -H 'Content-Type: application/json' -H 'verif-hash: wrong' \
  -d '{"data":{"status":"successful"}}'
# → {"status":"rejected"}  (HTTP 401)
```

## PIN lockout check

Fire five wrong PINs against withdraw; fifth returns 401 and sets `pinLockedUntil` in Mongo. Re-run `npm run seed` to reset.

## Known limitations

- **Staff OTP:** there is no dev-mode OTP bypass. Either configure RESEND_API_KEY and read the code from the inbox, or temporarily set the seeded admin's passwordHash check in a local branch — never commit that branch.
- Auto-save requires a valid `TOKEN_KEY` (64 hex). Without it, card-token routes return 503.
- Flutterwave live keys needed for real payments; seed wallet/plans work offline for UI demos.
