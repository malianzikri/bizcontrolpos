# Production Checklist — BizControl Online V1.7

## Database
- [ ] `migration-v1.7-production-foundations.sql` berhasil dijalankan.
- [ ] RLS aktif pada seluruh tabel exposed.
- [ ] `supabase_realtime` publication memuat `sync_events` dan Realtime client menerima sinyal perubahan.
- [ ] Security Key owner sudah dibuat.
- [ ] Test role Kasir tidak bisa mengubah biaya dan tidak menerima HPP/laba dari RPC.
- [ ] Test role Finance tidak bisa membuat penjualan.
- [ ] Test role Gudang hanya bisa mengubah stok/min stok, bukan HPP/harga/master produk.

## Dokumen
- [ ] Invoice baru berformat `INV-YYYY-######`.
- [ ] Kwitansi baru berformat `KWT-YYYY-######`.
- [ ] Surat Jalan baru berformat `SJ-YYYY-######`.
- [ ] Tidak ada nomor duplikat saat dua perangkat membuat transaksi berdekatan.

## Sync
- [ ] HP → Laptop.
- [ ] Laptop → HP.
- [ ] Internet diputus ketika form masih terbuka.
- [ ] Retry tidak menghasilkan transaksi ganda.
- [ ] Session yang kedaluwarsa dapat refresh atau diarahkan login ulang.

## Kasir
- [ ] Penjualan mengurangi stok.
- [ ] Edit qty mengoreksi stok.
- [ ] Hapus transaksi mengembalikan stok.
- [ ] Pembayaran tidak melebihi invoice.
- [ ] Hapus pembayaran menambah piutang kembali.

## Export / Backup
- [ ] Backup JSON berhasil diunduh.
- [ ] Produk CSV terbuka di Excel.
- [ ] Penjualan CSV terbuka di Excel.
- [ ] Pembayaran CSV terbuka di Excel.
- [ ] Biaya CSV terbuka di Excel.

## UX
- [ ] Tidak ada modal terpotong pada HP.
- [ ] Tombol submit disabled saat saving.
- [ ] Error jaringan tampil ke user.
- [ ] Role tampil jelas.
- [ ] Menu menyesuaikan role.

## Beta
- [ ] Minimal 5 UMKM sudah mencoba.
- [ ] Feedback dicatat.
- [ ] Critical bug = 0 sebelum launch berbayar.
