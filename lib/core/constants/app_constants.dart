/// App-wide constants.
class AppConstants {
  AppConstants._();

  /// Admin support WhatsApp number in international format WITHOUT the
  /// leading '+' (wa.me requirement). All admin contact flows (paywall,
  /// verification gate, subscription renewals) route through this number.
  static const String adminWhatsAppNumber = '21624449959';

  /// Public-facing admin support hotline displayed on ban / blocking screens.
  /// Displayed as-is in the UI and read aloud in both language variants.
  static const String adminSupportNumber = '24449959';

  /// Cancellation threshold at which a client account is automatically
  /// blocked by the anti-abuse system. Tracked silently; no UI feedback is
  /// shown until the threshold is reached.
  static const int antiAbuseCancellationLimit = 50;
}