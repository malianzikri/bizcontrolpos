#!/usr/bin/env python3
from pathlib import Path
import sys, re, shutil

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 apply-auto-demo-appjs.py app.js")

src = Path(sys.argv[1])

if not src.exists():
    raise SystemExit(f"❌ File tidak ditemukan: {src}")

js = src.read_text(encoding="utf-8")

marker = "const demoRequested = new URLSearchParams(location.search).get('demo') === '1';"

if marker in js:
    print("✅ Auto Demo sudah terpasang di app.js. Tidak ada perubahan.")
    raise SystemExit(0)

if "function enterDemoSandbox()" not in js:
    raise SystemExit(
        "❌ function enterDemoSandbox() tidak ditemukan di app.js.\n"
        "Patch dibatalkan agar aman."
    )

if "loadRecoverySessionFromUrl" not in js:
    raise SystemExit(
        "❌ loadRecoverySessionFromUrl tidak ditemukan di app.js.\n"
        "Patch dibatalkan agar aman."
    )

# Cari blok session Cloud di area akhir file / Boot.
# Struktur aktual user:
# if(state.cloudConfig&&state.session){state.mode='cloud';cloudBootstrap();}
# else {state.mode='local';setAuthMode('login');showAuth();}
pattern = re.compile(
    r"if\s*\(\s*state\.cloudConfig\s*&&\s*state\.session\s*\)\s*\{\s*"
    r"state\.mode\s*=\s*['\"]cloud['\"]\s*;\s*"
    r"cloudBootstrap\(\)\s*;\s*\}",
    re.MULTILINE
)

matches = list(pattern.finditer(js))
if not matches:
    raise SystemExit(
        "❌ Blok Boot `if(state.cloudConfig&&state.session)` tidak ditemukan.\n"
        "Patch dibatalkan. Jangan edit manual dulu."
    )

# Ambil match TERAKHIR karena yang terakhir adalah Boot app.
m = matches[-1]
insert_at = m.start()

insert = """// Direct Demo entry dari landing page.
  // Visitor baru tanpa session Cloud + ?demo=1 langsung masuk Demo.
  // User existing yang masih login tetap masuk akun Cloud.
  const demoRequested = new URLSearchParams(location.search).get('demo') === '1';
  if(demoRequested && !(state.cloudConfig && state.session)){
    enterDemoSandbox();
    return;
  }
  """

backup = src.with_name(src.name + ".before-auto-demo.bak")
if not backup.exists():
    shutil.copy2(src, backup)

patched = js[:insert_at] + insert + js[insert_at:]
src.write_text(patched, encoding="utf-8")

# QA
new_js = src.read_text(encoding="utf-8")
ok = all([
    marker in new_js,
    "enterDemoSandbox();" in new_js,
    "loadRecoverySessionFromUrl" in new_js,
    "cloudBootstrap();" in new_js
])

print("✅ PATCH BERHASIL" if ok else "⚠️ Patch ditulis, tetapi QA perlu dicek")
print(f"File   : {src}")
print(f"Backup : {backup}")
print("")
print("Setelah deploy:")
print("URL normal    -> tetap Login")
print("URL ?demo=1   -> visitor baru langsung Demo")
print("")
print("Tes sebaiknya pakai Incognito agar tidak membawa session Cloud lama.")
