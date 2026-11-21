'use strict';
// Account deletion: the rules, the erasure recipe and the public web page.
// Google Play requires a working web link where a member can ask for their account to be deleted, plus a way to do it
// inside the app. Both use closeMemberAccount() in server.js, which uses the helpers below.

const naira = n => '₦' + Number(n).toLocaleString('en-NG');

// Returns the reason an account cannot be closed yet, or null when it can be.
// Money must never disappear with an account, so any balance or unfinished payment blocks the deletion.
function deletionBlocker({ planBalance = 0, openPayouts = 0, openPayments = 0 } = {}) {
  if (openPayouts > 0) return 'A withdrawal is still being processed. Wait until it finishes, then try again.';
  if (openPayments > 0) return 'A payment is still being confirmed. Wait a few minutes, then try again.';
  const held = Number(planBalance) || 0;
  if (held > 0) return `Your savings still hold ${naira(held)}. Withdraw it to your bank account first (a locked plan can be withdrawn only after its unlock date), then delete your account.`;
  return null;
}

// The update that erases a member's personal details but keeps the row, so payment records stay consistent.
const ERASED_FIELDS = ['pinHash', 'kyc', 'kycRejectReason', 'kycRejectedAt', 'aiConsentAt', 'referralCode', 'referredBy',
  'resetCodeHash', 'resetExpires', 'otpHash', 'otpExpires', 'pendingDevice', 'lastCountry', 'fraudReason'];
function erasedUser(id, randomPasswordHash, now = new Date()) {
  return {
    $set: { name: 'Deleted member', email: `deleted-${String(id).toLowerCase()}@deleted.invalid`, passwordHash: randomPasswordHash,
      active: false, deletedAt: now, kycStatus: 'none', kycApprovals: [], trustedDevices: [] },
    $unset: Object.fromEntries(ERASED_FIELDS.map(f => [f, 1])),
    $inc: { tokenVersion: 1 },   // every signed-in phone is logged out
  };
}

const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// The public page. Its address goes into Play Console > App content > Data safety > Account deletion link.
function deletePageHtml({ support = '' } = {}) {
  const sup = support ? `<p>Cannot sign in at all? Email <a href="mailto:${esc(support)}?subject=Delete%20my%20C%27SAVE%20account">${esc(support)}</a> from the address you registered with, and we will close your account within 30 days.</p>` : '';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Delete your C’SAVE account</title>
<style>
:root{--bg:#0b0b0b;--card:#1b1b1b;--ink:#f4f1ee;--mute:#a39e98;--gold:#d4730a;--red:#e5484d;--ok:#3fb56b}
@media (prefers-color-scheme:light){:root{--bg:#faf7f4;--card:#fff;--ink:#1c1917;--mute:#6b645d}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif}
main{max-width:640px;margin:0 auto;padding:28px 18px 60px}
h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:26px 0 8px;color:var(--gold)}
.mute{color:var(--mute)}.card{background:var(--card);border:1px solid #2a2a2a33;border-radius:14px;padding:18px;margin-top:16px}
ul,ol{padding-left:20px;margin:6px 0}li{margin:4px 0}
label{display:block;font-size:14px;margin:12px 0 4px}input[type=email],input[type=password]{width:100%;padding:13px;border-radius:10px;border:1px solid #77777788;background:transparent;color:var(--ink);font-size:16px}
.check{display:flex;gap:10px;align-items:flex-start;margin-top:14px;font-size:14px}.check input{margin-top:4px}
button{margin-top:16px;width:100%;padding:14px;border:0;border-radius:12px;background:var(--red);color:#fff;font-size:16px;font-weight:600;cursor:pointer}button[disabled]{opacity:.55}
#msg{margin-top:14px;padding:12px;border-radius:10px;display:none}#msg.err{display:block;background:#e5484d22;color:var(--red)}#msg.ok{display:block;background:#3fb56b22;color:var(--ok)}
a{color:var(--gold)}
</style></head><body><main>
<h1>Delete your C’SAVE account</h1>
<p class="mute">C’SAVE (com.abiacsave.app) by Abia C’save Service LTD</p>

<h2>Option 1: inside the app</h2>
<ol><li>Open C’SAVE and sign in.</li><li>Go to <b>Profile</b>.</li><li>Tap <b>Delete my account</b>, enter your password and confirm.</li></ol>

<h2>Option 2: on this page</h2>
<div class="card">
<form id="f" autocomplete="off">
<label for="e">Email address of your C’SAVE account</label><input id="e" type="email" required autocomplete="email">
<label for="p">Password</label><input id="p" type="password" required autocomplete="current-password">
<div class="check"><input id="c" type="checkbox" required><label for="c" style="margin:0">I understand that my account will be permanently deleted and this cannot be undone.</label></div>
<button id="b" type="submit">Delete my account</button>
<div id="msg" role="alert"></div>
</form></div>
<p class="mute">Forgot your password? Use <b>Forgot password?</b> on the sign-in screen of the app first, then come back here.</p>
${sup}

<h2>Before you delete</h2>
<ul><li>All your savings plans must be empty. Withdraw your money to your bank account first. A locked plan can be withdrawn only after its unlock date.</li>
<li>Withdrawals and payments that are still processing must finish first.</li></ul>

<h2>What is deleted right away</h2>
<ul><li>Your name, email address, phone number, address, date of birth and next of kin</li>
<li>Your ID number, your profile picture and your selfie, ID and proof-of-address photos</li>
<li>Your withdrawal PIN, password and saved card details for auto-save</li>
<li>Your budgets, expenses, goals, reminders, notifications, coach chats and support messages</li></ul>

<h2>What we keep, and why</h2>
<ul><li>Records of deposits, withdrawals, the membership fee and plan movements (amounts, dates and references). They no longer carry your name or contact details. We keep them for six years because financial record-keeping and anti-money-laundering rules require it, then they are securely deleted.</li>
<li>Security logs of actions on the platform, kept without your personal details.</li></ul>
<p class="mute">After deletion you can sign up again with the same email address as a new member.</p>
</main>
<script>
var f=document.getElementById('f'),m=document.getElementById('msg'),b=document.getElementById('b');
f.addEventListener('submit',function(ev){ev.preventDefault();m.className='';m.style.display='none';b.disabled=true;
fetch('/api/account/delete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:document.getElementById('e').value.trim(),password:document.getElementById('p').value})})
.then(function(r){return r.json().catch(function(){return{}}).then(function(j){return{ok:r.ok,j:j}})})
.then(function(x){if(x.ok){m.className='ok';m.textContent='Your account has been deleted. We sent a confirmation to your email.';f.reset();}else{m.className='err';m.textContent=x.j.error||'Something went wrong. Please try again.';b.disabled=false;}})
.catch(function(){m.className='err';m.textContent='No internet connection. Please try again.';b.disabled=false;});});
</script></body></html>`;
}

module.exports = { deletionBlocker, erasedUser, deletePageHtml, ERASED_FIELDS };
