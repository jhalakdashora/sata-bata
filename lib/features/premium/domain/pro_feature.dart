/// Features reserved for the paid tier. Mirrors the Pro feature set observed
/// in the reference app (see docs/FEATURE_SPEC.md), implemented independently.
enum ProFeature {
  receiptScanning(
    'Scan receipts',
    'Snap a receipt and fill in the expense automatically.',
  ),
  itemization('Itemize receipts', 'Assign individual receipt items to people.'),
  search('Search', 'Search every expense, note and comment.'),
  charts('Charts & totals', 'See spending by category and over time.'),
  export('Export', 'Export any group or friend ledger to CSV.'),
  unequalDefaultSplit(
    'Default splits',
    'Set an unequal default split for a group.',
  ),
  placeholderMembers(
    'Placeholder members',
    'Add people now, invite them later.',
  ),
  settleUpReminders(
    'Settle-up reminders',
    'Automatic reminders for group members.',
  ),
  balanceAlerts(
    'Balance alerts',
    'Get notified when a balance passes a limit.',
  );

  new(this.title, this.description);
  final String title;
  final String description;
}

/// Free users get a few receipt scans before scanning requires Pro (the
/// reference app gates scanning the same way: `freeScansAllowed` and
/// `freeScansRemaining` on its server-driven feature status).
const kFreeReceiptScans = 3;

class Entitlement {
  const new({
    required this.isPro,
    this.expiresAt,
    this.freeScansRemaining = kFreeReceiptScans,
  });
  const new free()
    : isPro = false,
      expiresAt = null,
      freeScansRemaining = kFreeReceiptScans;

  final bool isPro;
  final DateTime? expiresAt;
  final int freeScansRemaining;

  bool allows(ProFeature feature) => isPro;

  bool get canScanReceipt => isPro || freeScansRemaining > 0;
}
