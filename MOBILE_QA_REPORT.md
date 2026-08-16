# BizControl Online V1.7.1 — Mobile QA Report

Viewport test utama: **390 × 844 px**.

## Hasil

- Kasir: PASS — tabel berubah menjadi kartu, tanpa horizontal overflow.
- Produk: PASS — kartu mobile, HPP/harga/stok tetap mudah dibaca sesuai role.
- Biaya: PASS — deskripsi dan nilai diprioritaskan.
- Laporan: PASS — tren 6 bulan berubah menjadi kartu per bulan.
- Audit Log: PASS — tabel menjadi kartu dan tombol detail tetap aktif.
- Tim & Role: PASS — tabel menjadi kartu.
- Riwayat Pembayaran: PASS — tabel popup menjadi kartu dan aksi kwitansi/edit/hapus tetap usable.
- JavaScript page errors pada skenario di atas: **0**.
- Lebar konten tabel di viewport 390 px: **tidak melebihi container**.

## Perilaku responsive

- Desktop > 760 px: tabel biasa.
- Mobile ≤ 760 px: satu baris tabel = satu card.
- Mobile sangat kecil ≤ 350 px: field card menjadi satu kolom.
- Tombol aksi mobile minimum ±39 px dan ditata grid agar mudah disentuh.

Update ini hanya mengubah UI/responsiveness. **Tidak membutuhkan migration Supabase/database.**
