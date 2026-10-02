/**
 * Firebase ID token verification + email allow-list.
 *
 * The Flutter app signs in with Google via Firebase and sends the resulting
 * ID token as `Authorization: Bearer <token>`. This module verifies that token
 * against Google's public signing keys, so the identity attached to a request
 * is proven rather than claimed — a client cannot simply post an email string
 * and have it believed.
 *
 * No service-account key is needed: Firebase ID tokens are RS256-signed and
 * their public certs are published, so verification only needs the project id.
 *
 * Env:
 *   FIREBASE_PROJECT_ID  required — e.g. 'odon-dashboard-fin'
 *   ALLOWED_EMAILS       optional — comma-separated seed for the allow-list
 *   AUTH_ENFORCE         'true' rejects unauthenticated writes on the hotel-app
 *                        routes. Default false (soft mode: verify + attribute
 *                        when a token is sent, but still serve clients that
 *                        don't send one yet).
 *
 * Scope: this only guards the hotel app's own routes, which opt in via
 * requireUser. The AI report routes use their own shared-secret guard and are
 * deliberately untouched by any of this.
 */

const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || '';
const ENFORCE = String(process.env.AUTH_ENFORCE || '').toLowerCase() === 'true';

// Firebase ID tokens are signed with these rotating Google keys.
const client = jwksClient({
  jwksUri: 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  cache: true,
  cacheMaxEntries: 5,
  cacheMaxAge: 6 * 60 * 60 * 1000, // 6h — keys rotate roughly daily
  rateLimit: true,
  jwksRequestsPerMinute: 10,
});

function getSigningKey(header, callback) {
  client.getSigningKey(header.kid, (err, key) => {
    if (err) return callback(err);
    callback(null, key.getPublicKey());
  });
}

/** Verifies a Firebase ID token. Resolves with its claims, rejects if invalid. */
function verifyIdToken(token) {
  return new Promise((resolve, reject) => {
    if (!PROJECT_ID) {
      return reject(new Error('FIREBASE_PROJECT_ID is not set on the server'));
    }
    jwt.verify(
      token,
      getSigningKey,
      {
        algorithms: ['RS256'],
        issuer: `https://securetoken.google.com/${PROJECT_ID}`,
        audience: PROJECT_ID,
      },
      (err, claims) => {
        if (err) return reject(err);
        // `sub` is the Firebase uid and must be present on a real ID token.
        if (!claims || !claims.sub) return reject(new Error('Token has no subject'));
        resolve(claims);
      }
    );
  });
}

/**
 * Builds the auth middleware. [isAllowed] is injected (rather than read from a
 * constant) so the allow-list can live in the database and be edited from an
 * admin screen without a redeploy.
 */
function makeAuthMiddleware({ isAllowed }) {
  return async function authenticate(req, res, next) {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : null;

    if (!token) {
      // Identity is *attached* here, never required here. Blocking is the job
      // of requireUser on the routes that need it — other clients of this API
      // (the AI report routes) authenticate with their own shared secret and
      // must not be caught by this middleware.
      req.user = null;
      return next();
    }

    try {
      const claims = await verifyIdToken(token);
      const email = (claims.email || '').toLowerCase().trim();

      if (!email) {
        return res.status(403).json({ message: 'Account has no email address' });
      }
      if (!(await isAllowed(email))) {
        console.warn(`Blocked sign-in attempt from non-allow-listed email: ${email}`);
        return res.status(403).json({ message: 'This account is not allowed to use the app' });
      }

      req.user = { uid: claims.sub, email, name: claims.name || '' };
      return next();
    } catch (err) {
      // An invalid/expired token is always rejected, even in soft mode — a bad
      // token is a real signal, unlike simply not having one yet.
      console.warn('Rejected token:', err.message);
      return res.status(401).json({ message: 'Invalid or expired sign-in' });
    }
  };
}

/** Blocks writes from unauthenticated callers once enforcement is on. */
function requireUser(req, res, next) {
  if (!ENFORCE) return next();
  if (!req.user) return res.status(401).json({ message: 'Sign-in required' });
  next();
}

/** Attribution stamp for a newly created record. */
function createStamp(req) {
  return {
    createdBy: req.user ? req.user.email : null,
    createdByName: req.user ? req.user.name : '',
    createdAt: new Date(),
    updatedBy: req.user ? req.user.email : null,
    updatedByName: req.user ? req.user.name : '',
    updatedAt: new Date(),
  };
}

/** Attribution stamp for an edit — leaves the original creator untouched. */
function updateStamp(req) {
  return {
    updatedBy: req.user ? req.user.email : null,
    updatedByName: req.user ? req.user.name : '',
    updatedAt: new Date(),
  };
}

/** Mongoose fields to mix into any schema that should carry an audit trail. */
const auditFields = {
  createdBy: { type: String, default: null },
  createdByName: { type: String, default: '' },
  updatedBy: { type: String, default: null },
  updatedByName: { type: String, default: '' },
  updatedAt: { type: Date, default: null },
};

module.exports = {
  ENFORCE,
  PROJECT_ID,
  verifyIdToken,
  makeAuthMiddleware,
  requireUser,
  createStamp,
  updateStamp,
  auditFields,
};
