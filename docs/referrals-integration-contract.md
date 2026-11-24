# Wasally referrals — شير بكودك واكسب هدايا

The Flutter campaign uses `WASALLY_REFERRAL_REGISTRATION` at build time.
The Worker keeps `REFERRAL_REGISTRATION_ENABLED` and
`REFERRAL_DELIVERY_ENABLED` off unless explicitly configured. There are no
Cloud Functions or new Firestore snapshot listeners.

## Registration and campaign

- The optional invite code is entered **inside the authenticated campaign page**
  (`حسابي ← شير بكودك واكسب هدايا`) immediately after first Google registration;
  it is no longer shown on the login screen. The first-registration code-entry
  window is five minutes. The Worker independently validates the Firebase
  session, first-login timestamp, account creation time and campaign policy,
  and writes one immutable attribution using a Firestore transaction.
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
