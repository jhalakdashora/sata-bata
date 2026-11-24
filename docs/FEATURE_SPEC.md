# Sata Bata: feature spec

Sata Bata is an expense-splitting app built in Flutter. It is a clean-room
implementation: the reference app (Splitwise for Android 26.11.1, build 972)
was studied only to learn **what** features exist and how free and Pro differ.
No code, artwork or branding was taken from it.

## Where this comes from

| Source | What it gave | REA evidence |
|---|---|---|
| Decoded `AndroidManifest.xml` | Screens, deep links, permissions, SDKs | `ev_56a5631a…d0f25d35` (apktool 3.0.3, APK sha256 `0cf24232…09f9e9`) |
| `res/values/strings.xml` (2,552 strings) | Feature wording, Pro-gated features, split rules | same decode |
| APK file listing | Native libraries: ML Kit OCR and document scan, barcode, SQLite | `unzip -l` |
| JADX class search (3,166 app classes) | Feature packages and model classes | REA CLI `search-android-classes` |
| JADX class inventories | Fields of the data model (below) | `Expense` ev_b2620aeffc7…, `Share` ev_9d3156aa5ef…, `ExpenseComment` ev_e4c4efbbf41…, `Group` ev_b8a629d9c9c…, `GroupMember` ev_cf828588a52…, `Friendship` ev_f262ec4d2e7…, `ReceiptScanningFeatureStatus` ev_7757b33fff1… |

### Data model in the reference app (from JADX field lists)

Field names were observed; meanings are inferred from the names.

- **Expense:** `cost`, `currencyCode`, `date`, `description`, `notes`,
  `categoryId`, `groupId`, `payment` (bool), `creationMethod` (includes
  refund and settle-all-balances), `repeatInterval`, `nextRepeatTimestamp`,
  `emailReminderDaysInAdvance`, `receiptPath`, `comments`, `commentsCount`,
  `deletedAt` (soft delete), created/updated/deleted by.
- **Share:** `personId`, `paidShare`, `owedShare`, `netBalance`. This is the
  same paid/owed-per-person model Sata Bata uses.
- **ExpenseComment:** `content`, `commentType` (user or system),
  `personId`, `deletedAt`.
- **Group:** `groupType`, `members`, `simplifyByDefault`, `originalDebts`,
  `simplifiedDebts`, `inviteLink`, `whiteboard` (a shared group note),
  `groupReminders`, `activeProPass`.
- **GroupMember:** `balance`, plus a per-member `defaultSplit`.
- **Friendship:** `registrationStatus` is confirmed, invited, dummy (a
  placeholder) or unsubscribed.
- **Pro gating is driven by the server.** Classes like
  `ReceiptScanningFeatureStatus` carry `enabled`, `visible`,
  `freeScansAllowed`, `freeScansRemaining` and `adUrl`. Free users get a
  small receipt-scan quota rather than none.

## Reference app at a glance

- Native Android app (Kotlin, Compose and Views, Hilt, Room, WorkManager), not Flutter.
- Integrations: Firebase (messaging, Crashlytics), Google Play Billing 9,
  Google Pay / Wallet, Plaid (bank linking), Tink (pay by bank), Venmo,
  ML Kit (OCR, document scanner, barcode), Microblink (receipt parsing).
- Screens seen in the manifest: Dashboard, AddExpense, AddPayment, SelectPeopleWizard,
  LiveSplitsFlow, Passcode and Biometrics lock, invite, magic-link and
  password-reset link handlers, ImageCapture, Card onboarding.

## Free features

| Area | Behaviour | Sata Bata status |
|---|---|---|
| Groups | Types: home, trip, couple, other; members; personal default split | ✅ create, type, members |
| Friends | Balances outside groups; balances across all groups | ✅ |
| Expenses | Description, amount, currency, category (48 categories), date, notes, payer(s) | ✅ (one payer in UI; model supports several) |
| Split methods | Equal, exact amounts, percentages, shares, adjustment | ✅ all 5, tested |
| Simplify debts | Per-group setting that minimises the number of payments | ✅ tested |
| Settle up | Record a payment; "settle all balances" across groups | ✅ record payment |
| Activity feed | Every change, newest first | ✅ basic |
| Sign-in | Google | ✅ Supabase `signInWithIdToken` |
| Comments | On expenses; user and system types | ✅ add and view (system comments: model only) |
| Recurring expenses | Weekly, fortnightly, monthly, yearly | ✅ app plus server (`materialize_recurring_expenses`, pg_cron); email reminder ⏳ |
| Invites | Phone, email or link; group invite link; account merge | ⏳ |
| App lock | Device biometrics or passcode | ⏳ |
| Multi-currency | Balances kept per currency | ✅ |

## Pro features (Sata Bata Pro)

Each Pro feature below appears in a "… is a Splitwise Pro feature" string in
the reference app.

| Pro feature | Sata Bata status |
|---|---|
| Receipt scanning (OCR) | ✅ ML Kit on the phone; 3 free scans, then Pro |
| Itemize receipt (assign items to people) | ✅ Pro; tax and tip shared in proportion to items |
| Search | ✅ gated and working |
| Charts and group totals | ✅ gated, spending by category |
| Currency conversion | ❌ dropped (app is rupees-only) |
| Export (CSV) | ✅ gated, copies to clipboard |
| Unequal default split for a group | 🔒 planned |
| Placeholder members | 🔒 model supports it, no UI yet |
| Settle-up reminders | 🔒 planned |
| Balance alerts | 🔒 planned |
| Transaction import (bank or card) | ❌ out of scope (regulated) |
| "Pro trip" pass (temporary Pro for every group member) | 💡 later |

**Out of scope:** the Splitwise Card, Splitwise Pay, and the KYC and
SSN flows. These are regulated banking products, not app features.

## Architecture

```
lib/
  core/            Money (integer minor units)
  app/             router (go_router), providers (Riverpod), theme
  features/
    ledger/
      domain/      models, SplitCalculator, BalanceCalculator (pure Dart, tested)
      data/        LedgerRepository + InMemory (demo) + Supabase
      presentation/ screens
    premium/
      domain/      ProFeature, Entitlement
      data/        EntitlementRepository (mock now, RevenueCat later)
      presentation/ paywall, ensurePro() gate
supabase/migrations/  Postgres schema, row-level security, add_expense() RPC
```

**Key rules**

- Money is never stored as a floating-point number. Amounts are `int` minor
  units, and leftover cents are handed out by largest remainder, so splits are
  deterministic.
- Every expense must satisfy `sum(paid) == sum(owed) == total`. This is checked
  in Dart (`Expense` constructor) and in Postgres (`add_expense`).
- Payments are stored as expenses of kind `payment`, so the same balance math
  covers both.
- Billing sits behind `EntitlementRepository`, so swapping the mock for
  RevenueCat needs no UI changes.
