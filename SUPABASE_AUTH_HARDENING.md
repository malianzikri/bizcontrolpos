# Supabase Auth Hardening — BizControl V1.8.1

Frontend V1.8.1 sudah menyediakan login, signup, Forgot Password, Reset Password, minimum password 8 karakter, sessionStorage, dan Turnstile-ready. Konfigurasi Auth production tetap harus dilakukan di Supabase Dashboard.

## Wajib sebelum staging/public launch

1. **Site URL**
   - Set ke URL utama aplikasi, misalnya `https://app.domain.com`.

2. **Redirect URLs**
   - Tambahkan URL staging dan production yang sah.
   - Forgot Password menggunakan halaman aplikasi sebagai redirect target.

3. **Password policy**
   - Minimum 8 karakter atau lebih kuat.
   - Frontend juga menolak password < 8 karakter.

4. **Email / SMTP**
   - Siapkan SMTP production untuk email confirmation/recovery.
   - Uji Forgot Password end-to-end, jangan hanya mengecek request API.

5. **CAPTCHA**
   - Jika Cloudflare Turnstile digunakan, aktifkan provider/secret pada Supabase Auth.
   - Isi hanya **Site Key** pada `runtime-config.js`/frontend.

6. **Key management**
   - Frontend hanya boleh menerima publishable/anon key.
   - Jangan pernah memasukkan `service_role`, secret key, database password, atau SMTP secret ke repository/frontend.

## Forgot Password V1.8.1

Flow:
- user klik `Lupa password?`;
- app POST ke `/auth/v1/recover`;
- UI selalu memberi pesan generik: `Jika email terdaftar, link reset password akan dikirim.`;
- recovery link membuka aplikasi dengan recovery session;
- user membuat password baru;
- app PUT password baru ke `/auth/v1/user`;
- recovery session logout/clear;
- user wajib login normal kembali.

## Production test

Gunakan akun tester nyata dan cek:
- email terkirim;
- redirect valid;
- expired/invalid link ditolak;
- password baru dapat dipakai login;
- session recovery tidak tetap aktif setelah password berhasil diubah;
- CAPTCHA/rate-limit berfungsi jika dikonfigurasi.
