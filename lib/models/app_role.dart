/// دور المستخدم في التطبيق.
/// عميل: الافتراضي. مندوب: ليه مستند في couriers/{uid}. مدير: ليه مستند في admins/{uid}.
/// صاحب محل: ليه مستند في storeOwners/{uid} بيربطه بمحل واحد.
enum AppRole { customer, courier, admin, storeOwner, supervisor }
