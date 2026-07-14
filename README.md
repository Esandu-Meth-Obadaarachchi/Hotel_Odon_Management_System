# ODON Booking

A Flutter app for managing **The ODON**, a small hotel in Anuradhapura, Sri Lanka. Handles room bookings, expenses, salaries, inventory, invoices, and AI-driven business insights, backed by a Node.js/Express + MongoDB API.

Runs on **Android** and in the **browser** (mobile-first UI works on desktop too). The web build is deployed to Netlify.

## Running

### Flutter app

```bash
flutter pub get
flutter run                  # connected device / emulator
flutter run -d chrome        # in the browser
flutter build apk            # Android release build
```

### Backend

```bash
cd flutter_mongodb_backend
npm install
npm start                    # Express server on port 3000
```

The frontend defaults to the production Railway backend. To point it at a local server, edit `baseUrl` in [`lib/core/api/api_service.dart`](lib/core/api/api_service.dart) — use `http://<your-LAN-IP>:3000` for a physical Android device or `http://10.0.2.2:3000` for an emulator.

## Deployment

- **Web** — Flutter web is deployed to Netlify at <https://odon-booking.netlify.app>. Pushes to `main` auto-deploy via [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).
- **Backend** — runs on Railway; auto-deploys from `main`.

## Recent additions

- **Invoice Ready dialog** — after generating an invoice the app shows an in-app dialog with **Share PDF** (Web Share API, so iOS Safari can hand the file to WhatsApp / Mail with the right filename and without leaking the page URL), **Open PDF**, and a **copy-able WhatsApp summary message** built from the form. The invoice form now has an optional **NIC field** that's included in the summary.
- **iOS / web PDF fixes** — wrap PDF bytes in `Uint8List` so the browser's Blob gets a real `ArrayBufferView` (fixes a corrupt-PDF bug on web), and return the blob URL up to the caller so "Open PDF" can run from a fresh user gesture (iOS Safari blocks `window.open` after async PDF builds).
- **Bulk import from Claude** — the Expenses screen has a *"Paste month JSON from Claude"* banner. Paste a JSON block produced by the in-app Claude prompt to bulk-create salaries and expenses; salary types and expense categories are clamped to the allowed dropdown values before review.
- **Business analyst / expenses AI fixes** — fixes around how the AI insights and expenses-OCR flows handle responses.

## More reference

See [`CLAUDE.md`](CLAUDE.md) for the full architecture reference: folder layout, MongoDB schemas, packages and meal logic, room type system, screen-by-screen notes, the Invoice Ready dialog internals, the bulk-import JSON parser, and dev tips.
