# BizControl Online V1.7 — Beta Test Plan

## Tujuan
Memastikan user UMKM dapat menggunakan alur inti tanpa pendampingan intensif dan memastikan data yang dibuat dari HP/laptop tetap konsisten.

## Target peserta
Minimal **5 user**, ideal **10 user UMKM** dengan variasi:
- toko/retail;
- jasa;
- kuliner;
- material/distribusi;
- usaha dengan transaksi tempo/piutang.

## Durasi
3–7 hari penggunaan ringan per peserta sudah cukup untuk beta pertama.

## Jangan terlalu banyak mengajari
Berikan:
1. URL/demo BizControl;
2. akun beta;
3. petunjuk singkat 1 halaman;
4. minta mereka mencoba sendiri.

Catat setiap titik ketika user bertanya atau salah input.

## Skenario wajib

### A. Login & role
- Owner login.
- Tambah user Kasir.
- Kasir login dari perangkat berbeda.
- Pastikan Kasir tidak melihat menu owner-only seperti Audit Log/Tim.

### B. Produk
- Input 5 produk nyata.
- Edit harga 1 produk.
- Ubah stok 1 produk.

### C. Kasir
- Buat 3 transaksi:
  - cash lunas;
  - transfer lunas;
  - transaksi tempo / DP.
- Pastikan nomor invoice otomatis dan unik.

### D. Pembayaran
- Tambah cicilan kedua pada transaksi tempo.
- Cetak kwitansi pembayaran tersebut.
- Bayar sisa sampai lunas.

### E. Dokumen
- Cetak Invoice.
- Cetak Kwitansi.
- Cetak Surat Jalan.
- Pastikan nomor dokumen berbeda dan mudah dibaca.

### F. Cloud sync
- Buka bisnis yang sama di HP dan laptop.
- Buat transaksi dari HP.
- Pastikan data muncul di laptop tanpa reload manual atau setelah fallback sync maksimal ±10 detik.

### G. Delete security
- Coba hapus dengan Security Key salah.
- Coba hapus dengan Security Key benar.
- Cek Audit Log.

### H. Export
- Export Produk CSV.
- Export Penjualan CSV.
- Buka hasilnya di Excel.

## Pertanyaan akhir ke peserta
1. Seberapa mudah digunakan? 1–5.
2. Bagian mana yang paling membingungkan?
3. Apakah istilah yang digunakan mudah dipahami?
4. Apakah kamu percaya angka di dashboard?
5. Apakah kamu mau memakai ini sehari-hari?
6. Fitur apa yang paling berguna?
7. Apa satu hal yang harus diperbaiki sebelum kamu mau bayar?
8. Berapa harga bulanan yang terasa wajar?

## Kriteria lulus beta pertama
- ≥ 80% peserta berhasil login tanpa bantuan teknis.
- ≥ 80% berhasil input produk.
- ≥ 80% berhasil membuat transaksi.
- ≥ 80% memahami Lunas / Belum Lunas.
- ≥ 80% berhasil membuat pembayaran kedua.
- ≥ 80% berhasil mencetak salah satu dokumen.
- Tidak ada transaksi ganda pada test normal.
- Tidak ada kehilangan data kritis.
- Rata-rata skor kemudahan ≥ 4/5.

## Aturan keputusan
- Masalah muncul 1 kali → catat.
- Masalah sama muncul ≥ 3 peserta → prioritas perbaikan.
- Error yang mengubah uang/stok/piutang → PRIORITAS CRITICAL walau hanya 1 kasus.
