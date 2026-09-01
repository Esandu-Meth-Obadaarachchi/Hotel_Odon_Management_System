// Upstash Redis cache for the bookings list.
//
// The view-bookings calendar re-reads every booking whenever it opens or the
// month changes, and that list barely moves between writes. So reads are served
// from Redis and only fall through to Mongo on a miss.
//
// Correctness comes from invalidation, not from the clock: every write path
// (create / update / delete) drops the key, so the next read rebuilds it. The
// TTL is only a backstop — it bounds how long a stale list could survive if
// something edits Mongo without going through this API (Compass, a script, an
// instance whose DEL failed).
//
// Redis is optional. With no credentials, or if Upstash is unreachable, every
// helper here quietly degrades to "no cache" and the routes still answer from
// Mongo.

const zlib = require('zlib');
const { Redis } = require('@upstash/redis');

const BOOKINGS_KEY = 'bookings:all';

// 5 minutes by default. Short enough that an out-of-band edit self-heals
// quickly, long enough that a burst of calendar reads costs one Mongo query.
const configuredTtl = Number.parseInt(process.env.BOOKINGS_CACHE_TTL, 10);
const TTL_SECONDS = Number.isFinite(configuredTtl) && configuredTtl > 0 ? configuredTtl : 300;

// Upstash caps a single record at 1 MB on the free plan. The list is stored
// gzipped, which takes ~1275 bookings from 520 KB to well under 100 KB, but a
// hard guard keeps a future-sized list from failing the write silently.
const MAX_ENTRY_BYTES = 900 * 1024;

const url = process.env.UPSTASH_REDIS_REST_URL;
const token = process.env.UPSTASH_REDIS_REST_TOKEN;

let redis = null;
if (url && token) {
  redis = new Redis({ url, token });
  console.log(`Cache: Upstash Redis enabled (bookings TTL ${TTL_SECONDS}s)`);
} else {
  console.log('Cache: UPSTASH_REDIS_REST_URL/TOKEN not set — running without a cache');
}

const enabled = () => redis !== null;

// Stored shape: { v: 1, gz: '<base64 gzipped JSON>' }. The version tag means a
// later format change can be rolled out without serving the old bytes to a
// reader that cannot parse them — an unrecognised shape is simply a miss.
function encode(bookings) {
  return {
    v: 1,
    gz: zlib.gzipSync(Buffer.from(JSON.stringify(bookings), 'utf8')).toString('base64'),
  };
}

function decode(entry) {
  if (!entry || entry.v !== 1 || typeof entry.gz !== 'string') return null;
  const json = zlib.gunzipSync(Buffer.from(entry.gz, 'base64')).toString('utf8');
  const parsed = JSON.parse(json);
  return Array.isArray(parsed) ? parsed : null;
}

async function getBookings() {
  if (!redis) return null;
  try {
    return decode(await redis.get(BOOKINGS_KEY));
  } catch (err) {
    // A corrupt or unreadable entry must never take the route down — fall
    // through to Mongo and let the next write replace it.
    console.error('Cache read failed (serving from Mongo):', err.message);
    return null;
  }
}

async function setBookings(bookings) {
  if (!redis) return;
  try {
    const entry = encode(bookings);
    if (entry.gz.length > MAX_ENTRY_BYTES) {
      console.warn(
        `Cache write skipped: ${bookings.length} bookings compress to ` +
        `${Math.round(entry.gz.length / 1024)} KB, over the ${Math.round(MAX_ENTRY_BYTES / 1024)} KB limit`
      );
      return;
    }
    await redis.set(BOOKINGS_KEY, entry, { ex: TTL_SECONDS });
  } catch (err) {
    console.error('Cache write failed (ignored):', err.message);
  }
}

// Called after every booking write. A failure here would leave a stale list
// behind, so it is logged loudly even though it cannot fail the request — the
// TTL still caps the damage at TTL_SECONDS.
async function invalidateBookings() {
  if (!redis) return;
  try {
    await redis.del(BOOKINGS_KEY);
  } catch (err) {
    console.error(
      'Cache invalidation FAILED — list may be stale until the TTL expires:',
      err.message
    );
  }
}

module.exports = {
  BOOKINGS_KEY,
  TTL_SECONDS,
  enabled,
  getBookings,
  setBookings,
  invalidateBookings,
};
