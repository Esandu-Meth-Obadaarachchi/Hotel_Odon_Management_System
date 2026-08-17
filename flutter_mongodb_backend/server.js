// Loads a local .env when present. Already a dependency but was never wired up.
// Does not override variables that are already set, so Railway's own env still wins.
require('dotenv').config();

const express = require('express');
const mongoose = require('mongoose');
const bodyParser = require('body-parser');
const cors = require('cors');
const {
  ENFORCE,
  PROJECT_ID,
  makeAuthMiddleware,
  requireUser,
  createStamp,
  updateStamp,
  auditFields,
} = require('./auth');

const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());

// MongoDB connection. The URI lives in the environment (.env locally, project
// variables on Railway) — it carries the database password, so it must not sit
// in source control.
const dbURI = process.env.MONGO_URI;
if (!dbURI) {
  console.error(
    'FATAL: MONGO_URI is not set. Add it to flutter_mongodb_backend/.env for ' +
    'local runs, or to the Railway project variables for the deploy.'
  );
  process.exit(1);
}
mongoose.connect(dbURI)
  .then(() => console.log('MongoDB connected'))
  .catch(err => console.log(err));

// ── Access control ───────────────────────────────────────────────────────────
//
// Applies to the hotel app's own routes only. The AI report routes further down
// keep their own shared-secret guard and are unaffected.
//
// The allow-list lives in the database so the admin screen can edit it without
// a redeploy. It is seeded once from ALLOWED_EMAILS (or the two owner accounts)
// and cached briefly to keep it off the hot path of every request.

const settingSchema = new mongoose.Schema({
  key: { type: String, required: true, unique: true },
  value: mongoose.Schema.Types.Mixed,
  updatedAt: { type: Date, default: Date.now },
});

const Setting = mongoose.model('Setting', settingSchema);

const SEED_EMAILS = (process.env.ALLOWED_EMAILS ||
  'dinushaobadaarachchi@gmail.com,eobadaarachchi@gmail.com')
  .split(',')
  .map((e) => e.toLowerCase().trim())
  .filter(Boolean);

let allowCache = { emails: null, at: 0 };
const ALLOW_CACHE_MS = 60 * 1000;

async function allowedEmails() {
  if (allowCache.emails && Date.now() - allowCache.at < ALLOW_CACHE_MS) {
    return allowCache.emails;
  }
  let doc = await Setting.findOne({ key: 'allowedEmails' });
  if (!doc) {
    doc = await Setting.create({ key: 'allowedEmails', value: SEED_EMAILS });
    console.log(`Seeded allow-list with ${SEED_EMAILS.length} email(s)`);
  }
  const emails = (doc.value || []).map((e) => String(e).toLowerCase().trim());
  allowCache = { emails, at: Date.now() };
  return emails;
}

async function isAllowed(email) {
  return (await allowedEmails()).includes(email);
}

// Verifies the Firebase ID token when one is sent and attaches req.user.
// Never blocks on a missing token — that is requireUser's job.
app.use(makeAuthMiddleware({ isAllowed }));

console.log(
  `Auth: project=${PROJECT_ID || 'UNSET'} enforcement=${ENFORCE ? 'ON' : 'OFF (soft mode)'}`
);

// The seed accounts are the owners: always allowed, always admin, and they
// cannot be removed from the allow-list — otherwise a member added later could
// lock the owners out of their own system.
function isOwner(email) {
  return SEED_EMAILS.includes((email || '').toLowerCase().trim());
}

// Managing who has access always requires a proven identity, regardless of
// AUTH_ENFORCE.
function requireAdmin(req, res, next) {
  if (!req.user) return res.status(401).json({ message: 'Sign-in required' });
  if (!isOwner(req.user.email)) {
    return res.status(403).json({ message: 'Only the owner accounts can manage access' });
  }
  next();
}

async function saveAllowedEmails(emails) {
  await Setting.findOneAndUpdate(
    { key: 'allowedEmails' },
    { $set: { value: emails, updatedAt: new Date() } },
    { upsert: true }
  );
  allowCache = { emails: null, at: 0 }; // force a re-read on the next request
}

// Who am I? The app asks this after signing in, so the server — not a hardcoded
// list in the client — decides whether the account may use the dashboard.
app.get('/me', async (req, res) => {
  if (!req.user) return res.status(401).json({ message: 'Sign-in required' });
  res.json({
    email: req.user.email,
    name: req.user.name,
    isAdmin: isOwner(req.user.email),
    allowed: true, // reaching here means the middleware already allow-listed them
  });
});

// ── Access management (owner accounts only) ──────────────────────────────────

app.get('/admin/allowed-emails', requireAdmin, async (req, res) => {
  try {
    const emails = await allowedEmails();
    res.json({
      emails,
      owners: SEED_EMAILS, // shown as protected in the UI
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

app.post('/admin/allowed-emails', requireAdmin, async (req, res) => {
  try {
    const email = String(req.body.email || '').toLowerCase().trim();
    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return res.status(400).json({ message: 'That does not look like an email address' });
    }
    const emails = await allowedEmails();
    if (emails.includes(email)) {
      return res.status(409).json({ message: 'That address already has access' });
    }
    const next = [...emails, email];
    await saveAllowedEmails(next);
    console.log(`Access granted to ${email} by ${req.user.email}`);
    res.status(201).json({ emails: next, owners: SEED_EMAILS });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

app.delete('/admin/allowed-emails/:email', requireAdmin, async (req, res) => {
  try {
    const email = String(req.params.email || '').toLowerCase().trim();
    if (isOwner(email)) {
      return res.status(403).json({ message: 'Owner accounts cannot be removed' });
    }
    const emails = await allowedEmails();
    if (!emails.includes(email)) {
      return res.status(404).json({ message: 'That address is not on the list' });
    }
    const next = emails.filter((e) => e !== email);
    await saveAllowedEmails(next);
    console.log(`Access revoked from ${email} by ${req.user.email}`);
    res.json({ emails: next, owners: SEED_EMAILS });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

const bookingSchema = new mongoose.Schema({
  roomNumber: String,   // legacy field (single-room bookings)
  roomType: String,     // legacy field (single-room bookings)
  rooms: [{             // new: one entry per room in the booking
    roomNumber: String,
    roomType: String,
    pax: Number,
  }],
  package: String,
  extraDetails: String,
  checkIn: Date,
  checkOut: Date,
  num_of_nights: Number,
  total: String,
  advance: String,
  balanceMethod: String,
  guestName: String,
  guestPhone: String,
  mealStart: String,  // 'Lunch' or 'Dinner' — first meal on arrival day for FB/HB
  needDriver: { type: Boolean, default: false },
  ...auditFields,     // createdBy / updatedBy — stamped from the verified token
});

const Booking = mongoose.model('Booking', bookingSchema);

// Guest Schema — phone is the unique identifier
const guestSchema = new mongoose.Schema({
  phone: { type: String, required: true, unique: true, index: true },
  name:  { type: String, required: true },
}, { timestamps: true });

const Guest = mongoose.model('Guest', guestSchema);

// Helper: upsert a guest record from a booking. Skips if phone is missing.
async function upsertGuest(name, phone) {
  const cleanPhone = (phone || '').toString().trim();
  if (!cleanPhone) return; // no phone → not in guest db
  const cleanName = (name || '').toString().trim() || 'Guest';
  try {
    await Guest.findOneAndUpdate(
      { phone: cleanPhone },
      { $set: { name: cleanName }, $setOnInsert: { phone: cleanPhone } },
      { upsert: true, new: true }
    );
  } catch (e) {
    console.error('upsertGuest failed:', e.message);
  }
}

// RoomConfig Schema — single document, all rooms for the hotel
const roomConfigSchema = new mongoose.Schema({
  rooms: [{
    roomNumber: { type: String, required: true },
    baseType: { type: String, enum: ['Family', 'Double'], required: true },
    floor: { type: String, enum: ['Ground', 'Upper'], required: true },
    isBlocked: { type: Boolean, default: false },
  }],
});

const RoomConfig = mongoose.model('RoomConfig', roomConfigSchema);

const defaultRooms = [
  { roomNumber: '1',   baseType: 'Family', floor: 'Ground', isBlocked: false },
  { roomNumber: '2',   baseType: 'Double', floor: 'Ground', isBlocked: false },
  { roomNumber: '3',   baseType: 'Double', floor: 'Ground', isBlocked: false },
  { roomNumber: '4',   baseType: 'Double', floor: 'Ground', isBlocked: true  },
  { roomNumber: '5',   baseType: 'Family', floor: 'Ground', isBlocked: false },
  { roomNumber: '101', baseType: 'Family', floor: 'Upper',  isBlocked: false },
  { roomNumber: '102', baseType: 'Double', floor: 'Upper',  isBlocked: false },
  { roomNumber: '103', baseType: 'Double', floor: 'Upper',  isBlocked: false },
  { roomNumber: '104', baseType: 'Double', floor: 'Upper',  isBlocked: false },
  { roomNumber: '105', baseType: 'Double', floor: 'Upper',  isBlocked: false },
  { roomNumber: '106', baseType: 'Double', floor: 'Upper',  isBlocked: false },
  { roomNumber: '107', baseType: 'Family', floor: 'Upper',  isBlocked: false },
];

app.get('/room-config', async (req, res) => {
  try {
    let config = await RoomConfig.findOne();
    if (!config) {
      config = await RoomConfig.create({ rooms: defaultRooms });
    }
    res.json(config);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

app.put('/room-config', requireUser, async (req, res) => {
  try {
    let config = await RoomConfig.findOne();
    if (!config) {
      config = new RoomConfig({ rooms: req.body.rooms });
    } else {
      config.rooms = req.body.rooms;
    }
    const saved = await config.save();
    res.json(saved);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Routes
app.get('/bookings', async (req, res) => {
  try {
    const bookings = await Booking.find();
    res.json(bookings);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});
// Salary Schema
const salarySchema = new mongoose.Schema({
  employeeName: { type: String, required: true },
  salaryType: { type: String, required: true }, // OT, Monthly, Weekly, Commission
  amount: { type: Number, required: true },
  date: { type: Date, default: Date.now },
  createdAt: { type: Date, default: Date.now },
  ...auditFields,
});

const Salary = mongoose.model('Salary', salarySchema);

// Expense Schema
const expenseSchema = new mongoose.Schema({
  expenseName: { type: String, required: true },
  category: { type: String, required: true }, // Food, Utilities, Maintenance, etc.
  amount: { type: Number, required: true },
  date: { type: Date, required: true },
  reason: { type: String }, // Optional description
  createdAt: { type: Date, default: Date.now },
  ...auditFields,
});

const Expense = mongoose.model('Expense', expenseSchema);
// Routes
app.post('/bookings', requireUser, async (req, res) => {
  const booking = new Booking({
    // Attribution comes from the verified token, never from the request body,
    // so it cannot be forged by a caller.
    ...createStamp(req),
    roomNumber: req.body.roomNumber,
    roomType: req.body.roomType,
    rooms: req.body.rooms || [],
    package: req.body.package,
    extraDetails: req.body.extraDetails,
    checkIn: req.body.checkIn,
    checkOut: req.body.checkOut,
    num_of_nights: req.body.num_of_nights,
    total: req.body.total,
    advance: req.body.advance,
    balanceMethod: req.body.balanceMethod,
    guestName: req.body.guestName,
    guestPhone: req.body.guestPhone,
    mealStart: req.body.mealStart,
    needDriver: req.body.needDriver ?? false,
  });

  try {
    console.log('POST /bookings needDriver:', req.body.needDriver, '→', booking.needDriver);
    const newBooking = await booking.save();
    await upsertGuest(req.body.guestName, req.body.guestPhone);
    res.status(201).json(newBooking);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

app.put('/bookings/:id', requireUser, async (req, res) => {
    console.log("updating product");
  try {
    // Calculate the number of nights if check-in and check-out are provided
    const checkInDate = new Date(req.body.checkIn);
    const checkOutDate = new Date(req.body.checkOut);
    const num_of_nights =
      req.body.checkIn && req.body.checkOut
        ? (checkOutDate - checkInDate) / (1000 * 60 * 60 * 24)
        : undefined;

    // Prepare the update data
    const updateData = {
      roomNumber: req.body.roomNumber,
      roomType: req.body.roomType,
      rooms: req.body.rooms,
      package: req.body.package,
      extraDetails: req.body.extraDetails,
      checkIn: req.body.checkIn,
      checkOut: req.body.checkOut,
      ...(num_of_nights !== undefined && { num_of_nights }),
      total: req.body.total,
      advance: req.body.advance,
      balanceMethod: req.body.balanceMethod,
      guestName: req.body.guestName,
      guestPhone: req.body.guestPhone,
      mealStart: req.body.mealStart,
      needDriver: req.body.needDriver ?? false,
      // Records who last touched it; createdBy is deliberately left alone.
      ...updateStamp(req),
    };

    console.log('PUT /bookings needDriver:', req.body.needDriver, '→', updateData.needDriver);

    // Update booking
    const updatedBooking = await Booking.findOneAndUpdate(
      { _id: req.params.id },
      { $set: updateData },
      { new: true }
    );

    if (!updatedBooking) {
      return res.status(404).json({ message: 'Booking not found' });
    }

    await upsertGuest(req.body.guestName, req.body.guestPhone);
    res.json(updatedBooking);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

app.delete('/bookings/:id', requireUser, async (req, res) => {
  try {
    const booking = await Booking.findById(req.params.id);
    if (!booking) {
      return res.status(404).json({ message: 'Booking not found' });
    }

    // Use deleteOne for the document
    await Booking.deleteOne({ _id: req.params.id });
    res.json({ message: 'Booking deleted successfully' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// GUEST ROUTES

// One-time backfill: if guests collection is empty but bookings exist,
// extract distinct (phone, name) pairs from existing bookings.
async function backfillGuestsIfNeeded() {
  const guestCount = await Guest.estimatedDocumentCount();
  if (guestCount > 0) return;
  const bookings = await Booking.find({ guestPhone: { $exists: true, $nin: [null, ''] } });
  const seen = new Map();
  for (const b of bookings) {
    const phone = (b.guestPhone || '').toString().trim();
    if (!phone || seen.has(phone)) continue;
    seen.set(phone, { phone, name: (b.guestName || 'Guest').toString().trim() || 'Guest' });
  }
  if (seen.size === 0) return;
  try {
    await Guest.insertMany([...seen.values()], { ordered: false });
    console.log(`Backfilled ${seen.size} guests from existing bookings`);
  } catch (e) {
    console.error('Guest backfill error (continuing):', e.message);
  }
}

// List all guests with booking count + last booking date, most recent first
app.get('/guests', async (req, res) => {
  try {
    await backfillGuestsIfNeeded();
    const guests = await Guest.aggregate([
      {
        $lookup: {
          from: 'bookings',
          localField: 'phone',
          foreignField: 'guestPhone',
          as: 'bookings',
        },
      },
      {
        $project: {
          phone: 1,
          name: 1,
          createdAt: 1,
          updatedAt: 1,
          bookingCount: { $size: '$bookings' },
          lastBooking: { $max: '$bookings.checkIn' },
        },
      },
      { $sort: { lastBooking: -1, name: 1 } },
    ]);
    res.json(guests);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Search guests by name OR phone (case-insensitive prefix-ish match) — used for autocomplete
app.get('/guests/search', async (req, res) => {
  try {
    const q = (req.query.q || '').toString().trim();
    if (!q) return res.json([]);
    const safe = q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); // escape regex meta chars
    const regex = new RegExp(safe, 'i');
    const guests = await Guest.find({
      $or: [{ name: regex }, { phone: regex }],
    })
      .limit(10)
      .sort({ updatedAt: -1 });
    res.json(guests);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Get a single guest by phone
app.get('/guests/:phone', async (req, res) => {
  try {
    const guest = await Guest.findOne({ phone: req.params.phone });
    if (!guest) return res.status(404).json({ message: 'Guest not found' });
    res.json(guest);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Get all bookings for a guest (sorted most recent first)
app.get('/guests/:phone/bookings', async (req, res) => {
  try {
    const bookings = await Booking.find({ guestPhone: req.params.phone }).sort({ checkIn: -1 });
    res.json(bookings);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

app.listen(port, "0.0.0.0",() => {
  console.log(`Server is running on port http://15.207.116.36:3000`);
});

app.get('/', (req, res) => {
    res.send('🟢 Server is running boii!');
});

//////Run server on localhost
//app.listen(port, '192.168.1.26', () => {
//  console.log(`Server running on http://192.168.1.26:${port}`);
//});


// Inventory Schema
const inventorySchema = new mongoose.Schema({
  item_name: { type: String, required: true }, // Item name
  quantity: { type: Number, required: true, default: 0 }, // Quantity
  purchasedDate: Date,
  uploaded_time: { type: Date, default: Date.now }, // Timestamp of record creation/update
});

const Inventory = mongoose.model('Inventory', inventorySchema);


// Inventory Routes
// Get all inventory items
app.get('/inventory', async (req, res) => {
  try {
    const items = await Inventory.find();
    res.json(items);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Add or update an inventory item
app.post('/inventory', requireUser, async (req, res) => {
  const { item_name, quantity, purchasedDate} = req.body;

  if (!item_name || quantity == null) {
    return res.status(400).json({ message: 'Item ID, name, and quantity are required' });
  }

  try {
    const existingItem = await Inventory.findOne({item_name});

    if (existingItem) {
      // If the item exists, update its quantity
      existingItem.quantity += quantity;
      existingItem.uploaded_time = Date.now();
      const updatedItem = await existingItem.save();
      existingItem.purchasedDate = purchasedDate;
      res.json(updatedItem);
    } else {
      // If the item doesn't exist, create a new record
      const newItem = new Inventory({
        ...createStamp(req),
        item_name,
        quantity,
        purchasedDate
      });
      const savedItem = await newItem.save();
      res.status(201).json(savedItem);
    }
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

app.put('/inventory/:id', requireUser, async (req, res) => {
  console.log("Updating inventory item");
  try {
    // Prepare the update data
    const updateData = {
      item_name: req.body.item_name,
      quantity: req.body.quantity,
      purchasedDate: req.body.purchasedDate,
      ...updateStamp(req),
    };

    // Update inventory item
    const updatedInventoryItem = await Inventory.findOneAndUpdate(
      { _id: req.params.id },
      updateData,
      { new: true } // Return the updated document
    );

    if (!updatedInventoryItem) {
      return res.status(404).json({ message: 'Inventory item not found' });
    }

    res.json(updatedInventoryItem);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

app.delete('/inventory/:id', requireUser, async (req, res) => {
  try {
    const inventory = await Inventory.findById(req.params.id);
    if (!Inventory) {
      return res.status(404).json({ message: 'inventory not found' });
    }

    // Use deleteOne for the document
    await Inventory.deleteOne({ _id: req.params.id });
    res.json({ message: 'Inventory deleted successfully' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});



// SALARY ROUTES

// Get all salary records
app.get('/salaries', async (req, res) => {
  try {
    const salaries = await Salary.find().sort({ createdAt: -1 });
    res.json(salaries);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Add new salary record
app.post('/salaries', requireUser, async (req, res) => {
  const { employeeName, salaryType, amount } = req.body;

  if (!employeeName || !salaryType || !amount) {
    return res.status(400).json({ message: 'Employee name, salary type, and amount are required' });
  }

  const salary = new Salary({
    ...createStamp(req),
    employeeName: req.body.employeeName,
    salaryType: req.body.salaryType,
    amount: req.body.amount,
    date: req.body.date || Date.now()
  });

  try {
    const newSalary = await salary.save();
    res.status(201).json(newSalary);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Update salary record
app.put('/salaries/:id', requireUser, async (req, res) => {
  console.log("Updating salary record");
  try {
    const updateData = {
      employeeName: req.body.employeeName,
      salaryType: req.body.salaryType,
      amount: req.body.amount,
      date: req.body.date,
      ...updateStamp(req),
    };

    const updatedSalary = await Salary.findOneAndUpdate(
      { _id: req.params.id },
      updateData,
      { new: true }
    );

    if (!updatedSalary) {
      return res.status(404).json({ message: 'Salary record not found' });
    }

    res.json(updatedSalary);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Delete salary record
app.delete('/salaries/:id', requireUser, async (req, res) => {
  try {
    const salary = await Salary.findById(req.params.id);
    if (!salary) {
      return res.status(404).json({ message: 'Salary record not found' });
    }

    await Salary.deleteOne({ _id: req.params.id });
    res.json({ message: 'Salary record deleted successfully' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// EXPENSE ROUTES

// Get all expense records
app.get('/expenses', async (req, res) => {
  try {
    const expenses = await Expense.find().sort({ createdAt: -1 });
    res.json(expenses);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Add new expense record
app.post('/expenses', requireUser, async (req, res) => {
  const { expenseName, category, amount, date } = req.body;

  if (!expenseName || !category || !amount || !date) {
    return res.status(400).json({ message: 'Expense name, category, amount, and date are required' });
  }

  const expense = new Expense({
    ...createStamp(req),
    expenseName: req.body.expenseName,
    category: req.body.category,
    amount: req.body.amount,
    date: req.body.date,
    reason: req.body.reason || ''
  });

  try {
    const newExpense = await expense.save();
    res.status(201).json(newExpense);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Update expense record
app.put('/expenses/:id', requireUser, async (req, res) => {
  console.log("Updating expense record");
  try {
    const updateData = {
      expenseName: req.body.expenseName,
      category: req.body.category,
      amount: req.body.amount,
      date: req.body.date,
      reason: req.body.reason,
      ...updateStamp(req),
    };

    const updatedExpense = await Expense.findOneAndUpdate(
      { _id: req.params.id },
      updateData,
      { new: true }
    );

    if (!updatedExpense) {
      return res.status(404).json({ message: 'Expense record not found' });
    }

    res.json(updatedExpense);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Delete expense record
app.delete('/expenses/:id', requireUser, async (req, res) => {
  try {
    const expense = await Expense.findById(req.params.id);
    if (!expense) {
      return res.status(404).json({ message: 'Expense record not found' });
    }

    await Expense.deleteOne({ _id: req.params.id });
    res.json({ message: 'Expense record deleted successfully' });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }

});


// Get expenses for a specific month
app.get('/expenses/month/:year/:month', async (req, res) => {
  try {
    const { year, month } = req.params;
    const startDate = new Date(year, month - 1, 1);
    const endDate = new Date(year, month, 0, 23, 59, 59);

    const expenses = await Expense.find({
      date: {
        $gte: startDate,
        $lte: endDate
      }
    }).sort({ date: -1 });

    res.json(expenses);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// PRICE CONFIG

const priceConfigSchema = new mongoose.Schema({
  packages: { type: mongoose.Schema.Types.Mixed, required: true },
  driverRoomPrice: { type: Number, required: true },
}, { timestamps: true });

const PriceConfig = mongoose.model('PriceConfig', priceConfigSchema);

// Get prices (seeds defaults if none exist)
app.get('/prices', async (req, res) => {
  try {
    let config = await PriceConfig.findOne();
    if (!config) {
      config = new PriceConfig({ packages: DEFAULT_PACKAGE_PRICES, driverRoomPrice: 2500 });
      await config.save();
    }
    res.json(config);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// Update prices
app.put('/prices', requireUser, async (req, res) => {
  try {
    let config = await PriceConfig.findOne();
    if (!config) {
      config = new PriceConfig({ packages: req.body.packages, driverRoomPrice: req.body.driverRoomPrice });
    } else {
      config.packages = req.body.packages;
      config.driverRoomPrice = req.body.driverRoomPrice;
      config.markModified('packages'); // required for Mixed type
    }
    await config.save();
    res.json(config);
  } catch (err) {
    res.status(400).json({ message: err.message });
  }
});

// Get salaries for a specific month
app.get('/salaries/month/:year/:month', async (req, res) => {
  try {
    const { year, month } = req.params;
    const startDate = new Date(year, month - 1, 1);
    const endDate = new Date(year, month, 0, 23, 59, 59);

    const salaries = await Salary.find({
      date: {
        $gte: startDate,
        $lte: endDate
      }
    }).sort({ date: -1 });

    res.json(salaries);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ══════════════════════════════════════════════════════════════════════════════
// AI INSIGHT REPORTS
// Additive only — no existing collection, schema or route is touched.
// The dashboard posts an already-computed metric pack; this stores and serves the
// generated reports, and only calls Claude when the cache genuinely misses.
// ══════════════════════════════════════════════════════════════════════════════
const aiInsights = require('./aiInsights');

const aiReportSchema = new mongoose.Schema({
  scope:       { type: String, required: true },          // 'month' | 'year'
  year:        { type: Number, required: true },
  month:       { type: Number, default: null },           // 0-11 for scope 'month'
  inputHash:   { type: String, required: true },          // sha256 of the source figures
  model:       { type: String },
  report:      { type: mongoose.Schema.Types.Mixed, required: true },
  usage:       { type: mongoose.Schema.Types.Mixed },
  generatedAt: { type: Date, default: Date.now },
});
aiReportSchema.index({ scope: 1, year: 1, month: 1 }, { unique: true });
const AiReport = mongoose.model('AiReport', aiReportSchema);

// Shared-secret guard. The rest of this API is unauthenticated, but these routes
// spend money, so they do not stay open. Set AI_REPORT_SECRET in the environment.
function requireAiSecret(req, res, next) {
  const expected = process.env.AI_REPORT_SECRET;
  if (!expected) {
    return res.status(503).json({ error: 'AI reports are not configured on this server (AI_REPORT_SECRET unset).' });
  }
  if (req.get('x-ai-secret') !== expected) {
    return res.status(401).json({ error: 'Unauthorised.' });
  }
  next();
}

// List cached reports for a year. The client compares inputHash against its freshly
// built pack to decide whether a report is current or stale.
app.get('/ai-reports', requireAiSecret, async (req, res) => {
  try {
    const year = parseInt(req.query.year, 10);
    if (!Number.isInteger(year)) return res.status(400).json({ error: 'year query parameter is required.' });
    const reports = await AiReport.find({ year }).sort({ scope: 1, month: 1 });
    res.json(reports);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Generate (or return cached) the report for one month.
app.post('/ai-reports/month', requireAiSecret, async (req, res) => {
  try {
    const { year, month, dataPack, force } = req.body || {};
    if (!Number.isInteger(year))  return res.status(400).json({ error: 'year is required.' });
    if (!Number.isInteger(month) || month < 0 || month > 11) return res.status(400).json({ error: 'month must be 0-11.' });
    if (!dataPack || !Array.isArray(dataPack.months)) return res.status(400).json({ error: 'dataPack is required.' });
    if (dataPack.year !== year) return res.status(400).json({ error: 'dataPack.year does not match the requested year.' });

    const inputHash = aiInsights.hashMonth(dataPack, month);
    const existing = await AiReport.findOne({ scope: 'month', year, month });

    if (existing && existing.inputHash === inputHash && !force) {
      return res.json({ cached: true, stale: false, report: existing });
    }

    const result = await aiInsights.generateMonthReport(dataPack, month);
    const saved = await AiReport.findOneAndUpdate(
      { scope: 'month', year, month },
      { scope: 'month', year, month, inputHash: result.inputHash, model: result.model,
        report: result.report, usage: result.usage, generatedAt: new Date() },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    console.log(`[ai] month ${year}-${month + 1}: ${result.usage.tool_calls} tool calls, ` +
      `${result.usage.input_tokens} in / ${result.usage.output_tokens} out, ` +
      `cache_read ${result.usage.cache_read_input_tokens}, $${result.usage.cost_usd}`);
    res.json({ cached: false, stale: false, report: saved });
  } catch (err) {
    console.error('[ai] month report failed:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// Generate (or return cached) the annual roll-up. Reads the stored monthly reports
// rather than the raw data, so closing a new month never regenerates the other eleven.
app.post('/ai-reports/year', requireAiSecret, async (req, res) => {
  try {
    const { year, dataPack, force } = req.body || {};
    if (!Number.isInteger(year)) return res.status(400).json({ error: 'year is required.' });
    if (!dataPack || !Array.isArray(dataPack.months)) return res.status(400).json({ error: 'dataPack is required.' });
    if (dataPack.year !== year) return res.status(400).json({ error: 'dataPack.year does not match the requested year.' });

    const monthly = await AiReport.find({ scope: 'month', year }).sort({ month: 1 });
    const inputHash = aiInsights.hashYear(dataPack, monthly.map(m => m.inputHash));
    const existing = await AiReport.findOne({ scope: 'year', year });

    if (existing && existing.inputHash === inputHash && !force) {
      return res.json({ cached: true, stale: false, report: existing });
    }

    const result = await aiInsights.generateYearReport(
      dataPack,
      monthly.map(m => ({ month: m.month, report: m.report }))
    );
    const saved = await AiReport.findOneAndUpdate(
      { scope: 'year', year, month: null },
      { scope: 'year', year, month: null, inputHash, model: result.model,
        report: result.report, usage: result.usage, generatedAt: new Date() },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    console.log(`[ai] year ${year}: built from ${monthly.length} monthly reports, ` +
      `${result.usage.input_tokens} in / ${result.usage.output_tokens} out, $${result.usage.cost_usd}`);
    res.json({ cached: false, stale: false, report: saved });
  } catch (err) {
    console.error('[ai] year report failed:', err.message);
    res.status(500).json({ error: err.message });
  }
});

app.delete('/ai-reports/:id', requireAiSecret, async (req, res) => {
  try {
    const deleted = await AiReport.findByIdAndDelete(req.params.id);
    if (!deleted) return res.status(404).json({ error: 'Report not found.' });
    res.json({ message: 'Report deleted.' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});
