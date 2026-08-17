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
first boot from `ALLOWED_EMAILS`. Read through a 60-second cache, so changes
take effect within a minute.

**Manage it from the app**: the *User Access* tile on the home screen (owner
accounts only) adds and removes people. No redeploy, no new app version.

Endpoints behind it:

| Route | Who | Purpose |
|---|---|---|
| `GET /me` | any signed-in, allow-listed account | who am I, am I an owner |
| `GET /admin/allowed-emails` | owners only | current list + protected owners |
| `POST /admin/allowed-emails` | owners only | grant access |
| `DELETE /admin/allowed-emails/:email` | owners only | revoke access |

**Owners** are the addresses in `ALLOWED_EMAILS`. They are always allowed,
always admin, and cannot be removed — otherwise someone added later could lock
the owners out of their own system. Change who counts as an owner by editing
that variable and restarting.

The app asks `/me` after sign-in rather than carrying its own copy of the list.
If the server cannot answer (old backend, no network) it falls back to the
built-in owner addresses in `auth_gate.dart`, so an outage can't lock you out.

## Audit fields

`bookings`, `expenses`, `salaries` and `inventory` records carry:

`createdBy`, `createdByName`, `createdAt`, `updatedBy`, `updatedByName`, `updatedAt`

Records written before this change have `null` creators; the UI simply omits
the line for them rather than showing a blank.

## Security note — outstanding

The MongoDB connection string is committed in `server.js`, including the
password. Set `MONGO_URI` in Railway and **rotate that password** — it is in git
history and must be assumed compromised.
