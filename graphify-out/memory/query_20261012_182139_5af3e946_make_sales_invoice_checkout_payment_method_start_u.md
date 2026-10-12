---
type: "query"
date: "2026-10-12T18:21:39.328353+00:00"
question: "Make sales invoice checkout payment method start unselected and prevent saving until a method is selected."
contributor: "graphify"
outcome: "useful"
source_nodes: ["invoice_checkout_sheet.dart", "DecreaseProductPage"]
---

# Q: Make sales invoice checkout payment method start unselected and prevent saving until a method is selected.

## Answer

Expanded graph vocabulary: sales invoice checkout payment save. Verified current invoice_checkout_sheet.dart hardcoded نقداً for new checkouts; its exact-amount validation accepted an empty payment method. Added required-method validation returning يرجى اختيار طريقة الدفع for empty/whitespace strings. New sales checkout initializes paymentMethod to empty and disables Continue until a method is selected. The existing inline validation displays the selection prompt. Editing retains the recorded method; quote and return defaults remain as before. DecreaseProductPage passes no default cash method for new checkout and its private save method now requires an explicit paymentMethod argument; it reuses the required-method validator before local financial writes. Regression tests first reproduced both cash preselection and blank-method acceptance. All7 checkout tests now pass, covering no initial selection, disabled Continue even after entering payment, cash selection and successful overpayment, deferred/card amount validation, editing existing deferred selection, and payment breakdown. Static analysis found no errors;4 unused-code warnings and45 style/deprecation infos are preexisting in the sales page/shared checkout. Did not build an APK, following the user preference.

## Outcome

- Signal: useful

## Source Nodes

- invoice_checkout_sheet.dart
- DecreaseProductPage