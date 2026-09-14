# BizControl Online V1.16 — Final Role Matrix

Role di bawah berlaku pada UI **dan** dibatasi kembali pada data/RPC Cloud untuk aksi sensitif.

| Modul / Aksi | Owner | Admin | Kasir | Finance | Gudang | Staff |
|---|---|---|---|---|---|---|
| Dashboard | Penuh | Finansial | Dasar | Finansial | Stok | Dasar non-finansial |
| Kasir / buat transaksi POS | Ya | Ya | Ya | Tidak | Tidak | Tidak |
| Buka/Tutup Shift + Kas Masuk/Keluar | Ya | Ya | Ya | Tidak | Tidak | Tidak |
| Edit transaksi selesai | Ya | Ya | Tidak | Tidak | Tidak | Tidak |
| Refund / Retur / Void | Ya | Ya | Tidak | Tidak | Tidak | Tidak |
| Kelola pembayaran / piutang | Ya | Ya | Ya | Ya | Tidak | Tidak |
| Cetak Invoice / Thermal | Ya | Ya | Ya | Ya | Surat Jalan saja | Tidak |
| Lihat master produk | Ya | Ya | Ya | Ya | Ya | Ya |
| Lihat harga jual | Ya | Ya | Ya | Ya | Tidak | Ya |
| Lihat HPP | Ya | Ya | Tidak | Ya | Tidak | Tidak |
| Tambah/Edit produk, varian, barcode | Ya | Ya | Tidak | Tidak | Tidak | Tidak |
| Update stok/minimum stok | Ya | Ya | Tidak | Tidak | Ya | Tidak |
| Stock Opname | Ya | Ya | Tidak | Tidak | Ya | Tidak |
| Recipe / BOM | Ya | Ya | Tidak | Tidak | Ya | Tidak |
| Purchase Order | Ya | Ya | Tidak | Ya | Lihat/Terima | Tidak |
| Nilai PO / harga beli / hutang supplier | Ya | Ya | Tidak | Ya | **Disembunyikan** | Tidak |
| Supplier | Ya | Ya | Tidak | Ya | Lihat kontak | Tidak |
| CRM / Member | Ya | Ya | Tambah/Edit profil | Lihat | Tidak | Tidak |
| Ubah saldo point secara manual | Tidak lewat UI | Tidak lewat UI | Tidak | Tidak | Tidak | Tidak |
| Atur Point/Pajak/Service default | Ya | Ya | Tidak | Tidak | Tidak | Tidak |
| Biaya | Ya | Ya | Tidak | Ya | Tidak | Tidak |
| Laporan finansial | Ya | Ya | Tidak | Ya | Tidak | Tidak |
| Export / Backup | Ya | Ya | Tidak | Ya | Tidak | Tidak |
| Audit Log | Ya | Ya | Tidak | Tidak | Tidak | Tidak |
| Tim & Role | Kelola | Lihat | Tidak | Tidak | Tidak | Tidak |
| Pengaturan akun sendiri | Ya | Ya | Ya | Ya | Ya | Ya |

## Menu desktop yang terlihat

- **Owner:** Dashboard, Kasir, Produk, Pembelian, Biaya, Pelanggan, Laporan, Tim & Role, Audit Log, Pengaturan.
- **Admin:** Dashboard, Kasir, Produk, Pembelian, Biaya, Pelanggan, Laporan, Tim & Role, Audit Log, Pengaturan.
- **Kasir:** Dashboard, Kasir, Produk, Pelanggan, Pengaturan.
- **Finance:** Dashboard, Produk, Pembelian, Biaya, Pelanggan, Laporan, Pengaturan. Menu Kasir sengaja tidak ditampilkan.
- **Gudang:** Dashboard, Pengiriman, Produk, Pembelian, Pengaturan.
- **Staff:** Dashboard, Produk, Pengaturan.

## Prinsip pembatasan penting

1. **Kasir tidak mengedit transaksi selesai.** Koreksi operasional dilakukan melalui Refund/Void oleh Owner/Admin agar jejak transaksi tetap ada.
2. **Gudang tidak menerima nilai finansial PO.** Total PO, paid amount, unit cost, line total dan hutang supplier dimasking di RPC Cloud.
3. **Gudang hanya boleh mengubah stock/min_stock.** Barcode, varian, inventory mode, SKU, nama, kategori, harga dan HPP dijaga pada database trigger.
4. **Kasir boleh mengubah profil member, bukan saldo point.** Grant kolom Customer membatasi Kasir ke nama/kontak/alamat/catatan; point, total spend dan visit counter dikelola RPC transaksi.
5. **Finance tidak membuka POS.** Finance tetap dapat membaca penjualan/pembayaran untuk rekonsiliasi dan laporan.
6. **Staff bersifat read-only.** Dashboard dasar dan master produk saja; tidak ada transaksi, pembelian, customer, atau finansial.
