# BizControl Online V1.16 — FINAL POS Operations Suite

Paket ini dibuat supaya source dapat **ditimpa ke project BizControl V1.9.3** tanpa reset database existing.

## Urutan upgrade Cloud yang aman

1. Backup database Supabase.
2. Pastikan `migration-v1.9-purchasing.sql` sudah pernah dijalankan jika V1.9 Pembelian digunakan.
3. Jalankan **sekali** `migration-v1.10-to-v1.16-pos-suite.sql` di Supabase SQL Editor pada staging/database BizControl yang benar.
4. Pastikan SQL selesai tanpa error.
5. Timpa source project dengan isi ZIP V1.16 dan deploy ke Vercel.
6. Hard refresh / clear PWA cache pada device kasir lama.
7. Test role Owner, Admin, Kasir, Finance, Gudang, Staff mengikuti `ROLE_MATRIX.md`.

**Jangan** menjalankan ulang `supabase-schema.sql` pada database existing.

## Isi fitur V1.10–V1.16

- **V1.10 Shift Kasir:** modal kas awal, kas masuk/keluar, expected cash, closing cash dan selisih.
- **V1.11 Refund/Retur/Void:** histori transaksi tetap ada; stok/BOM dikembalikan dan laporan memakai nilai neto.
- **V1.12 Stock Opname:** hitung stok fisik + adjustment history.
- **V1.13 Variant + Barcode:** SKU/barcode unik, varian, dukungan scanner keyboard/USB.
- **V1.14 Promo/Pajak/Service:** diskon nominal/persen, promo name, tax %, service %.
- **V1.15 Recipe/BOM:** penjualan produk recipe mengurangi bahan baku dan HPP dihitung dari formula.
- **V1.16 CRM/Member/Point:** member, point earn/redeem, total belanja, kunjungan, loyalty settings.

## Final role hardening

- Kasir tidak lagi bisa edit transaksi selesai atau Refund/Void.
- Finance tidak ditampilkan menu Kasir.
- Gudang memiliki menu **Pengiriman** dan menerima PO tanpa melihat harga/HPP/hutang supplier.
- Gudang hanya dapat mengubah stock/min_stock di database; master produk tetap terkunci.
- Staff hanya Dashboard dasar + Produk read-only + Pengaturan akun.
- Kasir dapat tambah/edit profil member tetapi tidak dapat memanipulasi saldo point melalui REST.
- Setiap role melihat ringkasan hak aksesnya di Pengaturan; Owner/Admin melihat panduan role pada Tim & Role.

Lihat `ROLE_MATRIX.md` dan `V1.16_ROLE_ACCESS_QA.md`.

## Smoke test setelah deploy

Buka Shift → scan barcode → pilih member → transaksi + promo/pajak/service → cetak thermal/A4 → refund oleh Admin/Owner → stock opname → transaksi produk recipe → penerimaan PO sebagai Gudang → tutup shift → cek Laporan sebagai Finance/Owner.
