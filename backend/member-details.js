'use strict';
// What a member may see about themselves, and the rules for their profile picture.
// The full ID number and the KYC photos are never sent to the phone: only the last 4 digits and which photos are on file.

// Hidden until the member proves it is them (password) in the app: contact, address, birth date, family and ID digits.
const SENSITIVE = ['phone', 'address', 'dob', 'nextOfKin', 'placeOfOrigin', 'idLast4'];

function memberDetails(u, photoSlots = [], hasProfilePhoto = false, reveal = false) {
  const k = u.kyc || {};
  const kyc = k.submittedAt ? {
      phone: k.phone, address: k.address, dob: k.dob, gender: k.gender, maritalStatus: k.maritalStatus, occupation: k.occupation,
      placeOfOrigin: k.placeOfOrigin, idType: k.idType, idLast4: k.idLast4, nextOfKin: k.nextOfKin, proofOfAddress: k.proofOfAddress, submittedAt: k.submittedAt,
    } : null;
  if (kyc && !reveal) for (const f of SENSITIVE) kyc[f] = null;   // the values never leave the server until confirmed
  return {
    locked: !reveal,
    name: u.name, email: u.email, memberSince: u.createdAt || null,
    kycStatus: u.kycStatus, membershipPaid: !!u.membershipPaid, membershipId: u.membershipPaid ? (u.membershipId || null) : null,
    kyc,
    photosOnFile: photoSlots,
    hasProfilePhoto: !!hasProfilePhoto,
  };
}

const PHOTO_MAX_BYTES = 600 * 1024;
// Checks a profile picture sent as a data URL. Returns { buf, mime } or { error }.
function parseProfilePhoto(dataUrl, sniff, maxBytes = PHOTO_MAX_BYTES) {
  const m = /^data:image\/(?:jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/.exec(String(dataUrl || ''));
  if (!m) return { error: 'Use a JPEG, PNG or WebP photo.' };
  const buf = Buffer.from(m[1], 'base64'), mime = sniff(buf);
  if (!mime) return { error: 'That file is not a real photo.' };
  if (buf.length > maxBytes) return { error: 'That photo is too big. Pick a smaller one.' };
  return { buf, mime };
}

module.exports = { memberDetails, parseProfilePhoto, PHOTO_MAX_BYTES, SENSITIVE };
