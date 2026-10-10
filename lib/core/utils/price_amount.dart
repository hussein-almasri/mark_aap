class PriceAmount {
  PriceAmount._();

  static const int filsPerJod = 1000;

  /// The app stores money as integer fils (1 دينار = 1000 فلس). قرش is a
  /// display/input unit only: 1 دينار = 100 قرش, therefore 1 قرش = 10 فلس
  /// exactly. Storage is deliberately left in فلس so existing documents keep
  /// their meaning and no bulk data migration is required.
  static const int qirshPerJod = 100;
  static const int filsPerQirsh = filsPerJod ~/ qirshPerJod; // == 10

  static final BigInt _maxFirestoreInteger = BigInt.parse(
    '9223372036854775807',
  );

  /// Converts an integer قرش amount entered by the user into stored فلس.
  static int qirshToFils(int qirsh) => qirsh * filsPerQirsh;

  /// Converts a stored فلس amount into whole قرش (floor). Prefer
  /// [formatQirsh] when the sub-قرش remainder must be shown exactly.
  static int filsToQirsh(int fils) => fils ~/ filsPerQirsh;

  static int parseJodToFils(String input) {
    final value = input.trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(value);
    if (match == null) {
      throw const FormatException(
        'Enter a non-negative JOD amount with up to three decimal places.',
      );
    }

    final whole = BigInt.parse(match.group(1)!);
    final fractionalText = (match.group(2) ?? '').padRight(3, '0');
    final fractional = BigInt.parse(
      fractionalText.isEmpty ? '0' : fractionalText,
    );
    final fils = whole * BigInt.from(filsPerJod) + fractional;
    if (fils > _maxFirestoreInteger) {
      throw const FormatException('The amount is too large.');
    }
    return fils.toInt();
  }

  static String formatJod(int fils, {bool includeCurrency = true}) {
    final sign = fils < 0 ? '-' : '';
    final absolute = BigInt.from(fils).abs();
    final whole = absolute ~/ BigInt.from(filsPerJod);
    final fraction = (absolute % BigInt.from(filsPerJod)).toString().padLeft(
      3,
      '0',
    );
    final formatted = '$sign$whole.$fraction';
    return includeCurrency ? '$formatted د.أ' : formatted;
  }

  /// Formats a stored فلس amount as قرش using exact integer arithmetic (no
  /// double). A whole قرش shows without a fraction; a sub-قرش remainder shows
  /// one decimal digit because 1 قرش = 10 فلس exactly.
  static String formatQirsh(int fils, {bool includeCurrency = true}) {
    final sign = fils < 0 ? '-' : '';
    final absolute = fils.abs();
    final whole = absolute ~/ filsPerQirsh;
    final remainder = absolute % filsPerQirsh;
    final formatted = remainder == 0
        ? '$sign$whole'
        : '$sign$whole.$remainder';
    return includeCurrency ? '$formatted قرش' : formatted;
  }
}
