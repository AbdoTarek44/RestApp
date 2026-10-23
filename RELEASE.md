# Maalish V10 release candidate

Firebase project `maalish-8cd54`; Enterprise native Firestore database `maalish`,
Frankfurt `europe-west3`. Google and anonymous sign-in are enabled. The separate
Google Cloud project `maalish-abdotarek44` owns the restricted Gemini API key.

## Conversations and memory

The app saves a complete transcript locally before requesting a reply. Private
conversation metadata and immutable message documents sync through a revisioned
local outbox. Retries run on app resume, chat opening, history refresh and later
saves. Stable message IDs prevent duplicates. History opens the original
conversation without sending a new introduction. Legacy summaries are retained
separately; their original messages were never saved and cannot be recovered.

Each normal reply includes a bounded rolling summary. Subsequent requests carry
that summary and recent messages within a UTF-8 budget. Cross-chat memories are
separate, optional, editable and individually deletable. New storage has no
fifty-conversation eviction. Transcripts currently load in full when opened;
exceptionally large archives will need pagination. Concurrent devices merge
message IDs on opening; metadata remains last-write-wins.

Conversation deletion clears private metadata, purges messages in retryable
batches and retains an empty tombstone to block stale offline resurrection.
Account deletion verifies ownership, locks new writes, purges private data and
per-account activity identifiers, then deletes Firebase Auth identity. Local
preferences are erased immediately; SDK disk-cache erasure runs before Firestore
starts on the next app launch. The administrator account is protected.

## Administration and operations

Worker: https://maalish-ai.maalish-abdotarek44.workers.dev

- `/admin`: verified Google allowlist, fresh authentication and live account check.
- `/privacy`: public privacy explanation; `/delete-account`: deletion instructions.
- User directory: selected Auth fields only, pagination, exact email/UID search,
  current-page CSV and audited disable/enable controls.
- Operational analytics: request/error counts, server durations, token usage,
  unique active account IDs and audit records. No transcripts, memories, mood or
  conversation summaries are collected as operational events.
- Settings: maintenance and its message, announcement, temperature, output budget,
  and optional administrator-entered pricing estimates. Metrics start at
  deployment and are not historical reports or a billing invoice.
- `/chat`: Firebase token validation, account-status checks, 64KiB size limit and
  UID rate limiting (15/minute per Worker location).

Gemini uses `gemini-3.5-flash-lite` with minimal thinking. Provider latency remains
variable; the app enforces deadlines and explicit retryable errors. It does not
pretend that a local fallback is a Gemini reply.

Runtime secrets `GEMINI_API_KEY` and `GOOGLE_OPERATIONS_CREDENTIALS` must never be
committed or included in APKs. The operations service account has a custom role
with Auth user get/update and Firestore entity operations, without IAM management.
Client Firebase configs and OAuth IDs are public identifiers. Edit `admin/` assets
then run `python scripts/build_admin_assets.py` before deploying the Worker.

## Validation and publication boundary

Worker tests include admin authorization, field redaction, origin restrictions,
protected account and settings validation. Live Rules tests cover both legacy
state and conversation schemas. Flutter tests exercise restart persistence,
resumption, independent deletion and more than fifty conversations. A synthetic
account-erasure test verifies removal of Auth identity, preferences, conversation,
messages and activity identifiers. Synthetic test users/documents are cleaned.

The user confirmed Google login, improved response speed and admin dashboard
login with data visible. Phone testing of the new transcript/resumption UI is
still required. Crashlytics is opt-in and initially disabled; the app adds only
technical exception type/stack information. Compilation is not delivery proof:
a controlled device report still needs verification in Firebase Crashlytics.

Preview package `com.maalish.app.maalish_app.preview` (`معلش تجربة`) shares Firebase
users/data with the original app. CI reuses development signing cache
`maalish-preview-development-signing-v1`; verify the final APK certificate matches
the registered preview fingerprint before delivery. It is not a production key.

Store publication still requires a protected release key, Play App Signing SHA
registration, production AAB, listing and privacy/data-safety review. No Play
publication is performed. Rules remain a prototype and need independent review
before broad distribution. Keep the existing PR draft until device feedback.
