# Maalish V7 integration

Firebase: `maalish-8cd54` (Google and anonymous sign-in enabled).
Android: `com.maalish.app.maalish_app`.
Firestore: Enterprise native database `maalish`, `europe-west3`, free tier enabled.
Worker: `https://maalish-ai.maalish-abdotarek44.workers.dev`.
Gemini: `gemini-3.1-flash-lite`, dedicated API-restricted server secret.

Verified live: Firebase anonymous login -> signed ID token -> Cloudflare authentication -> Gemini structured reply. Unauthenticated chat returns 401. Worker health returns 200.
Firestore prototype rules compiled and deployed. Eighteen live access/validation tests passed, including cross-user isolation, owner spoofing, schema/type constraints, oversized data and owner CRUD. Five local Worker tests pass. Review rules before broad release.

The V7 Flutter patch synchronizes owner-scoped preferences and the last 50 session summaries with Firestore. It keeps a per-user local cache and retries dirty local state after offline writes. Full chat transcripts are not persisted by this service. JSON payload fields are bounded private app data and never grant permissions. Concurrent devices use last-write-wins state synchronization; this is not a merge engine.

Client Firebase config and Google OAuth client ID in config/firebase.android.json are public client identifiers. The Gemini key, Firebase login tokens and Cloudflare credentials are excluded from source and APK. Old Google Cloud project maalish-abdotarek44 still hosts the Gemini-only API credential; Firebase data lives in maalish-8cd54. Neither project is deleted.

Android CI builds V7 from the verified legacy snapshot plus patches. A known corrupt archived chat file is replaced by its committed patch; other archive corruption fails. CI reports the APK development signing SHA-1/SHA-256. Those fingerprints must be registered for the Firebase Android app before Google login can work for that APK. Production signing and Google login on a physical device still require verification. CI uses Flutter's development signing configuration for this test APK.

Local commands:
- node --test cloudflare-worker/test/worker.test.js
- python scripts/reconstruct.py (requires app/ absent)
- npx -y firebase-tools@latest deploy --only auth,firestore --project maalish-8cd54
- wrangler deploy inside cloudflare-worker after Cloudflare authentication

Wrangler secrets persist across updates; never commit GEMINI_API_KEY. Configure Cloudflare CI credentials separately if automated deployment is desired.
