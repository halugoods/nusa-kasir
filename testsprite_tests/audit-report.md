# 📋 Audit Report — NUSA Kasir
**Date:** 2026-07-12
**Project Type:** Flutter (Dart) — POS App for Indonesian Grocery Stores
**Files Analyzed:** 80 Dart files
**DB Schema:** Drift v4, 18 tables
**Router:** GoRouter, 20 routes
**State:** Riverpod StateNotifier

---

## 1️⃣ Code Quality Summary

| Category | Issues | Risk |
|---|---|---|
| Error Handling | 14 `catch (_) {}` — swallowed exceptions | 🔴 Critical |
| Data Consistency | 3 places missing DB transactions | 🔴 Critical |
| Background Tasks | Supabase re-init in worker, no retry | 🟡 Medium |
| JSON Parsing | Silent failures → data loss | 🟡 Medium |
| Async Safety | 1 missing mounted check | 🟢 Low |
| Redundant Code | Duplicate DB writes in product form | 🟢 Low |

---

## 2️⃣ Architecture & Structure

```
nusa_kasir/lib/
├── main.dart                    # Entry — Supabase init, Workmanager, DB
├── app.dart                     # GoRouter (20 routes), Riverpod providers
├── core/
│   ├── activation/              # License key system (RSA verify)
│   ├── auth/                    # Employee session (8h expire)
│   ├── config/                  # NusaConfig (colors, categories)
│   ├── services/                # Supabase, Google Auth, Backup, Update, Notif
│   └── theme/                   # Light/dark themes
├── data/
│   ├── database/                # Drift ORM (18 tables, schema v4)
│   └── repositories/            # 10+ repos wrapping Drift queries
├── features/                    # Screens per feature (14 screens)
│   ├── dashboard/               # Main menu + stats + Buka Kasir CTA
│   ├── pos/                     # Product grid + scanner + cart
│   ├── checkout/                # Payment, promo, customer, receipt
│   ├── online_orders/           # Order management + store setup
│   ├── products/                # CRUD + image + barcode
│   ├── transactions/            # History + filters
│   ├── customers/               # Loyalty tiers
│   ├── promo/                   # Discount codes
│   ├── reports/                 # Sales reports
│   ├── finance/                 # Expenses, payroll, liquidity
│   ├── employees/               # Pin-based auth
│   ├── attendance/              # Check-in/out
│   ├── suppliers/               # Supplier contacts
│   ├── branches/                # Multi-branch
│   ├── settings/                # Theme, printer, backup, toko online
│   └── spreadsheet/             # GAS integration
└── shared/widgets/              # Reusable: NusaCard, NusaInput, Toast, etc.
```

**Data Flow:**
```
Supabase Cloud ←→ Activation/Online Orders
       ↓
SQLite (Drift) ← Repositories ← Riverpod ← UI (ConsumerWidget)
       ↓
Workmanager (background: stock check + online poll)
```

---

## 3️⃣ Feature Inventory

| # | Feature | Files | Key Files |
|---|---|---|---|
| 1 | Activation/License | 5 | activation_key.dart, activation_screen.dart |
| 2 | Dashboard + Menu | 1 | dashboard_screen.dart |
| 3 | POS (Product Grid + Scanner) | 2 | pos_screen.dart, cart.dart |
| 4 | Checkout (Payment + Receipt) | 2 | checkout_screen.dart, receipt_sheet.dart |
| 5 | Products CRUD | 2 | products_screen.dart, product_form_screen.dart |
| 6 | Stock Management | 1 | stock_screen.dart |
| 7 | Transactions History | 1 | transactions_screen.dart |
| 8 | Customer Loyalty | 1 | customers_screen.dart |
| 9 | Promo/Discount Codes | 1 | promo_screen.dart |
| 10 | Reports | 1 | reports_screen.dart |
| 11 | Finance (Expenses/Payroll) | 1 | finance_screen.dart |
| 12 | Employees + PIN Auth | 1 | employees_screen.dart |
| 13 | Attendance (Check-in/out) | 1 | attendance_screen.dart |
| 14 | Suppliers | 1 | suppliers_screen.dart |
| 15 | Branches | 1 | branch_screen.dart |
| 16 | Settings (Theme/Printer/Backup) | 3 | settings_screen.dart, backup_sheet.dart, printer_settings_sheet.dart |
| 17 | Online Orders + Store Setup | 2 | online_orders_screen.dart, online_store_setup_screen.dart |
| 18 | Spreadsheet (GAS) | 1 | spreadsheet_screen.dart |
| 19 | Onboarding | 1 | onboarding_screen.dart |

---

## 5️⃣ Key Findings & Risks

### 🔴 Critical — Must Fix

**[CRIT-1] Swallowed exceptions everywhere** — 14 instances of `catch (_) {}`
- `stok_alert_worker.dart:33` — Entire background task dispatcher silently fails. If both stock check and online poll crash, owner never knows.
- `stok_alert_worker.dart:171` — Top-level `_checkOnlineOrders` catches all errors. If Supabase is down or token expired, new orders silently lost.
- `activation_repository.dart:42,66,87,108` — All cloud backup operations swallow errors with `catch (_) { return false; }`. Owner can't tell if backup failed from permission issue vs network.
- `online_orders_screen.dart:204,213` — Transaction recording and loyalty update silently fail during `_completeOrder()` → stock deducted but transaction not recorded.
- **Fix:** Log errors at minimum. Show user-visible feedback where appropriate. Use `catch (e, st)` and at least `debugPrint`.

**[CRIT-2] No database transactions for multi-step writes**
- `online_orders_screen.dart:168-222` `_completeOrder()`: stock deduction (line 180), transaction recording (line 193), loyalty points (line 211), status update (line 218) — all separate writes. If app crashes or DB fails after stock deduction but before transaction recorded → inventory lost, no trace of sale.
- `product_form_screen.dart:136-155`: Update product calls `repo.updateProduct()` then 3 separate `db.update()` calls (sku, stock, barcode/image/isOnline). If any fails, product in inconsistent state.
- **Fix:** Wrap in `await db.transaction(() async { ... })`.

**[CRIT-3] JSON parse failure silently drops all items**
- `online_orders_screen.dart:170-174`: `jsonDecode(order.items)` catches error and sets `items = []`. If items JSON is corrupted (e.g. escaping issue from Supabase), `_completeOrder` runs but deducts 0 stock and records a 0-item transaction.
- **Fix:** Return early if items can't be parsed, show error.

### 🟡 Medium — Should Fix

**[MED-1] Supabase re-initialized in background worker**
- `stok_alert_worker.dart:104-108`: `Supabase.initialize()` called inside `_checkOnlineOrders`. Supabase was already initialized in `main.dart`. The 2nd initialize may succeed or fail silently — behavior is non-deterministic across platforms.
- **Fix:** Either check `Supabase.instance.isInitialized` or pass the client reference into the worker.

**[MED-2] Background task has no retry logic**
- Both `registerStokCheck()` and `registerOnlineCheck()` use `ExistingPeriodicWorkPolicy.replace`. If a task fails (network error, DB locked), it waits until next interval (30 min for stock, 2 min for online). No exponential backoff or retry.
- **Fix:** Use `ExistingWorkPolicy.append` + track attempt count, or use `RetryPolicy`.

**[MED-3] `_checkOnlineOrders` silently skips on empty Supabase URL**
- `stok_alert_worker.dart:104-108`: If `NusaConfig.supabaseUrl` is empty, the function silently returns. No log, no indication that online order polling is broken. Since this runs in background, owner will never notice orders aren't coming.
- **Fix:** Log a warning or skip registration entirely if config is missing.

**[MED-4] Error in `_filter()` after tab switch could leave stale state**
- `online_orders_screen.dart:58-65`: `_filter()` calls async `repo.getAll()` but doesn't check `mounted` before `setState`. If user rapidly switches tabs and widget disposes, crashes.
- **Fix:** Add `if (!mounted) return;` before setState, or cancel previous filter operation with a token.

**[MED-5] Duplicate DB writes in product form**
- `product_form_screen.dart:136-155`: Editing a product results in 3-4 separate DB writes in a row. Each one opens a new query. Should be batched or use a single `ProductsCompanion`.
- **Fix:** Construct a single `ProductsCompanion` with all changed fields and write once.

### 🟢 Low — Nice to Have

**[LOW-1] `ignore_for_file: use_build_context_synchronously`**
- `dashboard_screen.dart:20`: Blanket lint ignore instead of targeted `// ignore:` on specific lines. Hides real async context bugs.
- **Fix:** Remove blanket ignore, add targeted ignores.

**[LOW-2] Hardcoded string "Pusat" for default branch**
- `online_orders_screen.dart`, `stok_alert_worker.dart`: Branch defaults to hardcoded "Pusat". Should use a constant from `NusaConfig`.
- **Fix:** Add `defaultBranch` to `NusaConfig`.

**[LOW-3] TabController listener fires on every animation frame**
- `online_orders_screen.dart:39-41`: `_tabController.addListener` fires on every scroll frame of tab transition (not just on index change). The `indexIsChanging` guard is correct, but simpler to use `_tabController.index` listener approach.
- **Fix:** Track previous index and compare, or use `TabController.onIndexChanged` pattern.

**[LOW-4] Supabase Realtime subscription never disposed**
- `online_orders_screen.dart:67-85`: `supabase.channel().subscribe()` has no unsubscribe in `dispose()`. Once subscribed, channel lives forever even after screen is popped.
- **Fix:** Store channel reference and call `supabase.removeChannel(channel)` in dispose.

---

## 6️⃣ Recommendations

### Immediate fixes (before next release):
1. ~~Wrap `_completeOrder()` in database transaction~~ (CRIT-2)
2. ~~Don't silently swallow JSON parse errors in `_completeOrder()`~~ (CRIT-3)
3. ~~Log all swallowed exceptions with at least `debugPrint`~~ (CRIT-1)

### Short-term (this sprint):
4. Fix Supabase re-initialize in background worker (MED-1)
5. Batch product form writes into single DB operation (MED-5)
6. Dispose Supabase Realtime channel (LOW-4)
7. Add `mounted` check in `_filter()` (MED-4)

### Long-term (architectural):
8. Centralized error handling service — wrap all `catch` blocks with error reporting
9. Background task resilience — retry policy, health check endpoints
10. Add `analysis_options.yaml` with stricter lint rules (`avoid_catches_without_on_clauses`, `use_build_context_synchronously`)

---

## 7️⃣ Manual Test Checklist

Since this is a Flutter app (no browser-based Playwright testing available), verify these critical paths on a real device:

### Core POS Flow
- [ ] Open app → Login with PIN → Dashboard shows
- [ ] Buka Kasir → Product grid loads → Tap product → Cart increments
- [ ] Cart → Checkout → Apply promo code → Select customer → Pay cash
- [ ] Receipt shown correctly → Back to POS → Cart cleared
- [ ] Stock deducted after transaction (verify in Stock menu)

### Online Orders
- [ ] Pengaturan → Toko Online → Fill store info → Activate → URL shown
- [ ] Sync products (Products with "Tampil di Toko Online" enabled)
- [ ] Open store URL in browser → Products visible → Place order
- [ ] Flutter app gets notification + order appears in Pesanan Online
- [ ] Terima & Siapkan → Siap Diambil → Selesai (Lunas) — verify stock deduction
- [ ] Batalkan order at "Online Baru" → verify status changes

### Edge Cases
- [ ] Kill app during _completeOrder() → verify DB consistency on restart
- [ ] Place order with no internet → retry when online
- [ ] Supabase down → app doesn't crash, offline POS still works
- [ ] Switch tabs rapidly in Pesanan Online → no crash
- [ ] Edit product → save → verify all fields persisted (sku, stock, barcode, image, isOnline)

### Backup & Restore
- [ ] Link Google account → Pindah Device → Upload backup
- [ ] Fresh install → Login Google → Restore → verify data intact
- [ ] Backup without Google linked → shows login prompt

### Theme & Printer
- [ ] Toggle dark/light/sistem → persists across restart
- [ ] Printer: scan Bluetooth → print receipt → format correct
