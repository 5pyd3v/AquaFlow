/// The five dashboards the app ships. Stored as `profiles.role` in
/// Postgres (as a matching enum — see supabase/migrations) and used
/// throughout routing/guards to decide which shell a user lands in.
enum UserRole {
  customer,
  vendor,
  rider,
  admin,
  superAdmin;

  String get dbValue => switch (this) {
        UserRole.customer => 'customer',
        UserRole.vendor => 'vendor',
        UserRole.rider => 'rider',
        UserRole.admin => 'admin',
        UserRole.superAdmin => 'super_admin',
      };

  String get label => switch (this) {
        UserRole.customer => 'Customer',
        UserRole.vendor => 'Vendor',
        UserRole.rider => 'Delivery Rider',
        UserRole.admin => 'Company Admin',
        UserRole.superAdmin => 'Super Admin',
      };

  static UserRole fromDbValue(String value) {
    return UserRole.values.firstWhere(
      (r) => r.dbValue == value,
      orElse: () => UserRole.customer,
    );
  }

  /// Roles selectable during self-service sign-up. Admin/Super Admin
  /// accounts are provisioned internally, never through the public
  /// registration screen.
  static List<UserRole> get selfServiceRoles =>
      [UserRole.customer, UserRole.vendor, UserRole.rider];
}
