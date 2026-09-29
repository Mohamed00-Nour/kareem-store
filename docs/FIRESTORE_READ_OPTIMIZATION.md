# Cloud Firestore read audit and optimization

Audited 2026-09-29 against the current application. No production Firebase data, rules, or indexes were changed. The Firebase Console screenshots showed large read spikes, but the console does not identify which client query caused them. The causes below are confirmed from source; numerical savings are static estimates until the repeatable device procedure at the end is run against a separate test project.

## Confirmed causes, ranked by likely impact

1. **Opening a customer repeatedly downloaded several complete histories.** `ClientInvoiceBalanceSyncService.syncForClient` previously read the client, all root sales and returns, copied customer invoices, the full customer `balanceHistory`, and the full `financialOperations` subcollection. `ClientInvoicesPage._backgroundSyncInvoices` then repeated history and invoice synchronization. Cost grew with all historical invoices and events, not with changes since the last visit.
2. **Supplier screens repeated full collection and per-supplier reads.** The supplier balance service and supplier list/detail screens previously loaded purchase invoices, returns, histories, and financial events again as pages opened. List flows could issue queries inside a supplier loop.
3. **Methods named `deltaSync` were full downloads.** Sales, returns, purchases, and quotes reopened complete collections. Purchases read both the canonical root collection and the legacy collection-group copies. Repeated navigation therefore paid for the same documents again.
4. **First-install party hydration had an N+1 query pattern.** After reading all clients or suppliers, hydration queried each party's `financialOperations` subcollection. The bootstrap also read all balance histories. A fresh installation with thousands of historical documents can therefore plausibly produce a single-minute spike in the thousands. This is a code-supported explanation for the observed spike, not proof that it was the only source on the measured device.
5. **Supplier statement generation read complete cloud datasets.** Each report opened the supplier document, history, invoices, and returns from Firestore even when Hive already held the synchronized data.
6. **Equivalent listeners could be recreated by widgets.** Printer settings and expense categories could attach overlapping listeners as widgets rebuilt or multiple dialogs consumed the same stream.
7. **Some editing screens refetched complete lookup collections.** Product editing loaded every department. Stock/purchase editing also repeated product reads even when the product ID and Hive record were known.
8. **An upload advanced download cursors from device time.** `BatchSyncEngine._updateLastSyncMeta` wrote `DateTime.now()` into client, supplier, or product sync checkpoints. This did not cause the spike, but it could skip remote records when clocks differed. It has been removed because a read optimization is unsafe if it can hide another device's update.

## Resulting synchronization model

Ordinary screens read Hive. Firestore is used by the synchronization layer for initial hydration, incremental catch-up, the financial receipt stream, and a small set of bounded or explicitly complete user actions.

- A device without `financialChangeSequence` first reads the receipt-feed head, hydrates the complete compatibility dataset, imports all historical `financialOperations` with one collection-group query, imports legacy `balanceHistory` with one collection-group query, persists the baseline, and then listens for receipts after the saved sequence. Clearing app data repeats this required bootstrap.
- A warm device reads only non-receipt collections that still need catch-up, then attaches one financial receipt listener and one filtered product listener. New financial operations name the exact root documents and party events to fetch.
- Sales, returns, purchases, quotes, clients, suppliers, products, expenses, departments, and payment breakdowns use `updatedAt >= checkpoint` (expenses use their legacy `time` field). Replaying the equal timestamp boundary avoids losing concurrent records with identical timestamps. Version and operation guards make the overlap idempotent.
- A checkpoint advances only to the newest timestamp in documents returned and persisted by that pass. Empty results retain the previous checkpoint. Uploads never advance download checkpoints.
- `CloudRefreshGate` shares an in-flight equivalent query and suppresses the same successful screen refresh for one minute. Failures remain immediately retryable.
- Financial receipt sequence advancement occurs only after every affected Hive merge and party event is durable. A crash before that point replays the same receipt safely.

The timestamp deltas complement rather than replace the financial receipt protocol. The receipt marker, transaction reads, conflict checks, local journal, snapshot guards, post-upload refresh, and balance ledger remain intact.

## Active read inventory

| Trigger | Query and bound | Current behavior |
| --- | --- | --- |
| Empty-cache compatibility bootstrap | Full `products`, `clients`, `suppliers`, root sales/returns/purchases, legacy purchase copies, quotes, vouchers, expenses, departments, payment breakdowns; `box/mainBox`; full `financialOperations` and `balanceHistory` collection groups | Complete by design so offline views and historical balances are not misleading. One query per collection/group, rather than one event query per party. |
| Warm start or sync dashboard refresh | Expense, department, and payment-breakdown deltas; `box/mainBox`; three `orderBy(invoiceNumber desc).limit(1)` counter seeds | Bounded by changed timestamp plus one cash document and at most three counter documents. Concurrent startup/manual requests share the same `DataSyncService` future. |
| Financial realtime catch-up | `financial_operation_receipts where sequence > cursor orderBy sequence` | One owned listener. Each new receipt causes point reads only for its listed cached paths and affected party event documents. |
| Product realtime catch-up | `products where updatedAt >= cursor` | One owned listener. Invoice stock effects also arrive in financial receipts. |
| Customer and supplier pages | Hive view plus a gated client/supplier profile delta | No invoice, ledger, balance-history, or event scan on page open. Reopening within one minute does not issue the same delta again. |
| Sales/purchase/return/quote lists and details | Hive | No view-time Firestore read. Print and WhatsApp invoice preparation use Hive and cached printer settings. |
| Supplier statement | Hive supplier, purchases, returns, and balance history | No Firestore read while generating the statement. Correctness depends on the completed bootstrap/receipt cursor shown by synchronization state. |
| Financial upload | Firestore transaction reads receipt marker, feed head, and each affected root before atomic writes | Necessary for idempotency, conflict detection, increments, and sequence allocation. Firestore may rerun the transaction callback after contention. |
| Successful financial upload | Point read for each affected root, party document, and this operation's party event | Retained to recover a valid remote change delivered while the local path was protected. A complete party-event scan occurs only when the local and cloud balances still disagree, as compatibility support for older writers. |
| Printer settings | `settings/printer_settings` | One ref-counted shared listener; local cached settings render first. |
| Expense categories | Complete, normally small `expense_categories` listener; `limit(1)` only when ensuring defaults | One shared listener while at least one consumer exists; detached after the last consumer leaves. |
| Product and cash history screens | Ordered pages of 50 with `startAfterDocument` | Pagination bounds each request and user-visible memory. It does not reduce total reads if the user deliberately loads every page. |
| Damaged-product list | Ordered pages of 50 | Same pagination tradeoff. Export and moving/restoring a product may intentionally read all required rows/history. |
| Party rename | Known party document, duplicate-name query limited to 2, then all invoices matching the old party name | Explicit, rare user action. All matching documents must be updated for compatibility, so pagination would change peak size but not total reads. Renamed documents now receive server `updatedAt` values for device catch-up. |
| Product resolution fallback | Known ID point read, then exact-name query limited to 1 only when Hive lacks the mapping | Bounded compatibility fallback. Normal invoice creation resolves products from Hive. |
| Login | Known/filtered credential record | User-triggered and outside business-data hydration. |

The old `FirebaseService`, employee, material, pipe, injection, supervisor, and `ExpensesDetails` listeners remain in source but are not reachable from the current `GNavPage`/`HomePage` navigation. They must be audited before any of those modules is restored to navigation.

## Implemented changes

- Customer and supplier invoice-balance synchronization now ensures the single shared realtime service is running instead of querying histories on every page open.
- Customer/supplier screen refreshes no longer loop over parties or duplicate invoice and history syncs.
- Invoice, return, purchase, quote, client, supplier, product, expense, department, and payment-breakdown catch-up uses persisted incremental checkpoints. The canonical purchase query and legacy copy query remain separate because both schemas exist in production data.
- Full event hydration changed from one query per party to one `collectionGroup(financialOperations)` query. This removes query overhead and duplicate downloads; the first install still reads each historical event document once because the local ledger requires it.
- Supplier statements, department selection, product edits, invoice pages, reports, and print preparation use existing Hive data.
- Printer settings and expense-category consumers share owned listeners with attach/detach lifecycle management.
- Product/cash history and damaged-product views use cursor pagination.
- Active writers used by delta synchronization now publish `updatedAt`, including rename cascades and product quantity updates. Financial writes also remain visible through receipts.
- Upload-side device-time checkpoint mutation was removed.
- Debug builds emit process-local `[FirestoreReads]` diagnostics. Metrics keep query execution count, documents delivered, cached source, listener attach/snapshot/detach and active counts, listener document changes, errors, transaction attempts, and transaction document reads. These counters are not Firebase billing totals and are never uploaded.

## Static before/after estimates

These formulas describe source behavior; they are not measured billing data.

| Scenario | Before | After |
| --- | --- | --- |
| Reopen one customer | Root sales + root returns + copied invoices + customer history (sometimes repeated) + all customer financial events + party doc | Hive rendering; at most one gated changed-client profile query. Financial documents arrive through receipts. |
| Open supplier list/details | Repeated purchase/history/return queries, including queries inside supplier loops | Hive rendering; at most one gated changed-supplier profile query. |
| Warm invoice sync | Every sales/return document and both complete purchase locations | Documents at or after the saved timestamp boundary; identical calls coalesce. |
| First install with `N` parties | Two root party queries plus up to `N` financial-event subcollection queries, alongside history listeners | Two root party queries plus one financial-event collection-group query and one balance-history collection-group query. Event/history document count is still proportional to required history. |
| Generate supplier statement | Party + all statement history/invoices/returns | Zero Firestore reads during generation. |
| Rebuild printer/category widgets | Could attach another upstream listener | One upstream listener shared by all current consumers. |

No defensible exact before/after read count is available from source alone. A Firebase Console total includes other devices, console browsing, cached/server behavior, reconnects, and transaction retries. Use the procedure below before claiming a measured percentage reduction.

## Checkpoints, compatibility, and indexes

- Existing Hive records and Firestore paths are unchanged. No balances are repaired or reset. Historical documents lacking `updatedAt` are included by the one-time full bootstrap. Modern financial changes are additionally authoritative through the sequence receipt feed.
- A device upgraded with an older cursor keeps its cache. The former upload-side device-time cursor is no longer advanced. If a known older installation has a suspicious future cursor, inspect it and perform a controlled test-project rebaseline; do not clear live data or balances blindly.
- Deletions used by delta flows must remain tombstones with `updatedAt`. A hard delete cannot be discovered by a timestamp query. Current queue handlers use tombstones where incremental removal is required.
- Default single-field indexes must remain enabled for `updatedAt`, `time`, `sequence`, and `invoiceNumber`. The legacy collection-group query on `buying invoices.updatedAt` may prompt for a collection-group-scope index if that field was exempted or the project does not already have it. Follow the Firestore error's generated index link in a non-production rollout first. No index was deployed by this change.
- All app versions sharing a project should be upgraded. Older writers that do not publish receipts/timestamps are supported by bootstrap and the post-upload mismatch fallback, but cannot provide the same efficient realtime guarantee.

## Verification

Automated checks added in `test/firestore_read_optimization_test.dart` cover:

- coalescing concurrent identical refreshes;
- suppressing immediate navigation repeats and allowing the next interval;
- retrying a failed refresh without waiting for cooldown;
- listener lifecycle and document-change diagnostics;
- transaction attempt/read visibility;
- advancing checkpoints only from returned timestamps and preserving a cursor on an empty delta.

The existing customer/supplier financial tests remain the authority for offline creation, restart recovery, repeated upload attempts, lost acknowledgement, stale snapshots, invoice edits/deletes, returns, payments, stock, cash, and concurrent remote effects.

Results on 2026-09-29:

- `flutter test --no-pub`: **137 passed**.
- Focused read/financial/offline run: **108 passed**.
- Analysis of the 36 changed/new Dart files found **no compile errors**. It still reports the repository's existing warning and style backlog.
- No emulator or real test-project usage measurement was performed, so billed read reduction remains unverified until the manual procedure below is run.

## Remaining reads and risks

- A fresh installation must download complete offline business data and legacy histories. Pagination would only split that required total across requests.
- The financial transaction reads and targeted receipt/post-upload reads are correctness costs. Removing them would risk duplicate money/stock effects or missed concurrent changes.
- The compatibility balance-mismatch fallback can still read every event for one affected party. Debug diagnostics label it separately. Repeated fallback activity means an older writer or ledger inconsistency needs investigation.
- The cash box is one point read on startup/manual synchronization because it does not yet have its own non-financial sequence.
- Expense categories are cloud-backed and are not fully offline-managed. The expense records themselves render and save locally first.
- Party rename and some damaged-product maintenance actions still require direct Firestore reads/writes and therefore are not fully offline.
- Complete exports intentionally read the complete requested result when Hive does not contain that maintenance dataset.
- Dormant legacy modules contain unbounded listeners and queries. They are not counted as active, and must not be re-enabled without migration to the shared Hive/sync model.
- Actual two-device receipt delivery, reconnect behavior, and Firebase billed reads were not measured against production or a real client project during this audit.

## Repeatable manual measurement

1. Use a separate Firebase test project or emulator with a fixed dataset. Record counts for products, parties, invoices, histories, events, and receipts.
2. Disconnect all other app devices. Close Firebase Console data viewers during the timed run because console browsing can itself read documents.
3. Enable a debug build and capture `[FirestoreReads]` lines. Reset the local diagnostic process by restarting the app between scenarios. These logs show client-observed requests/documents, not exact billing.
4. Measure the same fixed windows for: empty-cache start; warm start; five idle minutes; ten tab-navigation cycles; five repeated opens of one customer, invoice, report, and print preview; create/edit/delete one invoice; offline saves followed by restart/reconnect; and a burst of connectivity events.
5. For two-device checks, finish Device B's bootstrap first. Then create a sale on Device A and verify Device B imports one receipt and its named documents. Repeat with a Device B pending local sale while Device A creates a payment.
6. Record debug query executions, delivered documents, listener changes, transaction retries, dataset size, elapsed window, and Firebase Console reads separately. Do not equate cached snapshots with server reads.
7. Compare identical seeded datasets and actions before/after. A warm idle app should show no repeating collection scans; repeated page opens should render from Hive; reconnect bursts should share synchronization work. Investigate any recurring `legacy balance compatibility fallback` line.
