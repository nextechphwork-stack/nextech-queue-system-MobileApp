## 🛠 Recent fixes (ticket input, dept sections, push notifications)

**Ticket input validation.** The field beside "Track" now only accepts
`R001`–`R100`, `A001`–`A100`, or `S001`–`S100` (letters/digits only —
emojis and junk like `AAA`, `000`, `---` are blocked as you type and
rejected with an "Invalid Input" alert on submit). After a valid format is
entered, a Yes/No confirmation dialog checks it against the printed ticket
before tracking starts. Entering a number that's already been served shows
a "Ticket has been served" alert instead. Once tracking is confirmed, the
input + Track button are replaced with a small "Tracking <ticket>" chip
until the ticket is served (at which point tracking, and the "Your Ticket"
label, are cleared automatically).

**Waiting Queue.** The "All" tab has been removed. Each department now has
its own card with an internal scrollbar (shows the first 10 without
growing the page). While a ticket is being tracked, only that department's
card is shown; the other two are hidden until tracking ends.

**Footer.** The "v2.1.1 — Synced with Firebase" line has been removed.

**Push notifications (works even when the app is closed).** This required
adding the `firebase_messaging` package and a companion Cloud Function
(`functions/index.js`). The Flutter side now requests notification
permission and registers a push token under `/queue_tokens/{ticketId}` in
Realtime Database whenever someone starts tracking. That's only half of
it, though — a server has to be the one to actually *send* the
notification once the app is closed, since no app code runs once it's
killed. `functions/index.js` is that server-side piece: it watches
`/queue`, and sends a push when a tracked ticket gets within 10 of being
served, and again when it's served. **It needs to be deployed separately**
(`firebase deploy --only functions`, see the comment at the top of that
file for the full steps) and requires your Firebase project to be on the
Blaze (pay-as-you-go) plan, since Realtime Database triggers for Cloud
Functions require it. iOS additionally needs an APNs key uploaded in the
Firebase console (Project Settings → Cloud Messaging) before push will
work on iPhones. Until that function is deployed, the app still shows
in-app toast alerts whenever it's open in the foreground/background — it's
only the "notification while fully closed" behavior that depends on the
Cloud Function being live.

> Note: an earlier version of this project tried `flutter_local_notifications`
> and had to remove it after it broke the FlutLab Android build. This fix
> deliberately avoids that package — `firebase_messaging` displays the
> system notification itself for background/terminated pushes, so
> `flutter_local_notifications` isn't needed. Still, since builds happen on
> FlutLab rather than a local machine here, do a full Build/Run after
> pulling these changes to confirm `firebase_messaging` resolves cleanly
> before relying on it.

---

# Quelio Mobile — Flutter App for FlutLab.io

A pixel-perfect Flutter port of `mobile.html` that syncs live with the same
Firebase Realtime Database used by the web kiosk, TV, and admin panels.

---

## 🚀 How to run on FlutLab.io

### Step 1 — Upload the project
1. Go to [flutlab.io](https://flutlab.io) and sign in.
2. Create a **New Project → Blank Flutter App**.
3. Replace the default files with the files in this folder:
   - `lib/main.dart`         → paste/upload the full content
   - `lib/firebase_options.dart` → paste/upload
   - `pubspec.yaml`          → replace completely

### Step 2 — Firebase is already configured, no extra file needed
This project talks to Firebase using hardcoded credentials in
`lib/firebase_options.dart` (the standard FlutterFire-generated approach),
**not** the native Android `google-services.json` + Gradle plugin approach.
Do **not** add `google-services.json` or the
`com.google.gms.google-services` plugin — doing so without also wiring up
the matching Gradle classpath will break the build. If you ever regenerate
Firebase config, just re-run `flutterfire configure` and it will update
`firebase_options.dart` — no Android-side changes required.

### Step 2.5 — Fixed: build error from an unused dependency
`flutter_local_notifications` was listed in `pubspec.yaml` but never
actually used anywhere in `lib/main.dart`. Its Android native code had a
known compile error (`bigLargeIcon is ambiguous`) on newer Android SDKs.
It's been removed since nothing in the app depended on it. `compileSdk` was
also bumped to 35 (required by `path_provider_android` /
`shared_preferences_android`) and the Android Gradle Plugin bumped to
8.3.2 / Gradle 8.4 (FlutLab's build log was warning that 8.1.2 would soon
stop being supported).

### Step 3 — Build & Run
Click **Run** / **Build APK** in FlutLab. When picking a target
architecture, choose **arm64** (or **Universal / Fat APK**) — **not
`android-x64`**. `x64` only targets x86_64 devices (emulators / a few
Intel-based tablets); it will not install on the vast majority of real
Android phones, which are ARM. If your build still fails, capture the exact
error text from the FlutLab build log — that error is needed to diagnose
anything beyond this.

### Step 4 — Alternative: build via GitHub Actions
This project also includes `.github/workflows/build-apk.yml`. Push it to a
GitHub repo and the Actions tab will build a release APK (both a universal
one and per-architecture ones, including `arm64-v8a`) using the real
Flutter/Android toolchain, downloadable as a build artifact — useful if
FlutLab keeps giving trouble.

---

## 📱 Features (mirrors mobile.html exactly)

| Feature | Status |
|---|---|
| Live Firebase Realtime DB sync | ✅ |
| "Now Serving" per department | ✅ |
| Waiting queue list with tabs | ✅ |
| My ticket tracking (persisted) | ✅ |
| QR code scanner | ✅ |
| "Get Ready" alert (10 positions away) | ✅ |
| "Your Turn" alert | ✅ |
| "Served" / "Skipped" banners | ✅ |
| Toast notifications | ✅ |
| Same Firebase project as web | ✅ |

---

## 🔥 Firebase config (already embedded)

```dart
apiKey:        'AIzaSyDzK9bpl2C_n0YN5WJyTXYXdGUGDWD1TGA'
databaseURL:   'https://queue-system-45b56-default-rtdb.asia-southeast1.firebasedatabase.app'
projectId:     'queue-system-45b56'
```

The app listens to the same `queue` node as the web pages — any change made
by the admin panel or kiosk is instantly reflected in the Flutter app.

---

## 🗂 File structure

```
lib/
  main.dart               ← entire app (single-file for FlutLab simplicity)
  firebase_options.dart   ← Firebase config
pubspec.yaml              ← dependencies
android/app/
  src/main/AndroidManifest.xml  ← camera + internet permissions
```

---

## 📱 Building for iOS

The `ios/` folder is already fully set up (camera permission, Firebase
config, deployment target 12.0 — compatible with all plugins used here).
Nothing in the code needs to change to build for iOS. To get an installable
build on a real iPhone:

1. **You need an Apple Developer Program membership** ($99/year;
   [developer.apple.com](https://developer.apple.com)). Apple requires every
   app to be cryptographically signed before it can run on a physical
   device — there's no way around this, on FlutLab or anywhere else.
2. In your Apple Developer account, create a signing certificate and a
   provisioning profile (for personal testing, a "Development" or "Ad Hoc"
   profile registered with your device's UDID; for wider testing, use
   TestFlight).
3. In FlutLab, go to your project's **Settings → iOS Signing** (or
   equivalent) and upload the `.p12` certificate and `.mobileprovision`
   profile.
4. In the Builder tab, select an **iOS** build target (e.g. `ios-release`)
   instead of an Android one, then Build. FlutLab will produce a signed
   `.ipa` you can install via TestFlight, Apple Configurator, or a device
   management tool.

Without a certificate/profile uploaded, FlutLab can still *compile* the iOS
build (useful to confirm there are no code errors) but the result won't
install on a physical device — there's also no Simulator available on
FlutLab's cloud build servers, since running the iOS Simulator requires a
Mac.
