import 'package:flutter/material.dart';

import 'photo_border.dart';

enum BoothEventTheme {
  classic,
  birthday,
  wedding,
  graduation,
  holiday,
  summer,
  coffeeBeans,
  coffeeCup,
  latteArt,
  valentines,
}

extension BoothEventThemeDetails on BoothEventTheme {
  String get label => switch (this) {
    BoothEventTheme.classic => 'Classic',
    BoothEventTheme.birthday => 'Birthday',
    BoothEventTheme.wedding => 'Wedding',
    BoothEventTheme.graduation => 'Graduation',
    BoothEventTheme.holiday => 'Christmas',
    BoothEventTheme.summer => 'Summer',
    BoothEventTheme.coffeeBeans => 'Coffee Shop - Coffee Beans',
    BoothEventTheme.coffeeCup => 'Coffee Shop - Cups & Steam',
    BoothEventTheme.latteArt => 'Coffee Shop - Latte Art',
    BoothEventTheme.valentines => "Valentine's Day",
  };

  PhotoBorderStyle get borderStyle => switch (this) {
    BoothEventTheme.classic => PhotoBorderStyle.none,
    BoothEventTheme.birthday => PhotoBorderStyle.birthday,
    BoothEventTheme.wedding => PhotoBorderStyle.wedding,
    BoothEventTheme.graduation => PhotoBorderStyle.graduation,
    BoothEventTheme.holiday => PhotoBorderStyle.christmas,
    BoothEventTheme.summer => PhotoBorderStyle.summer,
    BoothEventTheme.coffeeBeans => PhotoBorderStyle.none,
    BoothEventTheme.coffeeCup => PhotoBorderStyle.none,
    BoothEventTheme.latteArt => PhotoBorderStyle.none,
    BoothEventTheme.valentines => PhotoBorderStyle.wedding,
  };

  String get welcomeMessage => switch (this) {
    BoothEventTheme.classic => 'TAKE HOME A MEMORY',
    BoothEventTheme.birthday => 'HAPPY BIRTHDAY',
    BoothEventTheme.wedding => 'CELEBRATE LOVE',
    BoothEventTheme.graduation => 'CLASS OF THE YEAR',
    BoothEventTheme.holiday => 'HAPPY HOLIDAYS',
    BoothEventTheme.summer => 'SUMMER MEMORIES',
    BoothEventTheme.coffeeBeans => 'FRESHLY BREWED MEMORIES',
    BoothEventTheme.coffeeCup => 'SIP, SMILE, REPEAT',
    BoothEventTheme.latteArt => 'A LITTLE LATTE LOVE',
    BoothEventTheme.valentines => 'CELEBRATE LOVE',
  };

  bool get usesWhiteBackground => this != BoothEventTheme.classic;

  Color get resultTextColor => switch (this) {
    BoothEventTheme.classic => const Color(0xFF17212B),
    BoothEventTheme.birthday => const Color(0xFF9C2948),
    BoothEventTheme.wedding => const Color(0xFF75415F),
    BoothEventTheme.graduation => const Color(0xFF294E69),
    BoothEventTheme.holiday => const Color(0xFF216746),
    BoothEventTheme.summer => const Color(0xFF865A12),
    BoothEventTheme.coffeeBeans ||
    BoothEventTheme.coffeeCup ||
    BoothEventTheme.latteArt => const Color(0xFF68452D),
    BoothEventTheme.valentines => const Color(0xFF982F4C),
  };
}
