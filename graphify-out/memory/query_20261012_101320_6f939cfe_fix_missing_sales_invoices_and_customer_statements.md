---
type: "query"
date: "2026-10-12T10:13:20.372013+00:00"
question: "fix missing sales invoices and customer statements after another device successfully uploads"
contributor: "graphify"
outcome: "useful"
source_nodes: ["RealtimeSyncService", "ConnectivityService", "SyncDashboardScreen", "CloudSnapshotGuard"]
---

# Q: fix missing sales invoices and customer statements after another device successfully uploads

## Answer

Expanded via graph vocabulary: receipt sequence client statement sync. Implemented verification and recovery in RealtimeSyncService: server-only document, collection, and collection-group reads reject cache and uncommitted metadata; receipt imports require all referenced versions and financial events, preserve sequence continuity, and flush typed Hive boxes before checkpointing. One verified baseline after upgrading bypasses old timestamp checkpoints and restores missed roots/history/events; a persisted financialBaselineVersion keeps ordinary launches incremental. Dashboard Sync now requests a full repair via ConnectivityService.forceSync(repairDownloads:true). Pending local paths have durable deferredFinancialPath reminders, retried after uploads and restart without blocking unrelated receipts. Listener ignores cached snapshots, processes metadata-only server confirmations, and schedules restart on importer failures even with an empty queue. Opening balances and immutable event deduplication are preserved. Added 17 downloader tests against injected Firestore interfaces and real disposable Hive boxes. Full flutter test suite passes 169 tests; focused static analysis has no issues; formatting and whitespace checks pass. No live Firebase data read or changed. Physical multi-device verification remains for the user. Debug APK built successfully at build/app/outputs/flutter-apk/app-debug.apk (117980823 bytes). Device testing remains for the user. Production changes limited to realtime_sync_service.dart, connectivity_service.dart, sync_dashboard_screen.dart; documentation updated in docs/FIRESTORE_READ_OPTIMIZATION.md.

## Outcome

- Signal: useful

## Source Nodes

- RealtimeSyncService
- ConnectivityService
- SyncDashboardScreen
- CloudSnapshotGuard