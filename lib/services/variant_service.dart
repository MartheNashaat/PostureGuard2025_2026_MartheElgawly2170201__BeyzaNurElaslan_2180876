import 'package:shared_preferences/shared_preferences.dart';
import '../models/feedback_variant.dart';

/// Which feedback variant this install currently runs.
///
/// Chosen by the user with the three feedback buttons on the home screen and
/// remembered between sessions.
class VariantService {
  static const _key = 'feedback_variant';

  /// Returns null until the user has picked one, so no session is recorded
  /// without a known feedback mode.
  static Future<FeedbackVariant?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return FeedbackVariant.fromCode(prefs.getString(_key));
  }

  static Future<void> set(FeedbackVariant variant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, variant.code);
  }
}
