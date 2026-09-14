# Thermal Print QA — BizControl V1.9.2

Status: PASS

Checks:
- JavaScript syntax (`node --check app.js`) PASS.
- Popup transaksi selesai menampilkan Invoice A4 dan Struk Thermal.
- Pemilih ukuran menampilkan Thermal 58mm dan Thermal 80mm.
- Renderer 58mm menampilkan bisnis, invoice, item, total, uang diterima, dan kembalian pada transaksi Cash.
- Renderer 80mm menampilkan multi-item dengan lebar print 80mm.
- Cetak ulang dari modal dokumen tetap menyediakan Invoice A4 dan Struk Thermal.
- Invoice A4 lama tetap dipertahankan.
- Tidak ada migration SQL baru untuk V1.9.2.

Catatan: browser QA dijalankan dengan test harness in-memory karena akses localhost/file dibatasi oleh environment. Satu error localStorage pada origin test harness diabaikan karena berasal dari origin opaque test harness, bukan dari kode thermal print.
