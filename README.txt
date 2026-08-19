BIZCONTROL ONLINE V1.8.8 — AUTO DEMO PATCH
===========================================

Fungsi patch
------------
Normal:
  https://URL-POS/
  -> tetap membuka halaman Login.

Dari landing:
  https://URL-POS/?demo=1
  -> visitor BARU langsung masuk Mode Demo tanpa melihat Login.

User existing yang sudah punya session Cloud:
  https://URL-POS/?demo=1
  -> tetap masuk Cloud. Session tidak dihapus.

Invite / Reset Password:
  tetap diproses lebih dahulu. Patch tidak memotong flow Auth.

Kenapa aman
-----------
V1.8.8 sudah mempunyai fungsi enterDemoSandbox().
Patch ini hanya menambahkan pemeriksaan query parameter pada Boot.
Tidak mengubah:
- kasir
- produk/stok
- laporan
- database
- Supabase
- login
- role
- invitation
- reset password

CARA 1 — PALING MUDAH (otomatis)
--------------------------------
1. Taruh apply-auto-demo-v188.py di folder project.
2. Jalankan dari Terminal Mac:

   python3 apply-auto-demo-v188.py index.html

   Jika file V1.8.8 kamu namanya lain, ganti index.html dengan nama file tersebut.

3. Script otomatis membuat backup:
   index.html.before-auto-demo.bak

4. Commit dan push:
   git add .
   git commit -m "Add direct demo entry for BizControl"
   git push

CARA 2 — MANUAL
----------------
Cari bagian:
// -------- Boot --------

sampai penutup:
})();

Ganti blok tersebut dengan isi file BOOT-REPLACEMENT.txt.

SETELAH DEPLOY
--------------
Tes dua URL:

A. URL normal:
   https://URL-POS/
   Harus tetap tampil LOGIN.

B. URL demo:
   https://URL-POS/?demo=1
   Harus LANGSUNG masuk dashboard Demo.
   Jika Demo Conversion Add-on sudah terpasang, onboarding 3 langkah
   akan muncul setelah masuk Demo.

LANDING PAGE
------------
Di config landing page, ubah link `demo` menjadi:

  https://URL-POS/?demo=1

Contoh:
window.BIZCONTROL_LANDING = {
  links: {
    demo: 'https://URL-POS/?demo=1',
    ...
  }
};

Landing V2 yang dibuat sebelumnya akan meneruskan UTM/fbclid secara otomatis
ke URL demo.

FLOW FINAL
----------
Meta Ads
  -> Landing BizControl Online
  -> Coba Demo 2 Menit
  -> POS ?demo=1
  -> LANGSUNG Mode Demo
  -> onboarding transaksi -> stok -> laporan
  -> Aktifkan BizControl
  -> Landing #harga
  -> checkout
  -> InitiateCheckout

CATATAN
-------
Jangan ubah link login existing menjadi ?demo=1.
Query ?demo=1 khusus untuk CTA Demo dari landing/iklan.
