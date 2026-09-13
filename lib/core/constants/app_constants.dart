/// App-wide constants.
class AppConstants {
  AppConstants._();

  /// Admin support WhatsApp number in international format WITHOUT the
  /// leading '+' (wa.me requirement). All admin contact flows (paywall,
  /// verification gate, subscription renewals) route through this number.
  static const String adminWhatsAppNumber = '21624449959';
}