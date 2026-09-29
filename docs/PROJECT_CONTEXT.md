# Project context: Kareem Store

For the current Firestore read model, active query inventory, checkpoint rules,
rollout prerequisites, and measurement procedure, see
[FIRESTORE_READ_OPTIMIZATION.md](FIRESTORE_READ_OPTIMIZATION.md).

Updated 2026-09-28 after the customer and supplier financial/offline fixes. This is a code-based orientation, not a production audit. See [OFFLINE_BALANCE_AUDIT.md](OFFLINE_BALANCE_AUDIT.md) for confirmed defects, migration limits, remaining offline work and historical review. No production Firebase data was accessed.

## Purpose and active features

An Arabic, right-to-left hardware/tools store application. The Dart package is `kareem_store`; some README/platform names and branding come from earlier applications.

Verified from current navigation and implementations:

- Sales and purchase invoices, discounts, payments, editing/deletion, invoice lists/details, and special/starred invoices.
- Customer sales returns; saved price quotes that can later become sales invoices.
- Products with cost, three selling prices, stock, department, low-stock threshold, retail/on-demand flags; product creation/editing, history, inventory valuation, and PDF lists.
- Customers and suppliers, opening balances, transaction histories, payment vouchers, statements, and renaming. Supplier ledger/cache code also reads purchase returns; a complete purchase-return creation flow was not verified.
- Cash-box additions/deductions and change history; categorized expenses.
- Sales/profit, product, best-product, customer, inventory, monthly comparison, and payment-distribution reports.
- Thermal Bluetooth receipts, printer/store-branding settings, PDF/image output, and WhatsApp sharing.
- Offline local records, durable upload queue, connectivity status, and a sync dashboard.

Older employee attendance/borrowing/medical, accommodation, spare-parts requests, materials, pipes, injection, and supervisor modules remain in source. Representative code performs direct Firestore operations. No entry to these modules was found in the active home/tab navigation; do not assume they are current user-facing features.

## Stack and structure

Flutter/Dart, Material widgets, `flutter_screenutil`, Hive with generated adapters, Firebase Core/Firestore/Storage, SharedPreferences, PDF/screenshot/share/file plugins, and Android Kotlin method channels. `flutter_bloc` is installed, but most active screens manage state with `StatefulWidget`/`setState`, Hive listenables, and Firestore streams.

| Area | Responsibility / useful starting files |
| --- | --- |
| `lib/main.dart` | Hive/Firebase initialization, startup sync, background listeners, RTL responsive app shell. |
| `lib/auth/`, `lib/Screeens/SplashScreen.dart`, `ChangeCredentialsPage.dart` | Login, offline credential fallback, account editing, startup Bluetooth permission prompt. |
| `lib/Screeens/g_Nav.dart`, `home_page.dart` | Four tabs: home, sales invoices, purchase invoices, products; home feature menu. Direct `MaterialPageRoute` navigation. |
| `lib/Screeens/DecreaseProductPage.dart`, `DecreaseProductComponents/` | Sales/return/quote checkout, product selection, calculation, and edit mode. Much orchestration remains in the screen. |
| `lib/Screeens/AddProductPage.dart`, `lib/Buing Invoices/` | Purchase checkout/list/details. Preserve these existing directory spellings. |
| `lib/Screeens/Data/`, `CreateProductPage.dart`, `ProductListPage.dart`, `lib/EditProductPage.dart`, `lib/departments/` | Product master data, batch/inline creation, catalog, department management and valuation. |
| `lib/clients/`, `lib/suppliers/`, `lib/DeletedClientsPage.dart` | Party management, vouchers, invoice/history views, statements; large files contain several internal pages. |
| `lib/box/`, `lib/expenses/`, `lib/reports/` | Cash, expenses, reporting. `expenses/expense_service.dart` owns expense persistence/date compatibility. |
| `lib/repositories/` | Hive reads/upserts, cloud refreshes, invoice identity reconciliation, ledger calculation. Not a universal boundary for writes. |
| `lib/local_db/hive_init.dart`, `models/*.dart` | Box names, initialization, typed persistent entities, adapter type/field IDs. Companion `*.g.dart` files are generated. |
| `lib/sync/` | Durable queue, dependency-aware upload dispatch, classified retry/recovery, read-only cloud inspection, connectivity polling, Firestore-to-Hive listeners, sync UI. |
| `lib/Services/` | Invoice stock/number/balance helpers, save/update/delete actions, quote execution, quick entity creation, printing/export/sharing. |
| `lib/Widgets/`, `lib/models/`, `lib/utils/` | Shared responsive/receipt/phone/date widgets, print and legacy domain models, entity-name normalization. |
| `lib/Screeens/Materials/`, `Pipes/`, `Injection/`, `Suoervisors/`, employee/account screens | Older modules with separate Firestore schemas; inspect their reachability before changes. |
| `android/`, `windows/`, `ios/`, `macos/`, `linux/`, `web/` | Platform hosts/configuration. Android has custom receipt rendering, Bluetooth and WhatsApp handlers. Platform folders alone do not prove support. |
| `assets/`, `fonts/`, `test/` | Images/PDF resources, Arabic fonts and thirteen Dart test files. |

Ignore `build/`, `.dart_tool/`, `.gradle-local/`, platform `ephemeral/`, `.cxx/`, dependency folders, `dist/`, archives, and `.restore_tmp/` for ordinary source exploration. No `AGENTS.md` was found in the project or checked ancestor directories. Root `README.md` is a Flutter starter; the iOS launch-image README only explains asset replacement.

## Main flows and dependencies

1. **Startup/login:** initialize Hive; recover write-ahead preparing operations; preserve existing customer and supplier balances as accepted baselines; initialize Firebase and cached printer settings. Cloud startup sync and connectivity/realtime services start after the first local UI frame. Hive errors display a recovery screen and preserve box files. Startup labels the failing phase and Hive box, logs per-stage timing, and reopens an already-open box if its in-process generic type differs. A one-pass ledger calculation avoids a full metadata scan per customer during restart and customer-list rendering. Splash requests Bluetooth access and opens login. Login queries cloud users and can fall back to saved credentials; startup sync is not gated by login.

2. **Sales/customer finance:** home -> `DecreaseProductPage` -> checkout -> `CustomerOperationService`. Cached customers/products are required. One `LocalOperationJournal` record contains invoice, canonical history, customer ledger event/mirror, stock and cash after-images. The journal flushes before applying effects. `BatchSyncEngine` uploads version-2 operations through `FinancialCloudUploader`: invoice/copies/history/stock/customer/cash and an immutable receipt commit in one cloud transaction. Duplicate attempts return the receipt. No direct Firebase write is required for the local save.

3. **Purchases/suppliers:** `AddProductPage`, `BuyingInvoiceUpdateService`, purchase deletion screens, supplier creation and `SupplierPaymentService` route through `SupplierOperationService`. A purchase adds `total - paid` to supplier payable, adds stock and subtracts paid cash. Edits apply differences and deletion reverses current effects. The same write-ahead journal and cloud receipt cover supplier ledger, invoice/copy/history, products and cash. `SupplierBalanceStore` owns accepted payable; reconnect hydration cannot recalculate it. Cached purchase returns can be read, but no active return writer was found or verified.

4. **Returns/quotes/edit/delete:** customer return changes debt by `-(total-refund)`, restores stock and subtracts refunded cash. Edits reverse the stored effect then apply the new effect; deletion reverses the current invoice. Invoice-linked payments edit the invoice payment, not a second independent debt effect. Quote create/edit/delete has no financial effect; execution journals one deterministic sale and quote deletion together. Cached stale/concurrent edits fail visibly. Quote and invoice lists read Hive.

5. **Party balances/vouchers/footer/statements:** `CustomerBalanceStore` and `SupplierBalanceStore` compute preserved baselines plus immutable signed events; party model balances mirror them. Histories are display/review data and reads do not delete or repair them. Existing cloud balance assignments do not replace these ledgers; modern events import once. Customer manual payments, opening edits and vouchers use the same journal. Both sales/customer pages use `InvoiceFooterData`/`InvoiceTotalsFooter`; statement data uses the same local balance and invoice payload. `CustomerLocalViews` supplies customer balance reports. Supplier voucher `عليه` reduces payable and cash; `له` adds payable without a cash effect. Supplier voucher lookup/navigation uses local data. Party rename/permanent deletion and supplier statement generation still depend on direct cloud operations.

6. **Catalog/expenses/reports/output:** product batch entry saves Hive and queues product creation; image upload still requires Firebase Storage. Expense save/delete writes Hive and queues one background operation. Expense saving does not itself change the cash box. The active business reports read Hive repositories, and product PDF export reads the product cache. Invoice print and WhatsApp preparation resolve the newest invoice, party and product data from Hive and cached printer settings, so unsynced edits print immediately. Receipt preparation → print formatter/Bluetooth service → `thermal_print_channel.dart` → Android handlers; PDF/image and WhatsApp services are separate consumers of invoice data.

The Cubit in `DecreaseProductComponents/bloc/invoice_cubit.dart` loads Hive products/customers and listens for changes. Searches found its consumer in `client_selection_dialog.dart`, but no provider/creation in the active sales screen. Confirm wiring before extending it. `route_generator.dart` only defines `/Accounts` and is not registered in `MyApp`.

## Data storage and synchronization

| Data | Persistent locations |
| --- | --- |
| Products/departments | Firestore `products`, `departments`; Hive `products_cache`, `departments_cache`; product `changes` subcollection. Product images can go to Firebase Storage. |
| Customers/suppliers | Firestore `clients`, `suppliers`; Hive `clients_cache`, `suppliers_cache`; party `balanceHistory` subcollections and shared local `balance_history_cache`. |
| Invoices | Root `invoices`, `returnInvoices`, `buying invoices`; copies below customers/suppliers. Supplier purchase returns are read from `suppliers/{id}/returnBuyingInvoices`. Separate Hive boxes for sales, returns, purchases and purchase returns. |
| Quotes/expenses/cash | `price_quotes`, `expenses`, `expense_categories`, `box/mainBox` and its `changes`; corresponding Hive caches except categories/change logs. |
| Payments | `client_vouchers`, `supplier_vouchers`; informational `payment_breakdowns` mirrored in Hive `paymentBreakdownsBox`. Wallet/cash/Instapay/bank breakdowns do not drive invoice debt or cash calculations. |
| Local metadata/settings | Hive `app_meta` counters/timestamps and `sync_queue`; SharedPreferences credentials/role and printer settings. Printer settings also use `settings/printer_settings`; receipt logo path remains local. Some deleted-party views use additional local Hive boxes. |

`Hive.initFlutter()` uses platform-local storage; no encryption cipher is passed when opening boxes. Invoice lines are JSON within typed `InvoiceLocal`. Preserve Hive type/field IDs and legacy parsing compatibility when changing models.

Queue payloads are JSON with ISO dates. Financial version-2 operations add `financialFormat: 2`, absolute local after-images, cloud writes and signed customer/supplier deltas. Preparing saves replay on restart; local effects are never reapplied on upload. Each successful transaction also allocates a sequence in `financial_operation_receipts/_change_feed_head` and creates a receipt listing affected paths and parties. Other devices store the last imported sequence in Hive and request only later receipts, instead of reopening all invoice, party, voucher and ledger collections. A missing cursor causes one full compatibility baseline; clearing app data or reinstalling repeats that baseline.

Each queue record retains invoice/party diagnostics, classified error/code, attempt times, next retry and capped attempt history. Temporary errors use delayed automatic retry and safe per-item retry. Firestore quota exhaustion stays queued and can be retried manually after the quota resets or billing changes, but it is not retried automatically every few seconds. Conflicts, validation, permission and legacy errors require review. A failed operation blocks later operations that share an affected party, invoice, product or cash resource; unrelated version-2 work may continue. Legacy financial payloads remain a global barrier because they cannot enumerate every effect. The dashboard shows a concise Arabic failure reason and keeps the technical exception under Details.

Realtime financial events are converted from Firestore-only values such as `Timestamp` to Hive-supported values before persistence. A 2026-09-29 read audit found nine unfiltered root listeners plus unfiltered `financialOperations` and `balanceHistory` collection-group listeners. Their first snapshots reread the complete matching dataset and can explain the observed 4.4K-read one-minute spike. Financial updates now use the sequenced receipt feed; snapshots are processed serially and the Hive cursor advances only after all affected records are durable. A post-upload balance mismatch performs a full affected-party event read only as a compatibility fallback for older writers.

An installation without a sequence cursor performs one compatibility baseline, including legacy statement rows. Ordinary later launches read later financial receipts and their affected documents. Product/customer/supplier profile synchronization and expense/department/payment-breakdown hydration use persisted timestamp cursors after that baseline. Product change listening is filtered by `updatedAt`; invoice stock changes also arrive through receipts. Cash/product/material/pipe/injected histories and damaged products load 50 documents per cursor page. Reports and normal product lists read Hive. A fresh install must still read every legacy record once to create the offline cache.

When the user exits through the app's Back flow while an item is actively uploading, the exit dialog reports the number of unfinished operations and offers to stay in the app or close immediately. Closing is safe because the durable queue is recovered on the next launch; other devices will not see the operation until upload succeeds. Android force-stop, process termination and task swipe-away cannot reliably be intercepted, so they do not show this dialog.

Local baseline/events/version metadata live in existing `app_meta` keys, without adapter/schema changes. Cloud adds `financial_operation_receipts/<operationId>`, `financial_operation_receipts/_change_feed_head`, and party `financialOperations/<operationId>` documents; existing documents retain old fields plus versions/operation IDs. The head adds one document read and write to each new financial operation and provides crash-safe global ordering. Invoice/history/quote deletion uses versioned `_deleted` tombstones. Guards reject stale snapshots and snapshots for pending paths. Upgraded clients are required; old builds do not understand the new tombstones/ledger or publish feed receipts.

**Old customer/supplier/cash queue records are held for review**, because their prior partial effects cannot safely be inferred. They can block later uploads; Retry does not migrate them. Do not clear the queue or automatically repair balances. Dashboard -> customer balance review shows local/history/cloud differences without applying changes; follow the audit's historical review procedure.

Connectivity detects interfaces, not Firestore reachability. Older employee/material/pipe/injected/spare-part modules, expense categories, damaged-product actions, party profile/rename/delete paths and some export helpers still use direct Firebase operations; see the audit inventory before promising whole-app offline behavior or globally minimal reads.

## Permissions

- No Firebase Auth dependency or authenticated session flow was found. `user_role` is a local preference. Individual screens check `admin` for actions such as invoice editing/deletion, product actions, cost exports and some inventory views. There is no centralized route/repository authorization layer.
- Login defaults a missing cloud role to `admin`; most action screens default a missing preference to `user`. `ChangeCredentialsPage` lists accounts and updates selected credentials without an explicit role check in the inspected implementation.
- Android declares Bluetooth/nearby-device, older-device location, storage, WhatsApp package visibility and a FileProvider. `bluetooth_permission_service.dart` requests runtime Bluetooth/location access. Exact behavior requires device testing.
- No Firestore/Storage rules or index definitions were found in source; deployed authorization, indexes and backend access restrictions could not be verified.

## Files to start with for future changes

| Change | Inspect together |
| --- | --- |
| Invoice totals/checkout/returns | `Screeens/DecreaseProductPage.dart`, its component sheets, `Services/invoice_number_utils.dart`, `invoice_stock_service.dart`, `return_invoice_save_service.dart`, `local_db/models/invoice_local.dart`. |
| Edit/delete consistency | `Services/sales_invoice_update_service.dart`, `sales_invoice_actions_service.dart`, `buying_invoice_update_service.dart`, `sync/batch_sync_engine.dart`, party invoice pages, `repositories/balance_history_repository.dart`. |
| Balances/payment numbers | `Services/customer_operation_service.dart`, `customer_balance_store.dart`, `supplier_operation_service.dart`, `supplier_balance_store.dart`, `customer_statement_data.dart`, `invoice_footer_data.dart`, client/supplier pages and repositories, both `*_invoice_balance_sync_service.dart` services, `client_invoice_running_balance_service.dart`, `repositories/payment_breakdown_repository.dart`. |
| Product/schema changes | `Screeens/Data/DataEntryScreen.dart`, `Data/quick_add_product_sheet.dart`, `CreateProductPage.dart`, `EditProductPage.dart`, `ProductListPage.dart`, `local_db/models/product_local.dart`, `repositories/product_repository.dart`, `Services/quick_entity_creation_service.dart`. |
| Offline/sync behavior | `sync/local_operation_journal.dart`, `financial_cloud_store.dart`, `cloud_snapshot_guard.dart`, `main.dart`, `local_db/hive_init.dart`, `repositories/data_sync_service.dart`, relevant repositories, all four main `sync/` services, sync UI. |
| Receipt/branding/sharing | `PrinterSettingsPage.dart`, `models/printer_settings.dart`, `Services/printer_settings_service.dart`, `invoice_print_service.dart`, `invoice_print_formatter.dart`, PDF/image/share services, `Widgets/invoice_receipt_card.dart`, Android `com/kareemham/store/` handlers. |
| Navigation/layout/login | `main.dart`, splash/login, `g_Nav.dart`, `home_page.dart`, `Widgets/app_responsive.dart`, `responsive_screen_util_host.dart`, credential page and per-screen role checks. |

Paths in this table are relative to `lib/`, except Android paths.

## Running and verification

Run commands from the project root:

```powershell
flutter pub get
flutter devices
flutter run -d windows
# Or use an Android device ID from flutter devices:
flutter run -d <device-id>
flutter test --no-pub
flutter analyze --no-pub
```

Use existing authorized Firebase configuration and a test dataset for manual flows: launching the app starts cloud reads and background writes. Initial login needs an available cloud account; offline login requires saved credentials. No custom development scripts, CI pipeline or integration-test directory were found.

Environment inspection found cached Flutter 3.29.3 / Dart 3.7.2. `pubspec.yaml` declares Dart `>=2.18.0 <3.0.0`, while `pubspec.lock` requires Dart `>=3.7.0 <4.0.0` and Flutter `>=3.29.0`. Fresh dependency resolution was not attempted; reconcile this mismatch before relying on a clean setup. Existing cached dependencies allowed tests to run.

**Verified:** `flutter test --no-pub` passed **122 tests**. Tests use real temporary Hive storage/reopening and the production transaction algorithm with an atomic in-memory cloud. They cover local creation, interrupted saves, restart, classified/per-item retries, Firestore quota suppression/migration, timestamp-safe cloud event imports, retry history, lost acknowledgements, reconnect, dependency isolation, read-only receipt inspection, Android backup exclusion, sales/return and purchase edits/deletes, customer/supplier payments/openings/vouchers, stock/cash, stale snapshots, concurrent edits, quote execution, unsynced invoice printing, shared footer data/rendering, and both choices in the active-upload exit dialog. The smoke test constructs `MyApp`; it is not an end-to-end device test.

**Analysis:** `flutter analyze --no-pub` completed with zero errors and 1,252 warning/info findings. `git diff --check` passed.

**Not verified:** actual Firestore rules/transactions/listener permissions, the new receipt `sequence` query, two devices, platform builds, physical printing/sharing or an OS power-loss scenario. No app launch, fresh dependency install or production cloud access was performed. Rules/index files are absent; test the feed head, receipt query and event paths in a test Firebase project before release.

For later behavioral changes, run the relevant tests plus the suite, then manually check create/edit/delete, stock, both party ledgers and cash; offline save → restart → reconnect → queue drain; two-device refresh; and receipt/report agreement. Schema changes additionally need old-cache compatibility checks. Adapter generation, when intentionally changing Hive models, uses `dart run build_runner build --delete-conflicting-outputs` and should be reviewed as a code change.

## Specific risks and remaining uncertainties

- **Historical balances:** existing accepted balances are preserved, even if wrong historically. Cache incompleteness, ambiguous aliases and partial legacy uploads require review; the read-only difference screen does not pick a repair target.
- **Remaining offline work:** purchase-return writes, product CRUD/prices/images/history, party rename/permanent-delete/phone changes, departments, expenses/categories, cloud reports, supplier statements, printing metadata/settings and account management retain cloud dependencies or older crash gaps. See the complete operation inventory and [FIREBASE_REFERENCES.md](FIREBASE_REFERENCES.md).
- **Identity/display numbers:** local counters are not globally unique. Root IDs and explicit aliases establish identity. Some older product/party paths still resolve names. Voucher numbering/legal requirements and overpayment/payment-method cash rules need business decisions before redesign.
- **Credentials/permissions:** raw passwords and local roles are trusted in login/account screens. No deployed rules were inspected. This change does not establish backend authorization.
- **Platform/build:** pubspec/lock SDK constraints disagree; Android has paired Gradle files with differing settings and debug release signing. Linux Firebase options throw; active file APIs complicate web support. Release permission merging, iOS/macOS settings and custom Android printer/share handlers need device/build verification.
- **Coverage:** active customer and ordinary purchase/supplier financial flows were traced through UI, local stores, queue, transaction planner and guarded hydration. No active purchase-return writer was found. Product/expense/report/older cloud callers were inspected for the inventory, not all reproduced. Older modules' active reachability and every export layout remain unverified. Source comments can describe obsolete migrations; prefer current implementation and the audit.
