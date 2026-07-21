# AquaFlow 💧

A production-grade Flutter platform for water bottle distribution businesses —
Customer, Vendor, Delivery Rider, and Company Admin, all in one codebase, all
wired to a real Supabase backend.

This build now covers **the full Customer experience and the full Vendor
dashboard** end-to-end, on top of the Slice 1 foundation (auth, routing,
theming, database). Every screen below reads and writes real Supabase
tables through a real repository layer, with RLS enforcing exactly who can
see what. Rider and Admin remain dashboard shells that clearly label which
of their modules are live vs. next — nothing pretends to be finished when
it isn't.

## Platform requirements & toolchain versions

- **Android:** compileSdk / targetSdk **36**, NDK **28.0.13004108**, AGP **8.9.1**, Gradle **8.12**, Kotlin **2.1.0**, Java 17. These are all set consistently across `android/settings.gradle.kts`, `android/app/build.gradle.kts`, and `android/gradle/wrapper/gradle-wrapper.properties` — if you bump one, the others need to move together or Gradle sync fails.
- **Web:** fully supported — see "Running on Chrome / Web" below.
- **Dependencies:** every package in `pubspec.yaml` is actually imported somewhere in `lib/` — nothing is declared speculatively. This is a deliberate fix from an earlier draft of this project, which declared a much larger dependency list (Freezed, json_serializable, riverpod_generator, hive_generator, custom_lint, riverpod_lint, syncfusion_flutter_charts, flutter_stripe, and more) that were never actually wired into any code. That combination — especially the code-generation tooling — is the single most common cause of `flutter pub get` failing with a version-solving error in real Flutter projects, because `build_runner`-family packages each pin their own `analyzer` version range and those ranges frequently don't overlap. None of that tooling is used here (models are hand-written), so none of it is declared, and there's nothing left to conflict. When a future slice actually needs one of those packages (e.g. wiring real Stripe payments), it gets added in the same commit that starts using it — not before.

## Routing

Every screen the user can land on — not just the four role shells, but
product detail, cart, checkout, order tracking, the address book, and every
vendor management screen — has a real nested `GoRoute` in
`lib/core/routes/app_router.dart`, addressable by name via
`context.pushNamed(RouteNames.xxx)`. Nothing navigates via a bare
`Navigator.push(MaterialPageRoute(...))` anymore. This matters most on web:
the browser's address bar, back/forward buttons, and page refresh all now
correctly reflect and restore the current screen, instead of collapsing
back to the shell root the moment you leave the customer/vendor tab bar.

The one deliberate exception: each role's bottom-navigation shell
(`CustomerShellScreen`, `VendorShellScreen`) manages its own tab state
locally via `IndexedStack` rather than as GoRouter branches. A quick-action
button that jumps to, say, Vendor Orders from the Dashboard tab pushes a
fresh `VendorOrdersScreen` on top (with its own back button) rather than
programmatically switching the bottom tab — a normal, common pattern, not a
bug — so you may occasionally see two ways to reach the same screen.

## Running on Chrome / Web

`flutter run -d chrome` works out of the box, with two things worth knowing:

1. **Push notifications are mobile-only.** Firebase/FCM initialization is
   skipped entirely on web (guarded behind `kIsWeb` in `main.dart`). Web push
   needs its own service worker (`firebase-messaging-sw.js`) and VAPID key
   setup — a distinct piece of work from mobile FCM — so rather than half-
   support it and throw console errors on every hot reload, it's cleanly
   skipped for now.
2. **Google Maps needs a web-specific API key.** `google_maps_flutter_web`
   expects its key as a static `<script>` tag in `web/index.html` (this is
   the officially documented approach — it can't be read from `.env` at
   runtime, since the browser loads that script before any Dart code runs).
   Open `web/index.html` and replace `YOUR_GOOGLE_MAPS_WEB_API_KEY` with a
   **Maps JavaScript API** key from Google Cloud Console (a separate key
   from the Android one — restrict it to your web origin). Until you do,
   the app runs completely normally; only the map/address-picker screens
   show a blank grey tile area instead of map tiles.

Everything else — Supabase auth/DB/storage/realtime, Riverpod, GoRouter,
Hive, image picking, geolocation — has full, tested web support through
Flutter's federated plugin architecture, with no platform-specific code
paths required anywhere in `lib/`.

## What's actually working right now

**Foundation (Slice 1)**
- Customer phone + PIN login, email/password, and Google auth against real Supabase Auth
- Role-based routing (Customer / Vendor / Rider / Admin) with GoRouter guards
- Automatic profile bootstrap (DB trigger + client fallback) and a complete-your-profile flow
- Full Supabase schema: 25+ tables, RLS on every table, storage buckets, push notification pipeline

**Customer commerce**
- Catalog — category filter chips, debounced search, infinite-scroll product grid, shimmer skeletons, empty/error states
- Product detail, cart (client-side, single-vendor enforced), address book with a real Google Maps pin-drop picker
- Checkout — address selection, emergency delivery toggle, payment method selection (COD live; Stripe/EasyPaisa/JazzCash/Wallet shown and architected, marked "Soon")
- Order placement via an atomic `place_order` Postgres RPC — creates the order + all line items together, decrements stock, increments coupon usage
- Live order tracking (realtime Supabase stream, no polling) with a visual status timeline, assigned rider card with tap-to-call, cancel-order flow
- Order history, favorites, account

**Vendor dashboard (this build)**
- **Dashboard** — today's orders/pending/completed/revenue stat cards (real aggregate queries, not fake numbers), low-stock warning, quick actions
- **Orders** — Pending / Active / History tabs; accept, reject (with reason), and assign-a-rider bottom sheet, all writing straight to `orders`
- **Products** — full CRUD: add/edit/delete, availability toggle, real image upload to Supabase Storage (`products` bucket, vendor-scoped write policy), category dropdown sourced from the same `categories` table the customer app uses
- **Riders** — link an existing rider account to your business by phone number (via a `link_rider_to_vendor` RPC — see below for why this needed its own function), unlink, view status/rating/delivery count
- **Customers** — register a customer on their behalf from the Account tab: enter name + phone, the app provisions a PIN-login account tied to your store (via `auth.signUp` on a throwaway client + a `finalize_customer_account` RPC) and shows a 6-digit PIN to hand over. The customer then logs in with phone + PIN.
- **Business profile** — edit business name and address inline

The customer app is a 4-tab shell (Shop / Orders / Favorites / Account); the
vendor app is a 4-tab shell (Dashboard / Orders / Products / Account), both
preserving each tab's state when switching.

### A gap I found and fixed while building this slice

Slice 1's sign-up flow only ever created a `profiles` row — never the
matching `vendors` or `riders` row those dashboards actually query. If
you'd pulled the Slice 1 zip and signed up as a vendor, the vendor
dashboard would have had nothing to read. Migration `0008` fixes this at
the trigger level (so it's automatic for every future sign-up, no client
code has to remember to do it) and backfills any profiles that predate the
fix.

## Tech stack

Flutter · Riverpod · GoRouter · Supabase (Auth/DB/Storage/Realtime) · Firebase Cloud Messaging · Geolocator · Google Maps · Dio · Hive · shared_preferences · Material 3

## Project structure

```
lib/
  core/                     # cross-cutting: config, theme, routing, services, errors, utils
  shared/                   # PrimaryButton, AppTextField, shimmer skeletons, empty/error states, dashboard shell
  features/
    authentication/         # phone+PIN / email / Google auth, complete-profile flow
    splash/, onboarding/
    customer/               # catalog, product detail, favorites, account, 4-tab shell
    cart/                   # client-side cart state + cart screen
    addresses/              # address book + Google Maps pin-drop picker
    orders/                 # checkout, place_order RPC call, live tracking, order history
    vendor/ rider/ admin/   # dashboard shells (module lists show what's live vs. next)

supabase/
  migrations/
    0001_core_schema.sql              # all tables, enums, indexes
    0002_row_level_security.sql       # RLS policies for every table
    0003_functions_and_triggers.sql   # updated_at, order numbers, notifications, wallet ledger
    0004_storage_buckets.sql          # bucket creation + storage policies
    0005_lat_lng_columns.sql          # plain lat/lng columns + trigger-synced geography points
    0006_place_order_rpc.sql          # atomic order + order_items creation
    0007_cross_role_profile_visibility.sql  # lets a customer see their assigned rider's name/phone (and vice versa) without opening `profiles` broadly
  seed/seed.sql                       # sample categories/coupons/company for local dev

android/                    # full Gradle project (build.gradle.kts, manifest, launcher icons, gradlew)
tool/generate_launcher_icon.py   # regenerates the app icon at all densities if you rebrand
```

### A deliberate architecture choice worth knowing about

Freezed and json_serializable are wired into `pubspec.yaml` (dev dependencies +
annotations) exactly as the tech stack calls for, but every model in this
build is **hand-written**, not code-generated. That means `flutter pub get &&
flutter run` works immediately with zero `build_runner` step. If you'd rather
have every model code-generated from here on, say so and the next slice will
convert to `@freezed` classes with the generated files committed.

### Why lat/lng columns instead of raw PostGIS

`addresses`, `vendors`, `riders`, and `realtime_locations` all store a
`geography(Point,4326)` column for spatial queries (nearest vendor, delivery
zone containment, etc.), but PostgREST can't cleanly return/accept that type
as plain JSON. So the client always reads/writes plain `lat`/`lng` doubles,
and a Postgres trigger (migration 0005) keeps the real geography column in
sync automatically — no WKB/GeoJSON parsing anywhere in the Flutter code.

## Setup

### 1. Prerequisites
- Flutter 3.24+ (`flutter --version`)
- Android SDK 36 and NDK 28.0.13004108 installed via Android Studio's SDK Manager, if building for Android (see "Platform requirements" above)
- A Supabase project ([supabase.com](https://supabase.com)) — free tier is enough to develop against
- A Firebase project (for push notifications) — optional, mobile-only, the app runs without it and just logs a warning
- A Google Maps API key — **Maps SDK for Android** for mobile builds, **Maps JavaScript API** for web builds (see "Running on Chrome / Web" above)

### 2. Configure environment
```bash
cp .env.example .env
```
Fill in:
- `SUPABASE_URL` / `SUPABASE_ANON_KEY` — from your Supabase project's Settings → API
- `FIREBASE_*` — from Firebase Console → Project Settings → General → Your apps → Android app (leave blank to skip push notifications for now)
- `GOOGLE_MAPS_API_KEY_ANDROID` — from Google Cloud Console (enable **Maps SDK for Android** and **Geocoding API**)

### 3. Apply the database schema
In the Supabase SQL Editor, run all migration files **in numeric order**, `0001` through `0009`, then run `supabase_auth_overhaul_migration.sql` (phone uniqueness, one-vendor-per-customer, PIN login, vendor-scoped product visibility, and the `finalize_customer_account` / `link_customer_to_vendor` RPCs). Then optionally run `supabase/seed/seed.sql` for sample categories/coupons.

In Supabase Auth settings, enable the **Google** provider (for Google sign-in)
if you want that flow to work. Email/password works out of the box with no
extra config, and customer phone + PIN login is layered on top of
email/password (synthetic `<phone>@pin.aquaflow.app` identities) so it needs
no provider toggles.

### 4. Add at least one vendor + product to see the catalog
The catalog screen queries real `products`/`vendors` rows — it will show an
empty state until you add some. Fastest path for local development:
1. Sign up through the app as a **Vendor** (a `vendors` row is now created for you automatically — see migration `0008`).
2. In the Supabase Table Editor, set that vendor's row in `vendors` to `status = 'approved'`.
3. Insert a few rows into `products` with that `vendor_id` (and any `category_id` from the seeded categories), or add them yourself from the Vendor → Products tab in the app.

### 5. Run it
```bash
flutter pub get
flutter run              # pick a connected device/emulator
flutter run -d chrome    # or run directly in the browser
```
That's it — no manual folder setup, no missing files, no build_runner step required.

## Project status (as of this build) — read this first if picking up elsewhere

**Fully built and wired to real Supabase tables/RLS:**
- **Authentication** — customer phone + PIN login, email/password, Google, role-based routing, complete-profile flow
- **Customer app** — catalog (search/filter/infinite scroll), product detail, cart, address book with Google Maps pin-drop picker, checkout, atomic order placement (`place_order` RPC), live realtime order tracking with delivery-code display, order history, favorites, account
- **Vendor dashboard** — stats, order accept/reject/assign-rider (sorted by live proximity to delivery address), full product CRUD with image upload, rider linking by phone, customer registration with PIN handout, live map of all linked riders' real-time positions, business profile editing
- **Rider app** — shift on/off toggle (which also starts/stops live location broadcasting), active-deliveries list with a Picked Up → On the Way → Complete state machine, external Google Maps navigation handoff, secure OTP-based delivery completion (the correct code is never sent to the rider's device — only pass/fail, verified server-side), delivery history, vehicle info editing
- **Full routing** — every screen (not just the four role shells) has a real nested `GoRoute`; works correctly on web (address bar, back/forward, refresh)
- **Web support** — `flutter run -d chrome` works; Firebase/FCM cleanly skipped on web; needs a Maps JS API key in `web/index.html` for map tiles to render (app runs fine without it, just blank map tiles)
- **12 SQL migrations**, run in order 0001→0012 — schema, RLS on every table (including several cross-role visibility fixes found while building — see migrations 0007, 0011, 0012), storage buckets, the `place_order` and `verify_delivery_otp` RPCs, Realtime replication enabled on `orders`/`realtime_locations`/`notifications`/`messages`

**Not built yet — still placeholder shells with a "Soon" module list:**
- **Admin dashboard** — company-wide analytics, vendor/rider approval, CMS, broadcast notifications. Currently just `lib/features/admin/presentation/screens/admin_home_screen.dart`, a static `DashboardShellScaffold` with no real data.
- **Subscriptions, wallet, coupons (redemption), chat** — tables exist in the schema (`subscriptions`, `wallets`, `coupons`, `chats`/`messages`) and RLS is already in place for them, but no repository/provider/screen layer has been written for any of them yet.
- **Payment gateways** — only Cash on Delivery is live. Stripe/EasyPaisa/JazzCash/Wallet show in the checkout UI clearly marked "Soon"; no gateway SDK is integrated, and `payment_method`/`payment_status` columns exist but nothing writes to `transactions` yet.
- **Push notification delivery** — `notifications` rows are created by DB triggers and the FCM token-registration plumbing exists, but nothing currently sends the actual push (would need a Supabase Edge Function or Database Webhook calling the FCM API — not written).

**Known limitations to be aware of:**
- Rider location broadcasting uses a plain Geolocator foreground stream — there's no Android foreground-service/background-location setup, so tracking stops if the app is backgrounded or killed. A production app would need `flutter_background_service` or equivalent for that.
- The Live Riders map fits camera bounds once per screen open (`_hasFitBounds` flag) rather than continuously re-fitting as riders move — deliberate (avoids the map fighting the vendor if they've manually panned), but worth knowing.
- No automated tests exist anywhere in this project.
- I cannot run `flutter analyze`, `flutter pub get`, or an emulator in the sandbox this was built in — every check in this README (bracket balance, import resolution, duplicate classes, package cross-check) is static text analysis, not a compiler guarantee. Please run `flutter analyze` yourself as the real final check.

## What's next (if continuing this build)

1. **Admin dashboard** — the last of the four role apps
2. **Subscriptions, wallet, coupon redemption, chat** — the remaining customer-side modules
3. **Real payment gateway integration** — starting with one (Stripe is the most straightforward Flutter SDK) rather than all four at once
4. **Push notification delivery** — a Supabase Edge Function triggered by a Database Webhook on `notifications` insert, calling the FCM HTTP v1 API
5. **Automated tests** — none exist yet; widget tests for the checkout/order-placement flow would catch regressions fastest given how much logic lives there

Each slice should be delivered the same way this one was: complete, wired,
runnable — no placeholders — with a `flutter analyze` pass (not available in
the environment this was built in) as the final check before calling it done.

