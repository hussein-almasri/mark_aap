class PriceAmount {
  PriceAmount._();

  static const int filsPerJod = 1000;
  static final BigInt _maxFirestoreInteger = BigInt.parse(
    '9223372036854775807',
  );

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
}
