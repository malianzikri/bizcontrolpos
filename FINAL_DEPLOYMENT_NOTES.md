# BizControl Online V1.8.7 — Final Deployment Notes

## Perubahan utama dari V1.8.6

1. **Demo mobile sekarang punya tombol Masuk di topbar.** Tidak perlu membuka Pengaturan untuk kembali ke Cloud login.
2. **Pendaftaran Owner publik dihapus.** Landing hanya: Masuk, Lupa Password, Chat Admin untuk Daftar, dan Coba Demo Gratis.
3. **Owner provisioning sekarang server-authorized.** Migration menambah `owner_accounts`; user Auth biasa tidak dapat membuat bisnis hanya dengan memanggil RPC sendiri.
4. **Admin Sistem** hanya muncul untuk akun yang emailnya terdaftar pada secret Edge Function `BIZCONTROL_SYSTEM_ADMIN_EMAILS`.
5. Admin Sistem dapat **mengundang Owner baru** dan **mengirim reset password Owner**.
6. Owner dapat **mengirim reset password karyawan aktif** dari Tim & Role.
7. Semua user Cloud dapat **Ganti Password sendiri** dari Pengaturan → Akun & Password.
8. Pada mobile Cloud ada tombol **Akun** di topbar agar Pengaturan/password selalu terjangkau.
9. Kasir multi-item V1.8.6 tetap dipertahankan tanpa perubahan model transaksi.

## Upgrade database

Jalankan setelah migration V1.8.6:

`migration-v1.8.7-invite-only-access.sql`

Migration ini wajib untuk model invite-only yang aman karena memperketat `create_business()`.

## Edge Function baru

Deploy file:

`account-admin-edge-function.ts`

Nama function:

`account-admin`

Set secrets:
- `BIZCONTROL_SYSTEM_ADMIN_EMAILS` = email Admin BizControl, bisa beberapa dipisah koma.
- `BIZCONTROL_ALLOWED_REDIRECTS` = origin localhost/staging/production yang boleh dipakai invite dan reset password.

`team-invite` lama tetap digunakan untuk undangan karyawan.

## Supabase Auth

Setelah V1.8.7 aktif, nonaktifkan **Allow new users to sign up** pada Auth General Configuration. Owner baru dibuat dari Admin Sistem, sedangkan karyawan dibuat dari Tim & Role.

## Vercel frontend

Deploy seluruh folder source ke repository yang sama. `runtime-config.js` tetap menggunakan Project URL dan Publishable Key yang sama, dengan tambahan `supportWhatsApp` untuk tombol Chat Admin.

Setelah deploy lakukan hard refresh dan bila PWA pernah di-install, tutup/buka ulang aplikasi agar service worker V1.8.7 mengambil cache baru.

## Minimum production smoke test

- HP Demo → tombol Masuk terlihat dan membuka login.
- Landing tidak memiliki pendaftaran Owner langsung.
- Chat Admin bekerja.
- Admin Sistem muncul hanya pada akun yang diizinkan.
- Invite Owner → email → set password → login → `Bisnis Saya` dibuat.
- User Auth non-Owner gagal memanggil `create_business()`.
- Ganti password sendiri dari akun Owner/Kasir/Gudang.
- Owner mengirim reset password Kasir.
- Admin Sistem mengirim reset password Owner.
- Kasir multi-item tetap dapat membuat satu invoice berisi beberapa barang.

Never place Supabase service-role/secret key in frontend files.
