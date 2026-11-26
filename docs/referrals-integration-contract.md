# Wasally referrals — شير بكودك واكسب هدايا

The Flutter campaign uses `WASALLY_REFERRAL_REGISTRATION` at build time.
The Worker keeps `REFERRAL_REGISTRATION_ENABLED` and
`REFERRAL_DELIVERY_ENABLED` off unless explicitly configured. There are no
Cloud Functions or new Firestore snapshot listeners.

## Registration and campaign

- A brand-new account is offered an **optional invitation-code dialog inside
  the signed-in app immediately after its first Google registration**. The login
  page and existing accounts never show an input field. If the new customer
  skips the invitation and closes the dialog, they cannot add one later.
  The Worker checks authoritative Firebase Auth creation, original-session
  authentication and last-login timestamps (not client claims), plus campaign
  policy, and commits one immutable attribution. No arbitrary 5-minute or
  24-hour countdown is used; eligibility is tied to initial registration.
- Customers and active, approved store owners can obtain a stable code. The
  administrator issues a marketer code against an existing account UID. The
  account screen shows that marketer's code and its own aggregate balances.
- The administrator can set reward amounts, per-inviter caps, and enabled flags
  for customer, marketer, store-to-customer, and store-to-store referrals.
  Store policies support cash or commission credit. Policy updates use Firestore
  version and document preconditions.

## Account deletion and repeated signup protection

- Firebase Auth assigns a new UID if a person deletes and recreates an account.
  Do not treat a new UID as proof of a new Google identity.
- The Worker obtains the stable Google provider subject from the verified
  Firebase Auth `accounts:lookup.providerUserInfo` response, never from the
  client or a client-editable Firestore document. During account deletion the
  Worker stores ONLY an HMAC-SHA256 digest (purpose-separated; a dedicated
  `REFERRAL_IDENTITY_HMAC_KEY` Cloudflare Secret) in
  `referral_deleted_identities/{digest}`. Neither email, name, old Firebase UID
  nor raw Google subject is stored in the marker.
- On first-registration claims the Worker calculates the digest for the new
  account's verified Google identity and refuses the referral if an unexpired
  deletion marker exists. It still permits normal use of the newly created
  account; the restriction only applies to claiming a new-user referral.
- There is an explicit **365-day retention** period. The Worker runs a
  bounded daily scheduled cleanup of expired records (no Firebase paid TTL,
  no Blaze, no Cloud Functions); expired records do not block a claim even
  if removal is scheduled but not completed. The digest is pseudonymous
  personal data, not anonymized data, and this retention is disclosed in both
  the app and the public privacy/deletion pages.
- Deployment is **blocked for referral rewards** until the 32+ byte
  `REFERRAL_IDENTITY_HMAC_KEY` is set in Cloudflare Secrets and verified.
  Missing secret or missing verified Google identity fails closed on the
  *claim* endpoint. Account deletion remains available even if this secret
  is missing. Keep the secret stable for the full retention period; rotating
  it requires a dual-key migration, otherwise old records no longer match.
- This only protects deletions performed after the updated Worker and secret
  have been deployed; preexisting deletions cannot be reconstructed from
  completely erased account data. Test deletion->rejoin and two different
  Google accounts against staging before production activation.

## One-invitation-per-device guard (Android)

- Multiple Google accounts may sign in and use Wasally normally, but **only the
  first Google identity bound to an Android device may claim an invitation code**.
  Even if the first user never enters an invitation code, their first login
  reserves that device so a later Google account cannot claim a second new-user
  referral. Every login attempts a low-read, idempotent binding; resumed
  Firebase sessions bind in the role gate without new Firestore listeners.
- Android `Settings.Secure.ANDROID_ID` is scoped by device, Android profile
  and app signing key on Android 8+. Flutter gets it through a native MethodChannel,
  sends it only via HTTPS to the Worker; it is never stored in the app's
  Firestore data or logged. The Worker stores separate HMAC digests for the
  device and the Google subject (no raw device ID, email or UID), using the
  existing `REFERRAL_IDENTITY_HMAC_KEY` Cloudflare secret.
- The Worker conditionally creates `referral_device_bindings/{deviceDigest}`
  and rejects any other verified Google identity while the record is active.
  Firestore preconditions defeat racing account registration; existing owner
  requests are idempotent. Claim requires the device ID and rechecks the server
  binding. Read/list/write are denied to all app roles including admin.
- **Only these two referral endpoints** require valid Firebase App Check
  (Play Integrity) in production, controlled by
  `REFERRAL_DEVICE_APP_CHECK_REQUIRED=true`. Other Worker routes remain
  in monitor mode. Device identity alone is spoofable; Play Integrity
  makes ordinary automation harder but does not guarantee uniqueness.
- Device markers expire in 365 days; existing daily Worker Cron deletes expired
  records from both `referral_deleted_identities` and
  `referral_device_bindings`. Expired markers can be replaced by a new
  Google identity. The device ID can also change on factory reset, Android
  profile or app signing-key changes. This is a proportional anti-abuse guard,
  not a tamper-proof hardware identity.
- Device marker retention is pseudonymous personal data and is disclosed in
  the app and the public privacy/deletion pages. **Do not deploy without
  publishing those notices** and verifying the actual production App Check
  configuration and HMAC secret. Android debug builds signed differently
  can have a different scoped Android ID than Play-signed builds.
- Older app versions that do not send device identity will safely fail code
  submission; regular ordering and sign-in are unaffected. iOS/web cannot
  submit an Android invitation under this safeguard.

## Delivery and rewards

- A successful regular order has status `delivered` and a canonical
  `deliveredAt` timestamp. A courier's PIN closes an internal delivery. An
  external delivery closes after the store confirms cash receipt.
- The Worker schedules referral settlement after the existing delivery write.
  A bounded indexed query selects the earliest delivered regular order from
  history, including the quick-order service for customer-based rewards. The first-order record is immutable. Grant creation, the credit,
  and the per-channel count update commit together.
- The store approval batch records the approved draft's applicant in a
  private collection and records initial activation time when the store is
  published. A store reward requires that provenance, active owner mapping,
  approval, activation, and the store's first delivery. An existing store
  assigned to a new owner is ineligible as a new-store referral.

## Cash payout

Cash is available for a full-balance withdrawal request. A transaction reserves
the cash and creates one pending request per account. One administrator claims the request before processing. That administrator
can record a completed manual transfer by its reference or reject the request and return
the reserved balance. A repeated resolution cannot decrement or return the same
cash twice.

## Remaining release decisions

- The administration sets the value of a point and the maximum discount per
  order in minor units. In regular Worker checkout, the discount applies only
  to merchandise. The Worker reserves points atomically with order creation.
  The customer pays the reduced amount. Delivery and service fees are calculated
  independently of points.
- Cancellation releases the reservation once. The customer or an administrator
  can retry the release if the status callback was interrupted.
- For delivered orders, an administrator claims the reimbursement from the
  order details, manually pays the store the discount amount, and records the
  transfer reference. The claim is exclusive and recording the same reference
  on the same order is idempotent.
- To settle recorded store commission, an administrator supplies the store ID,
  the mapped owner UID, the commission reference, and the amount due. Firestore
  records the due amount, applied referral credit, and remaining amount in the
  same commit as the credit deduction. Reusing the reference returns the saved
  settlement for the same owner and amount.
- Cash transfers are handled outside the app. Production confirmation requires a
  test of the team's chosen payout channel and a reconciliation with its transfer
  reference. The Worker records the confirmation and does not send money.
- Verify deployment of the Firestore indexes and test both courier modes against
  the staging Worker before enabling delivery settlement.
