import 'package:shared_preferences/shared_preferences.dart';

/// The participant ID for this phone, chosen by the user the first time and
/// kept until they edit it. Attached to every session so uploaded sessions
/// can be grouped per participant.
class ParticipantService {
  static const _key = 'participant_id';
  static const int minLength = 6;

  /// Shown under the entry field.
  static const String rule = 'At least $minLength characters, letters and numbers only.';

  static final RegExp _allowed = RegExp(r'^[A-Za-z0-9]+$');

  /// [input] exactly as typed (only stray spaces at the ends removed), or
  /// null if it breaks [rule]. Case is kept: `ab12cd` and `AB12CD` are
  /// different IDs.
  static String? normalize(String input) {
    final s = input.trim();
    if (s.length < minLength || !_allowed.hasMatch(s)) return null;
    return s;
  }

  /// True if [input] contains anything other than letters and numbers.
  static bool hasInvalidCharacters(String input) {
    final s = input.trim();
    return s.isNotEmpty && !_allowed.hasMatch(s);
  }

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Validates and saves [input]. Returns the saved ID, or null (and saves
  /// nothing) if it breaks [rule].
  static Future<String?> set(String input) async {
    final id = normalize(input);
    if (id == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
    return id;
  }
}
