# Backend — auth & audit trail

## Environment variables (set these in Railway)

| Variable | Required | Purpose |
|---|---|---|
| `FIREBASE_PROJECT_ID` | **yes** | `odon-dashboard-fin`. Without it every token is rejected. |
| `AUTH_ENFORCE` | no | `true` = reject requests with no sign-in. Defaults to `false`. |
| `ALLOWED_EMAILS` | no | Comma-separated seed for the allow-list. Only used on first boot. |
| `MONGO_URI` | no | Falls back to the URI hardcoded in `server.js` — see security note. |

## Rollout order — important

`AUTH_ENFORCE` defaults to **off** on purpose. The mobile app has no Firebase
sign-in yet, so it sends no token; turning enforcement on before mobile sign-in
ships would lock the front desk out of the app entirely.

Soft mode (`AUTH_ENFORCE` unset or `false`) behaves like this:

- Request **with** a valid token → verified, allow-list checked, record stamped
  with the signer's email.
- Request **with an invalid or expired token** → rejected with 401. A bad token
  is always a real signal.
- Request **with no token** → allowed through, record stamped `createdBy: null`.

So the web app starts producing a real audit trail immediately, while mobile
keeps working unattributed. Once mobile sign-in is added, set
`AUTH_ENFORCE=true` and the API is closed to everything else.

## How identity is established

Firebase ID tokens are RS256-signed by Google. `auth.js` fetches Google's
published public keys and verifies the signature, issuer and audience, so the
identity on a request is proven rather than claimed. No service-account key is
needed, which means no secret to leak.

Attribution (`createdBy` / `updatedBy`) is always taken from the verified token
claims and never from the request body — a client cannot post someone else's
email and have it recorded.

## The allow-list

Stored in Mongo as a `settings` document with `key: 'allowedEmails'`, seeded on
first boot from `ALLOWED_EMAILS` (or the two owner accounts). It is read through
a 60-second cache.

It lives in the database rather than in code so an admin settings screen can
edit it later without a redeploy. Until that screen exists, add a user by
editing the document directly:

```js
db.settings.updateOne(
  { key: 'allowedEmails' },
  { $addToSet: { value: 'newperson@gmail.com' } }
)
```

Changes take effect within a minute.

## Audit fields

`bookings`, `expenses`, `salaries` and `inventory` records carry:

`createdBy`, `createdByName`, `createdAt`, `updatedBy`, `updatedByName`, `updatedAt`

Records written before this change have `null` creators; the UI simply omits
the line for them rather than showing a blank.

## Security note — outstanding

The MongoDB connection string is committed in `server.js`, including the
password. Set `MONGO_URI` in Railway and **rotate that password** — it is in git
history and must be assumed compromised.
