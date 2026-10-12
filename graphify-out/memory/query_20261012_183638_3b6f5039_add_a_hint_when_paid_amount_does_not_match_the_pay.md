---
type: "query"
date: "2026-10-12T18:36:38.210348+00:00"
question: "Add a hint when paid amount does not match the payment distribution total in checkout and PaymentsReportPage."
contributor: "graphify"
outcome: "useful"
source_nodes: ["PaymentsReportPage", "PaymentBreakdownLocal", "PaymentBreakdownRepository", "invoice_checkout_sheet.dart"]
---

# Q: Add a hint when paid amount does not match the payment distribution total in checkout and PaymentsReportPage.

## Answer

Expanded graph vocabulary: payment breakdown checkout report paid. Added shared PaymentBreakdownMismatchHint displaying paid amount, distribution total and absolute difference whenever rounded currency cents differ. It is informational and never blocks saving. Checkout shows the hint below its distribution total, updates on payment/channel input, clears when totals match or Apply as paid is used, and suppresses it for invalid input. PaymentsReportPage resolves the linked canonical cached sales or return invoice paidAmount, shows the same hint per distribution card and while editing channels, and watches invoice and payment caches for live updates. Legacy unlinked records or missing linked invoice data are not falsely treated as paid0. Tests exposed a preexisting TextEditingController disposal race when closing a focused report edit dialog; now the dialog uses DialogRoute and waits for completed overlay removal before disposing controllers. All10 targeted checkout/report tests pass, including live invoice/distribution changes, edit hint updates and safe dialog cancellation, delayed return invoice arrival, unlinked legacy records, and floating-point currency equality. Targeted static analysis has no errors or warnings,15 preexisting style/deprecation infos. No APK build performed per user preference.

## Outcome

- Signal: useful

## Source Nodes

- PaymentsReportPage
- PaymentBreakdownLocal
- PaymentBreakdownRepository
- invoice_checkout_sheet.dart