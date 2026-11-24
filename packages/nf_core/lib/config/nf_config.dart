class NfConfig {
  static const String supabaseUrl = 'https://dsidhlpgdanmgndrbksx.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRzaWRobHBnZGFubWduZHJia3N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUyMzU4MjksImV4cCI6MjExMDgxMTgyOX0.lMPZB67yKcaT55sJjSZG-p0QJuuEc4Tfvez3GA_GA7o';

  static const String tenantId = 'nutrifresh';
  static const String defaultBranchId = 'cabang-1';
  static const String storageBucket = 'nutrifresh-media';
  static const String publicWebOrigin = 'https://nutrifresh.my.id';

  // Redirect URL OAuth untuk Windows (.exe) & Android (.apk)
  static const int windowsOAuthPort = 43821;
  static const String windowsOAuthRedirect =
      'http://localhost:43821/auth-callback';
  static const String androidPosOAuthRedirect =
      'id.my.nutrifresh.pos://login-callback';
}
