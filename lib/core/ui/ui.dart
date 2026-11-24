import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/theme.dart';
import 'package:split_app/features/ledger/domain/models.dart';

/// Small shared building blocks so every screen looks consistent.

const _avatarPalette = [
  Color(0xFF3E7BFA),
  Color(0xFF8E5CF7),
  Color(0xFFE0558F),
  Color(0xFFF08A3E),
  Color(0xFF15A386),
  Color(0xFF2FA4D8),
  Color(0xFFC9861A),
  Color(0xFF6A7CF0),
];

Color colorFor(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _avatarPalette[h % _avatarPalette.length];
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final letters = parts.take(2).map((p) => p.characters.first.toUpperCase());
  return letters.join();
}

/// Circle with initials on a stable, per-person color.
class PersonAvatar extends StatelessWidget {
  const new({super.key, required this.id, required this.name, this.size = 40});

  final String id;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = colorFor(id);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}

/// Overlapping row of avatars ("+2" when there are more than [max]).
class AvatarStack extends StatelessWidget {
  const new({super.key, required this.people, this.size = 28, this.max = 5});

  /// id -> name
  final Map<String, String> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final entries = people.entries.toList();
    final shown = entries.take(max).toList();
    final extra = entries.length - shown.length;
    final ring = Theme.of(context).colorScheme.surfaceContainerLow;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      height: size,
      width: size + (count - 1) * size * 0.7,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * size * 0.7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
                child: PersonAvatar(
                  id: shown[i].key,
                  name: shown[i].value,
                  size: size - 4,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * size * 0.7,
              child: CircleAvatar(radius: size / 2, child: Text('+$extra')),
            ),
        ],
      ),
    );
  }
}

/// Rounded tile with an icon, tinted by [color].
class IconTile extends StatelessWidget {
  const new({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

const _categoryStyle = <String, (IconData, Color)>{
  'General': (Icons.receipt_long_rounded, Color(0xFF607D8B)),
  'Groceries': (Icons.shopping_cart_rounded, Color(0xFF2E9D5B)),
  'Dining out': (Icons.restaurant_rounded, Color(0xFFE2683C)),
  'Rent': (Icons.home_rounded, Color(0xFF3E7BFA)),
  'Utilities': (Icons.bolt_rounded, Color(0xFFD4A015)),
  'Transportation': (Icons.directions_car_rounded, Color(0xFF2FA4D8)),
  'Entertainment': (Icons.movie_rounded, Color(0xFF8E5CF7)),
  'Hotel': (Icons.hotel_rounded, Color(0xFF6A7CF0)),
  'Gifts': (Icons.card_giftcard_rounded, Color(0xFFE0558F)),
  'Medical expenses': (Icons.medical_services_rounded, Color(0xFFD9534F)),
  'Payment': (Icons.payments_rounded, Color(0xFF15A386)),
  'Other': (Icons.category_rounded, Color(0xFF8D8D8D)),
};

class CategoryIcon extends StatelessWidget {
  const new({super.key, required this.category, this.size = 44});
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) =
        _categoryStyle[category] ?? _categoryStyle['General']!;
    return IconTile(icon: icon, color: color, size: size);
  }
}

IconData groupTypeIcon(GroupType t) => switch (t) {
  GroupType.home => Icons.home_rounded,
  GroupType.trip => Icons.flight_takeoff_rounded,
  GroupType.couple => Icons.favorite_rounded,
  GroupType.other => Icons.groups_rounded,
};

class GroupIcon extends StatelessWidget {
  const new({super.key, required this.group, this.size = 48});
  final Group group;
  final double size;

  @override
  Widget build(BuildContext context) => IconTile(
    icon: groupTypeIcon(group.type),
    color: colorFor(group.id),
    size: size,
  );
}

/// Small uppercase label above a section.
class SectionHeader extends StatelessWidget {
  const new(this.title, {super.key, this.trailing, this.padding});
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 24, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const new({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(icon: icon, color: theme.colorScheme.primary, size: 72),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-line right-aligned money label: small caption over a bold amount.
class MoneyLabel extends StatelessWidget {
  const new({
    super.key,
    required this.caption,
    required this.amount,
    required this.color,
  });

  final String caption;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          amount,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A Card wrapping a column of children, with consistent outer margins.
class SectionCard extends StatelessWidget {
  const new({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

extension MoneyColorsX on BuildContext {
  MoneyColors get money => MoneyColors.of(this);
}
