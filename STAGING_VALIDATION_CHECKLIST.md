# BizControl Online V1.8.1 — Staging Validation Checklist

## A. Backup & migration
- [ ] Backup database staging.
- [ ] Pastikan staging sudah berada di V1.8.
- [ ] Jalankan `migration-v1.8.1-production-patch.sql`.
- [ ] Pastikan transaction migration selesai tanpa error.
- [ ] Jalankan Supabase Security Advisor dan review warning baru.

## B. Auth
- [ ] Site URL menunjuk ke staging URL.
- [ ] Redirect URLs memasukkan staging URL.
- [ ] Password policy minimum ≥ 8 karakter.
- [ ] Custom SMTP/recovery email sudah diuji.
- [ ] Jika CAPTCHA digunakan, provider + secret aktif di Supabase dan Site Key benar di frontend.
- [ ] Forgot Password mengirim email.
- [ ] Link reset kembali ke aplikasi.
- [ ] Password baru tersimpan.
- [ ] Recovery session berakhir dan user harus login ulang.

## C. Role test dengan akun nyata
- [ ] Owner: semua fungsi owner berjalan.
- [ ] Admin: fungsi operasional berjalan, owner_id tidak dapat diganti.
- [ ] Kasir: dapat jual/edit/payment sesuai izin.
- [ ] Kasir: `list_sales_for_business()` mengembalikan HPP/laba sebagai null/tidak tersedia.
- [ ] Kasir: response `create_sale_with_payment()` tidak memiliki `unit_cost`/`gross_profit`.
- [ ] Kasir: response `update_sale_secure()` tidak memiliki `unit_cost`/`gross_profit`.
- [ ] Finance: dapat melihat finansial yang memang diizinkan.
- [ ] Gudang: tidak menerima harga/HPP/total/payment method/paid amount.
- [ ] Staff: akses sesuai role matrix.

## D. Direct API negative tests
- [ ] `next_document_number()` tidak dapat dipanggil browser role.
- [ ] legacy `set_delete_pin()` tidak executable dari browser role.
- [ ] legacy `secure_delete_record()` tidak executable dari browser role.
- [ ] direct table mutation Sales/Payment yang tidak diizinkan ditolak.
- [ ] attempt update `owner_id` ditolak.
- [ ] attempt update `business_id`/system identity fields ditolak.

## E. Transaction integrity
- [ ] Cash sale normal.
- [ ] Tempo sale tanpa pembayaran awal.
- [ ] Sale + DP awal.
- [ ] Cicilan beberapa kali.
- [ ] Edit payment.
- [ ] Delete payment dengan Security Key.
- [ ] Dua perangkat membayar invoice yang sama hampir bersamaan.
- [ ] Dua perangkat membuat penjualan bersamaan.
- [ ] Stok tidak menjadi minus ketika setting negative stock OFF.
- [ ] Idempotent retry tidak membuat invoice/payment ganda.

## F. Mobile / document
- [ ] Kasir nyaman pada 360–390px.
- [ ] Produk, Biaya, Audit, Laporan, Team tetap responsive.
- [ ] Invoice cetak benar.
- [ ] Kwitansi per pembayaran benar.
- [ ] Surat Jalan tidak menampilkan harga.

## G. Launch gate
- [ ] Critical bug = 0.
- [ ] High bug = 0.
- [ ] Backup restore sudah diuji minimal sekali.
- [ ] Closed beta 5–10 UMKM selesai.
- [ ] Feedback workflow utama tidak menunjukkan blocker berulang.

Jika semua item launch gate PASS, V1.8.1 dapat dinaikkan menjadi **BizControl Online v1.0 Production**.
