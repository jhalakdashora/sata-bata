import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:split_app/app/brand.dart';

/// Android/iOS read the name from config/brand.properties; the UI reads
/// Brand.name. Keep them identical (use tool/rename_app.sh).
void main() {
  test('Brand.name matches config/brand.properties', () {
    final props = {
      for (final line in File('config/brand.properties').readAsLinesSync())
        if (line.contains('='))
          line.substring(0, line.indexOf('=')): line.substring(
            line.indexOf('=') + 1,
          ),
    };
    expect(props['APP_DISPLAY_NAME'], Brand.name);
    expect(
      props['APP_ID'],
      matches(RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$')),
    );
  });
}
