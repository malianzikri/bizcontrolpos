# Deployment Security Checklist — BizControl Online V1.8

## A. Staging sebelum production
- [ ] Buat backup database Supabase.
- [ ] Gunakan project staging terpisah bila memungkinkan.
- [ ] Jalankan `migration-v1.8-security-hardening.sql`.
- [ ] Pastikan migration selesai tanpa error.
- [ ] Periksa tabel `security_key_attempts` dan kolom `businesses.allow_negative_stock`.
- [ ] Pastikan RPC V1.8 tersedia: `create_sale_with_payment`, `update_sale_secure`, `record_payment`, `set_delete_pin_v2`, `secure_delete_record_v2`.

## B. Access control
- [ ] Owner dapat seluruh workflow yang memang diizinkan.
- [ ] Admin tidak dapat mengubah `owner_id`.
- [ ] Kasir tidak dapat melihat HPP/laba.
- [ ] Finance dapat pembayaran/biaya/laporan sesuai role.
- [ ] Gudang tidak menerima HPP, harga, total invoice, jumlah dibayar, atau metode pembayaran.
- [ ] Gudang hanya dapat update stok/minimum stok.
- [ ] Staff tidak dapat mutation yang tidak diizinkan.
- [ ] Audit Log hanya tersedia sesuai role.

## C. Security Key
- [ ] Owner membuat Security Key 6 digit.
- [ ] PIN salah 1–4 kali ditolak.
- [ ] Percobaan salah ke-5 menghasilkan lock ±15 menit.
- [ ] PIN tidak muncul di Audit Log.
- [ ] Delete hanya berhasil melalui RPC V1.8.

## D. Transaction integrity
- [ ] Penjualan dengan pembayaran awal dibuat atomik.
- [ ] Simulasikan gagal request; tidak ada sale setengah jadi / pembayaran orphan.
- [ ] Dua device menambah pembayaran ke invoice yang sama secara bersamaan.
- [ ] Total pembayaran tidak pernah melebihi total invoice.
- [ ] Edit sale tidak bisa membuat total < pembayaran yang sudah masuk.
- [ ] Stok tidak boleh minus ketika setting OFF.
- [ ] Backorder bisa negatif hanya ketika setting ON.

## E. Auth
- [ ] Password minimum Supabase ≥ 8 karakter.
- [ ] CAPTCHA Supabase diaktifkan bila Turnstile digunakan.
- [ ] Turnstile Site Key di BizControl cocok dengan Secret Key provider di Supabase.
- [ ] Site URL/redirect allowlist memakai domain HTTPS production.
- [ ] Service Role Key tidak pernah ada di browser/source.
- [ ] Login error dan HTTP 429 ditampilkan dengan baik.

## F. Frontend security
- [ ] CSP response header aktif di production.
- [ ] `X-Content-Type-Options: nosniff` aktif.
- [ ] `X-Frame-Options: DENY` / `frame-ancestors 'none'` aktif.
- [ ] HSTS aktif setelah domain sudah HTTPS stabil.
- [ ] Tidak ada CDN Supabase JS floating/unpinned.
- [ ] Service Worker V1.8 terpasang dan cache versi lama terhapus.
- [ ] Response Supabase/Auth/API tidak tersimpan pada Cache Storage.

## G. XSS regression
- [ ] Test nama bisnis berisi `<img onerror=...>`.
- [ ] Test nama produk/customer/biaya berisi payload HTML/SVG.
- [ ] Test Invoice/Kwitansi/Surat Jalan dengan karakter `< > & " '`.
- [ ] Tidak ada HTML user-input yang dieksekusi.

## H. Mobile/multi-device
- [ ] Kasir 390px tidak overflow horizontal.
- [ ] Produk, Biaya, Audit, Tim, Pembayaran nyaman pada HP.
- [ ] HP membuat transaksi → laptop menerima data setelah refresh/poll.
- [ ] Laptop membuat pembayaran → HP melihat status terbaru.
- [ ] Koneksi offline/reconnect tidak membuat transaksi ganda.

## I. Launch gate
- [ ] Critical security bug = 0.
- [ ] High integrity bug = 0.
- [ ] 5–10 beta tester selesai.
- [ ] Backup dan rollback plan tersedia.
- [ ] Privacy Policy / Terms / Data Backup policy sudah tersedia sebelum public SaaS launch.
