const test = require('node:test');
const assert = require('node:assert/strict');
const { memberDetails, parseProfilePhoto, SENSITIVE } = require('../member-details');

const sniff = b => b[0] === 0xff && b[1] === 0xd8 ? 'image/jpeg' : null;
const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(100, 1)]);
const url = b => 'data:image/jpeg;base64,' + b.toString('base64');

const user = { name: 'Ada Obi', email: 'ada@example.com', createdAt: new Date('2026-01-02'), kycStatus: 'approved', membershipPaid: true, membershipId: 'CS-0001',
  kyc: { phone: '0801', address: '1 Aba Rd', dob: '1990-01-01', gender: 'Female', maritalStatus: 'Single', occupation: 'Trader', placeOfOrigin: 'Abia', idType: 'NIN',
    idLast4: '1234', idNumberEnc: 'SECRET-CIPHERTEXT', idHash: 'SECRET-HASH', nextOfKin: 'Chi', proofOfAddress: 'NEPA bill', submittedAt: new Date('2026-01-03') } };

test('a member sees their own details', () => {
  const d = memberDetails(user, ['selfie', 'idFront'], true, true);
  assert.equal(d.locked, false);
  assert.equal(d.name, 'Ada Obi'); assert.equal(d.email, 'ada@example.com');
  assert.equal(d.kyc.phone, '0801'); assert.equal(d.kyc.idLast4, '1234'); assert.equal(d.kyc.nextOfKin, 'Chi');
  assert.deepEqual(d.photosOnFile, ['selfie', 'idFront']); assert.equal(d.hasProfilePhoto, true);
  assert.equal(d.membershipId, 'CS-0001');
});

test('the full ID number, its hash and the photos are never sent', () => {
  const text = JSON.stringify(memberDetails(user, ['selfie'], false, true));
  assert.doesNotMatch(text, /SECRET/);
  assert.doesNotMatch(text, /idNumberEnc|idHash|passwordHash|pinHash/);
});

test('sensitive details stay hidden until the member confirms, and the values are not in the response at all', () => {
  const d = memberDetails(user, ['selfie'], false);
  assert.equal(d.locked, true);
  for (const f of SENSITIVE) assert.equal(d.kyc[f], null, f);
  const text = JSON.stringify(d);
  for (const secret of ['0801', '1 Aba Rd', '1990-01-01', 'Chi', 'Abia', '1234']) assert.doesNotMatch(text, new RegExp(secret), secret);
  assert.equal(d.kyc.occupation, 'Trader');   // ordinary details still show
  assert.equal(d.name, 'Ada Obi');
});

test('a member who has not done KYC gets kyc: null, and no membership id before paying', () => {
  const d = memberDetails({ name: 'New', email: 'n@x.ng', kycStatus: 'none', membershipPaid: false, membershipId: 'CS-9' });
  assert.equal(d.kyc, null); assert.equal(d.membershipId, null); assert.deepEqual(d.photosOnFile, []);
});

test('a real photo is accepted and its true type is used', () => {
  const r = parseProfilePhoto(url(jpeg), sniff);
  assert.equal(r.mime, 'image/jpeg'); assert.equal(r.buf.length, jpeg.length);
});

test('bad profile photos are refused', () => {
  assert.match(parseProfilePhoto('hello', sniff).error, /JPEG, PNG or WebP/);
  assert.match(parseProfilePhoto(url(Buffer.from('not an image at all')), sniff).error, /not a real photo/);
  assert.match(parseProfilePhoto(url(Buffer.concat([jpeg, Buffer.alloc(700 * 1024)])), sniff).error, /too big/);
  assert.match(parseProfilePhoto(undefined, sniff).error, /JPEG/);
});
