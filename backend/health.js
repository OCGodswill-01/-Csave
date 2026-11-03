// Health monitor rules. Pure functions: they read a snapshot of numbers and settings and return the problems found.
// server.js collects the snapshot (collectHealthSnapshot) and runs these rules every 5 minutes while the server is live.
// No names, emails, ID numbers or secrets ever appear in a problem's text.

// Each setting the server needs. env[name] is true when it is set correctly, false when it is missing.
const ENV_RULES = [
  { name: 'FLW_SECRET_KEY', label: 'Flutterwave secret key (FLW_SECRET_KEY)', severity: 'critical',
    why: 'No payment can start and no payout can be sent without it.',
    fix: 'Add FLW_SECRET_KEY in Render (Environment).' },
  { name: 'FLW_WEBHOOK_HASH', label: 'Flutterwave webhook hash (FLW_WEBHOOK_HASH)', severity: 'critical',
    why: 'Every payment message is rejected, so payments only credit when the slower re-check job finds them.',
    fix: 'Set FLW_WEBHOOK_HASH (16 characters or more) here, and the same value in the Flutterwave dashboard.' },
  { name: 'TOKEN_KEY', label: 'Card token key (TOKEN_KEY)', severity: 'warning',
    why: 'Auto-save stays off, and saved card tokens cannot be protected.',
    fix: 'Generate one with: openssl rand -hex 32, and set TOKEN_KEY in Render.' },
  { name: 'RESEND_API_KEY', label: 'Email key (RESEND_API_KEY)', severity: 'warning',
    why: 'No emails go out, so staff sign-in codes and receipts never arrive.',
    fix: 'Set RESEND_API_KEY, and an EMAIL_FROM on a domain verified in Resend.' },
  { name: 'ALERT_TARGET', label: 'Alert recipient (ALERT_EMAIL or ALERT_WEBHOOK_URL)', severity: 'warning',
    why: 'When money or a ticket needs a person, nobody is told.',
    fix: 'Set ALERT_EMAIL, or ALERT_WEBHOOK_URL for Slack, Discord, Make or Zapier.' },
  { name: 'PAYMENT_RETURN', label: 'Payment return page (PAYMENT_REDIRECT_URL or PUBLIC_BASE_URL)', severity: 'warning',
    why: 'Members are not sent back to the CSave payment page after they pay.',
    fix: 'Set PAYMENT_REDIRECT_URL to https://your-server-address/pay/return' },
  { name: 'DOJAH_KEYS', label: 'BVN checking (DOJAH_APP_ID and DOJAH_SECRET_KEY)', severity: 'warning',
    why: 'BVN numbers are accepted without being checked against the register.',
    fix: 'Set DOJAH_APP_ID and DOJAH_SECRET_KEY in Render.' },
  { name: 'TELEMETRY_KEY', label: 'App reporting key (TELEMETRY_KEY)', severity: 'info',
    why: 'Crashes and session counts from the app are not recorded.',
    fix: 'Set TELEMETRY_KEY to the same value as in app/flutter_app.env.' },
  { name: 'DEEPSEEK_API_KEY', label: 'AI key (DEEPSEEK_API_KEY)', severity: 'info',
    why: 'The coach, the Help chat and the admin AI will not answer.',
    fix: 'Set DEEPSEEK_API_KEY, or set AI_ENABLED=0 if you want the AI switched off on purpose.' },
  { name: 'ADMIN_WEB_URL', label: 'Console address (ADMIN_WEB_URL)', severity: 'info',
    why: 'Staff invite links will not open the console.',
    fix: 'Set ADMIN_WEB_URL to the public address of this server.' },
];

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/**
 * Returns the problems found in [s]. Each problem: { key, severity, area, title, detail, fix }.
 * The same problem always has the same key, so the server can tell a new problem from one it already knows.
 */
function evaluateHealth(s) {
  const out = [];
  const add = (key, severity, area, title, detail, fix) => out.push({ key, severity, area, title, detail, fix });

  // The platform itself
  if (!s.dbConnected) add('db.down', 'critical', 'Platform', 'The database is not connected',
    'The server cannot reach MongoDB. Members cannot sign in or pay while this lasts.',
    'Check DATABASE_URL in Render, and the database status in MongoDB Atlas.');
  if (s.memoryMb > 450) add('mem.high', 'warning', 'Platform', `Memory use is high (${s.memoryMb} MB)`,
    'Memory that keeps climbing can end in a restart while payments are in progress.',
    'Check the server logs for a steady rise. Restart the service in Render if it keeps climbing.');
  if (s.lastRecheckAgeMin != null && s.lastRecheckAgeMin > 30) add('job.recheck', 'warning', 'Platform',
    'The payment re-check job has stopped running',
    `It last ran ${Math.round(s.lastRecheckAgeMin)} minutes ago. Payments that were paid but never confirmed will not be found until it runs again.`,
    'Check the server logs for errors. The service may have restarted or gone to sleep.');

  // Money
  if (s.paymentsStuck > 0) add('pay.stuck', s.paymentsStuck >= 5 ? 'critical' : 'warning', 'Money',
    `${plural(s.paymentsStuck, 'payment has', 'payments have')} not been confirmed after 30 minutes`,
    'Flutterwave may have taken the money while our confirmation never arrived. The re-check job asks Flutterwave about these every 10 minutes.',
    'If the number does not fall within an hour, look up the references in the Flutterwave dashboard.');
  if (s.withdrawalsReview > 0) add('wd.review', 'critical', 'Money',
    `${plural(s.withdrawalsReview, 'withdrawal needs', 'withdrawals need')} a person to check`,
    'The payout network failed partway through. These were not refunded automatically, because the money may already have left.',
    'Finance: check each reference in Flutterwave before refunding anything. Use Finance, then Transactions.');
  if (s.withdrawalsStuck > 0) add('wd.stuck', 'warning', 'Money',
    `${plural(s.withdrawalsStuck, 'withdrawal is', 'withdrawals are')} still waiting for payout confirmation after 6 hours`,
    'Flutterwave has not confirmed these payouts yet. Members see them as pending.',
    'Check the transfers in Flutterwave by their reference.');

  // Members and verification
  if (s.kycOverdue > 0) add('kyc.overdue', 'warning', 'Members',
    `${plural(s.kycOverdue, 'KYC submission has', 'KYC submissions have')} waited more than 3 days`,
    'Members with KYC waiting cannot withdraw or unlock referrals.',
    'Operations: review them in Members.');
  if (s.bvnFailing) add('bvn.failing', 'warning', 'Verification', 'BVN checks are failing',
    'Dojah did not answer properly in the last 24 hours, so new BVN submissions are going to staff unchecked.',
    'Check the Dojah dashboard: the keys, the account balance and the service status.');

  // Auto-save
  if (s.autosaveFailing > 0) add('auto.failing', 'warning', 'Auto-save',
    `${plural(s.autosaveFailing, 'auto-save rule has', 'auto-save rules have')} failed 3 times or more`,
    'Members are told when auto-save pauses. The usual cause is an expired or unfunded card.',
    'Look up the affected members in Members. They can link a card again in the app.');
  if (s.autosaveOverdue > 0) add('auto.overdue', 'warning', 'Auto-save',
    `${plural(s.autosaveOverdue, 'active auto-save rule is', 'active auto-save rules are')} more than 2 hours overdue`,
    'Scheduled charges may not be running.',
    'Check the server logs for auto-save errors, and that the Render service stays awake.');

  // The app and its users
  if (s.crashRate24h != null && s.crashRate24h >= 5 && s.sessions24h >= 20) add('app.crash', 'warning', 'App',
    `The app crash rate is ${s.crashRate24h}% over the last 24 hours`,
    `${s.crashes24h} crash report(s) from ${s.sessions24h} sessions.`,
    'Open Technical, then Crashes, and fix the most common problem first.');
  if (s.failedLogins24h >= 200) add('sec.logins', 'warning', 'Security', `${s.failedLogins24h} failed sign-ins in the last 24 hours`,
    'This can be someone trying passwords at scale.',
    'Open Technical, then Security, to see the top sources.');
  if (s.staffStale > 0) add('staff.stale', 'info', 'Security',
    `${plural(s.staffStale, 'staff account has', 'staff accounts have')} not signed in for 30 days`,
    'Unused staff accounts are a risk if someone still knows the password.',
    'Deactivate the people who have left, in Staff and invites.');

  // Configuration
  for (const r of ENV_RULES) {
    if (s.env && s.env[r.name] === false) add('cfg.' + r.name, r.severity, 'Configuration', `${r.label} is not set`, r.why, r.fix);
  }
  return out;
}

/** red when any unresolved critical problem exists, amber for warnings, otherwise green. */
function overallStatus(issues) {
  const open = issues.filter(i => i.status !== 'resolved');
  if (open.some(i => i.severity === 'critical')) return 'red';
  if (open.some(i => i.severity === 'warning')) return 'amber';
  return 'green';
}

module.exports = { ENV_RULES, evaluateHealth, overallStatus };
