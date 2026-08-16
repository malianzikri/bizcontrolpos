# BizControl Online V1.8.7 — Setup Invite-Only Access

## 1. Database migration

Backup database lalu jalankan `migration-v1.8.7-invite-only-access.sql` di Supabase SQL Editor. Migration akan:
- membuat `owner_accounts`;
- memasukkan seluruh Owner yang sudah ada sebagai Owner aktif;
- menambahkan `can_create_business()` dan `activate_owner_account()`;
- memperketat `create_business()` sehingga user Auth biasa tidak dapat membuat bisnis sendiri.

## 2. Buat Edge Function `account-admin`

Supabase Dashboard → Edge Functions → New Function → nama: `account-admin`.
Paste isi `account-admin-edge-function.ts` dan deploy.

Gunakan konfigurasi function yang sama dengan `team-invite`. Jika project memakai Publishable Key baru dan function melakukan verifikasi Bearer token sendiri, gunakan konfigurasi Verify JWT yang sesuai setup staging Anda.

## 3. Secrets Edge Function

Tambahkan secrets berikut:

`BIZCONTROL_SYSTEM_ADMIN_EMAILS`
- Isi email akun BizControl milik pengelola sistem.
- Bisa lebih dari satu, pisahkan dengan koma.
- Contoh: `admin@domain.com,backup@domain.com`

`BIZCONTROL_ALLOWED_REDIRECTS`
- Daftar origin yang boleh menjadi tujuan invite/reset password.
- Pisahkan koma.
- Contoh staging + production: `http://localhost:5500,https://bizcontrol-anda.vercel.app`

Jangan pernah menaruh `SUPABASE_SERVICE_ROLE_KEY` di frontend. Edge Functions hosted Supabase menyediakan server secret tersebut pada environment function.

## 4. Matikan pendaftaran publik di Supabase Auth

Supabase Dashboard → Authentication → General Configuration → nonaktifkan **Allow new users to sign up**.

Dengan ini user publik hanya dapat login bila akun sudah dibuat/diundang. Owner baru dibuat melalui Admin Sistem; karyawan dibuat melalui Tim & Role.

## 5. Frontend config

`runtime-config.js` tetap berisi Project URL + Publishable Key. Tambahan V1.8.7:

```js
supportWhatsApp: '628117199210'
```

Nomor ini dipakai oleh tombol **Daftar BizControl — Chat Admin**. Gunakan format kode negara tanpa tanda `+`.

## 6. Flow Owner baru

1. Calon customer klik **Daftar BizControl — Chat Admin**.
2. Admin Sistem login ke BizControl.
3. Buka **Admin Sistem** → masukkan email Owner → **Kirim Undangan Owner**.
4. Owner membuka email → membuat password → login.
5. Login pertama mengaktifkan `owner_accounts` lalu otomatis membuat `Bisnis Saya`.

## 7. Password

### User mengganti password sendiri
Pengaturan → Akun & Password → Ganti Password → isi password baru dua kali. Setelah berhasil user diminta login ulang.

### Owner reset password karyawan
Tim & Role → pada anggota aktif klik **Reset Password**. Email reset hanya dapat dikirim untuk anggota yang memang terdaftar pada bisnis milik Owner tersebut.

### Admin Sistem reset password Owner
Admin Sistem → daftar Owner → **Kirim Reset Password**.

## 8. Test wajib sebelum production

- Demo via HP: tombol **Masuk** terlihat di topbar.
- Halaman Login tidak memiliki tab/aksi Daftar publik.
- Tombol Chat Admin membuka WhatsApp.
- User Auth biasa yang bukan Owner tidak dapat menjalankan `create_business()`.
- Admin Sistem dapat invite Owner.
- Owner invite dapat membuat password dan login.
- Semua role dapat mengganti password sendiri.
- Owner dapat reset karyawan aktif, tetapi bukan user bisnis lain.
- User non-system-admin tidak dapat menjalankan action `invite-owner`, `list-owners`, atau `reset-owner` pada Edge Function.
- Logout/login ulang dan reset password bekerja di URL Vercel production.
