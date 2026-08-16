# BizControl Online V1.8.6 — Final Deployment Notes

## What changed

1. Tombol **Keluar** dipindahkan dari Pengaturan ke topbar akun dan tetap bisa dijangkau pada mobile Cloud mode.
2. Kasir sekarang menggunakan **keranjang multi-item**: satu invoice dapat berisi beberapa produk/jasa.
3. Stok, HPP, laba kotor, dan total dihitung per item; pembayaran tetap satu invoice dan riwayat pembayaran/kwitansi tetap per pembayaran.
4. Invoice dan Surat Jalan mencetak semua item. Surat Jalan tetap tanpa harga.
5. Config Supabase tetap deployment-managed; Owner tidak memiliki UI untuk mengganti Project URL/Publishable Key.
6. Demo tetap one-click local sandbox tanpa Supabase Auth.

## Staging upgrade dari V1.8.5

**Database migration wajib**, karena V1.8.6 menambah tabel `sale_items` dan RPC transaksi multi-item.

1. Backup database staging.
2. Jalankan `migration-v1.8.6-multi-item-cashier.sql` sekali di Supabase SQL Editor.
3. Pastikan query selesai tanpa error sampai `COMMIT`.
4. Deploy source V1.8.6 ke Vercel/GitHub.
5. Copy deployment values yang sama ke `runtime-config.js`:

```js
window.BIZCONTROL_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  publishableKey: 'sb_publishable_...',
  turnstileSiteKey: ''
};
```

6. Edge Function `team-invite` tidak perlu diubah.
7. Hard refresh/PWA update setelah deploy.

## Existing data

Migration melakukan backfill transaksi lama menjadi satu `sale_items` per invoice lama **sebelum trigger stok item diaktifkan**, sehingga stok existing tidak dipotong ulang.

## Minimum staging test

- buat invoice 2–3 barang;
- edit qty salah satu barang;
- cek stok masing-masing produk;
- transaksi cash dan tempo;
- tambah cicilan dan lunasi;
- cetak Invoice/Kwitansi/Surat Jalan;
- hapus invoice dengan Security Key dan pastikan semua stok kembali;
- test Owner di laptop + Kasir di HP;
- test Logout dari topbar.

Never place a Supabase secret/service-role key in frontend files. Publishable key memang browser-visible; authorization tetap harus ditegakkan oleh RLS/RPC.
