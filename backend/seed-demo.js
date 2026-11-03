/**
 * Seed a full demo state so reviewers can sign in immediately.
 * Usage: node seed-demo.js  (or npm run seed)
 * Requires DATABASE_URL in .env
 * SAFETY: this DELETES whole collections. It refuses to run unless the database name
 * contains demo/dev/test (or the host is localhost) AND no real users exist. See seed-guard.js.
 */
require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const { assertUriIsSafe, assertNoRealUsers } = require('./seed-guard');

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is required');
  process.exit(1);
}

async function main() {
  assertUriIsSafe(process.env.DATABASE_URL);          // refuse non-demo/non-local databases
  await mongoose.connect(process.env.DATABASE_URL);
  const db = mongoose.connection.db;
  await assertNoRealUsers(db);                        // refuse if real members exist
  console.log(`Seeding ${mongoose.connection.host}/${mongoose.connection.name} ...`);

  // Drop demo collections for a clean slate (keep other data if mixed env)
  const collections = await db.listCollections().toArray();
  for (const name of ['users', 'plans', 'wallets', 'budgets', 'expenses', 'goals', 'configs', 'audits', 'notifs', 'txs', 'ledgers']) {
    if (collections.some(c => c.name === name)) await db.collection(name).deleteMany({});
  }

  const User = mongoose.model('User', new mongoose.Schema({
    name: String, email: { type: String, unique: true, lowercase: true }, passwordHash: String, pinHash: String,
    role: { type: String, default: 'customer' }, kycStatus: { type: String, default: 'none' },
    kyc: { phone: String, address: String, dob: String, idType: String, idLast4: String, nextOfKin: String, submittedAt: Date },
    membershipPaid: Boolean, membershipPaidAt: Date, membershipId: String, membershipEmailSent: Boolean,
    referralCode: String, active: { type: Boolean, default: true }, lastLoginAt: Date,
    pinFails: { type: Number, default: 0 }, pinLockedUntil: Date,
    tokenVersion: { type: Number, default: 0 }, loginFails: { type: Number, default: 0 },
    lastCountry: String, geoBlocked: { type: Boolean, default: false }, fraudFlag: { type: Boolean, default: false },
  }, { timestamps: true }));

  const Plan = mongoose.model('Plan', new mongoose.Schema({
    user: mongoose.Schema.Types.ObjectId, type: String, title: String, balance: Number,
    unlockDate: Date, targetAmount: Number, paused: { type: Boolean, default: false }, extensionHistory: Array,
  }, { timestamps: true }));

  const Wallet = mongoose.model('Wallet', new mongoose.Schema({
    user: { type: mongoose.Schema.Types.ObjectId, unique: true }, balance: { type: Number, default: 0 },
  }, { timestamps: true }));

  const Budget = mongoose.model('Budget', new mongoose.Schema({
    user: { type: mongoose.Schema.Types.ObjectId, unique: true }, payDay: Number, rollover: Boolean,
    savingsMode: String, savingsValue: Number,
    incomes: [{ name: String, freq: String, amount: Number }],
    categories: [{ name: String, color: String, limit: Number }],
  }, { timestamps: true }));

  const Expense = mongoose.model('Expense', new mongoose.Schema({
    user: mongoose.Schema.Types.ObjectId, category: String, amount: Number, note: String, source: String, date: Date,
  }));

  const Goal = mongoose.model('Goal', new mongoose.Schema({
    user: mongoose.Schema.Types.ObjectId, name: String, target: Number, saved: Number, deadline: Date, done: Boolean,
  }, { timestamps: true }));

  const Config = mongoose.model('Config', new mongoose.Schema({
    _id: String, ratePercent: Number, categories: Array, tasks: Array,
  }));

  const admin = await User.create({
    name: 'Demo Admin', email: 'admin@csave.demo',
    passwordHash: await bcrypt.hash('admin123', 12),
    role: 'admin', kycStatus: 'approved', membershipPaid: true, membershipPaidAt: new Date(),
    membershipId: 'CS-ADMIN-001', pinFails: 0, tokenVersion: 0, lastCountry: 'NG',
  });

  const member = await User.create({
    name: 'Ada Demo', email: 'member@csave.demo',
    passwordHash: await bcrypt.hash('demo123', 12),
    pinHash: await bcrypt.hash('1234', 12),
    role: 'customer', kycStatus: 'approved',
    kyc: { phone: '08012345678', address: 'Umuahia, Abia', dob: '1995-06-15', idType: 'NIN', idLast4: '4321', nextOfKin: 'Chidi Demo', submittedAt: new Date() },
    membershipPaid: true, membershipPaidAt: new Date(), membershipId: 'CS-DEMO-001',
    referralCode: 'ADA2026', pinFails: 0, tokenVersion: 0, lastCountry: 'NG',
  });

  const unlock = new Date(); unlock.setMonth(unlock.getMonth() + 6);
  await Plan.create({ user: member._id, type: 'C_PLAN', title: 'C Plan', balance: 180000, unlockDate: unlock });
  await Plan.create({ user: member._id, type: 'MISSION', title: 'Mission Plan', balance: 65800, targetAmount: 120000 });

  await Wallet.create({ user: member._id, balance: 12500 });

  const cats = [
    { name: 'Food & groceries', color: '#ff8a3d', limit: 40000 },
    { name: 'Transport', color: '#4a86e8', limit: 15000 },
    { name: 'Utilities & bills', color: '#7c6af0', limit: 20000 },
    { name: 'Healthcare', color: '#e5484d', limit: 10000 },
    { name: 'Entertainment', color: '#1fa971', limit: 8000 },
    { name: 'Education', color: '#f0a020', limit: 5000 },
    { name: 'Airtime & data', color: '#12b5cb', limit: 5000 },
    { name: 'Other', color: '#8a8580', limit: 7000 },
  ];
  await Budget.create({
    user: member._id, payDay: 25, rollover: true, savingsMode: 'percent', savingsValue: 20,
    incomes: [{ name: 'Salary', freq: 'monthly', amount: 150000 }],
    categories: cats,
  });

  const now = new Date();
  await Expense.insertMany([
    { user: member._id, category: 'Food & groceries', amount: 8500, note: 'Market run', source: 'manual', date: now },
    { user: member._id, category: 'Transport', amount: 3200, note: 'Weekly commute', source: 'manual', date: now },
    { user: member._id, category: 'Airtime & data', amount: 2500, note: 'Data bundle', source: 'manual', date: now },
    { user: member._id, category: 'Entertainment', amount: 4000, note: 'Weekend outing', source: 'manual', date: now },
  ]);

  await Goal.create({ user: member._id, name: 'New laptop', target: 300000, saved: 45000, done: false });

  await Config.findByIdAndUpdate('interest', { ratePercent: 5 }, { upsert: true });
  await Config.findByIdAndUpdate('budget', {
    categories: cats.map(c => ({ name: c.name, color: c.color })),
    tasks: [{ emoji: '✅', text: 'Review budget' }, { emoji: '💰', text: 'Move savings first' }],
  }, { upsert: true });

  console.log('Seed complete.');
  console.log('  Admin:  admin@csave.demo / admin123  (staff OTP via email)');
  console.log('  Member: member@csave.demo / demo123  (PIN 1234)');
  console.log('  Wallet: ₦12,500 | C Plan ₦180,000 | Mission ₦65,800 / ₦120,000');
  await mongoose.disconnect();
}

main().catch(e => { console.error(e); process.exit(1); });
