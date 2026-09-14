# BizControl Online V1.17 — Production Ready Foundation

V1.17 tidak menambah modul kasir baru. Fokus release ini adalah membuat BizControl V1.16 lebih aman dijual sebagai SaaS: subscription/masa aktif, onboarding, backup verification, monitoring, dan safe offline degraded mode.

## Upgrade database existing
1. Backup database Supabase.
2. Pastikan migration V1.9 Purchasing sudah pernah dijalankan jika modul Pembelian dipakai.
3. Pastikan migration V1.10–V1.16 sudah berhasil.
4. Jalankan `migration-v1.17-production-readiness.sql` **sekali** pada project Supabase BizControl yang benar.
5. Deploy ulang `account-admin` Edge Function memakai file `account-admin-edge-function.ts` V1.17.
6. Timpa source web dengan file V1.17 dan deploy ke Vercel.
7. Hard refresh perangkat kasir agar Service Worker cache pindah ke V1.17.

Jangan menjalankan `supabase-schema.sql` ulang pada database existing.

## Apa yang berubah
### Subscription SaaS
- Paket awal: Starter, Business, Pro.
- Trial bisnis baru: 14 hari + 3 hari grace.
- Existing business saat migration di-grandfather sebagai Business aktif tanpa expiry agar migration tidak tiba-tiba memblokir customer lama.
- Admin Sistem dapat mengubah paket, status, masa aktif, grace period, dan catatan.
- Status Expired/Suspended membuat bisnis **read-only**: login, membaca data, laporan, dan backup tetap dapat dilakukan; transaksi dan mutation bisnis diblokir pada frontend **dan database trigger**.
- V1.17 Cloud dibatasi 1 bisnis per Owner. Multi-outlet harus menjadi modul resmi, bukan cara membuat trial baru.

### Safe Offline Mode
V1.17 **tidak** melakukan offline transaction queue. Saat koneksi hilang:
- data yang sudah terbuka tetap dapat dibaca selama halaman masih terbuka;
- static app shell disimpan oleh Service Worker;
- transaksi/perubahan data diblokir sampai internet kembali;
- banner menjelaskan status offline.

Strategi ini sengaja dipilih untuk mencegah invoice/stok/pembayaran ganda akibat konflik sinkronisasi.

### Onboarding
Owner/Admin mendapat checklist:
- profil usaha;
- produk pertama;
- tes printer;
- transaksi pertama.

### Backup
- Backup JSON tetap tersedia.
- V1.17 menambahkan metadata versi `1.17.0` dan verifikasi file backup tanpa menulis ke database.
- Aktivitas export/verify dicatat pada `backup_events`.
- Restore production **tidak dilakukan langsung dari browser**. Gunakan backup Supabase/DB procedure agar restore tidak menimpa database tanpa kontrol.

### Monitoring
- Error JS / Promise dan kegagalan cloud penting dicatat melalui `app_events`.
- Telemetry hanya berisi metadata operasional seperti page, role, endpoint, code dan pesan error yang disanitasi; jangan memasukkan password/token/customer ke event context.
- Owner/Admin melihat System Health sederhana di Pengaturan.

## Edge Function account-admin
V1.17 menambahkan action:
- `list-subscriptions`
- `set-subscription`

Edge Function tetap membutuhkan secrets yang sudah dipakai versi sebelumnya:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `BIZCONTROL_SYSTEM_ADMIN_EMAILS`
- `BIZCONTROL_ALLOWED_REDIRECTS`

Service role tidak pernah ditempatkan di frontend/runtime-config.js.

## Smoke test minimum setelah deploy staging
1. Owner login → entitlement tampil.
2. Admin Sistem → ubah bisnis ke Active 30 hari → Owner tetap bisa transaksi.
3. Ubah bisnis ke Expired → Owner masih bisa lihat laporan + backup, tetapi checkout/stock/PO ditolak.
4. Kembalikan Active → mutation bekerja lagi.
5. Putus internet saat POS terbuka → checkout disabled + banner offline.
6. Sambungkan internet → sync/reload data bekerja kembali.
7. Jalankan onboarding printer test.
8. Download backup JSON lalu Verifikasi File Backup.
9. Trigger satu error staging yang aman dan cek System Health/App Events.
10. Test Owner/Admin/Kasir/Finance/Gudang/Staff sesuai `ROLE_MATRIX.md`.

## Catatan backup Supabase
Untuk production berbayar, gunakan backup database provider di samping Backup JSON aplikasi. V1.17 Backup JSON adalah lapisan portabilitas/data export, bukan pengganti backup database terjadwal.
