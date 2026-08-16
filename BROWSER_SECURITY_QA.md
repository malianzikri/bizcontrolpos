# BizControl Online V1.8 — Real Browser Security Regression

## Result
**35 / 35 PASS** using Chromium DOM/JavaScript execution.

### Suite A — 27/27 PASS
- App boots.
- V1.8 visible.
- Password minimum 8.
- Stored-XSS payload does not inject `<img>`.
- Stored-XSS event handler does not execute.
- Payload is rendered as text.
- Mobile Sales 390px: no horizontal overflow.
- Mobile Products 390px: no horizontal overflow.
- Mobile Expenses 390px: no horizontal overflow.
- Mobile Audit 390px: no horizontal overflow.
- Mobile Team 390px: no horizontal overflow.
- Warehouse Sales hides Total.
- Warehouse Sales hides Dibayar.
- Warehouse Sales shows Surat Jalan.
- Warehouse Sales has no Pembayaran action.
- Warehouse Products hides HPP.
- Warehouse Products hides Harga.
- Warehouse has stock-only product action.
- Warehouse Dashboard hides Piutang.
- Warehouse Dashboard hides Omzet.
- Warehouse Dashboard shows Pengiriman.
- Demo security warning visible.
- Negative-stock status visible.
- Legacy Cloud session migrates.
- Legacy localStorage session token removed.
- Cloud session stored in sessionStorage.
- clearSession removes both old/new token locations.

### Suite B — 8/8 PASS
- XSS payload escaped on Products.
- XSS payload escaped on Sales/Customer.
- XSS payload escaped on Expenses.
- Invoice generator encodes injected content.
- Surat Jalan generator encodes injected content.
- Negative stock default disabled.
- Local payment history recalculates invoice paid amount.
- Local invoice becomes LUNAS after payment.

## Limitation
These are frontend/browser regression tests. They do not replace executing the PostgreSQL migration on a real Supabase staging project and testing concurrent network requests with real Auth users.
