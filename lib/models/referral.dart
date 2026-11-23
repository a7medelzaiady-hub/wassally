import 'dart:math';

/// Referral domain primitives. No Firestore writes or reward payouts happen here.
///
/// IMPORTANT: Only a trusted Cloudflare Worker may create reward grants after
/// checking the authoritative completed-order record and idempotency key.
enum ReferralKind { customer, marketer, storeOwner }

enum ReferralRewardKind { points, cash, commissionDiscount }

/// A referral is bound once, at first registration, and is never editable by
/// the invited user. The Worker must enforce this against the stored record.
class ReferralAttribution {
  final String invitedUid;
  final String inviterUid;
  final String code;
  final ReferralKind kind;

  const ReferralAttribution({
    required this.invitedUid,
    required this.inviterUid,
    required this.code,
    required this.kind,
  });

  bool get isSelfReferral =>
      invitedUid.isNotEmpty && invitedUid == inviterUid;
}

/// Validates the public *format* only. A matching, active code must still be
/// resolved server-side; this does not establish entitlement.
bool isReferralCodeFormatValid(String value) =>
    RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(value);

/// A deterministic logical key for an award tied to the first qualifying
/// completed order. The Worker must atomically create this key exactly once.
///
/// The caller supplies IDs from trusted Firestore records, never user input.
String referralAwardKey({
  required String invitedUid,
  required ReferralKind kind,
}) {
  if (invitedUid.isEmpty || invitedUid.contains('/')) {
    throw ArgumentError.value(invitedUid, 'invitedUid', 'Invalid UID');
  }
  return '${kind.name}_${Uri.encodeComponent(invitedUid)}';
}

/// Reward configuration is data, not proof of a payable reward. The Worker
/// applies admin-approved limits and validates the eligibility event.
class ReferralRewardRule {
  final ReferralKind kind;
  final ReferralRewardKind reward;
  final int amount;
  final bool enabled;

  const ReferralRewardRule({
    required this.kind,
    required this.reward,
    required this.amount,
    required this.enabled,
  });

  bool get hasValidAmount => amount > 0;
}

/// Generates an unpredictable *candidate* referral code. The Worker must
/// reserve it atomically and retry if it collides with an existing code.
String generateReferralCode({Random? random, int length = 8}) {
  if (length < 6 || length > 12) {
    throw RangeError.range(length, 6, 12, 'length');
  }
  final source = random ?? Random.secure();
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(length, (_) => alphabet[source.nextInt(alphabet.length)])
      .join();
}

/// For UI input only. Never treat a normalized code as proof of ownership.
String normalizeReferralCode(String code) => code.trim().toUpperCase();
