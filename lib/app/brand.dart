import 'package:material_ui/material_ui.dart';

/// Everything user-visible about the brand lives here.
///
/// To rename the app, run `tool/rename_app.sh "New Name"`. It updates this
/// file and `config/brand.properties` (which Android and iOS read). A test
/// (`test/brand_test.dart`) fails if the two ever disagree.
abstract final class Brand {
  static const name = 'Sata Bata';
  static const proName = '$name Pro';
  static const tagline =
      'Split bills with friends and groups.\nNo more awkward math.';

  /// Seed for the whole color scheme.
  static const seedColor = Color(0xFF0E7C66);

  /// Accent used for Pro / premium surfaces.
  static const proColor = Color(0xFFF2A33A);
}
