import 'dart:math';

/// Generates and normalizes human-readable store join codes.
class JoinCode {
  JoinCode._();

  static const int _characterCount = 16;
  static const String _alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  static final RegExp _validCharacters = RegExp(
    '^[$_alphabet]{$_characterCount}\$',
  );

  static String generate() {
    final random = Random.secure();
    final characters = List.generate(
      _characterCount,
      (_) => _alphabet[random.nextInt(_alphabet.length)],
    ).join();
    return format(characters);
  }

  /// Returns a lowercase, separator-free claim ID.
  static String normalize(String value) {
    final normalized = value.trim().replaceAll('-', '').toUpperCase();
    if (!_validCharacters.hasMatch(normalized)) {
      throw const FormatException('Invalid store join code.');
    }
    return normalized.toLowerCase();
  }

  /// Formats a normalized code as four groups of four characters.
  static String format(String value) {
    final normalized = value.replaceAll('-', '').toUpperCase();
    if (!_validCharacters.hasMatch(normalized)) {
      throw const FormatException('Invalid store join code.');
    }
    return '${normalized.substring(0, 4)}-'
        '${normalized.substring(4, 8)}-'
        '${normalized.substring(8, 12)}-'
        '${normalized.substring(12, 16)}';
  }
}
