# Wasally referrals — شير بكودك واكسب هدايا

The Flutter campaign uses `WASALLY_REFERRAL_REGISTRATION` at build time.
The Worker keeps `REFERRAL_REGISTRATION_ENABLED` and
`REFERRAL_DELIVERY_ENABLED` off unless explicitly configured. There are no
Cloud Functions or new Firestore snapshot listeners.

## Registration and campaign

- The optional code travels with the first Google sign-in. The Worker validates
  the Firebase session and account creation time, checks campaign policy, and
  writes one immutable attribution using a Firestore transaction.
- Customers and active, approved store owners can obtain a stable code. The
  administrator issues a marketer code against an existing account UID. The
  account screen shows that marketer's code and its own aggregate balances.
- The administrator can set reward amounts, per-inviter caps, and enabled flags
  for customer, marketer, store-to-customer, and store-to-store referrals.
  Store policies support cash or commission credit. Policy updates use Firestore
  version and document preconditions.

## Delivery and rewards

- A successful regular order has status `delivered` and a canonical
  `deliveredAt` timestamp. A courier's PIN closes an internal delivery. An
  external delivery closes after the store confirms cash receipt.
- The Worker schedules referral settlement after the existing delivery write.
  A bounded indexed query selects the earliest delivered regular order from
  history. The first-order record is immutable. Grant creation, the credit,
  and the per-channel count update commit together.
- The store approval batch records the approved draft's applicant in a
  private collection and records initial activation time when the store is
  published. A store reward requires that provenance, active owner mapping,
  approval, activation, and the store's first delivery. An existing store
  assigned to a new owner is ineligible as a new-store referral.

## Cash payout

Cash is available for a full-balance withdrawal request. A transaction reserves
the cash and creates one pending request per account. Administrators can record
a completed manual transfer by its reference or reject the request and return
the reserved balance. A repeated resolution cannot decrement or return the same
cash twice.

## Remaining release decisions

- Points are tracked in the referral ledger. They still need an approved
  redemption rule and integration with order pricing before launch.
- Commission credits are tracked in the referral ledger. Applying them requires
  an authoritative Wasally store commission calculation.
- Cash transfers are handled outside the app. Production confirmation requires a
  test of the team's chosen payout channel and a reconciliation with its transfer
  reference. The Worker records the confirmation and does not send money.
- Verify deployment of the Firestore indexes and test both courier modes against
  the staging Worker before enabling delivery settlement. The delivery hook and
  indexes currently cover ordinary store orders.
