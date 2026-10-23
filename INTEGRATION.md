# Maalish integration

Firebase: `maalish-8cd54` (Google and anonymous sign-in enabled).
Android: `com.maalish.app.maalish_app`.
Firestore: Enterprise native database `maalish`, `europe-west3`, free tier enabled.
Worker: `https://maalish-ai.maalish-abdotarek44.workers.dev`.
Gemini: `gemini-3.1-flash-lite`, dedicated API-restricted server secret.

Verified live: Firebase anonymous login -> signed ID token -> Cloudflare authentication -> Gemini structured reply. Unauthenticated chat returns 401. Worker health returns 200.
Firestore prototype rules compiled and deployed. Eighteen live access/validation tests passed, including cross-user isolation, owner spoofing, schema/type constraints, oversized data and owner CRUD. Five local Worker tests pass. Review rules before broad release.

The V7 Flutter patch synchronizes owner-scoped preferences and the last 50 session summaries with Firestore. It keeps a per-user local cache and retries dirty local state after offline writes. Full chat transcripts are not persisted by this service. JSON payload fields are bounded private app data and never grant permissions. Concurrent devices use last-write-wins state synchronization; this is not a merge engine.

Client Firebase config and Google OAuth client ID in config/firebase.android.json are public client identifiers. The Gemini key, Firebase login tokens and Cloudflare credentials are excluded from source and APK. Old Google Cloud project maalish-abdotarek44 still hosts the Gemini-only API credential; Firebase data lives in maalish-8cd54. Neither project is deleted.

Android CI builds V7 from the verified legacy snapshot plus patches. A known corrupt archived chat file is replaced by its committed patch; other archive corruption fails. CI extracts the actual signing SHA-1/SHA-256 from the final APK using apksigner; a separately generated keystore can differ and is not authoritative. Those fingerprints must be registered for the Firebase Android app before Google login can work for that APK. Production signing and Google login on a physical device still require verification. CI uses Flutter's development signing configuration for this test APK.

Local commands:
- node --test cloudflare-worker/test/worker.test.js
- python scripts/reconstruct.py (requires app/ absent)
- npx -y firebase-tools@latest deploy --only auth,firestore --project maalish-8cd54
- wrangler deploy inside cloudflare-worker after Cloudflare authentication

Wrangler secrets persist across updates; never commit GEMINI_API_KEY. Configure Cloudflare CI credentials separately if automated deployment is desired.

V8 fixes: reset Google Credential Manager sign-in session before explicit authentication; reply generation uses cached preferences without waiting for Firestore; display the AI reply before background memory persistence; remove the backend URL field from the user profile and use the configured service endpoint exclusively. Registered the actual V7 APK certificate after independently extracting its V2 signing block. Measured service response at ~1.9s first and ~1.1s warm in one two-request smoke test (device/network timings vary).


V8 preview builds use an independent Android application ID (`com.maalish.app.maalish_app.preview`) and Firebase Android app so they can coexist with V7 without deleting local data. They still use the same Firebase project, Google users and Firestore database. A dedicated development keystore is restored with GitHub Actions cache and explicitly selected by Gradle; it is not committed and must not be used for production. Cache eviction may require new certificate registration and a migration plan. The original V7 Google login was confirmed working by the user after actual certificate registration.
