# Offline customer and supplier balances: implementation and review

The subsequent read audit preserves this financial contract while replacing
repeated history scans with Hive views, incremental catch-up, and the sequenced
receipt feed. See
[FIRESTORE_READ_OPTIMIZATION.md](FIRESTORE_READ_OPTIMIZATION.md).

Investigated 2026-09-27. No production Firebase data was read, written, repaired, or reconciled. Tests use disposable Hive directories and an atomic in-memory cloud backend. This document distinguishes source-confirmed defects from unverified production scenarios.

## Confirmed defects and their fixes

| Original defect | Evidence and affected paths | Fix |
| --- | --- | --- |
| Reading customer history could delete unmatched invoice rows when invoice cache hydration was incomplete. | `repositories/balance_history_repository.dart:getForClient`; regression retained zero rows before the fix. | Reads are pure; unmatched historical rows remain available for review. |
| Invoice-number deduplication merged different root IDs. Offline counters are per device, so equal numbers do not establish identity. | Same repository and old `Services/client_invoice_balance_sync_service.dart`; two invoices with different IDs and number 1 previously totalled 100 instead of 200. | Identity is the root document ID or an explicit sub-document `invoiceId` link. Never infer identity from a display number. |
| Realtime customer upserts replaced pending local balances with a cloud value. Other refresh paths followed different rules. | `sync/realtime_sync_service.dart`, `repositories/client_repository.dart`; regression changed local 150 to stale 100 before the fix. | Immutable local ledger; guarded cloud hydration; snapshot `balance` is diagnostic for existing customers. |
| Refresh/upload-triggered balance repair assigned totals from mutable and potentially incomplete histories, deleted orphan entries, and rewrote invoice balances. | Old `Services/client_invoice_balance_sync_service.dart` and calls in `sync/batch_sync_engine.dart`. Confirmed in code; which historical customers it affected was not established. | Compatibility service now hydrates only. No automatic financial repair during reconnect or reads. |
| Local invoice/payment/stock/cash effects and enqueueing were separate writes. Restart could leave an effect without an upload, or retry an already committed effect. | Sales, returns, edits, deletion, vouchers and cash paths formerly wrote multiple boxes before enqueueing; old upload formats had varying existence/marker checks. | Write-ahead local journal plus one transactional cloud receipt covering every effect. Fault tests cover interrupted saves and lost acknowledgements. |
| Cash adjustment both queued a cloud increment and performed it directly. | `box/MainBoxScreen.dart:_updateBoxValue` and legacy `BatchSyncEngine._syncUpdateBox`. Source-confirmed double-write path; no live cash history was investigated. | One journaled adjustment; repeated upload test checks exactly one cash effect. |
| Customer history editing/deletion and voucher document creation used direct Firebase writes. | `clients/ClientInvoicesPage.dart`, `clients/invoice_edit_sheet.dart`, `clients/ClientsPage.dart`. | Edits and deletion route through local customer operations. Voucher and ledger are in the same operation. |
| Sales-list Firestore overlay bypassed repository guards; pending edits/deletes could be overwritten or reintroduced. | `Screeens/Invoices/All_invoices.dart:_updateInvoicesFromRemote`. | List watches Hive; background synchronization owns cloud imports. Product fallback imports also use guards. |
| Customer footer and sales footer had separate calculations/layouts, different discount handling/labels, and inconsistent historical running balances. | `clients/ClientInvoicesPage.dart`, `Widgets/invoice_display_widgets.dart`, `Services/sales_invoice_actions_service.dart`. | Shared `InvoiceFooterData` and `InvoiceTotalsFooter`, using the same local invoice/ledger view, labels and `invoiceAmount` formatting. Opening/carry balances and deterministic chronology apply to both. |
| Purchase create/edit/delete and supplier voucher saves changed invoices, supplier balance/history, stock and cash in separate local steps before queueing. A crash could preserve only a prefix. | `Screeens/AddProductPage.dart`, `Services/buying_invoice_update_service.dart`, `supplier_payment_service.dart`, both purchase delete screens and supplier creation. | All effects now commit through `SupplierOperationService` and `LocalOperationJournal`; one version-2 receipt makes retries and lost acknowledgements idempotent. |
| Supplier synchronization recalculated and rewrote balances from mutable/incomplete history, so reconnecting could itself change a balance. | Old `Services/supplier_invoice_balance_sync_service.dart` plus supplier history reads. | Sync now hydrates guarded records only. `SupplierBalanceStore` owns preserved baseline plus immutable events; history reads are pure. |
| Supplier history inferred invoice identity from display numbers and mutated Hive while being read. Equal numbers can be created on different devices. | `repositories/balance_history_repository.dart:getForSupplier`. | Canonical invoice IDs drive projections. Ambiguous legacy rows remain visible for review and are never silently merged or repaired. |
| Supplier and purchase refreshes could overwrite pending local supplier values or clear locally cached purchase-return rows absent from one snapshot. | Supplier/invoice repositories and realtime hydration. | Pending/version guards protect supplier roots, purchases, histories and vouchers; refreshes merge records and no longer clear unseen purchase returns. |
| Printing loaded Hive and then allowed an older screen/cloud payload to overwrite it; it also performed Firebase fallback reads and remote settings loads during print. An unsynced edit could therefore print stale values or wait for the network. | `Services/invoice_print_service.dart`, `invoice_print_ui.dart`. | The current Hive invoice is authoritative, party/product metadata and settings come from local caches, and thermal print/WhatsApp preparation performs no Firebase read. Tests cover unsynced sales and purchase edits. |
| Android's default application backup restored old Hive files and legacy queue entries after clearing data, uninstalling and reinstalling. | The manifest had no backup policy; the same dated operations reappeared on the device and no code imports the queue from Firebase. | Android application backup is disabled for future builds. A reinstall can no longer restore stale Hive synchronization state. Existing restored data still requires one post-install clear or reviewed reconciliation. |
| Firestore `resource-exhausted` was treated as a short network failure and retried repeatedly even after the daily Spark quota was exhausted. | The reported Firebase usage screen showed about 91,000 reads against the 50,000 daily no-cost limit; the queue reached five attempts. `sync_operation_diagnostics.dart` included `resource-exhausted` in transient codes. | Quota exhaustion has a clear Arabic message, remains safely queued and manually retryable, but receives no rapid automatic retries. Startup reclassifies affected records created by the previous build. |
| Cloud financial events were copied to untyped Hive metadata with Firestore `Timestamp` values. | `CustomerBalanceStore.importEvent` and `SupplierBalanceStore.importEvent`; the device showed `HiveError: Cannot write, unknown type: Timestamp`. | Recursively convert Firestore timestamps to Hive-supported `DateTime` values before saving customer, supplier or deferred ledger events. |
| Startup and manual sync re-read collections already loaded by realtime listeners; realtime party hydration also issued one financial-event query per party, and “Sync now” launched the background refresh twice. | `main.dart`, `data_sync_service.dart`, `realtime_sync_service.dart`, `sync_dashboard_screen.dart`. These duplicate paths are source-confirmed; the Firebase usage screen does not identify how many of the 91,000 reads each path caused. | Realtime-covered collections are no longer fetched again at startup/dashboard refresh, party listeners rely on the shared collection-group event listener, duplicate refresh calls are removed, and concurrent refresh requests share one run. |

These findings explain mechanisms that can cause incorrect balances. They do not prove the cause of any particular historical customer's discrepancy.

## Financial contract

Customer debt is positive. A customer's accepted balance is an explicitly preserved baseline plus immutable signed operation events. `ClientLocal.balance` is a persisted mirror. `CustomerBalanceStore` is the calculation source; viewing history or changing connectivity does not recalculate or repair the baseline.

Supplier payable is also positive. `SupplierBalanceStore` is the equivalent accepted ledger and `SupplierLocal.balance` is its mirror. Purchases add `total - paid`; purchase edits apply only the difference; purchase deletion reverses that stored effect. Supplier voucher `عليه` reduces payable and subtracts cash, while `له` increases payable without changing cash, preserving the app's existing rule.

Existing installed Hive balances are preserved once. Newly hydrated modern cloud customers import `financialBaseBalance` and their existing events together. New customer creation starts at zero and records the opening amount as an event. A missing historical ledger is never interpreted as zero debt.

| Operation | Customer debt effect | Stock | Cash box |
| --- | --- | --- | --- |
| Sale | `total - paid` | subtract quantity | add paid |
| Return | `-(total - refund)` | add quantity | subtract refund |
| Invoice edit | new effect minus previous effect | undo old lines, apply new lines | new paid/refund effect minus old |
| Move invoice to another customer | reverse old customer's effect, apply new customer's effect | only line differences | only payment differences |
| Invoice deletion | reverse currently stored invoice effect | reverse current lines | reverse current paid/refund |
| Manual addition / voucher `عليه` | add amount | none | subtract amount |
| Manual deduction / voucher `له` | subtract amount | none | add amount |
| Opening balance edit/delete | difference from current opening entry | none | none |
| Quote create/edit/delete | none | none | none |
| Quote execution | one sale with deterministic `quote_sale_<quoteId>` ID | sale effect | sale effect |

Invoice total and its payment are separate display-history rows, but exactly one net financial event. Editing an invoice-linked payment edits `paidAmount`; deleting it sets that amount to zero. It does not separately deduct the invoice payment again. Costs are frozen on saved lines. Existing overpayment/negative-stock policies were not redesigned.

## Persistence and synchronization

- `sync/local_operation_journal.dart` serializes planning, imports and recovery. It flushes a `preparing` queue record containing absolute Hive after-images **before** writing any business box. Every affected box is flushed before status becomes `pending`. Restart replays a partial prefix safely. Queue timestamps are strictly ordered even if the clock moves backward.
- Version-2 payloads keep their existing operation-type names and carry `financialFormat: 2`, `localWrites`, `cloudWrites`, `customerDeltas`, and `supplierDeltas`. Firestore collection paths and the Hive adapter type ID remain unchanged. Optional queue fields 7–12 add diagnostics, attempt history, error classification and retry timestamps; the adapter supplies defaults when reading old records.
- `sync/financial_cloud_store.dart` reads all transaction documents before writing. `financial_operation_receipts/<operationId>`, invoice/copies, history, product increments/logs, customer effects/events and cash/logs commit together. Receipt existence makes another attempt a no-op, including loss of the acknowledgement after commit.
- Customer and supplier documents retain their old balance fields, with additive `financialBaseBalance`, `financialVersion`, `_version`, `_operationId`. Immutable events are stored below each party at `financialOperations/<operationId>`.
- Deletes use `_deleted: true` tombstones with versions, preserving financial evidence. Hive hides/deletes the relevant record. Existing report consumers were updated to ignore invoice tombstones. Old app builds must also be upgraded before using this format.
- `CloudSnapshotGuard` rejects pending-path snapshots and versions older than accepted receipts/imports. Acknowledging an older receipt cannot lower a recorded version. Root invoices, customers, history, stock, cash, quotes and vouchers use these guards. An upload refreshes affected stock/cash/records after acknowledgement because a listener may have delivered a valid newer snapshot while the path was protected.
- Existing invoice edits/deletes also compare the prior operation ID and normalized customer/line/total/payment state. A concurrent change fails atomically and remains visible in the queue. Later operations sharing its party/invoice/product/cash resources cannot overtake it; unrelated version-2 operations may continue. Legacy financial records remain global blockers because their payloads cannot prove all dependencies.
- `SyncStatusBadge` shows errors and pending saves. The dashboard displays invoice number/ID, customer or supplier, amount, error class/code, attempt/next-retry timestamps and full technical details. It supports safe per-item retry, diagnostic copying and a read-only Firebase receipt/path comparison. Temporary failures retry with increasing delay and jitter; authentication, permission, validation, conflict and legacy errors remain held for action. A local opening/recovery error displays a recovery screen and preserves box files.

**Legacy financial queue items are retained and held for review**, rather than replayed under an unproven old idempotency scheme. This includes old customer/supplier creation, sales/return/purchase creation/edit/delete, party balance adjustments and cash adjustments. They can block later operations. Pressing Retry does not convert them to safe version-2 operations. Do not delete the queue or recreate the business operation to bypass the hold.

## Historical review procedure

1. Open Sync Dashboard → **مراجعة أرصدة العملاء**. It shows accepted local balance, available history total, difference, last known cloud balance and pending status. This view performs no writes. A cached-history difference may indicate an incomplete cache or ambiguous legacy IDs rather than an incorrect accepted balance.
2. Before reconciliation, make secure backups of each device's Hive boxes (including `app_meta` and `sync_queue`) and an authorized Firestore export. Coordinate devices so financial writes do not continue during the comparison. Do not put these exports in this repository.
3. On a test copy, assemble root invoices, explicitly linked customer copies, returns, opening entries, manual payments/vouchers, receipts, pending payloads, product logs and cash logs. Preserve root IDs; list missing links, duplicate display numbers and missing documents separately. Show a table per customer: accepted local, cloud, evidenced ledger, proposed local delta, proposed cloud delta. Local and cloud deltas may differ because historical baselines differ.
4. For each held legacy item, establish whether **all** of its invoice/customer/stock/cash effects committed. Old root existence alone is insufficient evidence for all legacy operation types. Classify complete, not applied, partial, or unresolved. Keep unresolved items held. Complete items need a reviewed acknowledgement; not-applied/partial items need a reviewed migration plan with stable IDs and explicit effects, tested against the copy first.
5. Obtain the business owner's decision for unexplained opening/carry amounts, unmatched historical payments, invoice aliases, overpayments and voucher direction semantics. Do not choose a target by blindly summing the currently cached history.
6. Apply an approved reconciliation only through a separately reviewed transactional migration: assert expected before-values/versions, record an immutable receipt/audit entry, and adjust the local and cloud baselines/effects deliberately. Do **not** use a normal payment to repair an accounting discrepancy: that also changes cash. Re-run the difference report before/after and verify stock/cash remain as approved.

This change deliberately provides review and differences, not an automatic production reconciliation tool. It cannot determine a historical target without complete records and the business decision in steps 3–5.

## Firestore read reduction (2026-09-29)

The 4.4K/minute screenshot is consistent with a newly reinstalled device performing its compatibility baseline, amplified by several source-confirmed collection-wide reads. The Firebase graph alone cannot attribute reads to a query; use Firestore Query Insights in the test project to verify the production distribution.

Changes made:

- Normal application screens and all five business reports now read invoices, purchases, products, expenses, customers, suppliers, departments and balances from Hive. Product PDF export no longer downloads the products collection.
- Opening the sales-invoice editor no longer triggers full customer and product refreshes. Product, customer and supplier repository `deltaSync()` methods now query `updatedAt` after their persisted baseline cursors instead of calling `fullSync()`.
- The permanent product listener is bounded by the product cursor. Invoice-driven product changes still arrive through sequenced financial receipts. Current product create/edit/delete paths write `updatedAt`; deletes use tombstones so another device can observe them.
- Expenses no longer keep a collection-wide Firestore listener. Payment breakdowns, expenses and departments use timestamp deltas after their initial import; their deletes are observable tombstones.
- Cash history, product history, pipe history, injected-product history, material history and the edit-product history view use one-time cursor reads of 50 documents with an explicit **تحميل المزيد** action. Damaged products use the same 50-document cursor pattern.
- The deleted-customer list no longer performs one Firestore document read per row.

A fresh installation still intentionally downloads one complete compatibility baseline into Hive. This is required for existing records to work offline and includes legacy balance history/events that lack change timestamps. Pagination changes when pages read data; it does not reduce the total reads required to copy every historical record into an empty local database. After the baseline cursor is durable, reconnect and navigation should fetch only sequenced receipts, changed timestamped records, single settings/cash documents, and user-requested pages.

Remaining read risks:

- Expense categories use small realtime Firestore listeners, and several older employee/material/pipe/injected/spare-part screens still use cloud-only listeners. They are not linked from the inspected main home menu but remain callable code and were not migrated to Hive.
- Some damaged-product actions, party rename/profile/delete paths, supplier statement exports, account administration and legacy helper services still issue direct queries. Their offline migration remains separate work.
- Full PDF export of all damaged products deliberately reads all damaged records because the requested output contains all rows.
- Firestore bills listener result documents and may bill a reconnect as a new query. Read counts must be checked on a test Firebase project after installing this build, separating first baseline, warm restart, invoice navigation, and a second-device receipt.

## Offline inventory and remaining stages

“Verified” below means local save/read and fake-backend integration tests; device networking, deployed Firestore permissions and physical printing were not exercised. Warm caches are required to operate on existing customers/products/invoices. First download of unknown records still needs connectivity; missing products/uncached edits fail visibly before financial effects.

| Area / inspected implementation | Current status |
| --- | --- |
| Customer creation/opening, sale/return save/edit/delete, invoice-linked payments, manual payment edit/delete, both voucher directions | Verified locally durable and retry-safe through `CustomerOperationService`. Stock/cash reversals and moving a sale between customers tested. |
| Customer lists, balance/debt/credit reports and balance checks in `clients/ClientsPage.dart` | Read accepted Hive balances through `CustomerLocalViews`, including unsynced operations. No direct customer query for these balances. |
| Customer invoice/history pages, sales invoice list/details and shared footer | Hive reads/listeners; guarded background hydration. Footer data and rendered Arabic text match in tests. |
| Customer statement financial/invoice/return data and PDF generator | `CustomerStatementData` reads Hive and matches accepted ledger/footer; PDF generator uses these data and cached printer settings. Actual device PDF opening/sharing remains unverified. |
| Customer vouchers and voucher-number selection/PDF lookup | Stored in the journal and cached in `app_meta`; local lookup; background `CustomerVoucherRepository` hydration. Display numbers are local, not globally unique document IDs. |
| Quote creation/edit/delete/execution and list | Journaled and tested; execution is one durable sale/quote deletion. Stale quote snapshots cannot reintroduce an executed quote. |
| Cash addition/deduction | Journaled and tested once-only. Cash history uses a month-bounded cursor query and loads 50 rows at a time. |
| Supplier creation/opening, purchase create/edit/delete, supplier payments/vouchers | Verified locally durable and retry-safe through `SupplierOperationService`. Tests cover restart, failed upload/reconnect, lost acknowledgement, stale supplier snapshots, duplicate display numbers, payable, stock and cash. Voucher PDF lookup and supplier invoice navigation read local caches. |
| Purchase returns | Cached reads and guarded Firestore hydration were inspected. No active purchase-return creation/edit/delete UI was found, so write-side debt/stock/cash rules could not be verified or migrated. Do not claim this operation offline. |
| Customer/supplier rename, phone change, permanent deletion/restoration | Direct queries/updates/migration in `Services/party_rename_service.dart`, `clients/ClientsPage.dart`, `suppliers/`, `DeletedClientsPage.dart`. Phone writes can fail silently. Still pending offline migration. Local trash hiding is a different operation from permanent cloud deletion. |
| Product create/batch entry | `CreateProductPage.dart`, `Data/DataEntryScreen.dart`, `Data/Shared Lists.dart`, `QuickEntityCreationService`: mixed direct online writes and older local/queue paths; images use Storage. Complete product-stage durability and upload tests still pending. |
| Product editing, inline prices/quantity/damaged stock and deletion | Product list/export reads Hive; create/edit/delete queue writers maintain `updatedAt`; product history and damaged-product browsing load 50 rows per cursor page. Some inline price/damaged-stock actions and image/history-subcollection work still use direct Firebase calls, so this area is not fully offline. |
| Product/cash history | `ProductHistoryPage.dart`, `BoxChangesScreen.dart` cloud streams; newly pending local log entries are not displayed there yet. |
| Departments and valuation | Lists and valuation read Hive. Create/rename/delete and affected product renames save locally and queue timestamped cloud writes; startup uses a delta cursor after the baseline. Dedicated crash/retry tests for department changes are still pending. |
| Expenses and categories | Expense lists/reports read Hive; save/delete are local-first queued operations and deletion uses a timestamped tombstone. Category initialization/add/delete/list remains cloud-dependent. Expense writes do not debit cash automatically. |
| Payment-distribution metadata | `repositories/payment_breakdown_repository.dart`: local upsert/delete then a separate legacy queue operation and cloud refresh. Informational; no debt/stock/cash effect. Crash consistency and refresh stage pending. |
| Invoice special/star flag | `Services/invoice_special_service.dart`: local change then legacy queue. Works from cache but is not yet in the write-ahead journal. No financial effect; crash/retry stage pending. |
| Sales/profit, customer sales totals, best/product and monthly comparison reports | `reports/SalesReportPage.dart`, `ClientsReportPage.dart`, `BestProductsReportPage.dart`, `ProductReportPage.dart`, `MonthlyComparisonReportPage.dart`, `Services/FirebaseService.dart`: direct queries/streams. Tombstones are excluded, but unsynced sales are not guaranteed in these cloud reports. `SalesInvoicesFetchService` date/today invoice lists now read Hive only. |
| Supplier statements | `Services/supplier_statement_pdf_service.dart`: direct supplier/invoice/history queries; migration pending. Supplier permanent delete and rename also remain direct-cloud operations. |
| Printing/settings/sharing | Invoice thermal print and WhatsApp preparation now use the latest Hive invoice plus cached party/product metadata and cached printer settings, without waiting for Firebase. Printer settings save/stream still use direct cloud operations and offline settings upload is not durable. Printer hardware, image generation, sharing and Storage operations need separate device checks. |
| Login and credential change | `auth/LoginScreen.dart` has a local credential fallback after cloud lookup; `ChangeCredentialsPage.dart` requires cloud reads/updates. First login and account changes are not verified offline. |
| Older modules | `FirebaseService`, `EmployeeData`, employee attendance/borrowing/medicine, accommodation, expenses details, spare parts/requests, Materials/Pipes/Injection/Supervisors and legacy widgets contain direct cloud reads/writes. They were not found in active main feature navigation; runtime reachability and offline behavior remain unverified. |

Background network operations intentionally remain in repository hydration, local number seeding, `ClientInvoiceBalanceSyncService`, `RealtimeSyncService`, and upload adapters/legacy dispatch. They must not become dependencies of a customer local save. `InvoiceStockService.resolveCatalogVerified` and `SalesInvoiceActionsService.findClientSubInvoice` remain cloud compatibility helpers; current managed customer saves/edits do not call them.

See [FIREBASE_REFERENCES.md](FIREBASE_REFERENCES.md) for every current cloud reference location, including background and older/unreachable code. That generated map is a search aid; the table above reflects inspected behavior, not filenames alone.

### Firestore read audit (2026-09-29)

The Firebase chart showed 4.4K reads in the single 8:42-8:43 minute, not spread evenly across the hour. The confirmed trigger was `RealtimeSyncService`: every launch opened unfiltered listeners for nine root collections and two collection groups. Firestore bills the documents returned by each initial listener snapshot, so the startup cost grew with all historical invoices and ledger rows even when nothing changed.

Financial uploads now create an atomic receipt with a monotonically increasing sequence, affected paths and party IDs. Each device stores its imported sequence in Hive and listens only for larger values. It reads the changed root/history documents and the one matching party event, processes receipts serially, and advances the cursor only after Hive is durable. A crash therefore replays the receipt instead of skipping it. Post-upload refresh reads the operation's event; it falls back to the full affected-party event set only when cloud and local balances disagree, preserving compatibility with older writers.

The first run with this version still performs one full compatibility baseline because old receipts have no sequence. Clearing app data or reinstalling removes the cursor and repeats that baseline. Later normal launches do not reopen the full financial collections. One unfiltered product listener remains because active product flows still perform direct Firestore writes. Startup background sync also reads counters, expenses, cash, departments and payment breakdowns; product/report pages contain on-demand full queries. Those are confirmed remaining read sources, although their exact contribution to the production chart was not measured without Query Insights or production access.

## Verification and limits

- **Static analysis:** `flutter analyze --no-pub` completed with **0 errors** and **1,281 warning/info findings**. Lint is not clean; existing unused/dead elements, deprecated APIs and style findings remain.
- **Final test run:** `flutter test --no-pub` passed **122/122 tests** on 2026-09-29.
- Run `flutter test --no-pub` with the installed/cached Flutter SDK. Targeted suites: `test/customer_balance_regression_test.dart`, `test/customer_offline_operations_test.dart`, `test/supplier_offline_operations_test.dart`.
- Added tests exercise real Hive persistence/reopening, partial `preparing` saves, repeat attempts, classified/per-item retry, quota retry suppression/migration, retained attempt history, failures/reconnect, lost acknowledgements, Firestore timestamp conversion, stale customer/invoice/product/cash/history snapshots, receipt imports and read-only inspection, conflict/legacy rejection, related versus independent queue dependencies, Android backup exclusion, edit/delete/return/payment/opening/voucher effects, quote execution, historical review, shared footer data/rendering, and both active-upload exit choices.
- Tests use the production financial transaction algorithm via an in-memory atomic backend. They are **not** a Firestore emulator/security-rules test or an OS power-loss durability proof.
- Firestore rules/emulator config are not supplied here. Before release, verify transactional read/write access to `financial_operation_receipts/_change_feed_head`, receipt creation, the ordered `sequence` query, `clients/*/financialOperations`, and existing financial paths using a test Firebase project/emulator. Permission failures retain local operations and appear in the dashboard. No rules/configuration were changed.
- Test two upgraded devices, forced network changes, concurrent edits and app termination on the actual target device. Older writers do not publish operation events or versions; mixed-version deployments cannot guarantee cross-device financial consistency. Collection-group listener access and timestamp ordering were not verified against deployed indexes/rules.
- Historical correctness, opening/carry completeness, whether payment methods represent physical cash, globally unique legal voucher/invoice numbers, and credit/overpayment/negative-stock policy cannot be settled from this code. Existing sign/cash rules were preserved; owner review is required before changing them.

## File map for future work

Core: `Services/customer_operation_service.dart`, `customer_balance_store.dart`, `supplier_operation_service.dart`, `supplier_balance_store.dart`, `customer_local_views.dart`, `customer_statement_data.dart`, `customer_balance_review.dart`; `sync/local_operation_journal.dart`, `financial_cloud_store.dart`, `cloud_snapshot_guard.dart`, `batch_sync_engine.dart`, `realtime_sync_service.dart`, `sync_queue_manager.dart`, `sync_operation_diagnostics.dart`, `sync_operation_inspector.dart`.

Presentation/actions: `Screeens/DecreaseProductPage.dart`, `Invoices/All_invoices.dart`, `QuoteListPage.dart`, `ProductListPage.dart`; `clients/ClientsPage.dart`, `ClientInvoicesPage.dart`, `invoice_edit_sheet.dart`; `box/MainBoxScreen.dart`; `Widgets/invoice_display_widgets.dart`; save/update/return/quote/quick-create/action/running-balance/statement/fetch services. Shared footer model: `Services/invoice_footer_data.dart`.

Persistence: client/invoice/product/history/box/quote repositories, new `customer_voucher_repository.dart`, `data_sync_service.dart`, `local_db/hive_init.dart`, client/history/quote factories, `main.dart`. Sync UI: dashboard, status badge and new balance-review screen. Cloud reports touched only to exclude invoice tombstones. Existing adapter schemas and app/Firebase configuration remain intact.

Supplier-stage additions: `Services/supplier_operation_service.dart`, `supplier_balance_store.dart`, `supplier_invoice_balance_sync_service.dart`, `supplier_payment_service.dart`, `buying_invoice_update_service.dart`; `repositories/supplier_repository.dart`, `supplier_voucher_repository.dart`, `invoice_repository.dart`, `balance_history_repository.dart`; purchase/supplier list and detail screens; `test/supplier_offline_operations_test.dart`.

Startup regression coverage in `test/hive_startup_test.dart` reopens all boxes from a disposable directory, verifies pending uploads and accepted balances survive restart, and checks an already-open box with the wrong generic type is reopened without deleting its data. `main.dart` identifies the failing startup phase; `hive_init.dart` identifies the box when opening fails. The supplied device log showed an approximately 22-second hot restart and MIUI ANR messages, without a Dart exception. The device-specific bottleneck remains unconfirmed. Startup now logs Hive and recovery stage durations, restores/list-displays accepted balances with one metadata pass, and launches background hydration after the first local frame. A 300-customer disposable-Hive regression covers the bulk calculation.

## Exact application/test files changed

Paths are relative to the project root. Documentation also adds this audit and `FIREBASE_REFERENCES.md`, and updates `PROJECT_CONTEXT.md`. The queue adapter adds backward-compatible optional fields, and the Android manifest disables OS backup restoration. Firebase configuration and dependency manifests are unchanged.

- `lib/Screeens/DecreaseProductPage.dart`
- `lib/Screeens/Invoices/All_invoices.dart`
- `lib/Screeens/ProductListPage.dart`
- `lib/Screeens/QuoteListPage.dart`
- `lib/Screeens/AddProductPage.dart`
- `lib/Screeens/home_page.dart`
- `lib/Buing Invoices/BuyingInvoiceListPage.dart`
- `lib/Services/FirebaseService.dart`
- `lib/Services/client_invoice_balance_sync_service.dart`
- `lib/Services/client_invoice_running_balance_service.dart`
- `lib/Services/client_statement_pdf_service.dart`
- `lib/Services/customer_balance_review.dart`
- `lib/Services/customer_balance_store.dart`
- `lib/Services/customer_local_views.dart`
- `lib/Services/customer_operation_service.dart`
- `lib/Services/customer_statement_data.dart`
- `lib/Services/invoice_footer_data.dart`
- `lib/Services/invoice_print_service.dart`
- `lib/Services/invoice_print_ui.dart`
- `lib/Services/invoice_stock_service.dart`
- `lib/Services/quick_entity_creation_service.dart`
- `lib/Services/quote_execution_service.dart`
- `lib/Services/return_invoice_save_service.dart`
- `lib/Services/sales_invoice_actions_service.dart`
- `lib/Services/sales_invoice_update_service.dart`
- `lib/Services/sales_invoices_fetch_service.dart`
- `lib/Services/buying_invoice_update_service.dart`
- `lib/Services/supplier_balance_store.dart`
- `lib/Services/supplier_invoice_balance_sync_service.dart`
- `lib/Services/supplier_operation_service.dart`
- `lib/Services/supplier_payment_service.dart`
- `lib/Widgets/invoice_display_widgets.dart`
- `lib/box/MainBoxScreen.dart`
- `lib/clients/ClientInvoicesPage.dart`
- `lib/clients/ClientsPage.dart`
- `lib/clients/invoice_edit_sheet.dart`
- `lib/local_db/hive_init.dart`
- `lib/local_db/hive_safe_value.dart`
- `lib/local_db/models/balance_history_local.dart`
- `lib/local_db/models/client_local.dart`
- `lib/local_db/models/quote_local.dart`
- `lib/main.dart`
- `lib/reports/BestProductsReportPage.dart`
- `lib/reports/ClientsReportPage.dart`
- `lib/reports/MonthlyComparisonReportPage.dart`
- `lib/reports/ProductReportPage.dart`
- `lib/reports/SalesReportPage.dart`
- `lib/repositories/balance_history_repository.dart`
- `lib/repositories/box_repository.dart`
- `lib/repositories/client_repository.dart`
- `lib/repositories/customer_voucher_repository.dart`
- `lib/repositories/data_sync_service.dart`
- `lib/repositories/invoice_repository.dart`
- `lib/repositories/product_repository.dart`
- `lib/repositories/quote_repository.dart`
- `lib/repositories/supplier_repository.dart`
- `lib/repositories/supplier_voucher_repository.dart`
- `lib/suppliers/DeletedSuppliersPage.dart`
- `lib/suppliers/SupplierInvoicesPage.dart`
- `lib/suppliers/SuppliersPage.dart`
- `lib/sync/batch_sync_engine.dart`
- `lib/sync/cloud_snapshot_guard.dart`
- `lib/sync/connectivity_service.dart`
- `lib/sync/financial_cloud_store.dart`
- `lib/sync/local_operation_journal.dart`
- `lib/sync/realtime_sync_service.dart`
- `lib/sync/sync_operation_diagnostics.dart`
- `lib/sync/sync_operation_inspector.dart`
- `lib/sync/sync_queue_manager.dart`
- `lib/sync/ui/customer_balance_review_screen.dart`
- `lib/sync/ui/sync_dashboard_screen.dart`
- `lib/sync/ui/sync_exit_dialog.dart`
- `lib/sync/ui/sync_status_badge.dart`
- `test/customer_balance_regression_test.dart`
- `test/customer_offline_operations_test.dart`
- `test/quick_entity_creation_service_test.dart`
- `test/sync_infrastructure_test.dart`
- `test/hive_startup_test.dart`
- `test/supplier_offline_operations_test.dart`
- `test/sync_operation_inspector_test.dart`
- `test/sync_exit_warning_test.dart`
- `lib/local_db/models/sync_queue_item.dart`
- `lib/local_db/models/sync_queue_item.g.dart`
- `android/app/src/main/AndroidManifest.xml`
