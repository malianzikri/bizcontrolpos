#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 apply-auto-demo-v188.py path/to/index.html")

src = Path(sys.argv[1])
html = src.read_text(encoding="utf-8")

old = """// -------- Boot --------
(async()=>{
  // Remove legacy user-editable cloud configuration from older builds.
  localStorage.removeItem('bc_cloud_config');
  state.cloudConfig=loadCloudConfig();state.session=loadSession();setAuthMode('login');
  try{if(await loadRecoverySessionFromUrl())return;}catch(err){clearSession();setAuthMode('login');showAuth();toast(err.message,'error',7000);return;}
  if(state.cloudConfig&&state.session){state.mode='cloud';cloudBootstrap();}
  else {state.mode='local';setAuthMode('login');showAuth();}
})();"""

new = """// -------- Boot --------
(async()=>{
  // Remove legacy user-editable cloud configuration from older builds.
  localStorage.removeItem('bc_cloud_config');
  state.cloudConfig=loadCloudConfig();state.session=loadSession();setAuthMode('login');

  // Auth recovery / invite selalu diprioritaskan agar link undangan/reset tetap aman.
  try{
    if(await loadRecoverySessionFromUrl())return;
  }catch(err){
    clearSession();
    setAuthMode('login');
    showAuth();
    toast(err.message,'error',7000);
    return;
  }

  // Paid-traffic / landing-page demo shortcut.
  // Hanya auto-demo jika visitor BELUM memiliki session Cloud.
  // Jadi user existing yang masih login tidak dipaksa keluar dari akun.
  const demoRequested = new URLSearchParams(location.search).get('demo') === '1';

  if(demoRequested && !(state.cloudConfig && state.session)){
    enterDemoSandbox();
    return;
  }

  if(state.cloudConfig&&state.session){
    state.mode='cloud';
    cloudBootstrap();
  }else{
    state.mode='local';
    setAuthMode('login');
    showAuth();
  }
})();"""

if new in html:
    print("Patch sudah terpasang. Tidak ada perubahan.")
    raise SystemExit(0)

if old not in html:
    raise SystemExit(
        "Boot block V1.8.8 tidak ditemukan persis. "
        "Pastikan file yang dipatch adalah BizControl Online V1.8.8."
    )

backup = src.with_suffix(src.suffix + ".before-auto-demo.bak")
backup.write_text(html, encoding="utf-8")

html = html.replace(old, new, 1)
src.write_text(html, encoding="utf-8")

print(f"PATCH OK: {src}")
print(f"BACKUP  : {backup}")
print("Tes URL: https://URL-POS-KAMU/?demo=1")
