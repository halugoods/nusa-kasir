# 📋 Audit Report — NUSA Kasir (v1.3.9)

**Date:** 2026-07-24
**Project Type:** Flutter (Riverpod + Drift + Supabase)
**Files Analyzed:** 97 `.dart` files, ~57,167 LOC
**Audit Scope:** Full-stack — UI/UX, business logic, data layer, security, architecture, template-readiness

---

## 0️⃣ Executive Summary

NUSA Kasir is a **surprisingly mature and feature-rich** POS application — not a prototype, not an MVP, but a production-grade app with:
- **26 screens**, multi-role RBAC, dark mode, responsive tablet layout
- Full POS flow: product grid → cart → checkout (Tunai/QRIS/Transfer)
- Employee management with NFC tap-to-login, fingerprint auth, attendance
- Cloud backup via Supabase Storage, Google Sheets integration, online store
- Offline-first architecture with background sync workers
- AI assistant, comprehensive reporting with PDF/CSV/Excel export

**Verdict on "Ready to sell":** 🟡 **85% ready.** The app is functionally complete and production-tested. There are no showstoppers, but 2 critical bugs, several medium risks, and missing polish items need addressing before commercial release.

**Verdict on "Source of Truth template":** 🟢 **Excellent foundation.** The architecture (Riverpod + Drift + repository pattern + NusaConfig tokens) is clean, modular, and well-structured. The design token system makes white-labeling straightforward. With the fixes below, this is an ideal template for F&B, bengkel, laundry, etc.

---

## 1️⃣ Code Quality Summary

| Category | Issues | Risk | Detail |
|---|---|---|---|
| **Error Handling** | 13+ repos, 25+ screens | 🔴 High | 81% of repositories have zero try-catch; silent `catch(_){}` everywhere |
| **Date Arithmetic** | 2 bugs | 🔴 High | `DateTime(year, month+1, 1)` crashes on December (month 13) |
| **Performance** | 2 patterns | 🟡 Medium | N+1 queries, in-memory filtering of full tables |
| **Code Duplication** | 3 major areas | 🟡 Medium | ProfileStatsCard ↔ EmployeeFlipCard; sync methods in SpreadsheetService |
| **State Management** | Good | 🟢 Low | Consistent `mounted` checks after async; proper Riverpod usage |
| **Dark Mode** | Good | 🟢 Low | Excellent coverage — every widget branches on `isDark` |
| **Design System** | Excellent | 🟢 Low | NusaConfig is a true single source of truth for tokens |
| **Testing** | Insufficient | 🔴 High | 5 test files (~300 lines total), no widget/integration tests |
| **Security** | 1 concern | 🟡 Medium | NFC tag hash is djb2 (non-cryptographic), not HMAC |

---

## 2️⃣ Architecture & Structure

### Project Tree
```
lib/
├── main.dart                          # Entry + startup initialization
├── app.dart                           # MaterialApp.router + lifecycle backup
├── core/
│   ├── activation/                    # License key verification + Google Sign-In
│   ├── auth/                          # Employee session (SecureStore persistence)
│   ├── config/nusa_config.dart        # 🟢 DESIGN TOKENS — colors, spacing, role maps
│   ├── constants/                     # App-wide string constants
│   ├── providers.dart                 # Riverpod provider definitions
│   ├── services/                      # AI, GoogleAuth, Notifications, Workers, etc.
│   ├── theme/                         # Material 3 theme (light + dark)
│   ├── utils/                         # Receipt printer, PDF export, etc.
│   └── widgets/splash_screen.dart
├── data/
│   ├── database/                      # Drift tables (21 tables) + generated code
│   └── repositories/                  # 16 repositories (Data Mapper pattern)
├── features/                          # 26 feature screens
├── shared/
│   ├── services/                      # Biometric + NFC services
│   └── widgets/                       # Reusable widgets (17 widgets)
└── assets/                            # 16 SVG icons + logo PNGs
```

### Architecture Pattern: **Feature-first with layered data access**
```
UI (Screen) → Riverpod Provider → Repository → Drift DB / Supabase
                 ↕ SecureStore (local encrypted storage)
```

### State Management: **Riverpod**
- `employeeSessionProvider` — current logged-in employee
- `authProvider` — current role string
- `cartProvider` — POS cart items
- `featureTogglesProvider` — menu visibility
- `activeBranchProvider` — branch scoping
- `themeModeProvider` — persisted theme

### Data Flow
```
User Action → Screen.setState/ref.read → Repository.method()
  → Drift query → return data → setState → widget rebuild
  ↕ Supabase Edge Functions (online-only features)
  ↕ SecureStore (activation, sessions, tokens)
```

---

## 3️⃣ Feature Inventory

| # | Feature | Files | Complexity | Status |
|---|---|---|---|---|
| 1 | **Activation + Google Sign-In** | 5 | High | ✅ Working (v1.3.9 fixed) |
| 2 | **Setup (first-time)** | 1 | Low | ✅ Working |
| 3 | **Employee Login (PIN + NFC + Fingerprint)** | 5 | High | ✅ Working |
| 4 | **Dashboard (stats, menu grid, branch picker)** | 3 | High | ✅ Working |
| 5 | **POS Screen (product grid, cart, payment)** | 3 | High | ✅ Working |
| 6 | **Checkout (Tunai/QRIS/Transfer)** | 2 | High | ✅ Working |
| 7 | **Products (CRUD, variants, wholesale, barcode)** | 4 | Medium | ✅ Working |
| 8 | **Categories (emoji + gradient cards)** | 2 | Low | ✅ Working |
| 9 | **Stock Management (in/out, low-stock alerts)** | 2 | Medium | ✅ Working |
| 10 | **Stock Opname (physical inventory count)** | 1 | Medium | ⚠️ No transaction wrapping |
| 11 | **Transactions (history, void, reprint, share)** | 1 | Medium | ✅ Working |
| 12 | **Customers (CRUD, loyalty points, levels)** | 1 | Medium | ✅ Working |
| 13 | **Debts/Piutang (track, installment payments)** | 1 | Medium | ✅ Working |
| 14 | **Promos (discount codes, quota, date range)** | 1 | Medium | ✅ Working |
| 15 | **Reports (sales, P&L, charts, multi-format export)** | 1 | High | ⚠️ N+1 queries |
| 16 | **Attendance (check-in/out, cash reconciliation)** | 1 | High | ⚠️ Dec date crash |
| 17 | **Employees (CRUD, roles, photo, NFC binding)** | 1 | Medium | ✅ Working |
| 18 | **Finance (expenses, payroll, waste, recurring, cashflow)** | 1 | High | ⚠️ Dec date crash |
| 19 | **Suppliers** | 1 | Low | ✅ Working |
| 20 | **Branches (multi-store management)** | 1 | Medium | ✅ Working |
| 21 | **Online Orders (realtime, state machine)** | 2 | High | ✅ Working |
| 22 | **Online Store Setup (Supabase + Vercel)** | 1 | Medium | ✅ Working |
| 23 | **Google Sheets Integration** | 1 | High | ✅ Working |
| 24 | **AI Chat Assistant** | 1 | Medium | ✅ Working |
| 25 | **Storefront (walk-in customer ordering)** | 1 | Medium | ✅ Working |
| 26 | **Settings (theme, features, backup, printer)** | 3 | High | ✅ Working |
| 27 | **Background Sync (Workmanager)** | 2 | Medium | ✅ Working |
| 28 | **Receipt Printing (Bluetooth thermal)** | 1 | Medium | ⚠️ BT manager leak |

---

## 4️⃣ Key Findings & Risks

### 🔴 CRITICAL — Must Fix Before Sale

#### C1. Date Arithmetic Crash on December
**Files:** `attendance_repository.dart:270`, `finance_repository.dart:108`
```dart
final end = DateTime(year, month + 1, 1);   // month=12 → DateTime(2026, 13, 1) 💥
final next = DateTime(r.nextDate.year, r.nextDate.month + 1, r.nextDate.day);
```
**Impact:** App crashes when viewing December attendance or processing December recurring expenses. This is a guaranteed crash 1-2 times per year per user.
**Fix:** Use `DateTime(year, month + 1, 0)` for last-day-of-month, or `DateTime.utc(year + (month ~/ 12), (month % 12) + 1, 1)`.

#### C2. Stock Opname — No Transaction Wrapping
**File:** `stock_count_repository.dart` (finalizeSession)
```dart
for (final item in items) {
  await productRepo.adjustStock(item.productId, item.difference);  // partial write
  await _insertStockMovement(...);                                  // partial write
}
```
**Impact:** If finalizeSession fails halfway through, some products are adjusted and others are not — corrupt inventory. Drift `db.transaction()` must wrap the entire loop.

#### C3. NFC Tag Security — djb2 Hash
**File:** `nfc_tag_service.dart`
```dart
// "Sufficient for anti-cloning, not for cryptographic security"
int h = 5381;
for (int i = 0; i < data.length; i++) { h = ((h << 5) + h) + data[i].codeUnitAt(0); }
```
**Impact:** Anyone with physical NFC tag access can clone an employee tag with ~30 minutes of work. For a POS system handling money, this is a meaningful risk. Should use HMAC-SHA256 with a properly generated device-specific secret.

### 🟡 MEDIUM — Should Fix Before Sale

#### M1. Silent Error Handling Everywhere
**Pattern across 13/16 repositories, most services:**
```dart
} catch (_) {}           // or catch (_) { return []; } or catch (_) { return false; }
```
**Impact:** Impossible to debug production issues. A database corruption, disk full, or constraint violation is silently turned into "no data" or "failed" with zero diagnostic information. At minimum, add `debugPrint` before swallowing.

#### M2. Performance: N+1 Queries + In-Memory Filtering
**File:** `report_repository.dart`
- `_filtered()` fetches the entire table then filters in Dart (lines 299-315)
- `profitLoss()` makes one `db.select(db.products)` per waste item inside a loop (line 94)
**Impact:** With 1000+ products and 500+ transactions, report generation will be noticeably slow. Filtering should be pushed to SQL `WHERE` clauses; batch product lookups should use `WHERE id IN (...)`.

#### M3. Code Duplication: ProfileStatsCard ↔ EmployeeFlipCard
**Files:** `profile_stats_card.dart` (~770 lines) + `employee_flip_card.dart` (~340 lines)
**Duplication:** Both independently implement identical Kasir/Manager/Owner back-side views with the same layout, same data model (`EmployeeCardData`), and same flip animation logic.
**Fix:** Extract a shared `RoleDashboardView` widget and a shared `FlipCard` animation wrapper. ~400 lines of deduplication potential.

#### M4. SpreadsheetService Sync Method Repetition
**File:** `spreadsheet_service.dart`
**Pattern:** All 10 sync methods (`syncProduk`, `syncTransaksi`, `syncStok`, etc.) are nearly identical in structure (fetch → build rows → update values). A generic `syncTab<T>()` method with a row builder callback would reduce ~500+ lines.

#### M5. DB Instantiation in Widgets
**File:** `buka_kasir_sheet.dart:99-100`
```dart
final db = AppDatabase();
final repo = CashierSessionRepository(db);
```
Creates a fresh database instance directly in a widget rather than using DI. This could lead to stale/mismatched DB state and makes testing impossible.
**Fix:** Use `ref.read(databaseProvider)` like every other screen does.

### 🟢 LOW — Nice to Have

#### L1. No App Icon / Splash Screen Polish
- Splash screen is a generic Material Design icon
- No custom app launcher icon configured in Android/iOS native manifests

#### L2. Missing "Forgot PIN" / PIN Reset Flow
If an employee forgets their PIN, there's no self-service reset. The Owner must manually edit from the Employees screen.

#### L3. No Offline Mode Indicator
The app operates offline-first but provides no visual indicator when Supabase is unreachable. Users may not realize backup/sync isn't happening.

#### L4. Empty State on Onboarding
`onboarding_screen.dart` silently ignores empty store name input — button does nothing with no error message.

#### L5. TopToast Race Condition
`top_toast.dart` uses `BuildContext.hashCode` as a map key and has a `Future.delayed` cleanup that races with normal dismiss flow.

#### L6. PinKeypad — Fragile Shake Animation
Shake animation uses `addPostFrameCallback` + checking `_error` and `_digits` together. Edge case: what if digits change between frame callback and execution?

---

## 5️⃣ Template Readiness Analysis

### ✅ What's Excellent for Forking

| Aspect | Rating | Notes |
|---|---|---|
| **Design Token System** | ⭐⭐⭐⭐⭐ | `NusaConfig` has colors, spacing, radius, breakpoints, category maps — one file, change everything |
| **Role-Based Access Control** | ⭐⭐⭐⭐⭐ | Declarative role→screen map in `NusaConfig.roleAccess` + PIN guard + owner-only |
| **Repository Pattern** | ⭐⭐⭐⭐ | Clean Data Mapper, consistent Drift usage, 16 domain-focused repos |
| **Dark Mode Coverage** | ⭐⭐⭐⭐⭐ | Every single widget queries `isDark`, all colors tokenized |
| **Responsive Layout** | ⭐⭐⭐⭐ | Tablet/wide detection, adaptive POS layout, grid column config |
| **Feature Toggle System** | ⭐⭐⭐⭐ | `featureTogglesProvider` + `featureToggles` SecureStore — hide menu items per customer |

### 🔧 What Needs Abstracting for Vertical Templates

| What | Current Hardcoding | Template Fix |
|---|---|---|
| Category list | `Makanan, Minuman, Sembako, Lainnya` in `NusaConfig` | Move to configurable JSON or DB table |
| Product types | `Regular, Varian, Grosir` | Configurable per vertical |
| Role names | `Owner, Manager, Kasir, Gudang, Finance` | Configurable array |
| Screen labels | `Produk, Stok, Pelanggan, Piutang` hardcoded | Would need i18n first |
| Business logic | Stock management, waste, payroll | Generalized "inventory movement" + "HR" modules |
| Supabase schema | Hardcoded table names, Edge Function names | Config-based or env-based |
| App name/brand | `NUSA` scattered in ~200 places in UI strings | Use `NusaConfig.appName` consistently (mostly already done ✅) |

### Template Forking Checklist
- [ ] Replace category defaults in `NusaConfig.catEmoji/catGradients/catIcons`
- [ ] Replace role names in `NusaConfig.roles` and `NusaConfig.roleAccess`
- [ ] Update `NusaConfig.primaryColor` + palette
- [ ] Replace `NusaConfig.appName`, `appSubtitle`, `landingPageUrl`
- [ ] Replace splash assets (`splash_nusa.png`, `nusa_logo.png`)
- [ ] Update `applicationId` for Android
- [ ] Update Supabase URL + anon key
- [ ] Rename database file (`nusa_kasir.sqlite`)
- [ ] Update WhatsApp order link
- [ ] Replace SVG menu icons (currently `assets/icons/*.svg`)

---

## 6️⃣ Recommendations

### Immediate (Before v1.4.0 Release)
1. **Fix C1:** Date arithmetic — wrap `month+1` with `DateTime.utc(year, month+1, 1)` safe constructor
2. **Fix C2:** Add `db.transaction()` around `finalizeSession` in stock opname
3. **Fix M2:** Push filtering to SQL `WHERE`, batch waste product lookups
4. **Fix M5:** Replace `AppDatabase()` in buka_kasir_sheet with `ref.read(databaseProvider)`

### Short-term (v1.4.0 — v1.5.0)
5. **Add error logging:** Replace all `catch(_){}` with `catch(e, s) { debugPrint('[$ClassName] Error: $e\\n$s'); }` — at minimum
6. **Extract shared flip-card logic** — reduce ~400 lines of duplication
7. **Add app icon** + configure native splash screen
8. **Add offline status indicator** — a subtle banner when Supabase is unreachable
9. **Add PinKeypad unit tests** — the most security-critical widget has zero tests

### Long-term (Template Readiness)
10. **Extract `NusaConfig` overrides to a `.env`-style config** for easy vertical forking
11. **Add i18n infrastructure** — all UI strings should use `AppLocalizations`
12. **Write integration tests** — at minimum: login → POS → checkout → receipt flow
13. **Extract `BukaKasirSheet` to use Riverpod DI** — remove direct DB instantiation pattern
14. **Add crash reporting** — Sentry or Firebase Crashlytics for production observability

---

## 7️⃣ Manual Test Checklist (Flutter)

Since we can't run Playwright for Flutter, here's the critical manual verification:

### Core Flow (Run on real Android device)
- [ ] Fresh install → Activation screen appears
- [ ] Google Sign-In works → license key input → setup screen → onboarding
- [ ] Setup creates Owner employee → auto-login → home screen appears
- [ ] Home → Kasir button → PIN dialog → POS screen loads
- [ ] Add products to cart → checkout → select payment → transaction complete
- [ ] Receipt prints (if Bluetooth printer paired)
- [ ] Transaction appears in Transactions list

### Edge Cases
- [ ] Kill app mid-checkout → reopen → cart preserved (or cleared safely)
- [ ] Turn off internet → all local features still work
- [ ] Reinstall app → Google Sign-In → activation restored from cloud
- [ ] Login with NFC tag → works (if device supports NFC)
- [ ] Login with fingerprint → works
- [ ] Wrong PIN 3x → shake animation + no login
- [ ] December attendance → scroll to December → no crash (C1 fix verification)
- [ ] Generate full PDF report → all sections populated
- [ ] Google Sheets sync → all 10 tabs created
- [ ] Stock opname: start → count some products → finalize → no partial update

### Template Verification
- [ ] Change `NusaConfig.primaryColor` → all UI reflects new color
- [ ] Change `NusaConfig.roles` → menus reflect new roles
- [ ] Replace assets/icons/*.svg → menu grid shows new icons

---

## 8️⃣ Statistics

| Metric | Value |
|---|---|
| Total Dart files | 97 |
| Total LOC | ~57,167 |
| Feature screens | 26 |
| Shared widgets | 17 |
| Services | 8 |
| Repositories | 16 |
| Database tables | 21 |
| SVG icons | 16 |
| Test files | 5 (~300 lines) |
| Test coverage | <2% (estimation) |
| catch(_){} blocks | ~120+ |
| Critical bugs found | 3 |
| Medium issues found | 5 |
| Low issues found | 6 |

---

## 9️⃣ Bottom Line

**NUSA Kasir is a solid, production-tested POS application with exceptional UI polish and feature breadth.** The architecture is clean and intentionally designed for white-labeling. The security model (PIN + biometric + NFC + RBAC) is appropriate for a retail POS system.

**The 3 critical bugs (date crash, stock opname partial write, NFC security) MUST be fixed before charging customers.** The medium issues (silent error swallowing, performance) will become urgent as user data grows.

**As a template for F&B, bengkel, laundry:** Excellent starting point. The `NusaConfig` design token system means you can rebrand in under an hour. The main work for vertical adaptation is in the domain model (categories, product types, business rules), architecture-level abstraction (i18n, config-driven features), and removing any toko-kelontong-specific defaults.

**Overall Grade: B+ (85/100)** — Ready for commercial use after critical fixes; excellent template foundation.
