import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/brand.dart';

/// Semantic colors for money, tuned per brightness.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  const new({required this.owed, required this.owe, required this.neutral});

  /// "You are owed" / "you lent".
  final Color owed;

  /// "You owe" / "you borrowed".
  final Color owe;
  final Color neutral;

  static MoneyColors of(BuildContext context) =>
      Theme.of(context).extension<MoneyColors>()!;

  @override
  MoneyColors copyWith({Color? owed, Color? owe, Color? neutral}) =>
      MoneyColors(
        owed: owed ?? this.owed,
        owe: owe ?? this.owe,
        neutral: neutral ?? this.neutral,
      );

  @override
  MoneyColors lerp(MoneyColors? other, double t) => other == null
      ? this
      : MoneyColors(
          owed: Color.lerp(owed, other.owed, t)!,
          owe: Color.lerp(owe, other.owe, t)!,
          neutral: Color.lerp(neutral, other.neutral, t)!,
        );
}

abstract final class AppTheme {
  static const radius = 20.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.seedColor,
      brightness: brightness,
    ).copyWith(tertiary: Brand.proColor);
    final base = ThemeData(colorScheme: scheme, brightness: brightness);
    final t = base.textTheme;
    final text = t.copyWith(
      displaySmall: t.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      headlineLarge: t.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: t.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      headlineSmall: t.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: t.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final fieldRadius = BorderRadius.circular(14);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      extensions: [
        MoneyColors(
          owed: dark ? const Color(0xFF5FD4A4) : const Color(0xFF138A5B),
          owe: dark ? const Color(0xFFFF9A80) : const Color(0xFFD2492F),
          neutral: scheme.onSurfaceVariant,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: rounded,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 12,
        titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge?.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 3,
        highlightElevation: 4,
        shape: const StadiumBorder(),
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? const Icon(Icons.check, size: 16)
              : null,
        ),
      ),
    );
  }
}
