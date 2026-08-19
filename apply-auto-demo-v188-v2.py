#!/usr/bin/env python3
from pathlib import Path
import sys, re, shutil

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 apply-auto-demo-v188-v2.py index.html")

src = Path(sys.argv[1])

if not src.exists():
    raise SystemExit(f"File tidak ditemukan: {src}")

html = src.read_text(encoding="utf-8")

# Jangan patch dua kali.
if "const demoRequested = new URLSearchParams(location.search).get('demo') === '1';" in html:
    print("✅ Auto Demo sudah terpasang. Tidak ada perubahan.")
    raise SystemExit(0)

# Pastikan ini memang terlihat seperti BizControl yang punya fungsi Demo.
if "enterDemoSandbox" not in html:
    raise SystemExit(
        "❌ Fungsi enterDemoSandbox() tidak ditemukan.\n"
        "Pastikan index.html yang dipilih memang file utama BizControl Online."
    )

# Cari marker Boot.
boot_marker = "// -------- Boot --------"
boot_pos = html.find(boot_marker)

if boot_pos == -1:
    # fallback jika marker berubah sedikit: cari boot berdasarkan recovery/session area
    recovery_pos = html.find("loadRecoverySessionFromUrl")
    if recovery_pos == -1:
        raise SystemExit(
            "❌ Area Boot tidak ditemukan (marker Boot dan loadRecoverySessionFromUrl tidak ada).\n"
            "Jangan lanjut patch otomatis. Kirim bagian paling bawah index.html ke ChatGPT."
        )
    boot_pos = max(0, recovery_pos - 1800)

# Batasi pencarian ke area setelah Boot agar tidak menyentuh if lain di aplikasi.
region_end = min(len(html), boot_pos + 10000)
region = html[boot_pos:region_end]

# Pastikan recovery/auth memang berada di area ini.
if "loadRecoverySessionFromUrl" not in region:
    raise SystemExit(
        "❌ Marker Boot ditemukan, tetapi flow recovery tidak ditemukan di area Boot.\n"
        "Patch dibatalkan agar aman."
    )

# Cari if session Cloud dengan toleransi whitespace/minified.
pattern = re.compile(
    r'if\s*\(\s*state\.cloudConfig\s*&&\s*state\.session\s*\)\s*\{',
    re.MULTILINE
)
m = pattern.search(region)

if not m:
    raise SystemExit(
        "❌ Pengecekan session Cloud tidak ditemukan di area Boot.\n"
        "Patch dibatalkan. Jalankan:\n"
        "grep -n \"cloudConfig.*session\" index.html | tail -20\n"
        "lalu kirim hasilnya."
    )

absolute_insert = boot_pos + m.start()

insert = """  // Direct Demo entry dari landing page / Meta Ads.
  // Visitor tanpa session Cloud + ?demo=1 langsung masuk Demo.
  // User existing yang masih login tetap masuk akun Cloud.
  const demoRequested = new URLSearchParams(location.search).get('demo') === '1';

  if(demoRequested && !(state.cloudConfig && state.session)){
    enterDemoSandbox();
    return;
  }

"""

# Backup satu kali.
backup = src.with_name(src.name + ".before-auto-demo-v2.bak")
if not backup.exists():
    shutil.copy2(src, backup)

patched = html[:absolute_insert] + insert + html[absolute_insert:]
src.write_text(patched, encoding="utf-8")

# QA sederhana.
new_html = src.read_text(encoding="utf-8")
checks = {
    "demoRequested": "const demoRequested" in new_html,
    "enterDemoSandbox call": "if(demoRequested && !(state.cloudConfig && state.session))" in new_html,
    "Boot marker/recovery": "loadRecoverySessionFromUrl" in new_html,
}

print("✅ PATCH BERHASIL")
print(f"File   : {src}")
print(f"Backup : {backup}")
for k,v in checks.items():
    print(f"{'✅' if v else '❌'} {k}")

print("\nSetelah deploy, tes:")
print("1) URL normal     -> tetap Login")
print("2) URL + ?demo=1  -> langsung Demo (untuk visitor tanpa session Cloud)")
