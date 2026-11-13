class UserProfile {
  final String name;
  final String phone;
  final String address;

  const UserProfile({this.name = '', this.phone = '', this.address = ''});

  factory UserProfile.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const UserProfile();
    return UserProfile(
      name: (m['name'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'phone': phone,
    'address': address,
  };
}
