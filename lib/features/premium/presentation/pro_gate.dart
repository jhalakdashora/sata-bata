import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/features/premium/domain/pro_feature.dart';

/// Returns true if the user may use [feature]; otherwise opens the paywall
/// and returns whether they upgraded.
Future<bool> ensurePro(
  BuildContext context,
  WidgetRef ref,
  ProFeature feature,
) async {
  final entitlement = await ref.read(entitlementProvider.future);
  if (entitlement.allows(feature)) return true;
  if (!context.mounted) return false;
  await context.push('/pro?feature=${feature.name}');
  final after = await ref.read(entitlementProvider.future);
  return after.allows(feature);
}

class ProBadge extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD37A), Brand.proColor],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Color(0xFF3B2600),
        ),
      ),
    );
  }
}
