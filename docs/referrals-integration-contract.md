# Wasally referrals — integration contract (not deployed)

Status: **isolated implementation in draft PR; no endpoint, grant, balance, or payout enabled**.

## Ownership and isolation
- Work owns existing order, notification, and auth flows.
- This branch owns only new `referral.dart`, `referrals.ts` and their tests.
- Do not change `orders`, `serverOrders`, Firestore rules, or production Worker routes without coordination.

## Proposed server-owned data model (not yet created)
- `referral_codes/{CODE}`: code, ownerUid, channel, active, createdAt. Create with Firestore precondition `exists=false`; retry collisions. Never trust the client to select ownerUid.
- `referral_attributions/{invitedUid}`: invitedUid, inviterUid, code, channel, createdAt. Server creates once with `exists=false` at first registration; no updates by clients. For store invites, key by invited store ID instead of invited user ID to prevent multiple owner accounts earning for the same store.
- `referral_grants/{channel}_{invitedUid}`: inviterUid, invitedUid, sourceOrderId, rewardUnit, amount, policyVersion, createdAt, status. **Use a stable idempotency key**. For store invitations, use the store ID, not the invited UID.
- `referral_balances/{inviterUid}`: server-owned materialized points and cash ledger totals; no direct client writes.
- `app_info/referral_config`: admin-managed policy, with positive integer amounts, caps and enabled flags.

## Required server-side transaction
1. Authenticate Firebase ID token and enforce actor role; admin settings are admin-only.
2. Read attribution, policy and canonical completed order, plus approved/active store records where relevant.
3. Verify that this is the first eligible successful order; client-supplied timestamps/status are ignored.
4. In a Firestore transaction or equivalent concurrency-safe commit, reserve the grant using `exists=false`, update the balance, and write the audit event **atomically**. If using Firestore REST transactions, all reads and writes must use the same transaction. Retry conflicts with a bounded policy.
5. Return the existing grant for repeated delivery/retries without crediting the balance twice.
6. For cash payouts, use a separate approved payout ledger; a grant is **not** evidence of transfer. Store-owner commission discounts must be applied by the authoritative server-side commission calculation.
7. Ensure refunds, cancellation and reversals have explicit, auditable policy before enabling production.

## Security acceptance
- No self-referral, no reassignment, no reward for signup alone.
- No PII in referral statistics or marketer views.
- Rate limit code claims and referral endpoint.
- Test simultaneous duplicate grants, transaction failure, retry after response loss, disabled policies, admin-only writes, and store activation ordering.
- No new Firestore listeners; use bounded one-shot reads.
- Firebase Spark only, no Cloud Functions, no production deployment before explicit approval.

## Important
The pure `decideReferralReward` function is a defense-in-depth helper, **not** proof of order completion. All its inputs must come from verified server-side Firestore records. This PR is intentionally incomplete and must remain draft until server integration, rules, UI, and full tests are complete.
