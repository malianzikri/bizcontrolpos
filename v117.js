/* BizControl Online V1.17 — Production Readiness
   - Subscription / entitlement status + safe read-only expiry
   - Guided onboarding
   - Backup verification + backup history
   - Client health/error telemetry
   - Safe offline degraded mode (read-only, no offline transaction queue)
   - Admin Sistem subscription controls
*/
(() => {
'use strict';
const BC117_VERSION='1.17.0';
const _cloudRequestV117Base=cloudRequest;
const _renderV117Base=render;
const _renderDashboardV117Base=renderDashboard;
const _renderSettingsV117Base=renderSettingsPage;
const _renderSystemAdminV117Base=renderSystemAdmin;
const _cloudLoadBusinessDataV117Base=cloudLoadBusinessData;
const _loadManagedOwnersV117Base=loadManagedOwners;
const _handleActionV117Base=handleAction;
const _refreshPosSummaryV117Base=refreshPosSummary;
const _exportJsonV117Base=exportJson;

function ensureV117State(){
  if(state.entitlement===undefined)state.entitlement=null;
  if(state.onboarding===undefined)state.onboarding=null;
  if(!Array.isArray(state.appEvents))state.appEvents=[];
  if(!Array.isArray(state.backupEvents))state.backupEvents=[];
  if(!Array.isArray(state.managedSubscriptions))state.managedSubscriptions=[];
  if(!Array.isArray(state.saasPlans))state.saasPlans=[];
}
function v117Status(){return String(state.entitlement?.effective_status||state.entitlement?.status||'unknown').toLowerCase()}
function v117CanWrite(){
  if(state.mode!=='cloud')return true;
  if(!navigator.onLine)return false;
  if(!state.entitlement)return true; // DB trigger remains authoritative until entitlement finishes loading.
  return state.entitlement.can_write!==false && ['trial','active','grace'].includes(v117Status());
}
function v117WriteReason(){
  if(state.mode!=='cloud')return '';
  if(!navigator.onLine)return 'Internet sedang terputus. Untuk menjaga stok, invoice, dan pembayaran tetap konsisten, perubahan data dinonaktifkan sampai koneksi kembali.';
  const s=v117Status();
  if(['expired','suspended'].includes(s))return s==='suspended'?'Akun bisnis sedang disuspend. Data tetap dapat dilihat dan dibackup, tetapi perubahan data dinonaktifkan.':'Masa aktif BizControl sudah berakhir. Data tetap dapat dilihat dan dibackup, tetapi perubahan data dinonaktifkan sampai subscription diperpanjang.';
  return '';
}
function isMutationCloudRequest(path,opts={}){
  const method=String(opts?.method||'GET').toUpperCase();
  if(['GET','HEAD','OPTIONS'].includes(method))return false;
  const m=String(path||'').match(/\/rest\/v1\/rpc\/([A-Za-z0-9_]+)/);
  if(m){
    const n=m[1];
    if(/^(list_|get_|can_|is_|check_|verify_|search_|v117_effective)/.test(n))return false;
    if(['log_client_event_v117','record_backup_event_v117','activate_pending_memberships','activate_owner_account'].includes(n))return false;
    return true;
  }
  return /\/rest\/v1\//.test(String(path||''));
}
function sanitizeEventMessage(v){return String(v||'Unknown error').replace(/sb_(publishable|secret)_[A-Za-z0-9._-]+/g,'[key]').replace(/Bearer\s+[A-Za-z0-9._-]+/gi,'Bearer [token]').slice(0,900)}
const eventThrottle=new Map();
async function logClientEvent(level,code,message,context={}){
  ensureV117State();
  if(state.mode!=='cloud'||!state.currentBusinessId||!state.session?.access_token||!navigator.onLine)return;
  const msg=sanitizeEventMessage(message);const key=`${level}:${code}:${msg}`;const now=Date.now();
  if(now-(eventThrottle.get(key)||0)<60000)return;eventThrottle.set(key,now);
  const safeContext={page:state.page||'',role:currentRole(),online:navigator.onLine,app_version:BC117_VERSION,...context};
  delete safeContext.token;delete safeContext.password;delete safeContext.authorization;delete safeContext.customer;delete safeContext.phone;
  try{await _cloudRequestV117Base('/rest/v1/rpc/log_client_event_v117',{method:'POST',body:{p_bid:state.currentBusinessId,p_level:level,p_code:String(code||'CLIENT').slice(0,100),p_message:msg,p_context:safeContext}})}catch{}
}
cloudRequest=async function(path,opts={}){
  ensureV117State();
  if(isMutationCloudRequest(path,opts)&&!v117CanWrite())throw new Error(v117WriteReason()||'Akun sedang read-only');
  try{return await _cloudRequestV117Base(path,opts)}catch(err){
    const msg=String(err?.message||err||'Cloud request failed');
    if(navigator.onLine&&!/Tidak diizinkan|tidak memiliki akses|stok tidak cukup|PLAN_|SUBSCRIPTION_READ_ONLY/i.test(msg)) logClientEvent('error','CLOUD_REQUEST_FAILED',msg,{endpoint:String(path||'').split('?')[0],method:String(opts?.method||'GET').toUpperCase()});
    throw err;
  }
};

function subscriptionLabel(){return ({trial:'Trial',active:'Aktif',grace:'Masa Tenggang',expired:'Expired',suspended:'Suspended',unknown:'Belum Terbaca'})[v117Status()]||v117Status()}
function subscriptionClass(){const s=v117Status();return ['active'].includes(s)?'good':['trial','grace','unknown'].includes(s)?'warn':'bad'}
function subscriptionEndLabel(){const e=state.entitlement?.period_end;if(!e)return 'Tanpa tanggal berakhir';try{return new Date(e).toLocaleDateString('id-ID',{day:'2-digit',month:'short',year:'numeric'})}catch{return '-'}}
function subscriptionBannerHtml(){
  if(state.mode!=='cloud'||!state.entitlement)return '';
  const s=v117Status();
  if(s==='active')return '';
  const text=s==='trial'?`Trial ${state.entitlement.plan_name||''} aktif sampai ${subscriptionEndLabel()}.`:s==='grace'?`Subscription memasuki masa tenggang. Perpanjang sebelum akses tulis dinonaktifkan.`:v117WriteReason();
  return `<div class="subscription-banner ${subscriptionClass()}"><div><b>${escapeHtml(subscriptionLabel())}</b><span>${escapeHtml(text)}</span></div>${currentRole()==='owner'?'<button type="button" class="ghost" data-action="contact-admin">Hubungi Admin</button>':''}</div>`;
}
function connectivityBanner(){
  let el=document.getElementById('v117ConnectivityBanner');
  if(!el){el=document.createElement('div');el.id='v117ConnectivityBanner';el.className='connectivity-banner hidden';document.querySelector('.main')?.insertBefore(el,document.querySelector('.topbar')?.nextSibling||document.querySelector('.page-content'));}
  const offline=state.mode==='cloud'&&!navigator.onLine;el.classList.toggle('hidden',!offline);if(offline)el.innerHTML='<b>Mode Offline Aman</b><span>Data yang sudah terbuka tetap dapat dilihat. Transaksi dan perubahan data diblokir sampai koneksi kembali untuk mencegah duplikasi stok/invoice.</span>';
}

function onboardingProgress(){
  const b=activeBusiness()||{};const profile=Boolean(String(b.address||'').trim()&&String(b.phone||'').trim());
  const product=businessData(state.products||[]).length>0;
  const printer=Boolean(state.onboarding?.printer_tested_at);
  const sale=businessData(state.sales||[]).length>0;
  const steps=[['profile','Profil usaha',profile],['product','Produk pertama',product],['printer','Tes printer',printer],['sale','Transaksi pertama',sale]];
  return {steps,done:steps.filter(x=>x[2]).length,total:steps.length,complete:steps.every(x=>x[2])};
}
function onboardingHtml(){
  if(state.mode!=='cloud'||!['owner','admin'].includes(currentRole())||!state.currentBusinessId)return '';
  const p=onboardingProgress();
  if(p.complete)return `<div class="panel onboarding-complete"><div><b>✓ Setup bisnis selesai</b><span>Profil, produk, printer, dan transaksi pertama sudah siap.</span></div><span class="pill good">${p.done}/${p.total}</span></div>`;
  return `<div class="panel onboarding-panel"><div class="panel-title"><div><h3>Mulai Pakai BizControl</h3><span>${p.done}/${p.total} langkah selesai</span></div><span class="pill warn">SETUP</span></div><div class="onboarding-progress"><i style="width:${(p.done/p.total)*100}%"></i></div><div class="onboarding-list">${p.steps.map(([id,label,done])=>`<button type="button" class="onboarding-step ${done?'done':''}" data-action="onboarding-${id}"><b>${done?'✓':'○'} ${escapeHtml(label)}</b><span>${done?'Selesai':'Atur sekarang'} →</span></button>`).join('')}</div></div>`;
}
async function markPrinterTested(){
  if(state.mode==='cloud'&&state.currentBusinessId){await cloudRequest(`/rest/v1/business_onboarding?business_id=eq.${encodeURIComponent(state.currentBusinessId)}`,{method:'PATCH',body:{printer_tested_at:new Date().toISOString(),updated_at:new Date().toISOString()}});state.onboarding={...(state.onboarding||{}),printer_tested_at:new Date().toISOString()};}
}
function printTestReceipt(){
  const b=activeBusiness()||{};const w=window.open('','_blank','width=420,height=640');if(!w)return toast('Popup printer diblokir browser','error');
  const html=`<!doctype html><html><head><title>Tes Printer BizControl</title><style>@page{size:80mm auto;margin:4mm}body{font-family:Arial,sans-serif;width:72mm;margin:0 auto;font-size:12px;color:#111}.c{text-align:center}.line{border-top:1px dashed #333;margin:8px 0}h2{font-size:16px;margin:0 0 4px}p{margin:3px 0}</style></head><body><div class="c"><h2>${escapeHtml(b.name||'BizControl')}</h2><p>TES PRINTER · V1.17</p></div><div class="line"></div><p>Jika teks ini tercetak jelas, printer siap digunakan.</p><p>Tanggal: ${new Date().toLocaleString('id-ID')}</p><div class="line"></div><p class="c">BizControl POS</p></body></html>`;
  w.document.open();w.document.write(html);w.document.close();setTimeout(()=>{try{w.focus();w.print()}catch{}},180);markPrinterTested().then(()=>{render();toast('Tes printer ditandai selesai','success')}).catch(()=>{});
}

function healthStats(){
  const now=Date.now(),day=86400000;const events=state.appEvents||[];const recent=events.filter(x=>now-new Date(x.created_at||0).getTime()<=day);return {errors:recent.filter(x=>x.level==='error').length,warnings:recent.filter(x=>x.level==='warning').length,last:events[0]||null};
}
function healthHtml(){
  if(state.mode!=='cloud'||!['owner','admin'].includes(currentRole()))return '';
  const h=healthStats();const lastBackup=(state.backupEvents||[])[0];
  return `<div class="setting-block"><h3>System Health</h3><p class="muted">Monitoring ringan untuk koneksi dan error aplikasi. Tidak menyimpan password/token/customer pada telemetry.</p><div class="health-status-grid"><div><span>Koneksi</span><b class="${navigator.onLine?'status-good':'status-warn'}">${navigator.onLine?'Online':'Offline'}</b></div><div><span>Error 24 jam</span><b>${num(h.errors)}</b></div><div><span>Warning 24 jam</span><b>${num(h.warnings)}</b></div><div><span>Backup terakhir</span><b>${lastBackup?new Date(lastBackup.created_at).toLocaleString('id-ID'):'Belum tercatat'}</b></div></div>${h.last?`<div class="form-note">Event terakhir: ${escapeHtml(h.last.code||h.last.level)} · ${escapeHtml(String(h.last.message||'').slice(0,180))}</div>`:''}</div>`;
}
function subscriptionSettingsHtml(){
  if(state.mode!=='cloud'||!state.entitlement)return '';
  const e=state.entitlement;return `<div class="setting-block subscription-card"><div class="status-row"><div><h3>Paket & Masa Aktif</h3><p class="muted">Paket <b>${escapeHtml(e.plan_name||e.plan_code||'-')}</b> · berakhir ${escapeHtml(subscriptionEndLabel())}</p></div><span class="pill ${subscriptionClass()}">${escapeHtml(subscriptionLabel())}</span></div>${!v117CanWrite()?`<div class="form-note danger-note">${escapeHtml(v117WriteReason())}</div>`:''}${currentRole()==='owner'?'<button class="soft-btn" data-action="contact-admin">Perpanjang / Ubah Paket</button>':''}</div>`;
}
function backupCenterHtml(){
  if(state.mode==='cloud'&&!can('export'))return '';
  const last=(state.backupEvents||[])[0];return `<div class="setting-block"><h3>Backup Verification & Restore</h3><p class="muted">Gunakan Backup JSON pada bagian Backup & Export di atas. V1.17 menambah verifikasi file sebelum file dipercaya sebagai backup. Restore production tetap melalui prosedur admin/database agar tidak menimpa data tanpa kontrol.</p><div class="toolbar-left"><button class="ghost" data-action="verify-backup">Verifikasi File Backup</button></div><div class="micro">${last?`Aktivitas backup terakhir: ${new Date(last.created_at).toLocaleString('id-ID')}`:'Belum ada aktivitas backup V1.17.'}</div></div>`;
}

renderDashboard=function(){ensureV117State();return subscriptionBannerHtml()+onboardingHtml()+_renderDashboardV117Base()};
renderSettingsPage=function(){
  ensureV117State();let base=_renderSettingsV117Base();base=base.replace(/V1\.16[^<]*/g,'V1.17 · Production Ready');
  const insert=subscriptionSettingsHtml()+healthHtml()+backupCenterHtml();return `<div class="v117-settings-head">${subscriptionBannerHtml()}</div>`+base+`<div class="panel v117-production-panel"><div class="panel-title"><div><h3>Production Readiness</h3><span>V1.17</span></div></div>${insert}</div>`;
};

function adminSubscriptionTable(){
  if(!state.isSystemAdmin)return '';
  const rows=state.managedSubscriptions||[];
  return `<div class="panel admin-subscription-panel"><div class="panel-title"><div><h3>Subscription SaaS</h3><span>${rows.length} bisnis terdaftar</span></div><span class="code-chip">V1.17</span></div><div class="table-wrap"><table><thead><tr><th>Bisnis</th><th>Owner</th><th>Paket</th><th>Status</th><th>Berakhir</th><th>Aksi</th></tr></thead><tbody>${rows.length?rows.map(r=>`<tr><td><b>${escapeHtml(r.business_name||'-')}</b></td><td>${escapeHtml(r.owner_email||'-')}</td><td>${escapeHtml(r.plan_code||'-')}</td><td><span class="pill ${['active'].includes(r.effective_status)?'good':['trial','grace'].includes(r.effective_status)?'warn':'bad'}">${escapeHtml(r.effective_status||r.status||'-')}</span></td><td>${r.period_end?new Date(r.period_end).toLocaleDateString('id-ID'):'Tanpa batas'}</td><td><button class="row-action edit" data-action="manage-subscription" data-id="${escapeAttr(r.business_id)}">Kelola</button></td></tr>`).join(''):'<tr><td colspan="6"><div class="empty">Belum ada data subscription.</div></td></tr>'}</tbody></table></div></div>`;
}
renderSystemAdmin=function(){return _renderSystemAdminV117Base()+adminSubscriptionTable()};
loadManagedOwners=async function(){await _loadManagedOwnersV117Base();if(state.mode==='cloud'&&state.isSystemAdmin){try{const r=await invokeAccountAdmin('list-subscriptions',{});state.managedSubscriptions=r?.rows||[];state.saasPlans=r?.plans||[]}catch(e){console.warn('subscription admin:',e.message);state.managedSubscriptions=[];state.saasPlans=[]}}};
function toDateInput(v){if(!v)return '';const d=new Date(v);if(Number.isNaN(d.getTime()))return '';return d.toISOString().slice(0,10)}
function subscriptionAdminModal(bid){
  const row=(state.managedSubscriptions||[]).find(x=>x.business_id===bid);if(!row)return;const plans=state.saasPlans||[];
  openModal(`<div class="modal-title"><h2>Subscription · ${escapeHtml(row.business_name||'-')}</h2><button class="modal-close">×</button></div><form id="subscriptionAdminForm" class="form-grid"><label>Paket<select name="plan_code">${plans.map(p=>`<option value="${escapeAttr(p.code)}" ${p.code===row.plan_code?'selected':''}>${escapeHtml(p.name)} · ${p.max_team_users||'∞'} user · ${p.max_products||'∞'} produk</option>`).join('')}</select></label><label>Status<select name="status">${['trial','active','grace','expired','suspended'].map(s=>`<option value="${s}" ${s===row.status?'selected':''}>${s}</option>`).join('')}</select></label><label>Aktif Sampai<input type="date" name="period_end" value="${escapeAttr(toDateInput(row.period_end))}"></label><label>Grace Sampai<input type="date" name="grace_until" value="${escapeAttr(toDateInput(row.grace_until))}"></label><label class="span-2">Catatan<input name="notes" maxlength="500" value="${escapeAttr(row.notes||'')}"></label><div class="span-2 form-note">Kosongkan Aktif Sampai untuk subscription tanpa batas. Expired/Suspended membuat bisnis read-only; data tetap dapat dibaca dan dibackup.</div><div class="span-2 modal-actions"><button type="button" class="ghost modal-close">Batal</button><button class="primary">Simpan Subscription</button></div></form>`);
  $('#subscriptionAdminForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target);const end=String(f.get('period_end')||''),grace=String(f.get('grace_until')||'');const iso=x=>x?new Date(x+'T23:59:59').toISOString():null;try{await invokeAccountAdmin('set-subscription',{business_id:bid,plan_code:f.get('plan_code'),status:f.get('status'),period_end:iso(end),grace_until:iso(grace),notes:f.get('notes')});await loadManagedOwners();closeModal();render();toast('Subscription diperbarui','success')}catch(err){toast(err.message,'error')}};
}

async function loadV117BusinessData(){
  if(state.mode!=='cloud'||!state.currentBusinessId)return;const b=encodeURIComponent(state.currentBusinessId);const role=currentRole();
  try{state.entitlement=await cloudRequest('/rest/v1/rpc/get_business_entitlement_v117',{method:'POST',body:{p_bid:state.currentBusinessId}})}catch(e){state.entitlement=null;console.warn('entitlement:',e.message)}
  if(['owner','admin'].includes(role)){
    const [onboarding,events,backups]=await Promise.all([
      cloudRequest(`/rest/v1/business_onboarding?select=*&business_id=eq.${b}&limit=1`).catch(()=>[]),
      cloudRequest(`/rest/v1/app_events?select=id,level,source,code,message,context,created_at&business_id=eq.${b}&order=created_at.desc&limit=60`).catch(()=>[]),
      cloudRequest(`/rest/v1/backup_events?select=id,event_type,backup_version,details,created_at&business_id=eq.${b}&order=created_at.desc&limit=30`).catch(()=>[]),
    ]);state.onboarding=onboarding?.[0]||null;state.appEvents=events||[];state.backupEvents=backups||[];
  }else if(role==='finance'){
    const backups=await cloudRequest(`/rest/v1/backup_events?select=id,event_type,backup_version,details,created_at&business_id=eq.${b}&order=created_at.desc&limit=30`).catch(()=>[]);state.backupEvents=backups||[];state.appEvents=[];
  }else{state.appEvents=[];state.backupEvents=[];state.onboarding=null}
}
cloudLoadBusinessData=async function(){await _cloudLoadBusinessDataV117Base();ensureV117State();await loadV117BusinessData();connectivityBanner()};

refreshPosSummary=function(){_refreshPosSummaryV117Base();const btn=$('#posCheckoutBtn');if(btn&&state.mode==='cloud'&&!v117CanWrite()){btn.disabled=true;btn.textContent=navigator.onLine?'Akun Read-only — Perpanjang Subscription':'Offline — Transaksi Dinonaktifkan'}};

async function recordBackupEvent(type,version=BC117_VERSION,details={}){if(state.mode!=='cloud'||!state.currentBusinessId||!navigator.onLine)return;try{await _cloudRequestV117Base('/rest/v1/rpc/record_backup_event_v117',{method:'POST',body:{p_bid:state.currentBusinessId,p_event_type:type,p_backup_version:version,p_details:details}})}catch{}}
exportJson=function(){ensureV117State();const data={version:BC117_VERSION,exported_at:new Date().toISOString(),business:activeBusiness(),products:businessData(state.products),sales:businessData(state.sales),saleItems:businessData(state.saleItems||[]),payments:businessData(state.payments||[]),expenses:businessData(state.expenses),suppliers:businessData(state.suppliers||[]),purchaseOrders:businessData(state.purchaseOrders||[]),purchaseOrderItems:businessData(state.purchaseOrderItems||[]),cashierShifts:businessData(state.cashierShifts||[]),cashMovements:businessData(state.cashMovements||[]),saleAdjustments:businessData(state.saleAdjustments||[]),stockAdjustments:businessData(state.stockAdjustments||[]),productRecipes:businessData(state.productRecipes||[]),customers:businessData(state.customers||[]),loyaltyLedger:businessData(state.loyaltyLedger||[]),auditLogs:can('audit')?businessData(state.auditLogs||[]):[],backup_meta:{app_version:BC117_VERSION,role:currentRole(),mode:state.mode}};downloadBlob(JSON.stringify(data,null,2),'application/json',`bizcontrol-backup-${slug(activeBusiness()?.name||'bisnis')}-${today()}.json`);recordBackupEvent('export_json',BC117_VERSION,{page:state.page,role:currentRole()});toast('Backup V1.17 dibuat. Simpan file di lokasi terpisah.','success')};
function verifyBackupFile(){
  const i=document.createElement('input');i.type='file';i.accept='application/json';i.onchange=()=>{const f=i.files?.[0];if(!f)return;const r=new FileReader();r.onload=async()=>{try{const d=JSON.parse(String(r.result||''));if(!d||typeof d!=='object'||!d.business)throw new Error('Struktur business tidak ditemukan');const groups=['products','sales','saleItems','payments','expenses'];const counts=Object.fromEntries(groups.map(k=>[k,Array.isArray(d[k])?d[k].length:0]));await recordBackupEvent('verify_json',String(d.version||'unknown'),{size:f.size,counts});openModal(`<div class="modal-title"><h2>Backup Valid</h2><button class="modal-close">×</button></div><div class="backup-verify"><div class="status-row"><div><b>${escapeHtml(d.business?.name||'Bisnis')}</b><div class="muted">Versi backup ${escapeHtml(d.version||'-')} · ${d.exported_at?new Date(d.exported_at).toLocaleString('id-ID'):'tanggal tidak tersedia'}</div></div><span class="pill good">VALID</span></div><div class="backup-counts">${Object.entries(counts).map(([k,v])=>`<div><span>${escapeHtml(k)}</span><b>${num(v)}</b></div>`).join('')}</div><div class="form-note">Verifikasi ini hanya membaca file dan tidak menulis ke database. Restore production dilakukan melalui prosedur admin/backup database agar tidak menimpa data secara tidak sengaja.</div><div class="modal-actions"><button class="primary modal-close">Tutup</button></div></div>`)}catch(e){toast('Backup tidak valid: '+e.message,'error')}};r.readAsText(f)};i.click();
}

function handleV117Action(action,el){
  if(action==='verify-backup'){verifyBackupFile();return true}
  if(action==='manage-subscription'){subscriptionAdminModal(el?.dataset?.id);return true}
  if(action==='onboarding-profile'){openBusinessProfileModal();return true}
  if(action==='onboarding-product'||action==='onboarding-products'){navigate('products');return true}
  if(action==='onboarding-printer'){printTestReceipt();return true}
  if(action==='onboarding-sale'){navigate('sales');return true}
  return false;
}
handleAction=function(action,el){if(handleV117Action(action,el))return;return _handleActionV117Base(action,el)};

render=function(){ensureV117State();_renderV117Base();connectivityBanner();const btn=$('#quickSaleBtn');if(btn&&state.mode==='cloud'&&!v117CanWrite()){btn.disabled=true;btn.title=v117WriteReason()}const nb=$('#newBusinessBtn');if(nb&&state.mode==='cloud'){nb.classList.add('hidden');nb.title='V1.17 Cloud menggunakan 1 bisnis per Owner. Multi-outlet akan memakai modul khusus.'}}

window.addEventListener('error',e=>logClientEvent('error','WINDOW_ERROR',e.message||'Window error',{file:String(e.filename||'').split('/').pop(),line:e.lineno||0}));
window.addEventListener('unhandledrejection',e=>logClientEvent('error','UNHANDLED_REJECTION',e.reason?.message||e.reason||'Unhandled rejection'));
window.addEventListener('offline',()=>{connectivityBanner();try{render()}catch{}});
window.addEventListener('online',()=>{connectivityBanner()});

ensureV117State();
try{document.querySelector('.brand span')&&(document.querySelector('.brand span').textContent='ONLINE V1.17');document.title='BizControl Online V1.17'}catch{}
try{if(!$('#appShell')?.classList.contains('hidden'))render()}catch(e){console.warn('V1.17 initial render:',e)}
})();
