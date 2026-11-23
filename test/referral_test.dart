import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/models/referral.dart';

void main() {
  test('referral code format is strict and case sensitive', () {
    expect(isReferralCodeFormatValid('ABC123'), isTrue);
    expect(isReferralCodeFormatValid('ABCD12345678'), isTrue);
    for (final code in ['abc123', 'AB 123', 'ABC12', 'ABC1234567890', 'ABC-123', '']) {
      expect(isReferralCodeFormatValid(code), isFalse, reason: code);
    }
  });

  test('self referral is rejected by domain check', () {
    const same = ReferralAttribution(
      invitedUid: 'user-1', inviterUid: 'user-1',
      code: 'ABC123', kind: ReferralKind.customer,
    );
    expect(same.isSelfReferral, isTrue);
    const different = ReferralAttribution(
      invitedUid: 'user-2', inviterUid: 'user-1',
      code: 'ABC123', kind: ReferralKind.customer,
    );
    expect(different.isSelfReferral, isFalse);
  });

  test('award key stays stable across retries and distinct across kinds', () {
    expect(referralAwardKey(invitedUid: 'uid-1', kind: ReferralKind.customer),
        referralAwardKey(invitedUid: 'uid-1', kind: ReferralKind.customer));
    expect(referralAwardKey(invitedUid: 'uid-1', kind: ReferralKind.customer),
        isNot(referralAwardKey(invitedUid: 'uid-1', kind: ReferralKind.marketer)));
    expect(() => referralAwardKey(invitedUid: '', kind: ReferralKind.customer),
        throwsArgumentError);
    expect(() => referralAwardKey(invitedUid: 'a/b', kind: ReferralKind.customer),
        throwsArgumentError);
  });

  test('reward amount must be positive', () {
    const rule = ReferralRewardRule(
      kind: ReferralKind.storeOwner,
      reward: ReferralRewardKind.commissionDiscount,
      amount: 0,
      enabled: true,
    );
    expect(rule.hasValidAmount, isFalse);
  });
}
