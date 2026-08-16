const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];
const rupiah = (n=0) => new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(Number(n)||0);
const num = (n=0) => new Intl.NumberFormat('id-ID').format(Number(n)||0);
const today = () => new Date().toISOString().slice(0,10);
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36)+Math.random().toString(36).slice(2));
const monthKey = (d) => String(d||'').slice(0,7);

const NAV = [
  {id:'dashboard',label:'Dashboard',icon:'⌂'},
  {id:'sales',label:'Kasir',icon:'▣'},
  {id:'products',label:'Produk',icon:'◫'},
  {id:'expenses',label:'Biaya',icon:'↘'},
  {id:'reports',label:'Laporan',icon:'▤'},
  {id:'team',label:'Tim & Role',mobileLabel:'Tim',icon:'♙'},
  {id:'audit',label:'Audit Log',mobileLabel:'Audit',icon:'≣'},
  {id:'settings',label:'Pengaturan',icon:'⚙'},
  {id:'systemAdmin',label:'Admin Sistem',mobileLabel:'Admin',icon:'◆'},
];


const ROLE_LABELS={owner:'Owner',admin:'Admin',cashier:'Kasir',finance:'Finance',warehouse:'Gudang',staff:'Staff'};
const ROLE_PERMISSIONS={
  owner:['*'],
  admin:['dashboard_financial','sales_view','sales_create','sales_edit','sales_delete','payments_manage','payments_delete','products_view','products_create','products_edit','products_delete','expenses_view','expenses_edit','expenses_delete','reports','audit','team_view','business_edit','export','print','sync'],
  cashier:['dashboard_basic','sales_view','sales_create','sales_edit','payments_manage','products_view','print','sync'],
  finance:['dashboard_financial','sales_view','payments_manage','products_view','view_cost','expenses_view','expenses_edit','reports','export','print','sync'],
  warehouse:['dashboard_stock','sales_view','products_view','products_stock_edit','print','sync'],
  staff:['dashboard_basic','products_view','sync']
};
const NAV_PERMISSION={dashboard:null,sales:'sales_view',products:'products_view',expenses:'expenses_view',reports:'reports',team:'team_view',audit:'audit',settings:null,systemAdmin:null};
function currentRole(){return state.mode==='local'?(state.demoRole||'owner'):(state.currentRole||'staff')}
function can(permission){if(!permission)return true;const perms=ROLE_PERMISSIONS[currentRole()]||[];return perms.includes('*')||perms.includes(permission)}
function requirePermission(permission,message='Anda tidak memiliki akses untuk tindakan ini.'){if(!can(permission)){toast(message,'error');return false}return true}
function roleBadge(){return `<span class="role-chip role-${currentRole()}">${ROLE_LABELS[currentRole()]||currentRole()}</span>`}
function canSeeFinancial(){return can('dashboard_financial')||can('reports')}
function canSeeCost(){return currentRole()==='owner'||currentRole()==='admin'||currentRole()==='finance'||can('view_cost')}

const defaultState = () => ({
  page:'dashboard', mode:'local', businesses:[{id:'demo-business',name:'Toko Demo BizControl',owner_id:'local',address:'Jl. Contoh Usaha No. 10, Palembang',phone:'0812-3456-7890',email:'halo@tokodemo.id',city:'Palembang',document_footer:'Terima kasih sudah berbelanja dan mempercayai usaha kami.',allow_negative_stock:false}], currentBusinessId:'demo-business',
  products:[
    {id:'p1',business_id:'demo-business',sku:'PRD-001',name:'Produk A',category:'Produk',unit:'pcs',cost:45000,price:75000,stock:28,min_stock:10},
    {id:'p2',business_id:'demo-business',sku:'PRD-002',name:'Produk B',category:'Produk',unit:'pcs',cost:70000,price:110000,stock:14,min_stock:8},
    {id:'p3',business_id:'demo-business',sku:'PRD-003',name:'Produk C',category:'Produk',unit:'pcs',cost:30000,price:55000,stock:7,min_stock:8},
    {id:'p4',business_id:'demo-business',sku:'JASA-01',name:'Jasa Instalasi',category:'Jasa',unit:'paket',cost:120000,price:250000,stock:999,min_stock:0},
  ],
  sales:[
    {id:'s1',business_id:'demo-business',date:today(),invoice_no:'INV-001',delivery_no:'SJ-001',customer:'Rina',customer_phone:'0812-1111-2222',customer_address:'Jl. Anggrek No. 12, Palembang',notes:'Terima kasih atas pembelian Anda.',product_id:'p1',product_name:'Produk A +1 item',qty:3,unit_price:75000,unit_cost:45000,discount:0,total:260000,gross_profit:100000,payment_method:'QRIS',paid_amount:260000},
    {id:'s2',business_id:'demo-business',date:today(),invoice_no:'INV-002',customer:'Andi',customer_phone:'0813-2222-3333',customer_address:'Jl. Melati No. 8, Palembang',notes:'',product_id:'p2',product_name:'Produk B',qty:1,unit_price:110000,unit_cost:70000,discount:0,total:110000,gross_profit:40000,payment_method:'Cash',paid_amount:110000},
    {id:'s3',business_id:'demo-business',date:new Date(Date.now()-86400000).toISOString().slice(0,10),invoice_no:'INV-003',customer:'Budi',customer_phone:'0812-4444-5555',customer_address:'Jakabaring, Palembang',notes:'Jasa dijadwalkan sesuai kesepakatan.',product_id:'p4',product_name:'Jasa Instalasi',qty:1,unit_price:250000,unit_cost:120000,discount:20000,total:230000,gross_profit:110000,payment_method:'Transfer',paid_amount:230000},
    {id:'s4',business_id:'demo-business',date:new Date(Date.now()-2*86400000).toISOString().slice(0,10),invoice_no:'INV-004',customer:'Maya',customer_phone:'0813-7777-8888',customer_address:'Plaju, Palembang',notes:'Pembayaran sebagian.',product_id:'p3',product_name:'Produk C',qty:3,unit_price:55000,unit_cost:30000,discount:5000,total:160000,gross_profit:70000,payment_method:'Tempo',paid_amount:100000},
  ],
  saleItems:[
    {id:'si1',business_id:'demo-business',sale_id:'s1',line_no:1,product_id:'p1',product_name:'Produk A',unit:'pcs',qty:2,unit_price:75000,unit_cost:45000,line_total:150000,line_gross_profit:60000},
    {id:'si2',business_id:'demo-business',sale_id:'s1',line_no:2,product_id:'p2',product_name:'Produk B',unit:'pcs',qty:1,unit_price:110000,unit_cost:70000,line_total:110000,line_gross_profit:40000},
    {id:'si3',business_id:'demo-business',sale_id:'s2',line_no:1,product_id:'p2',product_name:'Produk B',unit:'pcs',qty:1,unit_price:110000,unit_cost:70000,line_total:110000,line_gross_profit:40000},
    {id:'si4',business_id:'demo-business',sale_id:'s3',line_no:1,product_id:'p4',product_name:'Jasa Instalasi',unit:'paket',qty:1,unit_price:250000,unit_cost:120000,line_total:250000,line_gross_profit:130000},
    {id:'si5',business_id:'demo-business',sale_id:'s4',line_no:1,product_id:'p3',product_name:'Produk C',unit:'pcs',qty:3,unit_price:55000,unit_cost:30000,line_total:165000,line_gross_profit:75000},
  ],
  payments:[
    {id:'pay1',business_id:'demo-business',sale_id:'s1',payment_no:1,payment_date:today(),amount:260000,method:'QRIS',notes:'Pembayaran transaksi',created_at:new Date().toISOString()},
    {id:'pay2',business_id:'demo-business',sale_id:'s2',payment_no:1,payment_date:today(),amount:110000,method:'Cash',notes:'Pembayaran transaksi',created_at:new Date().toISOString()},
    {id:'pay3',business_id:'demo-business',sale_id:'s3',payment_no:1,payment_date:new Date(Date.now()-86400000).toISOString().slice(0,10),amount:230000,method:'Transfer',notes:'Pembayaran transaksi',created_at:new Date(Date.now()-86400000).toISOString()},
    {id:'pay4',business_id:'demo-business',sale_id:'s4',payment_no:1,payment_date:new Date(Date.now()-2*86400000).toISOString().slice(0,10),amount:100000,method:'Transfer',notes:'Pembayaran sebagian',created_at:new Date(Date.now()-2*86400000).toISOString()},
  ],
  expenses:[
    {id:'e1',business_id:'demo-business',date:today(),category:'Marketing',description:'Iklan Meta',amount:75000,payment_method:'Transfer'},
    {id:'e2',business_id:'demo-business',date:new Date(Date.now()-86400000).toISOString().slice(0,10),category:'Transport',description:'Pengiriman lokal',amount:40000,payment_method:'Cash'},
  ],
  auditLogs:[], memberships:[], teamMembers:[], currentRole:'owner', demoRole:'owner', documentSequences:{}, syncStatus:'idle', syncError:null,
  session:null, cloudConfig:null, lastSync:null, isSystemAdmin:false, managedOwners:[]
});

let state = loadLocal();
let authMode = 'login';
let authLinkType = null;
let authInviteKind = null;
let pollTimer = null;

function loadLocal(){
  try {
    const raw=localStorage.getItem('bizcontrol_v1');
    const data=raw ? {...defaultState(),...JSON.parse(raw)} : defaultState();
    data.payments=Array.isArray(data.payments)?data.payments:[];
    data.saleItems=Array.isArray(data.saleItems)?data.saleItems:[];
    // Upgrade transaksi single-item lama menjadi sale_items lokal agar invoice lama tetap kompatibel.
    (data.sales||[]).forEach(sale=>{
      if(data.saleItems.some(i=>i.sale_id===sale.id&&i.business_id===sale.business_id))return;
      const prod=(data.products||[]).find(p=>p.id===sale.product_id)||{};
      data.saleItems.push({id:uid(),business_id:sale.business_id,sale_id:sale.id,line_no:1,product_id:sale.product_id,product_name:sale.product_name||prod.name||'Produk',unit:prod.unit||'pcs',qty:Number(sale.qty||0),unit_price:Number(sale.unit_price||0),unit_cost:Number(sale.unit_cost||0),line_total:Number(sale.qty||0)*Number(sale.unit_price||0),line_gross_profit:Number(sale.qty||0)*(Number(sale.unit_price||0)-Number(sale.unit_cost||0))});
    });
    // Upgrade data lama V1.5: setiap transaksi yang sudah punya paid_amount dibuatkan 1 riwayat pembayaran awal.
    (data.sales||[]).forEach(sale=>{
      const has=data.payments.some(p=>p.sale_id===sale.id&&p.business_id===sale.business_id);
      const paid=Number(sale.paid_amount||0);
      if(!has&&paid>0) data.payments.push({id:uid(),business_id:sale.business_id,sale_id:sale.id,payment_no:1,payment_date:sale.date||today(),amount:paid,method:sale.payment_method||'Transfer',notes:'Migrasi pembayaran dari BizControl V1.5',created_at:new Date().toISOString()});
    });
    return data;
  } catch { return defaultState(); }
}
function persist(){ if(state.mode==='local') localStorage.setItem('bizcontrol_v1',JSON.stringify(state)); }
function toast(msg,type='info',ms=3200){ const el=$('#toast'); el.textContent=msg; el.className=`toast show ${type}`; clearTimeout(el._t); el._t=setTimeout(()=>{el.className='toast'},ms); }
function setSyncState(status,error=null){state.syncStatus=status;state.syncError=error;renderSyncBadge()}
function isOnline(){return navigator.onLine!==false}
function setButtonBusy(btn,busy,label='Menyimpan...'){if(!btn)return;if(busy){btn.dataset.oldText=btn.textContent;btn.disabled=true;btn.classList.add('is-loading');btn.textContent=label}else{btn.disabled=false;btn.classList.remove('is-loading');if(btn.dataset.oldText)btn.textContent=btn.dataset.oldText;delete btn.dataset.oldText}}
async function withSubmitBusy(form,task,label='Menyimpan...'){const btn=form?.querySelector('button[type="submit"]');if(btn?.disabled)return;setButtonBusy(btn,true,label);try{return await task()}catch(err){console.warn(err);return null}finally{setButtonBusy(btn,false)}}
function businessData(list){ return list.filter(x=>x.business_id===state.currentBusinessId); }
function activeBusiness(){ return state.businesses.find(b=>b.id===state.currentBusinessId) || state.businesses[0]; }
function paymentsForSale(saleId){ return businessData(state.payments||[]).filter(p=>p.sale_id===saleId).slice().sort((a,b)=>Number(a.payment_no||0)-Number(b.payment_no||0)||String(a.payment_date||'').localeCompare(String(b.payment_date||''))||String(a.created_at||'').localeCompare(String(b.created_at||''))); }
function recalcLocalSalePaid(saleId){ const sale=state.sales.find(s=>s.id===saleId&&s.business_id===state.currentBusinessId); if(!sale)return; sale.paid_amount=Math.min(Number(sale.total||0),paymentsForSale(saleId).reduce((a,p)=>a+Number(p.amount||0),0)); }

function itemsForSale(saleId){
  const rows=(state.saleItems||[]).filter(x=>x.sale_id===saleId&&x.business_id===state.currentBusinessId).slice().sort((a,b)=>Number(a.line_no||0)-Number(b.line_no||0));
  if(rows.length)return rows;
  const sale=state.sales.find(s=>s.id===saleId&&s.business_id===state.currentBusinessId);
  if(!sale)return [];
  const p=state.products.find(x=>x.id===sale.product_id)||{};
  return [{id:`legacy-${sale.id}`,business_id:sale.business_id,sale_id:sale.id,line_no:1,product_id:sale.product_id,product_name:sale.product_name,unit:p.unit||'pcs',qty:Number(sale.qty||0),unit_price:Number(sale.unit_price||0),unit_cost:Number(sale.unit_cost||0),line_total:Number(sale.qty||0)*Number(sale.unit_price||0),line_gross_profit:Number(sale.qty||0)*(Number(sale.unit_price||0)-Number(sale.unit_cost||0))}];
}
function saleItemsLabel(sale){
  const rows=itemsForSale(sale.id); if(!rows.length)return sale.product_name||'-';
  return rows.length===1?(rows[0].product_name||sale.product_name||'-'):`${rows[0].product_name||'Barang'} +${rows.length-1} item`;
}
function saleItemsQty(sale){ const rows=itemsForSale(sale.id); return rows.length?rows.reduce((a,x)=>a+Number(x.qty||0),0):Number(sale.qty||0); }

function renderNav(){
  const visible=NAV.filter(n=>n.id==='systemAdmin'?(state.mode==='cloud'&&state.isSystemAdmin):can(NAV_PERMISSION[n.id]));
  if(!visible.some(n=>n.id===state.page)) state.page=state.isSystemAdmin&&!state.businesses.length?'systemAdmin':'dashboard';
  $('#desktopNav').innerHTML = visible.map(n=>`<button class="nav-item ${state.page===n.id?'active':''}" data-nav="${n.id}"><span class="nav-icon">${n.icon}</span>${n.label}</button>`).join('');
  const preferred=state.isSystemAdmin?['dashboard','sales','products','team','settings','systemAdmin']:['dashboard','sales','products','expenses','reports','team','audit'];
  const mobile=visible.filter(n=>preferred.includes(n.id)).slice(0,6);
  $('#mobileNav').style.setProperty('--mobile-count',Math.max(mobile.length,1));
  $('#mobileNav').innerHTML = mobile.map(n=>`<button class="${state.page===n.id?'active':''}" data-nav="${n.id}"><b>${n.icon}</b>${n.mobileLabel||n.label}</button>`).join('');
  $$('[data-nav]').forEach(b=>b.onclick=()=>navigate(b.dataset.nav));
}
function renderBusinessSelect(){
  const sel=$('#businessSelect');
  sel.innerHTML = state.businesses.map(b=>`<option value="${b.id}" ${b.id===state.currentBusinessId?'selected':''}>${escapeHtml(b.name)}</option>`).join('') || '<option>Belum ada bisnis</option>';
  sel.onchange=async()=>{state.currentBusinessId=sel.value;if(state.mode==='cloud'){state.currentRole=resolveCloudRole();await cloudLoadBusinessData();startRealtime()}persist();render();};
}
function renderSyncBadge(){
  const el=$('#syncBadge'); if(!el)return;
  if(state.mode!=='cloud'){el.className='sync-badge local';el.textContent=`● Demo Lokal · ${ROLE_LABELS[currentRole()]||currentRole()}`;return}
  const role=ROLE_LABELS[currentRole()]||currentRole();
  if(!isOnline()){el.className='sync-badge offline';el.textContent=`○ Offline · ${role}`;return}
  if(state.syncStatus==='syncing'){el.className='sync-badge syncing';el.textContent=`↻ Sinkronisasi · ${role}`;return}
  if(state.syncStatus==='error'){el.className='sync-badge error';el.textContent=`! Sync gagal · ${role}`;return}
  el.className='sync-badge cloud';el.textContent=`● Cloud · ${role}${state.lastSync?' · '+new Date(state.lastSync).toLocaleTimeString('id-ID',{hour:'2-digit',minute:'2-digit'}):''}`;
}
function navigate(page){ state.page=page; render(); }

function enhanceResponsiveTables(root=document){
  if(!root?.querySelectorAll) return;
  root.querySelectorAll('table:not(.doc-table)').forEach(table=>{
    const headers=[...table.querySelectorAll('thead th')].map(th=>(th.textContent||'').trim());
    if(!headers.length) return;
    table.classList.add('responsive-table');
    const wrap=table.closest('.table-wrap');
    if(wrap) wrap.classList.add('responsive-table-wrap');
    const lower=headers.map(x=>x.toLowerCase());
    let type='generic';
    if(lower.includes('invoice')&&lower.includes('customer')) type='sales';
    else if(lower.includes('sku')&&lower.includes('nama')) type='products';
    else if(lower.includes('kategori')&&lower.includes('deskripsi')&&lower.includes('nilai')) type='expenses';
    else if(lower.includes('aktivitas')&&lower.includes('ringkasan')) type='audit';
    else if(lower.includes('ke')&&lower.includes('metode')&&lower.includes('jumlah')) type='payments';
    else if(lower.includes('bulan')&&lower.includes('omzet')) type='reports';
    else if(lower.includes('user')&&lower.includes('role')) type='team';
    table.dataset.mobileType=type;
    table.querySelectorAll('tbody tr').forEach(row=>{
      const cells=[...row.children].filter(el=>el.tagName==='TD');
      if(cells.length===1&&Number(cells[0].colSpan||1)>1){ cells[0].classList.add('mobile-empty-cell'); return; }
      cells.forEach((td,i)=>{
        const label=headers[i]||'';
        td.dataset.label=label;
        td.dataset.mobileKey=label.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');
        if(label) td.setAttribute('aria-label',label);
      });
    });
  });
}

function render(){
  renderNav(); renderBusinessSelect(); renderSyncBadge();
  const meta={dashboard:['BUSINESS OVERVIEW','Dashboard'],sales:['TRANSAKSI','Kasir / Penjualan'],products:['INVENTORY','Produk & Stok'],expenses:['OPERASIONAL','Biaya Usaha'],reports:['PERFORMA','Laporan'],team:['ACCESS CONTROL','Tim & Role'],audit:['SECURITY & CONTROL','Audit Log'],settings:['SYSTEM','Pengaturan'],systemAdmin:['PLATFORM CONTROL','Admin Sistem']};
  const activeMeta=meta[state.page]||meta.dashboard; $('#pageEyebrow').textContent=activeMeta[0]; $('#pageTitle').textContent=activeMeta[1];
  const pages={dashboard:renderDashboard,sales:renderSales,products:renderProducts,expenses:renderExpenses,reports:renderReports,team:renderTeam,audit:renderAuditLog,settings:renderSettingsPage,systemAdmin:renderSystemAdmin};
  $('#pageContent').innerHTML=pages[state.page]();
  $('#quickSaleBtn')?.classList.toggle('hidden',!can('sales_create'));
  $('#newBusinessBtn')?.classList.toggle('hidden',state.mode==='cloud'&&currentRole()!=='owner');
  $('#openAuthBtn')?.classList.toggle('hidden',state.mode==='cloud');
  $('#logoutBtn')?.classList.toggle('hidden',state.mode!=='cloud');
  $('#demoLoginBtn')?.classList.toggle('hidden',state.mode!=='local');
  $('#accountSettingsBtn')?.classList.toggle('hidden',state.mode!=='cloud');
  bindPageActions();
  enhanceResponsiveTables($('#pageContent'));
}

function metrics(){
  const sales=businessData(state.sales), products=businessData(state.products), expenses=businessData(state.expenses);
  const currentMonth=new Date().toISOString().slice(0,7);
  const mSales=sales.filter(s=>monthKey(s.date)===currentMonth), mExp=expenses.filter(e=>monthKey(e.date)===currentMonth);
  const revenue=mSales.reduce((a,s)=>a+Number(s.total||0),0);
  const gross=mSales.reduce((a,s)=>a+Number(s.gross_profit||0),0);
  const hpp=Math.max(0,revenue-gross);
  const exp=mExp.reduce((a,e)=>a+Number(e.amount||0),0);
  const net=gross-exp;
  const receivable=sales.reduce((a,s)=>a+Math.max(Number(s.total||0)-Number(s.paid_amount||0),0),0);
  const stockValue=products.filter(p=>p.category!=='Jasa').reduce((a,p)=>a+Number(p.cost||0)*Number(p.stock||0),0);
  const lowStock=products.filter(p=>p.category!=='Jasa' && Number(p.stock)<=Number(p.min_stock)).length;
  const todayRevenue=sales.filter(s=>s.date===today()).reduce((a,s)=>a+Number(s.total||0),0);
  const margin=revenue?net/revenue:0;
  const score=Math.max(0,100-(net<0?30:0)-(receivable>revenue*.35&&revenue>0?20:0)-Math.min(lowStock*6,24)-(margin<.1&&revenue>0?15:0));
  return {sales,products,expenses,revenue,hpp,gross,exp,net,receivable,stockValue,lowStock,todayRevenue,margin,score};
}

function renderDashboard(){
  const m=metrics(); const role=currentRole();
  const days=[...Array(7)].map((_,i)=>{const d=new Date(Date.now()-(6-i)*86400000);return d.toISOString().slice(0,10)});
  const stockRole=role==='warehouse';
  const vals=days.map(d=>stockRole?m.sales.filter(s=>s.date===d).length:m.sales.filter(s=>s.date===d).reduce((a,s)=>a+Number(s.total||0),0));
  const max=Math.max(...vals,1);
  const financial=canSeeFinancial();
  const kpis=stockRole
    ? `${kpiCard('Produk Aktif',num(m.products.length),'Master produk','open-low-stock')}${kpiCard('Produk Menipis',num(m.lowStock),'Perlu restock','open-low-stock')}${kpiCard('Transaksi Hari Ini',num(m.sales.filter(s=>s.date===today()).length),'Referensi pengiriman','open-day-sales')}${kpiCard('Surat Jalan Hari Ini',num(m.sales.filter(s=>s.date===today()&&s.delivery_no).length),'Dokumen fulfilment','open-day-sales')}`
    : financial
      ? `${kpiCard('Omzet Bulan Ini',rupiah(m.revenue),'Hari ini '+rupiah(m.todayRevenue),'open-revenue-summary')}${kpiCard('Laba Bersih',rupiah(m.net),'Margin '+(m.margin*100).toFixed(1)+'%','open-profit-summary')}${kpiCard('Piutang',rupiah(m.receivable),m.receivable?'Perlu follow-up':'Tidak ada tagihan','open-receivable-summary')}${kpiCard('Nilai Stok',rupiah(m.stockValue),m.lowStock+' produk menipis','open-low-stock')}`
      : `${kpiCard('Omzet Hari Ini',rupiah(m.todayRevenue),'Akses operasional','open-day-sales')}${kpiCard('Transaksi Hari Ini',num(m.sales.filter(s=>s.date===today()).length),'Penjualan tercatat','open-day-sales')}${kpiCard('Piutang',rupiah(m.receivable),'Tagihan customer','open-receivable-summary')}${kpiCard('Stok Menipis',num(m.lowStock),'Perlu perhatian','open-low-stock')}`;
  const healthLabel=m.score>=80?'Kondisi cukup sehat':m.score>=60?'Perlu beberapa perhatian':'Perlu tindakan prioritas';
  const quick=[can('sales_create')?`<button class="quick-card" type="button" data-action="add-sale"><strong>+ Penjualan</strong><span>Catat transaksi baru</span></button>`:'',can('products_edit')?`<button class="quick-card" type="button" data-action="add-product"><strong>+ Produk</strong><span>Tambah produk / jasa</span></button>`:'',can('expenses_edit')?`<button class="quick-card" type="button" data-action="add-expense"><strong>+ Biaya</strong><span>Catat pengeluaran</span></button>`:'',can('reports')?`<button class="quick-card" type="button" data-nav="reports"><strong>Lihat Laporan</strong><span>Laba rugi & ringkasan</span></button>`:''].filter(Boolean).join('');
  const chartTitle=stockRole?'Aktivitas Pengiriman 7 Hari':'Omzet 7 Hari Terakhir';
  const chartHint=stockRole?'Klik batang untuk daftar transaksi/pengiriman pada hari tersebut.':'Klik batang untuk detail transaksi hari itu.';
  const chartBars=days.map((d,i)=>`<button type="button" class="bar-wrap bar-btn" data-action="open-day-sales" data-date="${d}"><div class="bar-value">${stockRole?num(vals[i]):(vals[i]?rupiah(vals[i]).replace(/,00$/,''):'Rp0')}</div><div class="bar" style="height:${Math.max(4,(vals[i]/max)*150)}px"></div><div class="bar-label">${new Date(d+'T00:00:00').toLocaleDateString('id-ID',{weekday:'short'})}</div></button>`).join('');
  const alerts=stockRole
    ? `<div class="alert-list"><button type="button" class="alert-item alert-btn" data-action="open-low-stock"><span><b>Stok menipis</b><small>Produk perlu restock</small></span><strong>${m.lowStock} ›</strong></button><button type="button" class="alert-item alert-btn" data-action="open-day-sales" data-date="${today()}"><span><b>Pengiriman hari ini</b><small>Invoice / surat jalan hari ini</small></span><strong>${num(m.sales.filter(s=>s.date===today()).length)} ›</strong></button></div>`
    : `<div class="alert-list"><button type="button" class="alert-item alert-btn" data-action="open-low-stock"><span><b>Stok menipis</b><small>Produk perlu restock</small></span><strong>${m.lowStock} ›</strong></button><button type="button" class="alert-item alert-btn" data-action="open-receivable-summary"><span><b>Piutang</b><small>Transaksi belum lunas</small></span><strong>${rupiah(m.receivable)} ›</strong></button>${can('expenses_view')?`<button type="button" class="alert-item alert-btn" data-action="open-expense-summary"><span><b>Biaya bulan ini</b><small>Rincian pengeluaran</small></span><strong>${rupiah(m.exp)} ›</strong></button>`:''}</div>`;
  return `<div class="role-banner"><div><span>Anda masuk sebagai</span>${roleBadge()}</div><small>Menu dan aksi otomatis menyesuaikan hak akses.</small></div>
    ${state.mode==='local'?`<div class="demo-security-warning"><b>MODE DEMO</b><span>Data tersimpan di browser perangkat ini. Jangan gunakan data bisnis sensitif atau data production.</span></div>`:''}
    <div class="kpi-grid">${kpis}</div>${quick?`<div class="quick-grid quick-grid-dynamic">${quick}</div>`:''}
    <div class="section-grid">
      <section class="panel dashboard-panel"><div class="panel-title dashboard-title-row"><div><h3>${chartTitle}</h3><span>${escapeHtml(activeBusiness()?.name||'')}</span></div><button type="button" class="panel-link" data-action="open-weekly-sales">Lihat ringkasan →</button></div><div class="panel-hint">${chartHint}</div><div class="bars">${chartBars}</div></section>
      <section class="panel dashboard-panel"><div class="panel-title dashboard-title-row"><div><h3>${financial?'Business Health':'Operational Alert'}</h3><span>Indikator sesuai role</span></div>${financial?`<button type="button" class="panel-link" data-action="open-health-summary">Lihat detail →</button>`:''}</div>${financial?`<button type="button" class="health-click" data-action="open-health-summary"><div class="health-ring" style="--score:${m.score}"><div class="health-score">${m.score}</div></div><p class="health-note">${healthLabel}</p></button>`:''}${alerts}</section>
    </div>${can('sales_view')?salesTable(m.sales.slice().sort((a,b)=>String(b.date).localeCompare(String(a.date))).slice(0,6),'Transaksi Terbaru'):''}`;
}
function kpiCard(label,value,foot,action){ return `<button type="button" class="kpi-card kpi-clickable" data-action="${action}"><div class="kpi-label">${label}</div><div class="kpi-value">${value}</div><div class="kpi-foot">${foot}</div></button>`; }

function renderSales(){
  if(!can('sales_view')) return accessDenied('Kasir / Penjualan');
  const sales=businessData(state.sales).slice().sort((a,b)=>String(b.date).localeCompare(String(a.date)));
  return `<div class="toolbar"><div class="toolbar-left"><input class="search" id="salesSearch" placeholder="Cari invoice / customer / produk" /></div><div class="toolbar-right">${can('sales_create')?'<button class="primary" data-action="add-sale">+ Penjualan Baru</button>':''}${can('export')?'<button class="ghost" data-action="export-sales">Export CSV</button>':''}</div></div>${salesTable(sales,'Semua Penjualan')}`;
}

function salesTable(sales,title){
  if(!sales.length) return `<div class="table-card"><div class="table-head"><h3>${escapeHtml(title)}</h3></div><div class="empty">Belum ada transaksi.</div></div>`;
  if(currentRole()==='warehouse'){
    return `<div class="table-card"><div class="table-head"><h3>${escapeHtml(title)}</h3><span class="muted">${sales.length} baris fulfilment</span></div><div class="table-wrap"><table><thead><tr><th>Tanggal</th><th>Invoice</th><th>Surat Jalan</th><th>Customer</th><th>HP</th><th>Tujuan</th><th>Produk</th><th>Qty</th><th>Aksi</th></tr></thead><tbody>${sales.map(s=>`<tr><td>${fmtDate(s.date)}</td><td>${escapeHtml(s.invoice_no||'-')}</td><td>${escapeHtml(s.delivery_no||'-')}</td><td>${escapeHtml(s.customer||'-')}</td><td>${escapeHtml(s.customer_phone||'-')}</td><td>${escapeHtml(s.customer_address||'-')}</td><td>${escapeHtml(saleItemsLabel(s))}</td><td>${num(saleItemsQty(s))}</td><td><div class="row-actions">${can('print')?`<button type="button" class="row-action print" data-action="print-sale" data-id="${escapeAttr(s.id)}">Surat Jalan</button>`:'—'}</div></td></tr>`).join('')}</tbody></table></div></div>`;
  }
  return `<div class="table-card"><div class="table-head"><h3>${escapeHtml(title)}</h3><span class="muted">${sales.length} baris</span></div><div class="table-wrap"><table><thead><tr><th>Tanggal</th><th>Invoice</th><th>Customer</th><th>Produk</th><th>Qty</th><th>Total</th><th>Dibayar</th><th>Status</th><th>Aksi</th></tr></thead><tbody>${sales.map(s=>{const due=Math.max(Number(s.total)-Number(s.paid_amount),0);const actions=[can('payments_manage')?`<button type="button" class="row-action pay" data-action="payments-sale" data-id="${escapeAttr(s.id)}">Pembayaran</button>`:'',can('print')?`<button type="button" class="row-action print" data-action="print-sale" data-id="${escapeAttr(s.id)}">Cetak</button>`:'',can('sales_edit')?`<button type="button" class="row-action edit" data-action="edit-sale" data-id="${escapeAttr(s.id)}">Edit</button>`:'',can('sales_delete')?`<button type="button" class="row-action delete" data-action="delete-sale" data-id="${escapeAttr(s.id)}">Hapus</button>`:''].filter(Boolean).join('');return `<tr><td>${fmtDate(s.date)}</td><td>${escapeHtml(s.invoice_no||'-')}</td><td>${escapeHtml(s.customer||'-')}</td><td>${escapeHtml(saleItemsLabel(s))}</td><td>${num(saleItemsQty(s))}</td><td class="money">${rupiah(s.total)}</td><td class="money">${rupiah(s.paid_amount)}</td><td><span class="pill ${due?'warn':'good'}">${due?'Belum Lunas':'Lunas'}</span></td><td><div class="row-actions">${actions||'—'}</div></td></tr>`}).join('')}</tbody></table></div></div>`;
}

function renderProducts(){
  if(!can('products_view')) return accessDenied('Produk & Stok');
  const products=businessData(state.products); const showCost=canSeeCost(); const showPrice=currentRole()!=='warehouse';
  return `<div class="toolbar"><div class="toolbar-left"><input class="search" id="productSearch" placeholder="Cari SKU / produk" /></div><div class="toolbar-right">${can('products_create')?'<button class="primary" data-action="add-product">+ Produk Baru</button>':''}${can('export')?'<button class="ghost" data-action="export-products">Export CSV</button>':''}</div></div>
  <div class="table-card"><div class="table-head"><h3>Master Produk</h3><span class="muted">${products.length} item</span></div><div class="table-wrap"><table><thead><tr><th>SKU</th><th>Nama</th><th>Kategori</th>${showCost?'<th>HPP</th>':''}${showPrice?'<th>Harga</th>':''}<th>Stok</th><th>Min</th><th>Status</th><th>Aksi</th></tr></thead><tbody>${products.map(p=>{const low=p.category!=='Jasa'&&Number(p.stock)<=Number(p.min_stock);const actions=[(can('products_edit')||can('products_stock_edit'))?`<button type="button" class="row-action edit" data-action="edit-product" data-id="${p.id}">${can('products_edit')?'Edit':'Update Stok'}</button>`:'',can('products_delete')?`<button type="button" class="row-action delete" data-action="delete-product" data-id="${p.id}">Hapus</button>`:''].filter(Boolean).join('');return `<tr><td>${escapeHtml(p.sku)}</td><td>${escapeHtml(p.name)}</td><td>${escapeHtml(p.category)}</td>${showCost?`<td class="money">${rupiah(p.cost)}</td>`:''}${showPrice?`<td class="money">${rupiah(p.price)}</td>`:''}<td>${p.category==='Jasa'?'—':num(p.stock)}</td><td>${p.category==='Jasa'?'—':num(p.min_stock)}</td><td><span class="pill ${low?'bad':'good'}">${p.category==='Jasa'?'Jasa':low?'Restock':'Aman'}</span></td><td><div class="row-actions">${actions||'—'}</div></td></tr>`}).join('')}</tbody></table></div></div>`;
}

function renderExpenses(){
  if(!can('expenses_view')) return accessDenied('Biaya Usaha');
  const items=businessData(state.expenses).slice().sort((a,b)=>String(b.date).localeCompare(String(a.date)));
  return `<div class="toolbar"><div class="toolbar-left"><input class="search" id="expenseSearch" placeholder="Cari deskripsi / kategori" /></div><div class="toolbar-right">${can('expenses_edit')?'<button class="primary" data-action="add-expense">+ Biaya Baru</button>':''}${can('export')?'<button class="ghost" data-action="export-expenses">Export CSV</button>':''}</div></div>
  <div class="table-card"><div class="table-head"><h3>Biaya Usaha</h3><span class="muted">Total ${rupiah(items.reduce((a,e)=>a+Number(e.amount),0))}</span></div><div class="table-wrap"><table><thead><tr><th>Tanggal</th><th>Kategori</th><th>Deskripsi</th><th>Metode</th><th>Nilai</th><th>Aksi</th></tr></thead><tbody>${items.length?items.map(e=>{const actions=[can('expenses_edit')?`<button type="button" class="row-action edit" data-action="edit-expense" data-id="${e.id}">Edit</button>`:'',can('expenses_delete')?`<button type="button" class="row-action delete" data-action="delete-expense" data-id="${e.id}">Hapus</button>`:''].filter(Boolean).join('');return `<tr><td>${fmtDate(e.date)}</td><td>${escapeHtml(e.category)}</td><td>${escapeHtml(e.description)}</td><td>${escapeHtml(e.payment_method)}</td><td class="money">${rupiah(e.amount)}</td><td><div class="row-actions">${actions||'—'}</div></td></tr>`}).join(''):`<tr><td colspan="6"><div class="empty">Belum ada biaya.</div></td></tr>`}</tbody></table></div></div>`;
}

function renderReports(){
  if(!can('reports')) return accessDenied('Laporan');
  const m=metrics();
  const months=[...Array(6)].map((_,i)=>{const d=new Date();d.setMonth(d.getMonth()-(5-i));return d.toISOString().slice(0,7)});
  const rows=months.map(k=>{const s=m.sales.filter(x=>monthKey(x.date)===k), e=m.expenses.filter(x=>monthKey(x.date)===k);const rev=s.reduce((a,x)=>a+Number(x.total),0), gross=s.reduce((a,x)=>a+Number(x.gross_profit),0), exp=e.reduce((a,x)=>a+Number(x.amount),0);return {k,rev,gross,exp,net:gross-exp};});
  return `<div class="toolbar"><div class="toolbar-left"><span class="muted">Laporan manajemen</span></div><div class="toolbar-right"><button class="ghost" data-action="export-all-csv">Export Semua CSV</button></div></div><div class="report-grid">
    <div class="panel"><div class="panel-title"><h3>Laba Rugi Bulan Ini</h3><span>${new Date().toLocaleDateString('id-ID',{month:'long',year:'numeric'})}</span></div><div class="metric-list">
      ${metricRow('Penjualan Neto',m.revenue)}${metricRow('HPP',m.hpp)}${metricRow('Laba Kotor',m.gross)}${metricRow('Biaya Operasional',m.exp)}
      <div class="metric-row total"><span>Laba Bersih</span><strong>${rupiah(m.net)}</strong></div>
    </div></div>
    <div class="panel"><div class="panel-title"><h3>Ringkasan Bisnis</h3><span>Current</span></div><div class="metric-list">
      ${metricRow('Piutang',m.receivable)}${metricRow('Nilai Persediaan',m.stockValue)}${metricRow('Produk perlu restock',m.lowStock,false)}${metricRow('Margin bersih',(m.margin*100).toFixed(1)+'%',false)}
      <div class="form-note">Versi V1 fokus laporan manajemen. Modul pembelian, hutang, kas/bank multi-account dan pajak masuk fase berikutnya.</div>
    </div></div>
  </div>
  <div class="table-card"><div class="table-head"><h3>Tren 6 Bulan</h3></div><div class="table-wrap"><table><thead><tr><th>Bulan</th><th>Omzet</th><th>Laba Kotor</th><th>Biaya</th><th>Laba Bersih</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${new Date(r.k+'-01T00:00:00').toLocaleDateString('id-ID',{month:'long',year:'numeric'})}</td><td class="money">${rupiah(r.rev)}</td><td class="money">${rupiah(r.gross)}</td><td class="money">${rupiah(r.exp)}</td><td class="money">${rupiah(r.net)}</td></tr>`).join('')}</tbody></table></div></div>`;
}
function metricRow(label,value,isMoney=true){return `<div class="metric-row"><span>${label}</span><strong>${isMoney?rupiah(value):value}</strong></div>`}

function auditModuleLabel(module){ return ({sales:'Penjualan',payments:'Pembayaran',products:'Produk',stock:'Stok',expenses:'Biaya',security:'Security',business:'Bisnis',team:'Tim & Role'})[module]||module||'-'; }
function auditActionLabel(action){ return ({CREATE:'Tambah',UPDATE:'Edit',DELETE:'Hapus',SECURITY:'Security'})[action]||action||'-'; }
function auditActionClass(action){ return action==='DELETE'?'bad':action==='UPDATE'?'warn':action==='SECURITY'?'info':'good'; }
function auditActor(log){ return log.actor_email || log.actor_name || (state.mode==='cloud'?'User Cloud':'Demo Owner'); }
function auditDateTime(v){ if(!v)return'-'; const d=new Date(v); return d.toLocaleDateString('id-ID',{day:'2-digit',month:'short',year:'numeric'})+' · '+d.toLocaleTimeString('id-ID',{hour:'2-digit',minute:'2-digit'}); }
function auditFieldMap(){ return {date:'Tanggal',invoice_no:'Invoice',customer:'Customer',product_name:'Produk',qty:'Qty',unit_price:'Harga/Unit',unit_cost:'HPP/Unit',discount:'Diskon',total:'Total',paid_amount:'Dibayar',payment_method:'Metode Bayar',sku:'SKU',name:'Nama',category:'Kategori',unit:'Satuan',cost:'HPP / Modal',price:'Harga Jual',stock:'Stok',min_stock:'Min Stok',customer_phone:'No. HP Customer',customer_address:'Alamat / Tujuan',notes:'Catatan',description:'Deskripsi',amount:'Nilai Biaya',address:'Alamat Usaha',phone:'Telepon / WhatsApp',email:'Email',city:'Kota',document_footer:'Footer Dokumen',payment_date:'Tanggal Bayar',payment_no:'Pembayaran Ke',method:'Metode Pembayaran',sale_id:'Invoice Ref',receipt_no:'No. Kwitansi',delivery_no:'No. Surat Jalan',line_no:'Baris',line_total:'Subtotal Item',line_gross_profit:'Laba Kotor Item',client_request_id:'Request ID',role:'Role',email:'Email',configured:'Security Key'}; }
function auditFormatValue(key,value){
  if(value===null||value===undefined||value==='') return '—';
  if(['unit_price','unit_cost','discount','total','paid_amount','cost','price','amount','gross_profit'].includes(key)) return rupiah(value);
  if(key==='date'||key==='payment_date') return fmtDate(value);
  if(key==='configured') return value?'Aktif':'Belum aktif';
  return String(value);
}
function paymentStatusFrom(obj){ if(!obj||obj.total===undefined) return null; return Math.max(Number(obj.total||0)-Number(obj.paid_amount||0),0)>0?'Belum Lunas':'Lunas'; }
function auditChanges(log){
  const before=log.before_data||{}, after=log.after_data||{};
  const skip=new Set(['id','business_id','created_at','updated_at']);
  const keys=[...new Set([...Object.keys(before),...Object.keys(after)])].filter(k=>!skip.has(k));
  const map=auditFieldMap();
  const changes=keys.filter(k=>JSON.stringify(before[k])!==JSON.stringify(after[k])).map(k=>({key:k,label:(log.module==='payments'&&k==='amount'?'Jumlah Pembayaran':map[k]||k),before:auditFormatValue(k,before[k]),after:auditFormatValue(k,after[k])}));
  if(log.module==='sales'&&log.action==='UPDATE'){
    const a=paymentStatusFrom(before), b=paymentStatusFrom(after); if(a&&b&&a!==b) changes.push({key:'payment_status',label:'Status Pembayaran',before:a,after:b});
  }
  return changes;
}
function auditSummary(log){
  const label=log.record_label||'data';
  if(log.action==='CREATE') return `Menambahkan ${auditModuleLabel(log.module).toLowerCase()} · ${label}`;
  if(log.action==='DELETE') return `Menghapus ${auditModuleLabel(log.module).toLowerCase()} · ${label}`;
  if(log.action==='SECURITY') return 'Mengatur / mengganti Security Key penghapusan';
  const changes=auditChanges(log);
  if(!changes.length) return `Memperbarui ${auditModuleLabel(log.module).toLowerCase()} · ${label}`;
  return changes.slice(0,2).map(c=>`${c.label}: ${c.before} → ${c.after}`).join(' · ')+(changes.length>2?` · +${changes.length-2} perubahan`:'');
}
function renderAuditLog(){
  if(!can('audit')) return accessDenied('Audit Log');
  const logs=businessData(state.auditLogs||[]).slice().sort((a,b)=>String(b.created_at||'').localeCompare(String(a.created_at||'')));
  const edits=logs.filter(x=>x.action==='UPDATE').length, deletes=logs.filter(x=>x.action==='DELETE').length;
  return `<div class="audit-kpi-grid">
    <div class="audit-kpi"><span>Total Aktivitas</span><strong>${num(logs.length)}</strong></div>
    <div class="audit-kpi"><span>Perubahan Data</span><strong>${num(edits)}</strong></div>
    <div class="audit-kpi"><span>Penghapusan</span><strong>${num(deletes)}</strong></div>
    <div class="audit-kpi"><span>Aktivitas Terakhir</span><strong class="audit-last">${logs[0]?auditDateTime(logs[0].created_at):'Belum ada'}</strong></div>
  </div>
  <div class="audit-note"><b>Jejak aktivitas tidak untuk diedit.</b><span>Gunakan Audit Log untuk mengecek perubahan transaksi, produk, stok, biaya, dan tindakan security. Pada Cloud, hanya owner/admin yang dapat melihat log.</span></div>
  <div class="toolbar audit-toolbar">
    <div class="toolbar-left audit-filters"><input class="search" id="auditSearch" placeholder="Cari user / data / ringkasan" />
      <select id="auditActionFilter" class="filter-select"><option value="">Semua Aktivitas</option><option value="CREATE">Tambah</option><option value="UPDATE">Edit</option><option value="DELETE">Hapus</option><option value="SECURITY">Security</option></select>
      <select id="auditModuleFilter" class="filter-select"><option value="">Semua Modul</option><option value="sales">Penjualan</option><option value="payments">Pembayaran</option><option value="products">Produk</option><option value="stock">Stok</option><option value="expenses">Biaya</option><option value="security">Security</option><option value="business">Bisnis</option></select>
    </div>
    <div class="toolbar-right"><button class="ghost" data-action="refresh-audit">↻ Refresh</button></div>
  </div>
  <div class="table-card audit-table-card"><div class="table-head"><h3>Riwayat Aktivitas</h3><span class="muted">${logs.length} log terakhir</span></div><div class="table-wrap"><table class="audit-table"><thead><tr><th>Waktu</th><th>User</th><th>Modul</th><th>Aktivitas</th><th>Data</th><th>Ringkasan</th><th>Detail</th></tr></thead><tbody>${logs.length?logs.map(log=>`<tr class="audit-row" data-audit-action="${escapeAttr(log.action||'')}" data-audit-module="${escapeAttr(log.module||'')}" data-audit-search="${escapeAttr((auditActor(log)+' '+(log.record_label||'')+' '+auditSummary(log)).toLowerCase())}"><td>${auditDateTime(log.created_at)}</td><td><div class="audit-user"><span class="avatar-mini">${escapeHtml(auditActor(log).slice(0,1).toUpperCase())}</span><span>${escapeHtml(auditActor(log))}</span></div></td><td>${escapeHtml(auditModuleLabel(log.module))}</td><td><span class="pill ${auditActionClass(log.action)}">${escapeHtml(auditActionLabel(log.action))}</span></td><td>${escapeHtml(log.record_label||'-')}</td><td class="audit-summary">${escapeHtml(auditSummary(log))}</td><td><button type="button" class="row-action edit" data-action="open-audit-detail" data-id="${log.id}">Lihat</button></td></tr>`).join(''):`<tr><td colspan="7"><div class="empty">Belum ada aktivitas yang tercatat.</div></td></tr>`}</tbody></table></div></div>`;
}
function bindAuditFilters(){
  const q=$('#auditSearch'), a=$('#auditActionFilter'), m=$('#auditModuleFilter'); if(!q&&!a&&!m) return;
  const apply=()=>{$$('.audit-row').forEach(r=>{const okQ=!q?.value||String(r.dataset.auditSearch||'').includes(q.value.toLowerCase());const okA=!a?.value||r.dataset.auditAction===a.value;const okM=!m?.value||r.dataset.auditModule===m.value;r.style.display=okQ&&okA&&okM?'':'none';});};
  if(q)q.oninput=apply;if(a)a.onchange=apply;if(m)m.onchange=apply;
}
function cloneAuditData(obj){ if(!obj)return null; return JSON.parse(JSON.stringify(obj)); }
function localActor(){ return state.session?.user?.email || 'Demo Owner'; }
function localAudit(action,module,recordId,recordLabel,beforeData=null,afterData=null){
  state.auditLogs=state.auditLogs||[];
  state.auditLogs.unshift({id:uid(),business_id:state.currentBusinessId,actor_email:localActor(),action,module,record_id:recordId||null,record_label:recordLabel||'',before_data:cloneAuditData(beforeData),after_data:cloneAuditData(afterData),created_at:new Date().toISOString()});
  if(state.auditLogs.length>500) state.auditLogs=state.auditLogs.slice(0,500);
}
function openAuditDetailModal(id){
  const log=(state.auditLogs||[]).find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(!log){toast('Audit log tidak ditemukan');return;}
  const changes=auditChanges(log);
  const snapshot=log.action==='DELETE'?(log.before_data||{}):(log.after_data||{});
  const map=auditFieldMap();
  const snapshotRows=Object.entries(snapshot).filter(([k])=>!['id','business_id','created_at','updated_at'].includes(k)).slice(0,12);
  openModal(`<div class="modal-title"><h2>Detail Audit Log</h2><button class="modal-close">×</button></div><div class="audit-detail-wrap">
    <div class="audit-detail-head"><span class="pill ${auditActionClass(log.action)}">${escapeHtml(auditActionLabel(log.action))}</span><div><b>${escapeHtml(auditModuleLabel(log.module))} · ${escapeHtml(log.record_label||'-')}</b><small>${escapeHtml(auditActor(log))} · ${auditDateTime(log.created_at)}</small></div></div>
    <div class="audit-summary-box">${escapeHtml(auditSummary(log))}</div>
    ${changes.length?`<div class="audit-change-list"><h4>Perubahan</h4>${changes.map(c=>`<div class="audit-change"><span>${escapeHtml(c.label)}</span><div><del>${escapeHtml(c.before)}</del><b>→</b><ins>${escapeHtml(c.after)}</ins></div></div>`).join('')}</div>`:''}
    ${snapshotRows.length?`<div class="audit-snapshot"><h4>${log.action==='DELETE'?'Data sebelum dihapus':'Snapshot data'}</h4><div class="snapshot-grid">${snapshotRows.map(([k,v])=>`<div><span>${escapeHtml(map[k]||k)}</span><strong>${escapeHtml(auditFormatValue(k,v))}</strong></div>`).join('')}</div></div>`:''}
    <div class="form-note">Audit Log bersifat read-only. Security Key/PIN tidak pernah disimpan di log.</div>
    <div class="modal-actions"><button type="button" class="primary modal-close">Tutup</button></div>
  </div>`);
}

function accessDenied(name){return `<div class="panel access-denied"><div class="lock-icon">🔒</div><h3>Akses ${escapeHtml(name)} dibatasi</h3><p>Role <b>${escapeHtml(ROLE_LABELS[currentRole()]||currentRole())}</b> tidak memiliki izin untuk membuka modul ini.</p></div>`}
function renderTeam(){
  if(!can('team_view'))return accessDenied('Tim & Role');
  const rows=state.teamMembers||[]; const owner=currentRole()==='owner';
  const memberRows=rows.map(m=>{
    const pending=m.status==='pending';
    const statusHtml=pending?'<span class="pill warn">Menunggu Undangan</span>':'<span class="pill good">Aktif</span>';
    const actionHtml=owner?`<div class="row-actions"><button class="row-action edit" data-action="edit-member" data-id="${m.user_id}" data-role="${m.role}" data-email="${escapeAttr(m.email||'')}">Ubah Role</button>${pending?'':`<button class="row-action" data-action="reset-member-password" data-id="${m.user_id}" data-email="${escapeAttr(m.email||'')}">Reset Password</button>`}<button class="row-action delete" data-action="remove-member" data-id="${m.user_id}" data-email="${escapeAttr(m.email||'')}">${pending?'Batalkan':'Hapus / Cabut Akses'}</button></div>`:'—';
    return `<tr><td>${escapeHtml(m.email||m.user_id||'-')}</td><td><span class="role-chip role-${escapeAttr(m.role)}">${escapeHtml(ROLE_LABELS[m.role]||m.role)}</span></td><td>${statusHtml}</td><td>${actionHtml}</td></tr>`;
  }).join('');
  return `<div class="role-guide"><div><b>Owner</b><span>Semua akses & security</span></div><div><b>Admin</b><span>Operasional penuh</span></div><div><b>Kasir</b><span>Kasir & pembayaran</span></div><div><b>Finance</b><span>Biaya & laporan</span></div><div><b>Gudang</b><span>Produk & stok</span></div></div>
  <div class="toolbar"><div class="toolbar-left"><span class="muted">${rows.length} anggota + owner</span></div><div class="toolbar-right">${owner&&state.mode==='cloud'?'<button class="primary" data-action="add-member">+ Undang Anggota</button>':''}</div></div>
  ${owner&&state.mode==='cloud'?'<div class="panel team-invite-info"><b>Alur tim baru</b><p class="muted">Masukkan email dan role. Jika email belum punya akun, BizControl mengirim undangan. Jika akun sudah ada, akses bisnis langsung diaktifkan. Karyawan tidak perlu daftar manual dari halaman depan.</p></div>':''}
  <div class="table-card"><div class="table-head"><h3>Hak Akses Tim</h3><span class="muted">${state.mode==='local'?'Demo role preview':'Cloud'}</span></div><div class="table-wrap"><table><thead><tr><th>User</th><th>Role</th><th>Status</th><th>Aksi</th></tr></thead><tbody><tr><td>${escapeHtml(state.mode==='cloud'?(state.session?.user?.email||'Owner'):'demo@bizcontrol.local')}</td><td><span class="role-chip role-owner">Owner</span></td><td><span class="pill good">Aktif</span></td><td>—</td></tr>${memberRows}</tbody></table></div></div>
  ${state.mode==='local'?`<div class="panel" style="margin-top:14px"><div class="panel-title"><h3>Preview Role di Demo</h3><span>Testing UI</span></div><div class="segmented role-preview">${Object.keys(ROLE_LABELS).map(r=>`<button class="segment ${currentRole()===r?'active':''}" data-action="preview-role" data-role="${r}">${ROLE_LABELS[r]}</button>`).join('')}</div><p class="micro">Preview ini hanya untuk menguji tampilan/hak akses di mode demo. Cloud memakai role database asli.</p></div>`:''}`;
}
function renderSettingsPage(){
  const canEdit=can('business_edit');
  return `<div class="panel">
    <div class="setting-block"><div class="status-row"><div><h3>Akun & Role</h3><div class="muted">${state.mode==='cloud'?escapeHtml(state.session?.user?.email||'User cloud'):'Mode Demo — tanpa login'}</div></div>${roleBadge()}</div>${state.mode==='local'?'<div class="toolbar-left"><button class="soft-btn" data-action="open-auth">Masuk ke Cloud</button><button class="ghost" data-action="contact-admin">Daftar — Chat Admin</button></div>':''}</div>
    ${state.mode==='cloud'?`<div class="setting-block"><h3>Akun & Password</h3><p class="muted">Ganti password akun Anda sendiri kapan saja.</p><button class="soft-btn" data-action="change-password">Ganti Password</button></div>`:''}
    ${state.mode==='local'?`<div class="demo-security-warning"><b>MODE DEMO</b><span>Sandbox simulasi tanpa login. Data hanya tersimpan di browser dan tidak masuk ke database cloud. Jangan masukkan data bisnis/customer asli.</span></div><div class="setting-block"><h3>Kontrol Demo</h3><p class="muted">Kembalikan semua data simulasi ke kondisi awal kapan saja.</p><div class="toolbar-left"><button class="ghost" data-action="reset-demo">Reset Data Demo</button><button class="primary" data-action="open-auth">Masuk ke Cloud</button><button class="ghost" data-action="contact-admin">Daftar — Chat Admin</button></div></div><div class="setting-block"><h3>Preview Role Demo</h3><p class="muted">Uji tampilan dan menu untuk role berbeda.</p><div class="segmented role-preview">${Object.keys(ROLE_LABELS).map(r=>`<button class="segment ${currentRole()===r?'active':''}" data-action="preview-role" data-role="${r}">${ROLE_LABELS[r]}</button>`).join('')}</div></div>`:''}
    <div class="setting-block"><div class="status-row"><div><h3>Mode Data</h3><div class="muted">${state.mode==='cloud'?'Cloud BizControl — data tersimpan dan sinkron antar perangkat':'Demo Sandbox — data simulasi hanya di browser ini'}</div></div><span class="pill ${state.mode==='cloud'?'good':'warn'}">${state.mode==='cloud'?'CLOUD':'DEMO'}</span></div></div>
    ${state.isSystemAdmin?`<div class="setting-block admin-system-card"><h3>Admin Sistem</h3><p class="muted">Khusus pengelola BizControl: undang Owner baru dan kirim reset password Owner.</p><button class="soft-btn" data-nav="systemAdmin">Buka Admin Sistem</button></div>`:''}
    ${canEdit&&activeBusiness()?`<div class="setting-block"><h3>Profil & Kontrol Bisnis</h3><p class="muted">Profil dokumen dan kebijakan stok.</p><div class="status-row"><span class="micro">${escapeHtml(activeBusiness()?.address||'Alamat bisnis belum diatur')} · Stok minus: <b>${activeBusiness()?.allow_negative_stock?'Diizinkan':'Diblokir'}</b></span><button class="soft-btn" data-action="business-profile">Atur Profil & Stok</button></div></div>`:''}
    ${currentRole()==='owner'&&activeBusiness()?`<div class="setting-block"><h3>Security Key Hapus Data</h3><p class="muted">PIN 6 digit. Cloud mengunci 15 menit setelah 5 percobaan salah.</p><button class="soft-btn" data-action="security-key">Atur / Ganti Key</button></div>`:''}
    ${can('team_view')&&activeBusiness()?`<div class="setting-block"><h3>Tim & Role</h3><p class="muted">Owner dapat mengundang, mengubah role, mengirim reset password, dan mencabut akses karyawan.</p><button class="soft-btn" data-nav="team">Buka Pengaturan Tim</button></div>`:''}
    ${can('audit')&&activeBusiness()?`<div class="setting-block"><h3>Audit Log</h3><p class="muted">Jejak perubahan data.</p><button class="soft-btn" data-nav="audit">Buka Audit Log</button></div>`:''}
    ${state.mode==='cloud'?`<div class="setting-block"><h3>Cloud & Sinkronisasi</h3><p class="muted">Koneksi server dikelola otomatis oleh sistem dan tidak dapat diubah dari akun Owner.</p><div class="status-row"><span class="micro">${isOnline()?'Internet terdeteksi':'Sedang offline'} · ${state.lastSync?'Sync terakhir '+new Date(state.lastSync).toLocaleString('id-ID'):'Belum sync'}</span><span class="pill good">DIKELOLA SISTEM</span></div></div>`:''}
    ${((can('export')&&activeBusiness())||state.mode==='local')?`<div class="setting-block"><h3>Backup & Export</h3><p class="muted">JSON untuk backup penuh; CSV untuk dipindahkan ke Excel.</p><div class="toolbar-left"><button class="ghost" data-action="export-json">Backup JSON</button><button class="ghost" data-action="export-all-csv">Export Semua CSV</button>${state.mode==='local'?'<button class="ghost" data-action="import-json">Import JSON</button>':''}</div></div>`:''}
    <div class="setting-block"><h3>Nomor Dokumen</h3><p class="muted">INV/KWT/SJ Cloud dibuat atomik di database dan dilindungi unique index.</p></div>
    <div class="setting-block"><h3>Versi</h3><div class="status-row"><span>BizControl Online</span><span class="code-chip">V1.8.7.2 Permission/Deploy Fix</span></div></div>
  </div>`;
}

function renderSystemAdmin(){
  if(state.mode!=='cloud'||!state.isSystemAdmin)return accessDenied('Admin Sistem');
  const rows=(state.managedOwners||[]).map(o=>`<tr><td>${escapeHtml(o.email||'-')}</td><td><span class="pill ${o.status==='active'?'good':'warn'}">${o.status==='active'?'Aktif':'Menunggu Undangan'}</span></td><td>${num(o.business_count||0)}</td><td>${o.created_at?new Date(o.created_at).toLocaleDateString('id-ID'):'-'}</td><td><button class="row-action" data-action="reset-owner-password" data-email="${escapeAttr(o.email||'')}">Kirim Reset Password</button></td></tr>`).join('');
  return `<div class="panel admin-system-panel">
    <div class="demo-security-warning admin-only-warning"><b>ADMIN SISTEM</b><span>Menu ini hanya aktif untuk email Admin BizControl yang diizinkan di Edge Function. Tombol yang dipaksa muncul lewat DevTools tetap tidak dapat menjalankan aksi tanpa otorisasi server.</span></div>
    <div class="setting-block"><h3>Daftarkan Owner Baru</h3><p class="muted">Owner baru menerima email undangan, membuat password, lalu akun dapat membuat bisnis Cloud. Tidak ada pendaftaran publik.</p><form id="systemOwnerInviteForm" class="inline-admin-form"><input name="email" type="email" placeholder="owner@bisnis.com" required autocomplete="email"><button class="primary" type="submit">Kirim Undangan Owner</button></form></div>
    <div class="table-card"><div class="table-head"><h3>Owner yang Dikelola</h3><button class="ghost" data-action="refresh-managed-owners">↻ Refresh</button></div><div class="table-wrap"><table><thead><tr><th>Email Owner</th><th>Status</th><th>Bisnis</th><th>Sejak</th><th>Aksi</th></tr></thead><tbody>${rows||'<tr><td colspan="5" class="empty">Belum ada owner terkelola.</td></tr>'}</tbody></table></div></div>
  </div>`;
}

function bindPageActions(){
  $$('[data-action]').forEach(el=>el.onclick=(e)=>{ e.stopPropagation(); handleAction(el.dataset.action,el); });
  $$('[data-nav]').forEach(el=>el.onclick=()=>navigate(el.dataset.nav));
  const ss=$('#salesSearch'); if(ss) ss.oninput=()=>filterRows(ss,'table tbody tr');
  const ps=$('#productSearch'); if(ps) ps.oninput=()=>filterRows(ps,'table tbody tr');
  const es=$('#expenseSearch'); if(es) es.oninput=()=>filterRows(es,'table tbody tr');
  bindAuditFilters();
  const ownerInviteForm=$('#systemOwnerInviteForm');
  if(ownerInviteForm) ownerInviteForm.onsubmit=async e=>{e.preventDefault();const f=new FormData(ownerInviteForm);await withSubmitBusy(ownerInviteForm,async()=>{try{const result=await invokeAccountAdmin('invite-owner',{email:f.get('email'),redirect_to:recoveryRedirectUrl()});ownerInviteForm.reset();await loadManagedOwners();render();toast(result?.message||'Undangan Owner diproses','success',6500)}catch(err){toast(err.message,'error');throw err}})};
}
function filterRows(input,selector){ const q=input.value.toLowerCase(); $$(selector).forEach(r=>r.style.display=r.textContent.toLowerCase().includes(q)?'':'none'); }

function handleAction(action,el){
  const id=el?.dataset?.id;
  if(action==='add-sale') return requirePermission('sales_create')&&openSaleModal();
  if(action==='edit-sale') return requirePermission('sales_edit')&&openSaleModal(id);
  if(action==='print-sale') return requirePermission('print')&&openPrintDocumentModal(id);
  if(action==='payments-sale') return requirePermission('payments_manage')&&openPaymentsModal(id);
  if(action==='add-payment') return openPaymentModal(id);
  if(action==='edit-payment') return openPaymentModal(el?.dataset?.saleId,id);
  if(action==='print-payment-receipt') return printSaleDocument(el?.dataset?.saleId,'receipt',id);
  if(action==='delete-payment') return requestSecureDelete('payment',id,'pembayaran '+(state.payments.find(x=>x.id===id)?.payment_no||''),'sales');
  if(action==='delete-sale') return requirePermission('sales_delete')&&requestSecureDelete('sale',id,'transaksi '+(state.sales.find(x=>x.id===id)?.invoice_no||''),'sales');
  if(action==='add-product') return requirePermission('products_create')&&openProductModal();
  if(action==='edit-product') return (can('products_edit')||can('products_stock_edit'))?openProductModal(id):toast('Tidak diizinkan','error');
  if(action==='delete-product') return requirePermission('products_delete')&&requestSecureDelete('product',id,'produk '+(state.products.find(x=>x.id===id)?.name||''),'products');
  if(action==='add-expense') return requirePermission('expenses_edit')&&openExpenseModal();
  if(action==='edit-expense') return requirePermission('expenses_edit')&&openExpenseModal(id);
  if(action==='delete-expense') return requirePermission('expenses_delete')&&requestSecureDelete('expense',id,'biaya '+(state.expenses.find(x=>x.id===id)?.description||''),'expenses');
  if(action==='business-profile') return requirePermission('business_edit')&&openBusinessProfileModal();
  if(action==='security-key') return currentRole()==='owner'?openSecurityKeyModal():toast('Hanya owner yang dapat mengatur Security Key','error');
  if(action==='open-auth') return openCloudAuth();
  if(action==='contact-admin') return contactSystemAdmin();
  if(action==='change-password') return openChangePasswordModal();
  if(action==='export-json') return exportJson();
  if(action==='import-json') return importJson();
  if(action==='open-day-sales') return openDaySalesModal(el?.dataset?.date);
  if(action==='open-weekly-sales') return openWeeklySalesModal();
  if(action==='open-health-summary') return openHealthSummaryModal();
  if(action==='open-low-stock') return openLowStockModal();
  if(action==='open-receivable-summary') return openReceivableSummaryModal();
  if(action==='open-expense-summary') return openExpenseSummaryModal();
  if(action==='open-revenue-summary') return openRevenueSummaryModal();
  if(action==='open-profit-summary') return openProfitSummaryModal();
  if(action==='open-audit-detail') return openAuditDetailModal(id);
  if(action==='refresh-audit') return refreshAuditLog();
  if(action==='export-sales') return requirePermission('export')&&exportCsv('penjualan',businessData(state.sales));
  if(action==='export-products') return requirePermission('export')&&exportCsv('produk',businessData(state.products));
  if(action==='export-expenses') return requirePermission('export')&&exportCsv('biaya',businessData(state.expenses));
  if(action==='export-all-csv') return exportAllCsv();
  if(action==='add-member') return openMemberModal();
  if(action==='edit-member') return openMemberModal({user_id:id,email:el.dataset.email,role:el.dataset.role});
  if(action==='remove-member') return removeMember(id,el.dataset.email);
  if(action==='reset-member-password') return sendMemberPasswordReset(id,el.dataset.email);
  if(action==='reset-owner-password') return sendOwnerPasswordReset(el.dataset.email);
  if(action==='refresh-managed-owners') return loadManagedOwners().then(()=>render()).then(()=>toast('Daftar Owner diperbarui','success')).catch(e=>toast(e.message,'error'));
  if(action==='preview-role'){state.demoRole=el.dataset.role;persist();render();toast('Preview role: '+ROLE_LABELS[state.demoRole]);return;}
  if(action==='logout') return logoutCloud();
  if(action==='reset-demo'){ if(confirm('Reset seluruh data demo ke kondisi awal?')){ localStorage.removeItem('bizcontrol_v1'); localStorage.removeItem('bc_delete_keys'); state=defaultState();state.mode='local';state.page='dashboard'; persist(); render(); toast('Data demo dikembalikan ke kondisi awal','success'); }}
}

function openModal(html){
  const backdrop=$('#modalBackdrop'), card=$('#modalCard');
  card.innerHTML=html;
  backdrop.classList.remove('hidden');
  document.body.classList.add('modal-open');
  card.scrollTop=0;
  $$('.modal-close').forEach(b=>b.onclick=closeModal);
  enhanceResponsiveTables(card);
  backdrop.onclick=e=>{ if(e.target===backdrop) closeModal(); };
  requestAnimationFrame(()=>{ const first=card.querySelector('input:not([type=hidden]),select,button'); first?.focus({preventScroll:true}); });
}
function closeModal(){
  $('#modalBackdrop').classList.add('hidden');
  document.body.classList.remove('modal-open');
}
document.addEventListener('keydown',e=>{ if(e.key==='Escape'&&!$('#modalBackdrop').classList.contains('hidden')) closeModal(); });


function summaryStat(label,value){ return `<div class="metric-row"><span>${label}</span><strong>${value}</strong></div>`; }
function openRevenueSummaryModal(){
  if(currentRole()==='warehouse'||!canSeeFinancial()) return toast('Role ini tidak memiliki akses omzet','error');
  const m=metrics();
  const count=m.sales.length;
  openModal(`<div class="modal-title"><h2>Ringkasan Omzet</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="metric-list">${summaryStat('Omzet bulan ini',rupiah(m.revenue))}${summaryStat('Omzet hari ini',rupiah(m.todayRevenue))}${summaryStat('Jumlah transaksi',num(count))}${summaryStat('Rata-rata per transaksi',rupiah(count?m.revenue/count:0))}</div><div class="form-note" style="margin-top:14px">Klik chart omzet 7 hari di dashboard untuk melihat detail penjualan per hari.</div></div>`);
}
function openProfitSummaryModal(){
  if(!canSeeFinancial()) return toast('Role ini tidak memiliki akses profit','error');
  const m=metrics();
  openModal(`<div class="modal-title"><h2>Ringkasan Profit</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="metric-list">${summaryStat('Omzet bulan ini',rupiah(m.revenue))}${summaryStat('HPP bulan ini',rupiah(m.hpp))}${summaryStat('Laba kotor',rupiah(m.gross))}${summaryStat('Biaya bulan ini',rupiah(m.exp))}<div class="metric-row total"><span>Laba bersih</span><strong>${rupiah(m.net)}</strong></div>${summaryStat('Margin bersih',((m.margin||0)*100).toFixed(1)+'%')}</div></div>`);
}
function openWeeklySalesModal(){
  const m=metrics(); const warehouse=currentRole()==='warehouse';
  const rows=[...Array(7)].map((_,i)=>{ const d=new Date(Date.now()-(6-i)*86400000).toISOString().slice(0,10); const daySales=m.sales.filter(s=>s.date===d); const total=daySales.reduce((a,s)=>a+Number(s.total||0),0); const gp=daySales.reduce((a,s)=>a+Number(s.gross_profit||0),0); return {d,count:daySales.length,total,gp}; });
  if(warehouse){
    openModal(`<div class="modal-title"><h2>Aktivitas Pengiriman 7 Hari</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="table-wrap"><table><thead><tr><th>Hari</th><th>Tanggal</th><th>Transaksi / Pengiriman</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${new Date(r.d+'T00:00:00').toLocaleDateString('id-ID',{weekday:'long'})}</td><td>${fmtDate(r.d)}</td><td>${num(r.count)}</td></tr>`).join('')}</tbody></table></div></div>`); return;
  }
  openModal(`<div class="modal-title"><h2>Omzet 7 Hari Terakhir</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="table-wrap"><table><thead><tr><th>Hari</th><th>Tanggal</th><th>Transaksi</th><th>Omzet</th><th>Laba Kotor</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${new Date(r.d+'T00:00:00').toLocaleDateString('id-ID',{weekday:'long'})}</td><td>${fmtDate(r.d)}</td><td>${num(r.count)}</td><td class="money">${rupiah(r.total)}</td><td class="money">${canSeeFinancial()?rupiah(r.gp):'—'}</td></tr>`).join('')}</tbody></table></div><div class="form-note" style="margin-top:14px">Tip: klik batang pada chart dashboard untuk membuka detail transaksi per hari.</div></div>`);
}
function openDaySalesModal(dateStr){
  const m=metrics(); const warehouse=currentRole()==='warehouse';
  const targetDate=dateStr||today();
  const list=m.sales.filter(s=>s.date===targetDate).sort((a,b)=>String(a.invoice_no).localeCompare(String(b.invoice_no)));
  if(warehouse){
    openModal(`<div class="modal-title"><h2>Pengiriman Harian</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="metric-list">${summaryStat('Tanggal',fmtDate(targetDate))}${summaryStat('Jumlah transaksi / pengiriman',num(list.length))}</div>${list.length?`<div class="table-wrap" style="margin-top:14px"><table><thead><tr><th>Invoice</th><th>Surat Jalan</th><th>Customer</th><th>Tujuan</th><th>Produk</th><th>Qty</th></tr></thead><tbody>${list.map(s=>`<tr><td>${escapeHtml(s.invoice_no||'-')}</td><td>${escapeHtml(s.delivery_no||'-')}</td><td>${escapeHtml(s.customer||'-')}</td><td>${escapeHtml(s.customer_address||'-')}</td><td>${escapeHtml(saleItemsLabel(s))}</td><td>${num(saleItemsQty(s))}</td></tr>`).join('')}</tbody></table></div>`:`<div class="empty" style="padding:22px 0">Tidak ada transaksi pada hari ini.</div>`}</div>`); return;
  }
  const total=list.reduce((a,s)=>a+Number(s.total||0),0); const paid=list.reduce((a,s)=>a+Number(s.paid_amount||0),0); const gp=list.reduce((a,s)=>a+Number(s.gross_profit||0),0);
  openModal(`<div class="modal-title"><h2>Detail Omzet Harian</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="metric-list">${summaryStat('Tanggal',fmtDate(targetDate))}${summaryStat('Jumlah transaksi',num(list.length))}${summaryStat('Omzet',rupiah(total))}${summaryStat('Dibayar',rupiah(paid))}${canSeeFinancial()?summaryStat('Laba kotor',rupiah(gp)):''}</div>${list.length?`<div class="table-wrap" style="margin-top:14px"><table><thead><tr><th>Invoice</th><th>Customer</th><th>Produk</th><th>Qty</th><th>Total</th><th>Status</th></tr></thead><tbody>${list.map(s=>{const due=Math.max(Number(s.total)-Number(s.paid_amount),0);return `<tr><td>${escapeHtml(s.invoice_no||'-')}</td><td>${escapeHtml(s.customer||'-')}</td><td>${escapeHtml(saleItemsLabel(s))}</td><td>${num(saleItemsQty(s))}</td><td class="money">${rupiah(s.total)}</td><td><span class="pill ${due?'warn':'good'}">${due?'Belum Lunas':'Lunas'}</span></td></tr>`}).join('')}</tbody></table></div>`:`<div class="empty" style="padding:22px 0">Tidak ada transaksi pada hari ini.</div>`}</div>`);
}
function openHealthSummaryModal(){
  const m=metrics();
  const marginPct=((m.margin||0)*100).toFixed(1)+'%';
  const note=m.score>=80?'Kondisi cukup sehat':m.score>=60?'Perlu beberapa perhatian':'Perlu tindakan prioritas';
  openModal(`<div class="modal-title"><h2>Business Health</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="metric-list"><div class="metric-row total"><span>Skor saat ini</span><strong>${m.score}/100</strong></div>${summaryStat('Status',note)}${summaryStat('Margin bersih',marginPct)}${summaryStat('Stok menipis',num(m.lowStock))}${summaryStat('Piutang',rupiah(m.receivable))}${summaryStat('Biaya bulan ini',rupiah(m.exp))}</div><div class="form-note" style="margin-top:14px">Skor ini adalah indikator cepat V1. Semakin bagus margin, semakin rendah piutang bermasalah, dan semakin sedikit stok kritis, maka skor akan naik.</div><div class="toolbar-left" style="margin-top:14px;flex-wrap:wrap"><button class="ghost" type="button" data-action="open-low-stock">Lihat stok menipis</button><button class="ghost" type="button" data-action="open-receivable-summary">Lihat piutang</button><button class="ghost" type="button" data-action="open-expense-summary">Lihat biaya</button></div></div>`);
  $$('[data-action]').forEach(el=>el.onclick=(e)=>{ e.stopPropagation(); handleAction(el.dataset.action,el); });
}
function openLowStockModal(){
  const items=businessData(state.products).filter(p=>p.category!=='Jasa'&&Number(p.stock)<=Number(p.min_stock));
  openModal(`<div class="modal-title"><h2>Produk Stok Menipis</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px">${items.length?`<div class="table-wrap"><table><thead><tr><th>SKU</th><th>Produk</th><th>Stok</th><th>Min Stok</th><th>Status</th></tr></thead><tbody>${items.map(p=>`<tr><td>${escapeHtml(p.sku)}</td><td>${escapeHtml(p.name)}</td><td>${num(p.stock)}</td><td>${num(p.min_stock)}</td><td><span class="pill bad">Restock</span></td></tr>`).join('')}</tbody></table></div>`:`<div class="empty">Tidak ada produk yang menipis saat ini.</div>`}<div class="modal-actions"><button type="button" class="ghost modal-close">Tutup</button><button type="button" class="primary" id="gotoProductsBtn">Buka Halaman Produk</button></div></div>`);
  const btn=$('#gotoProductsBtn'); if(btn) btn.onclick=()=>{ closeModal(); navigate('products'); };
}
function openReceivableSummaryModal(){
  if(currentRole()==='warehouse') return toast('Role Gudang tidak memiliki akses piutang','error');
  const rows=businessData(state.sales).map(s=>({...s,due:Math.max(Number(s.total||0)-Number(s.paid_amount||0),0)})).filter(s=>s.due>0).sort((a,b)=>b.due-a.due);
  const total=rows.reduce((a,s)=>a+s.due,0);
  openModal(`<div class="modal-title"><h2>Ringkasan Piutang</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="metric-list">${summaryStat('Total piutang',rupiah(total))}${summaryStat('Invoice belum lunas',num(rows.length))}</div>${rows.length?`<div class="table-wrap" style="margin-top:14px"><table><thead><tr><th>Invoice</th><th>Customer</th><th>Total</th><th>Dibayar</th><th>Piutang</th><th>Aksi</th></tr></thead><tbody>${rows.map(s=>`<tr><td>${escapeHtml(s.invoice_no||'-')}</td><td>${escapeHtml(s.customer||'-')}</td><td class="money">${rupiah(s.total)}</td><td class="money">${rupiah(s.paid_amount)}</td><td class="money">${rupiah(s.due)}</td><td><button type="button" class="row-action edit receivable-edit" data-id="${s.id}">Kelola Pembayaran</button></td></tr>`).join('')}</tbody></table></div>`:`<div class="empty" style="padding:22px 0">Tidak ada piutang. Semua transaksi sudah lunas.</div>`}</div>`);
  $$('.receivable-edit').forEach(b=>b.onclick=()=>{ const id=b.dataset.id; closeModal(); openPaymentsModal(id); });
}
function openExpenseSummaryModal(){
  const currentMonth=new Date().toISOString().slice(0,7);
  const rows=businessData(state.expenses).filter(e=>monthKey(e.date)===currentMonth).sort((a,b)=>String(b.date).localeCompare(String(a.date)));
  const total=rows.reduce((a,e)=>a+Number(e.amount||0),0);
  openModal(`<div class="modal-title"><h2>Biaya Bulan Ini</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px"><div class="metric-list">${summaryStat('Total biaya',rupiah(total))}${summaryStat('Jumlah catatan biaya',num(rows.length))}</div>${rows.length?`<div class="table-wrap" style="margin-top:14px"><table><thead><tr><th>Tanggal</th><th>Kategori</th><th>Deskripsi</th><th>Nilai</th></tr></thead><tbody>${rows.map(e=>`<tr><td>${fmtDate(e.date)}</td><td>${escapeHtml(e.category||'-')}</td><td>${escapeHtml(e.description||'-')}</td><td class="money">${rupiah(e.amount)}</td></tr>`).join('')}</tbody></table></div>`:`<div class="empty" style="padding:22px 0">Belum ada biaya pada bulan ini.</div>`}</div>`);
}

function openSaleModal(saleId=null){
  const products=businessData(state.products);
  if(!products.length){ toast('Tambahkan produk dulu'); openProductModal(); return; }
  const existing=saleId?state.sales.find(x=>x.id===saleId&&x.business_id===state.currentBusinessId):null;
  const editing=Boolean(existing);
  const submissionRequestId=existing?.client_request_id||newClientRequestId();
  const existingItems=editing?itemsForSale(existing.id):[];
  let cart=(existingItems.length?existingItems:[{product_id:products[0].id,qty:1}]).map((x,i)=>({product_id:x.product_id,qty:Number(x.qty||1),unit_price:Number(x.unit_price||0),unit_cost:Number(x.unit_cost||0),line_no:i+1}));
  const payMethods=['Cash','Transfer','QRIS','E-Wallet','Tempo'];
  openModal(`<div class="modal-title"><h2>${editing?'Edit Penjualan':'Penjualan Baru'}</h2><button class="modal-close">×</button></div>
  <form id="saleForm" class="form-grid sale-cart-form">
    <label>Tanggal<input name="date" type="date" value="${escapeAttr(existing?.date||today())}" required></label>
    <label>No. Invoice<input name="invoice_no" value="${escapeAttr(existing?.invoice_no||'Otomatis saat disimpan')}" readonly><small class="micro">Satu invoice dapat berisi banyak barang.</small></label>
    <label>Customer<input name="customer" value="${escapeAttr(existing?.customer||'')}" placeholder="Nama customer"></label>
    <label>No. HP Customer<input name="customer_phone" value="${escapeAttr(existing?.customer_phone||'')}" placeholder="08xxxxxxxxxx"></label>
    <label class="span-2">Alamat / Tujuan Pengiriman<textarea name="customer_address" rows="2" placeholder="Opsional — dipakai pada Surat Jalan">${escapeHtml(existing?.customer_address||'')}</textarea></label>
    <div class="span-2 sale-cart-block">
      <div class="sale-cart-head"><div><h3>Barang / Jasa</h3><small>Tambahkan beberapa item ke invoice yang sama.</small></div><button type="button" class="soft-btn" id="addCartItemBtn">+ Tambah Barang</button></div>
      <div id="saleCartRows" class="sale-cart-rows"></div>
    </div>
    <label>Diskon Invoice<input name="discount" type="number" min="0" value="${existing?.discount??0}"></label>
    <label>Metode Bayar${editing?`<input value="${escapeAttr(existing?.payment_method||'Lihat Riwayat Pembayaran')}" readonly><small class="micro">Metode awal; pembayaran berikutnya lewat Riwayat Pembayaran.</small>`:`<select name="payment_method" id="salePaymentMethod">${payMethods.map(v=>`<option ${v===(existing?.payment_method||'Cash')?'selected':''}>${v}</option>`).join('')}</select>`}</label>
    <label>${editing?'Sudah Dibayar':'Pembayaran Awal'}<input ${editing?'':'name="paid_amount"'} id="salePaidAmount" type="number" min="0" value="${editing?Number(existing?.paid_amount||0):''}" placeholder="Tempo kosong = Rp0" ${editing?'readonly':''}><small class="micro">${editing?'Dihitung dari Riwayat Pembayaran.':'DP/pembayaran awal otomatis menjadi Pembayaran #1.'}</small></label>
    <label class="span-2">Catatan Transaksi<textarea name="notes" rows="2" placeholder="Opsional — tampil di dokumen cetak">${escapeHtml(existing?.notes||'')}</textarea></label>
    <div class="span-2 payment-status-box"><div><span>Status Pembayaran</span><strong id="saleStatusText">—</strong><small id="saleCartSummary">—</small></div><button type="button" class="soft-btn" id="markPaidBtn">${editing?'Bayar Sisa / Tandai Lunas':'Tandai Lunas'}</button></div>
    <div class="span-2 form-note" id="salePreview"></div>
    <div class="span-2 modal-actions"><button type="button" class="ghost modal-close">Batal</button><button type="submit" class="primary">${editing?'Simpan Perubahan':'Simpan Penjualan'}</button></div>
  </form>`);
  const form=$('#saleForm');
  const lockedByProduct=new Map(existingItems.map(x=>[x.product_id,x]));
  const rowSnapshot=(line)=>{
    const p=products.find(x=>x.id===line.product_id);
    const locked=editing?lockedByProduct.get(line.product_id):null;
    return {p,qty:Number(line.qty||0),price:Number(locked?.unit_price??p?.price??0),cost:Number(locked?.unit_cost??p?.cost??0)};
  };
  const syncCartFromDom=()=>{
    const rows=[...document.querySelectorAll('.sale-cart-row')];
    cart=rows.map((row,i)=>({product_id:row.querySelector('.cart-product').value,qty:Number(row.querySelector('.cart-qty').value||0),line_no:i+1}));
  };
  const calc=()=>{
    syncCartFromDom();
    let subtotal=0,costTotal=0,totalQty=0;
    for(const line of cart){const x=rowSnapshot(line);subtotal+=x.qty*x.price;costTotal+=x.qty*x.cost;totalQty+=x.qty;}
    const disc=Math.max(Number(form.discount.value||0),0);const total=Math.max(subtotal-disc,0);
    const paidInput=$('#salePaidAmount').value;const method=editing?(existing?.payment_method||'Tempo'):$('#salePaymentMethod').value;
    const effectivePaid=editing?Number(existing?.paid_amount||0):(paidInput===''?(method==='Tempo'?0:total):Math.min(Number(paidInput||0),total));
    const due=Math.max(total-effectivePaid,0);
    $('#salePreview').innerHTML=`Subtotal ${rupiah(subtotal)} − diskon ${rupiah(disc)} = <strong>${rupiah(total)}</strong>`;
    $('#saleCartSummary').textContent=`${cart.length} jenis item · total qty ${num(totalQty)}`;
    $('#saleStatusText').textContent=due>0?`Belum Lunas · Sisa ${rupiah(due)}`:'Lunas';
    $('#saleStatusText').className=due>0?'status-warn':'status-good';
    document.querySelectorAll('.sale-cart-row').forEach((row,i)=>{const x=rowSnapshot(cart[i]);row.querySelector('.cart-price').textContent=rupiah(x.price);row.querySelector('.cart-stock').textContent=x.p?.category==='Jasa'?'Jasa':`Stok ${num(x.p?.stock||0)}`;row.querySelector('.cart-subtotal').textContent=rupiah(x.qty*x.price);});
    return {subtotal,costTotal,totalQty,disc,total,effectivePaid};
  };
  const renderCart=()=>{
    $('#saleCartRows').innerHTML=cart.map((line,i)=>`<div class="sale-cart-row" data-index="${i}"><div class="cart-index">${i+1}</div><label>Produk<select class="cart-product">${products.map(p=>`<option value="${p.id}" ${p.id===line.product_id?'selected':''}>${escapeHtml(p.sku)} — ${escapeHtml(p.name)}</option>`).join('')}</select></label><label>Qty<input class="cart-qty" type="number" min="0.01" step="0.01" value="${Number(line.qty||1)}"></label><div class="cart-meta"><span class="cart-price">Rp0</span><small class="cart-stock">—</small></div><strong class="cart-subtotal">Rp0</strong><button type="button" class="cart-remove" title="Hapus item" ${cart.length===1?'disabled':''}>×</button></div>`).join('');
    document.querySelectorAll('.sale-cart-row').forEach((row,i)=>{row.querySelector('.cart-product').onchange=calc;row.querySelector('.cart-qty').oninput=calc;row.querySelector('.cart-remove').onclick=()=>{if(cart.length<=1)return;syncCartFromDom();cart.splice(i,1);renderCart();};});
    calc();
  };
  $('#addCartItemBtn').onclick=()=>{syncCartFromDom();const used=new Set(cart.map(x=>x.product_id));const next=products.find(p=>!used.has(p.id))||products[0];cart.push({product_id:next.id,qty:1,line_no:cart.length+1});renderCart();};
  form.discount.oninput=calc; form.discount.onchange=calc; $('#salePaidAmount').oninput=calc; if(!editing)$('#salePaymentMethod').onchange=calc;
  $('#markPaidBtn').onclick=()=>{const c=calc();if(editing){closeModal();openPaymentModal(existing.id,null,true)}else{$('#salePaidAmount').value=c.total;calc()}};
  renderCart();
  form.onsubmit=async e=>{
    e.preventDefault();syncCartFromDom();const f=new FormData(form);
    if(!cart.length){toast('Tambahkan minimal 1 barang');return;}
    const ids=cart.map(x=>x.product_id);if(new Set(ids).size!==ids.length){toast('Produk yang sama cukup satu baris. Ubah Qty pada baris tersebut.','error');return;}
    for(const line of cart){if(Number(line.qty)<=0){toast('Qty setiap barang harus lebih dari 0','error');return;}const p=products.find(x=>x.id===line.product_id);if(!p){toast('Produk tidak ditemukan','error');return;}let available=Number(p.stock||0);if(editing){const old=lockedByProduct.get(p.id);if(old&&p.category!=='Jasa')available+=Number(old.qty||0);}if(p.category!=='Jasa'&&!activeBusiness()?.allow_negative_stock&&Number(line.qty)>available){toast(`Stok ${p.name} tidak cukup. Tersedia ${num(available)}`,'error');return;}}
    const calcData=calc();const rawPaid=editing?String(existing?.paid_amount||0):f.get('paid_amount');const saleMethod=editing?(existing?.payment_method||'Tempo'):f.get('payment_method');let paid=editing?Number(existing?.paid_amount||0):(rawPaid===''?(saleMethod==='Tempo'?0:calcData.total):Number(rawPaid||0));
    if(editing&&paid>calcData.total){toast('Total transaksi baru lebih kecil dari pembayaran yang sudah tercatat. Edit/hapus Riwayat Pembayaran terlebih dahulu.');return;}paid=Math.max(0,Math.min(paid,calcData.total));
    const lineItems=cart.map((line,i)=>{const x=rowSnapshot(line);return {business_id:state.currentBusinessId,sale_id:existing?.id||null,line_no:i+1,product_id:line.product_id,product_name:x.p?.name||'',unit:x.p?.unit||'pcs',qty:Number(line.qty),unit_price:x.price,unit_cost:x.cost,line_total:Number(line.qty)*x.price,line_gross_profit:Number(line.qty)*(x.price-x.cost)};});
    const first=lineItems[0];const summary=lineItems.length===1?first.product_name:`${first.product_name} +${lineItems.length-1} item`;
    const sale={business_id:state.currentBusinessId,client_request_id:submissionRequestId,date:f.get('date'),invoice_no:editing?existing.invoice_no:null,delivery_no:editing?existing.delivery_no:null,customer:f.get('customer'),customer_phone:f.get('customer_phone'),customer_address:f.get('customer_address'),notes:f.get('notes'),product_id:first.product_id,product_name:summary,qty:calcData.totalQty,unit_price:first.unit_price,unit_cost:first.unit_cost,discount:calcData.disc,total:calcData.total,gross_profit:calcData.total-calcData.costTotal,payment_method:saleMethod,paid_amount:paid,items:lineItems};
    await withSubmitBusy(form,async()=>{try{if(editing)await updateSale(existing.id,sale);else await addSale(sale);closeModal();navigate('sales');toast(editing?'Penjualan diperbarui':'Penjualan tersimpan','success')}catch(err){toast(err.message,'error',4500);throw err}},editing?'Menyimpan...':'Membuat invoice...');
  };
}

function openProductModal(productId=null){
  const existing=productId?state.products.find(x=>x.id===productId&&x.business_id===state.currentBusinessId):null;
  const editing=Boolean(existing);
  const submissionRequestId=existing?.client_request_id||newClientRequestId();
  const stockOnly=editing&&can('products_stock_edit')&&!can('products_edit');
  if(stockOnly){
    openModal(`<div class="modal-title"><h2>Update Stok Produk</h2><button class="modal-close">×</button></div><form id="productStockForm" class="form-grid">
      <label>SKU<input value="${escapeAttr(existing.sku||'')}" readonly></label><label>Nama Produk<input value="${escapeAttr(existing.name||'')}" readonly></label>
      <label>Stok Saat Ini<input name="stock" type="number" min="0" value="${existing.stock??0}" required></label><label>Min Stok<input name="min_stock" type="number" min="0" value="${existing.min_stock??0}" required></label>
      <div class="span-2 form-note">Role Gudang hanya dapat mengubah stok dan batas minimum stok. Harga, HPP, SKU, dan nama produk tetap terkunci.</div>
      <div class="span-2 modal-actions"><button type="button" class="ghost modal-close">Batal</button><button class="primary" type="submit">Simpan Stok</button></div>
    </form>`);
    $('#productStockForm').onsubmit=async e=>{e.preventDefault();const form=e.target;const f=new FormData(form);await withSubmitBusy(form,async()=>{try{await updateProductStock(existing.id,{stock:Number(f.get('stock')),min_stock:Number(f.get('min_stock'))});closeModal();navigate('products');toast('Stok diperbarui','success')}catch(err){toast(err.message,'error');throw err}})};
    return;
  }
  if(editing&&!requirePermission('products_edit'))return;
  if(!editing&&!requirePermission('products_create'))return;
  openModal(`<div class="modal-title"><h2>${editing?'Edit Produk / Jasa':'Produk / Jasa Baru'}</h2><button class="modal-close">×</button></div><form id="productForm" class="form-grid">
    <label>SKU<input name="sku" required value="${escapeAttr(existing?.sku||'')}" placeholder="PRD-001"></label><label>Nama<input name="name" required value="${escapeAttr(existing?.name||'')}" placeholder="Nama produk"></label>
    <label>Kategori<select name="category"><option ${existing?.category==='Produk'?'selected':''}>Produk</option><option ${existing?.category==='Jasa'?'selected':''}>Jasa</option></select></label><label>Satuan<input name="unit" value="${escapeAttr(existing?.unit||'pcs')}"></label>
    <label>HPP / Modal<input name="cost" type="number" min="0" value="${existing?.cost??0}" required></label><label>Harga Jual<input name="price" type="number" min="0" value="${existing?.price??0}" required></label>
    <label>${editing?'Stok Saat Ini':'Stok Awal'}<input name="stock" type="number" min="0" value="${existing?.stock??0}"></label><label>Min Stok<input name="min_stock" type="number" min="0" value="${existing?.min_stock??0}"></label>
    ${editing?`<div class="span-2 form-note">Perubahan stok di sini mengubah stok saat ini. Untuk produk yang sudah punya transaksi, penghapusan permanen akan diblokir agar histori penjualan tetap aman.</div>`:''}
    <div class="span-2 modal-actions"><button type="button" class="ghost modal-close">Batal</button><button class="primary" type="submit">${editing?'Simpan Perubahan':'Simpan Produk'}</button></div>
  </form>`);
  $('#productForm').onsubmit=async e=>{e.preventDefault();const form=e.target;const f=new FormData(form);const data={business_id:state.currentBusinessId,client_request_id:submissionRequestId,sku:f.get('sku'),name:f.get('name'),category:f.get('category'),unit:f.get('unit'),cost:Number(f.get('cost')),price:Number(f.get('price')),stock:Number(f.get('stock')),min_stock:Number(f.get('min_stock'))};await withSubmitBusy(form,async()=>{try{if(editing)await updateProduct(existing.id,data);else await addProduct(data);closeModal();navigate('products')}catch(err){toast(err.message,'error');throw err}})};
}

function openExpenseModal(expenseId=null){
  const existing=expenseId?state.expenses.find(x=>x.id===expenseId&&x.business_id===state.currentBusinessId):null;
  const editing=Boolean(existing);
  const submissionRequestId=existing?.client_request_id||newClientRequestId();
  const cats=['Operasional','Marketing','Gaji/Upah','Sewa','Utilitas','Transport','Administrasi','Lainnya'];
  const methods=['Cash','Transfer','QRIS','E-Wallet'];
  openModal(`<div class="modal-title"><h2>${editing?'Edit Biaya':'Biaya Baru'}</h2><button class="modal-close">×</button></div><form id="expenseForm" class="form-grid">
    <label>Tanggal<input name="date" type="date" value="${escapeAttr(existing?.date||today())}" required></label><label>Kategori<select name="category">${cats.map(v=>`<option ${v===(existing?.category||'Operasional')?'selected':''}>${v}</option>`).join('')}</select></label>
    <label class="span-2">Deskripsi<input name="description" value="${escapeAttr(existing?.description||'')}" required placeholder="Contoh: Iklan Meta Ads"></label><label>Nilai<input name="amount" type="number" min="0" value="${existing?.amount??''}" required></label><label>Metode<select name="payment_method">${methods.map(v=>`<option ${v===(existing?.payment_method||'Cash')?'selected':''}>${v}</option>`).join('')}</select></label>
    <div class="span-2 modal-actions"><button type="button" class="ghost modal-close">Batal</button><button class="primary" type="submit">${editing?'Simpan Perubahan':'Simpan Biaya'}</button></div>
  </form>`);
  $('#expenseForm').onsubmit=async e=>{e.preventDefault();const form=e.target;const f=new FormData(form);const data={business_id:state.currentBusinessId,client_request_id:submissionRequestId,date:f.get('date'),category:f.get('category'),description:f.get('description'),amount:Number(f.get('amount')),payment_method:f.get('payment_method')};await withSubmitBusy(form,async()=>{try{if(editing)await updateExpense(existing.id,data);else await addExpense(data);closeModal();navigate('expenses')}catch(err){toast(err.message,'error');throw err}})};
}


function openBusinessProfileModal(){
  const b=activeBusiness()||{};
  openModal(`<div class="modal-title"><h2>Profil Dokumen Bisnis</h2><button class="modal-close">×</button></div><form id="businessProfileForm" class="form-grid">
    <label>Nama Usaha<input name="name" value="${escapeAttr(b.name||'')}" required></label>
    <label>Kota<input name="city" value="${escapeAttr(b.city||'')}" placeholder="Contoh: Palembang"></label>
    <label>No. Telepon / WhatsApp<input name="phone" value="${escapeAttr(b.phone||'')}" placeholder="08xxxxxxxxxx"></label>
    <label>Email<input name="email" type="email" value="${escapeAttr(b.email||'')}" placeholder="nama@usaha.id"></label>
    <label class="span-2">Alamat Usaha<textarea name="address" rows="3" placeholder="Alamat lengkap usaha">${escapeHtml(b.address||'')}</textarea></label>
    <label class="span-2">Catatan Footer Dokumen<textarea name="document_footer" rows="2" placeholder="Contoh: Terima kasih atas kepercayaan Anda.">${escapeHtml(b.document_footer||'')}</textarea></label>
    <label class="span-2 checkbox-setting"><input name="allow_negative_stock" type="checkbox" ${b.allow_negative_stock?'checked':''}><span><b>Izinkan stok minus / backorder</b><small>Default tidak aktif. Jika mati, database menolak penjualan ketika stok tidak cukup.</small></span></label>
    <div class="span-2 form-note">Informasi ini akan tampil otomatis pada Invoice, Kwitansi, dan Surat Jalan.</div>
    <div class="span-2 modal-actions"><button type="button" class="ghost modal-close">Batal</button><button type="submit" class="primary">Simpan Profil</button></div>
  </form>`);
  $('#businessProfileForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target);const data={name:String(f.get('name')||'').trim(),city:String(f.get('city')||'').trim(),phone:String(f.get('phone')||'').trim(),email:String(f.get('email')||'').trim(),address:String(f.get('address')||'').trim(),document_footer:String(f.get('document_footer')||'').trim(),allow_negative_stock:f.get('allow_negative_stock')==='on'};try{await updateBusinessProfile(data);closeModal();render();toast('Profil dokumen disimpan');}catch(err){toast(err.message)}};
}

async function updateBusinessProfile(data){
  const b=activeBusiness(); if(!b) throw new Error('Bisnis aktif tidak ditemukan');
  if(state.mode==='cloud'){
    const rows=await cloudRequest(`/rest/v1/businesses?id=eq.${encodeURIComponent(b.id)}`,{method:'PATCH',body:data,prefer:true});
    if(rows?.[0]) Object.assign(b,rows[0]); else Object.assign(b,data);
    await cloudLoadBusinesses();
  }else{
    const before=cloneAuditData(b); Object.assign(b,data); localAudit('UPDATE','business',b.id,b.name,before,b); persist();
  }
}

function openPrintDocumentModal(saleId){
  const sale=state.sales.find(x=>x.id===saleId&&x.business_id===state.currentBusinessId); if(!sale){toast('Transaksi tidak ditemukan');return;}
  if(currentRole()==='warehouse'){
    openModal(`<div class="modal-title"><h2>Cetak Surat Jalan</h2><button class="modal-close">×</button></div><div class="document-modal-wrap"><div class="document-sale-summary"><div><span>Invoice</span><strong>${escapeHtml(sale.invoice_no||'-')}</strong></div><div><span>Surat Jalan</span><strong>${escapeHtml(sale.delivery_no||'-')}</strong></div><div><span>Customer</span><strong>${escapeHtml(sale.customer||'-')}</strong></div><div><span>Qty</span><strong>${num(sale.qty)}</strong></div></div><div class="document-choice-grid"><button type="button" class="document-choice doc-print-btn" data-doc="delivery"><span class="doc-icon">⇢</span><b>Surat Jalan</b><small>Barang, jumlah, tujuan, dan tanda tangan tanpa informasi harga.</small><em>Cetak Surat Jalan →</em></button></div><div class="modal-actions"><button type="button" class="primary modal-close">Selesai</button></div></div>`); $$('.doc-print-btn').forEach(btn=>btn.onclick=()=>printSaleDocument(saleId,'delivery')); return;
  }
  const due=Math.max(Number(sale.total||0)-Number(sale.paid_amount||0),0);
  const payRows=paymentsForSale(sale.id); const canReceipt=payRows.length>0||Number(sale.paid_amount||0)>0;
  openModal(`<div class="modal-title"><h2>Cetak Dokumen Kasir</h2><button class="modal-close">×</button></div><div class="document-modal-wrap">
    <div class="document-sale-summary"><div><span>Invoice</span><strong>${escapeHtml(sale.invoice_no||'-')}</strong></div><div><span>Customer</span><strong>${escapeHtml(sale.customer||'-')}</strong></div><div><span>Total</span><strong>${rupiah(sale.total)}</strong></div><div><span>Status</span><strong class="${due?'status-warn':'status-good'}">${due?'Belum Lunas · '+rupiah(due):'Lunas'}</strong></div></div>
    <div class="document-choice-grid">
      ${currentRole()!=='warehouse'?`<button type="button" class="document-choice doc-print-btn" data-doc="invoice"><span class="doc-icon">▤</span><b>Invoice</b><small>Harga, diskon, pembayaran, sisa tagihan, dan status.</small><em>Cetak Invoice →</em></button>`:''}
      ${currentRole()!=='warehouse'?`<button type="button" class="document-choice doc-print-btn ${canReceipt?'':'disabled'}" data-doc="receipt" ${canReceipt?'':'disabled'}><span class="doc-icon">✓</span><b>Kwitansi Pembayaran</b><small>Pilih pembayaran tertentu dari riwayat untuk mencetak kwitansi per cicilan/DP.</small><em>${canReceipt?'Pilih Pembayaran →':'Belum ada pembayaran'}</em></button>`:''}
      <button type="button" class="document-choice doc-print-btn" data-doc="delivery"><span class="doc-icon">⇢</span><b>Surat Jalan</b><small>Daftar barang & jumlah tanpa menampilkan harga.</small><em>Cetak Surat Jalan →</em></button>
    </div>
    <div class="document-tip">Tip: lengkapi <b>No. HP</b> dan <b>Alamat / Tujuan Pengiriman</b> pada Edit Penjualan agar dokumen lebih lengkap. Profil usaha diatur melalui Pengaturan → Profil Dokumen Bisnis.</div>
    <div class="modal-actions">${can('sales_edit')?'<button type="button" class="ghost" id="editSaleFromPrint">Edit Data Transaksi</button>':''}<button type="button" class="primary modal-close">Selesai</button></div>
  </div>`);
  $$('.doc-print-btn:not(:disabled)').forEach(btn=>btn.onclick=()=>{ if(btn.dataset.doc==='receipt'){closeModal();openPaymentsModal(saleId);} else printSaleDocument(saleId,btn.dataset.doc); });
  $('#editSaleFromPrint')?.addEventListener('click',()=>{closeModal();openSaleModal(saleId)});
}

function terbilang(value){
  let n=Math.floor(Math.abs(Number(value)||0));
  const w=['','Satu','Dua','Tiga','Empat','Lima','Enam','Tujuh','Delapan','Sembilan','Sepuluh','Sebelas'];
  const say=x=>{x=Math.floor(x);if(x<12)return w[x];if(x<20)return say(x-10)+' Belas';if(x<100)return say(Math.floor(x/10))+' Puluh'+(x%10?' '+say(x%10):'');if(x<200)return 'Seratus'+(x-100?' '+say(x-100):'');if(x<1000)return say(Math.floor(x/100))+' Ratus'+(x%100?' '+say(x%100):'');if(x<2000)return 'Seribu'+(x-1000?' '+say(x-1000):'');if(x<1e6)return say(Math.floor(x/1000))+' Ribu'+(x%1000?' '+say(x%1000):'');if(x<1e9)return say(Math.floor(x/1e6))+' Juta'+(x%1e6?' '+say(x%1e6):'');if(x<1e12)return say(Math.floor(x/1e9))+' Miliar'+(x%1e9?' '+say(x%1e9):'');if(x<1e15)return say(Math.floor(x/1e12))+' Triliun'+(x%1e12?' '+say(x%1e12):'');return num(x);};
  return n===0?'Nol':say(n).replace(/\s+/g,' ').trim();
}

function printSaleDocument(saleId,type,paymentId=null){
  const sale=state.sales.find(x=>x.id===saleId&&x.business_id===state.currentBusinessId); if(!sale){toast('Transaksi tidak ditemukan');return;}
  const payment=paymentId?(state.payments||[]).find(p=>p.id===paymentId&&p.sale_id===saleId&&p.business_id===state.currentBusinessId):null;
  if(type==='receipt'&&!payment){toast('Pilih pembayaran dari Riwayat Pembayaran untuk mencetak kwitansi');return;}
  const html=buildSaleDocumentHtml(sale,type,payment);
  const win=window.open('','_blank','width=980,height=820');
  if(!win){toast('Popup diblokir browser. Izinkan popup untuk mencetak dokumen.');return;}
  win.document.open();win.document.write(html);win.document.close();
  win.focus();setTimeout(()=>{try{win.print()}catch(e){console.warn(e)}},300);
}

function docSafe(v=''){return escapeHtml(v||'')}
function docNumber(prefix,invoice){return `${prefix}-${String(invoice||'').replace(/^(INV[-/]?)/i,'')||String(Date.now()).slice(-6)}`}
function buildSaleDocumentHtml(sale,type,payment=null){
  const b=activeBusiness()||{}; const lines=itemsForSale(sale.id);
  const discount=Number(sale.discount||0), total=Number(sale.total||0), paid=Number(sale.paid_amount||0), due=Math.max(total-paid,0);
  const subtotal=lines.reduce((a,x)=>a+Number(x.line_total??(Number(x.qty||0)*Number(x.unit_price||0))),0); const city=b.city||''; const date=fmtDate(sale.date); const status=due>0?'BELUM LUNAS':'LUNAS'; const paymentRows=paymentsForSale(sale.id); const paymentMethods=[...new Set(paymentRows.map(x=>x.method).filter(Boolean))].join(', ')||sale.payment_method||'-';
  const businessHead=`<div class="brandline"><div class="brandbox">${docSafe((b.name||'B').slice(0,1).toUpperCase())}</div><div class="biz"><h1>${docSafe(b.name||'Nama Bisnis')}</h1><p>${docSafe(b.address||'Alamat usaha belum diatur')}</p><p>${[b.phone,b.email].filter(Boolean).map(docSafe).join(' · ')||'Kontak belum diatur'}</p></div></div>`;
  const commonCss=`<style>*{box-sizing:border-box}body{margin:0;color:#17212b;font-family:Arial,Helvetica,sans-serif;font-size:12px;background:#fff}.page{max-width:820px;margin:0 auto;padding:8mm 4mm}.brandline{display:flex;gap:12px;align-items:flex-start}.brandbox{width:46px;height:46px;border-radius:10px;background:#17324d;color:white;font-weight:800;font-size:24px;display:grid;place-items:center}.biz h1{font-size:19px;margin:0 0 4px}.biz p{margin:2px 0;color:#52606d;line-height:1.35}.doc-title{display:flex;justify-content:space-between;align-items:flex-end;border-bottom:2px solid #17324d;padding-bottom:12px;margin-bottom:18px}.doc-title h2{margin:0;font-size:28px;letter-spacing:.06em;color:#17324d}.doc-title .no{text-align:right}.doc-title .no b{display:block;font-size:13px}.doc-title .no span{color:#667085}.two-col{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin:18px 0}.info-box{border:1px solid #dfe5ea;border-radius:10px;padding:12px}.info-box h3{margin:0 0 8px;font-size:10px;color:#667085;text-transform:uppercase;letter-spacing:.08em}.info-box p{margin:4px 0;line-height:1.45}.doc-table{width:100%;border-collapse:collapse;margin:14px 0}.doc-table th{background:#17324d;color:#fff;text-align:left;padding:9px;border:1px solid #17324d;font-size:10px}.doc-table td{padding:10px 9px;border:1px solid #dde3e8}.right{text-align:right}.summary{margin-left:auto;width:min(340px,100%)}.sumrow{display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid #e7eaee}.sumrow.total{font-size:14px;font-weight:800;border-top:2px solid #17324d;border-bottom:0;padding-top:10px}.status{display:inline-block;padding:5px 9px;border-radius:999px;font-size:10px;font-weight:800}.status.good{background:#ecfdf3;color:#027a48}.status.warn{background:#fff4e5;color:#b54708}.note{margin-top:20px;padding:11px 12px;background:#f7f9fa;border-radius:9px;color:#475467;line-height:1.5}.footer{margin-top:28px;padding-top:12px;border-top:1px solid #dfe5ea;color:#667085;font-size:10px;display:flex;justify-content:space-between;gap:20px}.sign-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:50px;margin-top:55px;text-align:center}.sign-space{height:55px}.sign-line{border-top:1px solid #7b8794;padding-top:5px}.amount-box{border:2px solid #17324d;border-radius:12px;padding:16px 18px;margin:18px 0;background:#f8fbfa}.amount-box span{font-size:10px;text-transform:uppercase;color:#667085;letter-spacing:.08em}.amount-box strong{display:block;font-size:25px;color:#17324d;margin-top:5px}.words{font-style:italic;line-height:1.55;background:#f5f7f9;padding:11px 13px;border-radius:8px}.receipt-body{font-size:13px;line-height:1.75}.receipt-body .line{display:grid;grid-template-columns:145px 12px 1fr;gap:5px;margin:5px 0}.delivery-head{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin:18px 0}.delivery-note{font-size:11px;color:#52606d;margin-top:8px}@media print{body{-webkit-print-color-adjust:exact;print-color-adjust:exact}.page{padding:0}.no-print{display:none}}@media(max-width:640px){.two-col,.delivery-head{grid-template-columns:1fr}.doc-title{align-items:flex-start;gap:15px}.doc-title h2{font-size:23px}.sign-grid{gap:20px}.receipt-body .line{grid-template-columns:110px 8px 1fr}} </style>`;
  const script=`<script>window.addEventListener('afterprint',()=>setTimeout(()=>window.close(),100));<\/script>`;
  if(type==='receipt'&&payment){
    const all=paymentsForSale(sale.id); const pos=Math.max(0,all.findIndex(x=>x.id===payment.id)); const cumulative=all.slice(0,pos+1).reduce((a,x)=>a+Number(x.amount||0),0); const dueAfter=Math.max(total-cumulative,0); const payAmount=Number(payment.amount||0); const payDate=fmtDate(payment.payment_date||sale.date); const receiptNo=payment.receipt_no||`${docNumber('KWT',sale.invoice_no)}-${String(payment.payment_no||pos+1).padStart(2,'0')}`; const purpose=dueAfter>0?`Pembayaran ke-${payment.payment_no||pos+1} Invoice ${docSafe(sale.invoice_no)} — sisa setelah pembayaran ${rupiah(dueAfter)}`:`Pelunasan Invoice ${docSafe(sale.invoice_no)}`;
    return `<!doctype html><html><head><meta charset="utf-8"><title>Kwitansi ${docSafe(receiptNo)}</title>${commonCss}<style>@page{size:A5 landscape;margin:10mm}.page{max-width:760px}</style></head><body><main class="page">${businessHead}<div class="doc-title"><h2>KWITANSI</h2><div class="no"><span>No.</span><b>${docSafe(receiptNo)}</b><span>${payDate}</span></div></div><div class="receipt-body"><div class="line"><b>Sudah terima dari</b><span>:</span><span>${docSafe(sale.customer||'Customer')}</span></div><div class="line"><b>Uang sejumlah</b><span>:</span><span class="words">${docSafe(terbilang(payAmount))} Rupiah</span></div><div class="line"><b>Untuk pembayaran</b><span>:</span><span>${purpose}</span></div><div class="line"><b>Metode</b><span>:</span><span>${docSafe(payment.method||'-')}</span></div></div><div class="amount-box"><span>Jumlah Pembayaran Ini</span><strong>${rupiah(payAmount)}</strong></div>${payment.notes?`<div class="note"><b>Catatan pembayaran:</b> ${docSafe(payment.notes)}</div>`:''}<div class="sign-grid"><div><div class="sign-space"></div><div class="sign-line">Penerima / Customer<br><b>${docSafe(sale.customer||'')}</b></div></div><div><div>${docSafe(city)}${city?', ':''}${payDate}</div><div class="sign-space"></div><div class="sign-line">Penerima Pembayaran<br><b>${docSafe(b.name||'')}</b></div></div></div><div class="footer"><span>${docSafe(b.document_footer||'Simpan kwitansi ini sebagai bukti pembayaran.')}</span><span>BizControl Online · Pembayaran #${payment.payment_no||pos+1}</span></div></main>${script}</body></html>`;
  }
  if(type==='delivery'){
    const sjNo=sale.delivery_no||docNumber('SJ',sale.invoice_no);
    return `<!doctype html><html><head><meta charset="utf-8"><title>Surat Jalan ${docSafe(sjNo)}</title>${commonCss}<style>@page{size:A4 portrait;margin:12mm}</style></head><body><main class="page">${businessHead}<div class="doc-title"><h2>SURAT JALAN</h2><div class="no"><span>No.</span><b>${docSafe(sjNo)}</b><span>${date}</span></div></div><div class="delivery-head"><div class="info-box"><h3>Tujuan / Penerima</h3><p><b>${docSafe(sale.customer||'Customer')}</b></p><p>${docSafe(sale.customer_address||'Alamat tujuan belum diisi')}</p><p>${docSafe(sale.customer_phone||'')}</p></div><div class="info-box"><h3>Referensi</h3><p>Invoice: <b>${docSafe(sale.invoice_no)}</b></p><p>Tanggal: ${date}</p><p>Pengirim: ${docSafe(b.name||'-')}</p></div></div><table class="doc-table"><thead><tr><th style="width:42px">No.</th><th>Nama Barang / Jasa</th><th style="width:95px">Qty</th><th style="width:95px">Satuan</th><th>Keterangan</th></tr></thead><tbody>${lines.map((x,i)=>`<tr><td>${i+1}</td><td><b>${docSafe(x.product_name)}</b></td><td>${num(x.qty)}</td><td>${docSafe(x.unit||'pcs')}</td><td>${docSafe(sale.notes||'-')}</td></tr>`).join('')}</tbody></table><div class="delivery-note">Dokumen ini tidak menampilkan harga. Mohon periksa jumlah dan kondisi barang saat diterima.</div><div class="sign-grid"><div><div class="sign-space"></div><div class="sign-line">Pengirim<br><b>${docSafe(b.name||'')}</b></div></div><div><div class="sign-space"></div><div class="sign-line">Penerima<br><b>${docSafe(sale.customer||'')}</b></div></div></div><div class="footer"><span>${docSafe(b.document_footer||'Barang telah diserahkan sesuai daftar di atas.')}</span><span>BizControl Online</span></div></main>${script}</body></html>`;
  }
  return `<!doctype html><html><head><meta charset="utf-8"><title>Invoice ${docSafe(sale.invoice_no)}</title>${commonCss}<style>@page{size:A4 portrait;margin:12mm}</style></head><body><main class="page">${businessHead}<div class="doc-title"><h2>INVOICE</h2><div class="no"><span>No. Invoice</span><b>${docSafe(sale.invoice_no)}</b><span>${date}</span></div></div><div class="two-col"><div class="info-box"><h3>Tagihan Kepada</h3><p><b>${docSafe(sale.customer||'Customer')}</b></p><p>${docSafe(sale.customer_address||'Alamat customer belum diisi')}</p><p>${docSafe(sale.customer_phone||'')}</p></div><div class="info-box"><h3>Informasi Pembayaran</h3><p>Metode: <b>${docSafe(paymentMethods)}</b></p><p>Pembayaran: <b>${paymentRows.length||0} kali</b></p><p>Status: <span class="status ${due?'warn':'good'}">${status}</span></p><p>Dibayar: <b>${rupiah(paid)}</b></p></div></div><table class="doc-table"><thead><tr><th>No.</th><th>Produk / Jasa</th><th>Qty</th><th>Satuan</th><th class="right">Harga</th><th class="right">Jumlah</th></tr></thead><tbody>${lines.map((x,i)=>{const p=state.products.find(p=>p.id===x.product_id)||{};return `<tr><td>${i+1}</td><td><b>${docSafe(x.product_name)}</b><br><small>${docSafe(p.sku||'')}</small></td><td>${num(x.qty)}</td><td>${docSafe(x.unit||p.unit||'pcs')}</td><td class="right">${rupiah(x.unit_price)}</td><td class="right">${rupiah(Number(x.line_total??(Number(x.qty||0)*Number(x.unit_price||0))))}</td></tr>`}).join('')}</tbody></table><div class="summary"><div class="sumrow"><span>Subtotal</span><b>${rupiah(subtotal)}</b></div><div class="sumrow"><span>Diskon</span><b>− ${rupiah(discount)}</b></div><div class="sumrow total"><span>Total</span><b>${rupiah(total)}</b></div><div class="sumrow"><span>Sudah Dibayar</span><b>${rupiah(paid)}</b></div><div class="sumrow"><span>Sisa Tagihan</span><b>${rupiah(due)}</b></div></div>${sale.notes?`<div class="note"><b>Catatan:</b> ${docSafe(sale.notes)}</div>`:''}<div class="sign-grid"><div><div class="sign-space"></div><div class="sign-line">Customer<br><b>${docSafe(sale.customer||'')}</b></div></div><div><div>${docSafe(city)}${city?', ':''}${date}</div><div class="sign-space"></div><div class="sign-line">Hormat Kami<br><b>${docSafe(b.name||'')}</b></div></div></div><div class="footer"><span>${docSafe(b.document_footer||'Terima kasih atas kepercayaan Anda.')}</span><span>Dokumen dibuat melalui BizControl Online</span></div></main>${script}</body></html>`;
}


function openPaymentsModal(saleId){
  const sale=state.sales.find(x=>x.id===saleId&&x.business_id===state.currentBusinessId); if(!sale){toast('Transaksi tidak ditemukan');return;}
  const rows=paymentsForSale(saleId); const paid=rows.reduce((a,p)=>a+Number(p.amount||0),0); const due=Math.max(Number(sale.total||0)-paid,0);
  openModal(`<div class="modal-title"><h2>Riwayat Pembayaran</h2><button class="modal-close">×</button></div><div class="panel" style="margin:16px">
    <div class="document-sale-summary"><div><span>Invoice</span><strong>${escapeHtml(sale.invoice_no||'-')}</strong></div><div><span>Customer</span><strong>${escapeHtml(sale.customer||'-')}</strong></div><div><span>Total</span><strong>${rupiah(sale.total)}</strong></div><div><span>Sisa</span><strong class="${due?'status-warn':'status-good'}">${rupiah(due)}</strong></div></div>
    <div class="toolbar" style="margin:14px 0"><div class="toolbar-left"><span class="muted">${rows.length} pembayaran · Total diterima ${rupiah(paid)}</span></div><div class="toolbar-right">${due>0?`<button class="primary" type="button" id="addPaymentBtn">+ Tambah Pembayaran</button>`:`<span class="pill good">LUNAS</span>`}</div></div>
    ${rows.length?`<div class="table-wrap"><table><thead><tr><th>Ke</th><th>Tanggal</th><th>Metode</th><th>Catatan</th><th>Jumlah</th><th>Aksi</th></tr></thead><tbody>${rows.map(p=>`<tr><td>#${num(p.payment_no)}</td><td>${fmtDate(p.payment_date)}</td><td>${escapeHtml(p.method||'-')}</td><td>${escapeHtml(p.notes||'-')}</td><td class="money">${rupiah(p.amount)}</td><td><div class="row-actions"><button type="button" class="row-action print payment-receipt-btn" data-id="${p.id}">Kwitansi</button><button type="button" class="row-action edit payment-edit-btn" data-id="${p.id}">Edit</button>${can('payments_delete')?`<button type="button" class="row-action delete payment-delete-btn" data-id="${p.id}">Hapus</button>`:''}</div></td></tr>`).join('')}</tbody></table></div>`:`<div class="empty">Belum ada pembayaran untuk invoice ini.</div>`}
    <div class="form-note" style="margin-top:14px">Setiap pembayaran disimpan terpisah. <b>paid_amount</b> pada invoice dihitung otomatis dari riwayat ini. Hapus pembayaran tetap membutuhkan Security Key.</div>
    <div class="modal-actions"><button type="button" class="ghost" id="backToPrintBtn">Cetak Dokumen Lain</button><button type="button" class="primary modal-close">Selesai</button></div>
  </div>`);
  $('#addPaymentBtn')?.addEventListener('click',()=>{closeModal();openPaymentModal(saleId)});
  $$('.payment-receipt-btn').forEach(b=>b.onclick=()=>printSaleDocument(saleId,'receipt',b.dataset.id));
  $$('.payment-edit-btn').forEach(b=>b.onclick=()=>{closeModal();openPaymentModal(saleId,b.dataset.id)});
  $$('.payment-delete-btn').forEach(b=>b.onclick=()=>{const id=b.dataset.id;requestSecureDelete('payment',id,'pembayaran #'+(state.payments.find(x=>x.id===id)?.payment_no||''),'sales')});
  $('#backToPrintBtn').onclick=()=>{closeModal();openPrintDocumentModal(saleId)};
}

function openPaymentModal(saleId,paymentId=null,fillDue=false){
  const sale=state.sales.find(x=>x.id===saleId&&x.business_id===state.currentBusinessId); if(!sale){toast('Transaksi tidak ditemukan');return;}
  const existing=paymentId?(state.payments||[]).find(x=>x.id===paymentId&&x.sale_id===saleId&&x.business_id===state.currentBusinessId):null; const editing=Boolean(existing); const submissionRequestId=existing?.client_request_id||newClientRequestId();
  const rows=paymentsForSale(saleId); const totalPaid=rows.reduce((a,p)=>a+Number(p.amount||0),0); const due=Math.max(Number(sale.total||0)-totalPaid,0); const maxAmount=editing?due+Number(existing.amount||0):due;
  if(!editing&&due<=0){toast('Invoice sudah lunas');openPaymentsModal(saleId);return;}
  const methods=['Cash','Transfer','QRIS','E-Wallet','Lainnya'];
  openModal(`<div class="modal-title"><h2>${editing?'Edit':'Tambah'} Pembayaran</h2><button class="modal-close">×</button></div><form id="paymentForm" class="form-grid">
    <div class="span-2 form-note"><b>${escapeHtml(sale.invoice_no)}</b> · ${escapeHtml(sale.customer||'-')} · Total ${rupiah(sale.total)} · Sudah dibayar ${rupiah(totalPaid)} · <b>Sisa ${rupiah(due)}</b></div>
    <label>Tanggal Pembayaran<input name="payment_date" type="date" value="${escapeAttr(existing?.payment_date||today())}" required></label>
    <label>Metode<select name="method">${methods.map(v=>`<option ${v===(existing?.method||sale.payment_method||'Cash')?'selected':''}>${v}</option>`).join('')}</select></label>
    <label>Jumlah<input name="amount" type="number" min="1" max="${maxAmount}" value="${editing?Number(existing.amount||0):(fillDue?due:'')}" placeholder="Maks ${rupiah(maxAmount)}" required></label>
    <label>Referensi / Catatan<input name="notes" value="${escapeAttr(existing?.notes||'')}" placeholder="Contoh: DP, pelunasan, transfer BCA"></label>
    <div class="span-2 payment-status-box"><div><span>Sisa Setelah Pembayaran</span><strong id="paymentDuePreview">${rupiah(due)}</strong><small>Tidak boleh melebihi total invoice.</small></div><button type="button" class="soft-btn" id="fillDuePaymentBtn">Isi Sisa Tagihan</button></div>
    <div class="span-2 modal-actions"><button type="button" class="ghost" id="cancelPaymentBtn">Batal</button><button type="submit" class="primary">${editing?'Simpan Perubahan':'Simpan Pembayaran'}</button></div>
  </form>`);
  const form=$('#paymentForm'); const preview=()=>{const a=Math.max(0,Number(form.amount.value||0)); const remaining=Math.max(0,maxAmount-a); $('#paymentDuePreview').textContent=rupiah(remaining); return a;}; form.oninput=preview; preview();
  $('#fillDuePaymentBtn').onclick=()=>{form.amount.value=maxAmount;preview();}; $('#cancelPaymentBtn').onclick=()=>{closeModal();openPaymentsModal(saleId)};
  form.onsubmit=async e=>{e.preventDefault();const f=new FormData(form);const amount=Number(f.get('amount')||0);if(amount<=0){toast('Jumlah pembayaran harus lebih dari Rp0','error');return;}if(amount>maxAmount){toast('Pembayaran melebihi sisa tagihan','error');return;}const data={business_id:state.currentBusinessId,client_request_id:submissionRequestId,sale_id:saleId,payment_date:f.get('payment_date'),amount,method:f.get('method'),notes:f.get('notes')};await withSubmitBusy(form,async()=>{try{if(editing)await updatePayment(existing.id,data);else await addPayment(data);closeModal();openPaymentsModal(saleId);toast(editing?'Pembayaran diperbarui':'Pembayaran tercatat','success')}catch(err){toast(err.message,'error');throw err}})};
}


function localDocNumber(type,date=today()){
  const year=String(date||today()).slice(0,4);state.documentSequences=state.documentSequences||{};const key=`${type}-${year}`;state.documentSequences[key]=Number(state.documentSequences[key]||0)+1;persist();return `${type}-${year}-${String(state.documentSequences[key]).padStart(6,'0')}`;
}
async function nextDocumentNumber(type,date=today()){
  if(state.mode==='cloud') throw new Error('Nomor dokumen Cloud hanya dibuat oleh transaksi server-side');
  return localDocNumber(type,date);
}
function newClientRequestId(){return uid()}
async function createCloudRow(table,row,requestId){
  const data={...row,client_request_id:requestId};
  try{await cloudRequest(`/rest/v1/${table}`,{method:'POST',body:data});return data}catch(err){
    if(/duplicate|unique|409/i.test(err.message)&&requestId){const b=encodeURIComponent(state.currentBusinessId);const rows=await cloudRequest(`/rest/v1/${table}?select=id,business_id,client_request_id&business_id=eq.${b}&client_request_id=eq.${encodeURIComponent(requestId)}&limit=1`);if(rows?.length)return rows[0]}
    throw err;
  }
}

async function addPayment(payment){
  if(!requirePermission('payments_manage'))throw new Error('Tidak diizinkan');
  const requestId=payment.client_request_id||newClientRequestId();
  if(state.mode==='cloud'){
    const result=await cloudRequest('/rest/v1/rpc/record_payment',{method:'POST',body:{p_bid:state.currentBusinessId,p_sale_id:payment.sale_id,p_payment_id:null,p_payment_date:payment.payment_date,p_amount:Number(payment.amount||0),p_method:payment.method,p_notes:payment.notes||null,p_request_id:requestId}});
    if(result?.ok===false)throw new Error(result.error||'Pembayaran gagal');
    await cloudLoadBusinessData();
  } else {
    const rows=paymentsForSale(payment.sale_id); const row={...payment,id:uid(),client_request_id:requestId,receipt_no:payment.receipt_no||await nextDocumentNumber('KWT',payment.payment_date),payment_no:(Math.max(0,...rows.map(p=>Number(p.payment_no||0)))+1),created_at:new Date().toISOString()}; state.payments.push(row); recalcLocalSalePaid(payment.sale_id); const sale=state.sales.find(s=>s.id===payment.sale_id); localAudit('CREATE','payments',row.id,`${sale?.invoice_no||'Invoice'} · ${row.receipt_no}`,null,row); persist();
  }
}
async function updatePayment(id,payment){if(!requirePermission('payments_manage'))throw new Error('Tidak diizinkan');
  if(state.mode==='cloud'){
    const result=await cloudRequest('/rest/v1/rpc/record_payment',{method:'POST',body:{p_bid:state.currentBusinessId,p_sale_id:payment.sale_id,p_payment_id:id,p_payment_date:payment.payment_date,p_amount:Number(payment.amount||0),p_method:payment.method,p_notes:payment.notes||null,p_request_id:payment.client_request_id||null}});
    if(result?.ok===false)throw new Error(result.error||'Pembayaran gagal');
    await cloudLoadBusinessData();
  } else { const row=(state.payments||[]).find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(!row)throw new Error('Pembayaran tidak ditemukan'); const before=cloneAuditData(row); Object.assign(row,payment); recalcLocalSalePaid(row.sale_id); const sale=state.sales.find(s=>s.id===row.sale_id); localAudit('UPDATE','payments',row.id,`${sale?.invoice_no||'Invoice'} · Pembayaran #${row.payment_no}`,before,row); persist(); }
}

function openBusinessModal(){
  openModal(`<div class="modal-title"><h2>Tambah Bisnis</h2><button class="modal-close">×</button></div><form id="businessForm" class="form-grid single"><label>Nama Bisnis<input name="name" required placeholder="Nama usaha"></label><div class="modal-actions"><button type="button" class="ghost modal-close">Batal</button><button class="primary">Simpan</button></div></form>`);
  $('#businessForm').onsubmit=async e=>{e.preventDefault(); const name=new FormData(e.target).get('name'); await addBusiness(name); closeModal(); render();};
}
async function addProduct(product){
  if(!requirePermission('products_create'))throw new Error('Tidak diizinkan');const requestId=product.client_request_id||newClientRequestId();
  if(state.mode==='cloud'){await createCloudRow('products',product,requestId);await cloudLoadBusinessData();}
  else{const row={...product,id:uid(),client_request_id:requestId};state.products.push(row);localAudit('CREATE','products',row.id,`${row.sku} · ${row.name}`,null,row);persist();} toast('Produk tersimpan','success');
}
async function addSale(sale){
  if(!requirePermission('sales_create'))throw new Error('Tidak diizinkan');const requestId=sale.client_request_id||newClientRequestId();const items=sale.items||[];
  if(!items.length)throw new Error('Minimal satu item diperlukan');
  if(state.mode==='cloud'){
    const result=await cloudRequest('/rest/v1/rpc/create_sale_with_items',{method:'POST',body:{p_bid:state.currentBusinessId,p_sale_date:sale.date,p_customer_name:sale.customer||null,p_customer_phone:sale.customer_phone||null,p_customer_address:sale.customer_address||null,p_sale_notes:sale.notes||null,p_items:items.map(x=>({product_id:x.product_id,qty:Number(x.qty||0)})),p_discount:Number(sale.discount||0),p_payment_method:sale.payment_method||'Cash',p_initial_paid:Number(sale.paid_amount||0),p_request_id:requestId}});
    if(result?.ok===false)throw new Error(result.error||'Gagal membuat transaksi');await cloudLoadBusinessData();
  } else {
    sale.invoice_no=sale.invoice_no||await nextDocumentNumber('INV',sale.date);sale.delivery_no=sale.delivery_no||await nextDocumentNumber('SJ',sale.date);const initialPaid=Number(sale.paid_amount||0);const rowId=uid();const clean={...sale};delete clean.items;const row={...clean,id:rowId,client_request_id:requestId,paid_amount:0,created_at:new Date().toISOString()};state.sales.push(row);
    items.forEach((it,i)=>{const p=state.products.find(x=>x.id===it.product_id);if(p&&p.category!=='Jasa')p.stock=Number(p.stock||0)-Number(it.qty||0);state.saleItems.push({...it,id:uid(),business_id:state.currentBusinessId,sale_id:rowId,line_no:i+1,created_at:new Date().toISOString()});});
    localAudit('CREATE','sales',row.id,`${row.invoice_no} · ${row.customer||row.product_name}`,null,{...row,items:items.map(x=>({product_id:x.product_id,product_name:x.product_name,qty:x.qty,unit_price:x.unit_price,line_total:x.line_total}))});if(initialPaid>0)await addPayment({business_id:state.currentBusinessId,client_request_id:requestId,sale_id:row.id,payment_date:row.date,amount:initialPaid,method:row.payment_method,notes:'Pembayaran awal'});persist();
  }
}

async function addExpense(exp){
  if(!requirePermission('expenses_edit'))throw new Error('Tidak diizinkan');const requestId=exp.client_request_id||newClientRequestId();
  if(state.mode==='cloud'){await createCloudRow('expenses',exp,requestId);await cloudLoadBusinessData();}else{const row={...exp,id:uid(),client_request_id:requestId};state.expenses.push(row);localAudit('CREATE','expenses',row.id,row.description,null,row);persist();} toast('Biaya tersimpan','success');
}

async function updateProduct(id,product){if(!requirePermission('products_edit'))throw new Error('Tidak diizinkan');
  if(state.mode==='cloud'){ const b=encodeURIComponent(state.currentBusinessId); const clean={sku:product.sku,name:product.name,category:product.category,unit:product.unit,cost:Number(product.cost||0),price:Number(product.price||0),stock:Number(product.stock||0),min_stock:Number(product.min_stock||0)}; await cloudRequest(`/rest/v1/products?id=eq.${encodeURIComponent(id)}&business_id=eq.${b}`,{method:'PATCH',body:clean}); await cloudLoadBusinessData(); }
  else { const row=state.products.find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(!row) throw new Error('Produk tidak ditemukan'); const before=cloneAuditData(row); Object.assign(row,product); localAudit('UPDATE','products',row.id,`${row.sku} · ${row.name}`,before,row); persist(); }
  toast('Produk diperbarui');
}
async function updateProductStock(id,patch){if(!requirePermission('products_stock_edit'))throw new Error('Tidak diizinkan');
  const clean={stock:Number(patch.stock||0),min_stock:Number(patch.min_stock||0)};
  if(state.mode==='cloud'){const b=encodeURIComponent(state.currentBusinessId);await cloudRequest(`/rest/v1/products?id=eq.${encodeURIComponent(id)}&business_id=eq.${b}`,{method:'PATCH',body:clean});await cloudLoadBusinessData();}
  else {const row=state.products.find(x=>x.id===id&&x.business_id===state.currentBusinessId);if(!row)throw new Error('Produk tidak ditemukan');const before=cloneAuditData(row);Object.assign(row,clean);localAudit('UPDATE','stock',row.id,`${row.sku} · ${row.name}`,before,row);persist();}
}
async function updateSale(id,sale){if(!requirePermission('sales_edit'))throw new Error('Tidak diizinkan');const items=sale.items||[];if(!items.length)throw new Error('Minimal satu item diperlukan');
  if(state.mode==='cloud'){
    const result=await cloudRequest('/rest/v1/rpc/update_sale_with_items',{method:'POST',body:{p_bid:state.currentBusinessId,p_sale_id:id,p_sale_date:sale.date,p_customer_name:sale.customer||null,p_customer_phone:sale.customer_phone||null,p_customer_address:sale.customer_address||null,p_sale_notes:sale.notes||null,p_items:items.map(x=>({product_id:x.product_id,qty:Number(x.qty||0)})),p_discount:Number(sale.discount||0),p_payment_method:sale.payment_method||'Tempo'}});
    if(result?.ok===false)throw new Error(result.error||'Gagal mengubah transaksi');await cloudLoadBusinessData();
  } else {
    const old=state.sales.find(x=>x.id===id&&x.business_id===state.currentBusinessId);if(!old)throw new Error('Transaksi tidak ditemukan');const before=cloneAuditData(old);const oldItems=itemsForSale(id);
    oldItems.forEach(it=>{const p=state.products.find(x=>x.id===it.product_id);if(p&&p.category!=='Jasa')p.stock=Number(p.stock||0)+Number(it.qty||0);});
    items.forEach(it=>{const p=state.products.find(x=>x.id===it.product_id);if(p&&p.category!=='Jasa')p.stock=Number(p.stock||0)-Number(it.qty||0);});
    state.saleItems=(state.saleItems||[]).filter(x=>x.sale_id!==id);items.forEach((it,i)=>state.saleItems.push({...it,id:uid(),business_id:state.currentBusinessId,sale_id:id,line_no:i+1,created_at:new Date().toISOString()}));
    const clean={...sale};delete clean.items;Object.assign(old,clean);localAudit('UPDATE','sales',old.id,`${old.invoice_no} · ${old.customer||old.product_name}`,before,{...cloneAuditData(old),items:items.map(x=>({product_id:x.product_id,product_name:x.product_name,qty:x.qty,unit_price:x.unit_price,line_total:x.line_total}))});persist();
  }
  toast('Penjualan diperbarui');
}

async function updateExpense(id,expense){if(!requirePermission('expenses_edit'))throw new Error('Tidak diizinkan');
  if(state.mode==='cloud'){ const b=encodeURIComponent(state.currentBusinessId); const clean={date:expense.date,category:expense.category,description:expense.description,amount:Number(expense.amount||0),payment_method:expense.payment_method}; await cloudRequest(`/rest/v1/expenses?id=eq.${encodeURIComponent(id)}&business_id=eq.${b}`,{method:'PATCH',body:clean,prefer:true}); await cloudLoadBusinessData(); }
  else { const row=state.expenses.find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(!row) throw new Error('Biaya tidak ditemukan'); const before=cloneAuditData(row); Object.assign(row,expense); localAudit('UPDATE','expenses',row.id,row.description,before,row); persist(); }
  toast('Biaya diperbarui');
}

function loadDeleteKeys(){ try{return JSON.parse(localStorage.getItem('bc_delete_keys')||'{}')}catch{return {}} }
function saveDeleteKeys(obj){ localStorage.setItem('bc_delete_keys',JSON.stringify(obj)); }
async function hashPin(pin){
  if(globalThis.crypto?.subtle){ const data=new TextEncoder().encode('bizcontrol-delete:'+pin); const buf=await crypto.subtle.digest('SHA-256',data); return [...new Uint8Array(buf)].map(b=>b.toString(16).padStart(2,'0')).join(''); }
  return btoa(unescape(encodeURIComponent('bizcontrol-delete:'+pin)));
}
async function hasDeleteSecurityKey(){
  if(state.mode==='cloud'){ const v=await cloudRequest('/rest/v1/rpc/has_delete_pin',{method:'POST',body:{bid:state.currentBusinessId}}); return Boolean(v); }
  return Boolean(loadDeleteKeys()[state.currentBusinessId]);
}
async function saveDeleteSecurityKey(pin,currentPin=''){
  if(!/^\d{6}$/.test(pin)) throw new Error('Security Key harus 6 digit angka');
  if(state.mode==='cloud'){ const result=await cloudRequest('/rest/v1/rpc/set_delete_pin_v2',{method:'POST',body:{p_bid:state.currentBusinessId,p_new_pin:pin,p_current_pin:currentPin||null}}); if(result?.ok===false)throw new Error(result.error||'Security Key gagal disimpan'); return; }
  const keys=loadDeleteKeys(); const old=keys[state.currentBusinessId]; const existed=Boolean(old);
  if(old){ if(!currentPin) throw new Error('Masukkan Security Key saat ini'); const currentHash=await hashPin(currentPin); if(currentHash!==old) throw new Error('Security Key saat ini salah'); }
  keys[state.currentBusinessId]=await hashPin(pin); saveDeleteKeys(keys); localAudit('SECURITY','security',null,'Security Key Hapus Data',{configured:existed},{configured:true}); persist();
}
async function openSecurityKeyModal(afterSetup=null){
  let exists=false; try{exists=await hasDeleteSecurityKey();}catch(e){toast(e.message);return;}
  const needCurrent=exists;
  openModal(`<div class="modal-title"><h2>${exists?'Ganti':'Buat'} Security Key</h2><button class="modal-close">×</button></div><form id="securityKeyForm" class="form-grid single">
    <div class="security-callout"><b>Proteksi penghapusan permanen</b><span>Security Key berupa 6 digit angka dan akan diminta setiap kali menghapus transaksi, produk, atau biaya.</span></div>
    ${needCurrent?'<label>Security Key Saat Ini<input name="current_pin" type="password" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" placeholder="••••••" required></label>':''}
    <label>Security Key Baru<input name="pin" type="password" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" placeholder="6 digit" required></label>
    <label>Ulangi Security Key<input name="confirm_pin" type="password" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" placeholder="6 digit" required></label>
    <div class="modal-actions"><button type="button" class="ghost modal-close">Batal</button><button class="primary" type="submit">Simpan Security Key</button></div>
  </form>`);
  $('#securityKeyForm').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target);const pin=String(f.get('pin')||''),confirmPin=String(f.get('confirm_pin')||'');if(pin!==confirmPin){toast('Ulangi Security Key belum sama');return;}try{await saveDeleteSecurityKey(pin,String(f.get('current_pin')||''));closeModal();toast('Security Key aktif');if(afterSetup) afterSetup();}catch(err){toast(err.message)}};
}
async function requestSecureDelete(entity,id,label,returnPage){
  try{
    const configured=await hasDeleteSecurityKey();
    if(!configured){ toast('Buat Security Key sebelum menghapus data'); return openSecurityKeyModal(()=>requestSecureDelete(entity,id,label,returnPage)); }
  }catch(err){toast(err.message);return;}
  openModal(`<div class="modal-title"><h2>Konfirmasi Hapus</h2><button class="modal-close">×</button></div><form id="secureDeleteForm" class="form-grid single">
    <div class="delete-warning"><b>Hapus permanen?</b><span>Anda akan menghapus <strong>${escapeHtml(label)}</strong>. Tindakan ini tidak bisa dibatalkan.</span></div>
    <label>Security Key<input name="pin" type="password" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" placeholder="Masukkan 6 digit" required autofocus></label>
    <div class="modal-actions"><button type="button" class="ghost modal-close">Batal</button><button type="submit" class="danger solid-danger">Hapus Permanen</button></div>
  </form>`);
  $('#secureDeleteForm').onsubmit=async e=>{e.preventDefault();const pin=String(new FormData(e.target).get('pin')||'');try{await secureDeleteRecord(entity,id,pin);closeModal();navigate(returnPage);toast('Data berhasil dihapus');}catch(err){toast(err.message)}};
}
async function secureDeleteRecord(entity,id,pin){
  const perm=entity==='sale'?'sales_delete':entity==='product'?'products_delete':entity==='expense'?'expenses_delete':'payments_delete';if(!requirePermission(perm))throw new Error('Tidak diizinkan');
  if(!/^\d{6}$/.test(pin)) throw new Error('Security Key harus 6 digit');
  if(state.mode==='cloud'){ const result=await cloudRequest('/rest/v1/rpc/secure_delete_record_v2',{method:'POST',body:{p_bid:state.currentBusinessId,p_entity:entity,p_record_id:id,p_pin:pin}}); if(result?.ok===false)throw new Error(result.error||'Penghapusan ditolak'); await cloudLoadBusinessData(); return; }
  const expected=loadDeleteKeys()[state.currentBusinessId]; if(!expected) throw new Error('Security Key belum diatur'); if(await hashPin(pin)!==expected) throw new Error('Security Key salah');
  if(entity==='sale'){
    const row=state.sales.find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(!row) throw new Error('Transaksi tidak ditemukan');
    const oldItems=itemsForSale(row.id);oldItems.forEach(it=>{const p=state.products.find(x=>x.id===it.product_id);if(p&&p.category!=='Jasa')p.stock=Number(p.stock||0)+Number(it.qty||0);});state.saleItems=(state.saleItems||[]).filter(x=>x.sale_id!==row.id);
    (state.payments||[]).filter(x=>x.sale_id===row.id&&x.business_id===state.currentBusinessId).forEach(pay=>localAudit('DELETE','payments',pay.id,`${row.invoice_no} · Pembayaran #${pay.payment_no}`,pay,null)); state.payments=(state.payments||[]).filter(x=>x.sale_id!==row.id); localAudit('DELETE','sales',row.id,`${row.invoice_no} · ${row.customer||row.product_name}`,{...row,items:oldItems},null); state.sales=state.sales.filter(x=>x.id!==id);
  }else if(entity==='product'){
    if((state.saleItems||[]).some(x=>x.product_id===id&&x.business_id===state.currentBusinessId)||state.sales.some(x=>x.product_id===id&&x.business_id===state.currentBusinessId)) throw new Error('Produk sudah punya riwayat penjualan. Demi histori laporan, produk ini tidak bisa dihapus. Edit datanya saja.');
    const row=state.products.find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(row) localAudit('DELETE','products',row.id,`${row.sku} · ${row.name}`,row,null); state.products=state.products.filter(x=>x.id!==id);
  }else if(entity==='expense'){ const row=state.expenses.find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(row) localAudit('DELETE','expenses',row.id,row.description,row,null); state.expenses=state.expenses.filter(x=>x.id!==id); }
  else if(entity==='payment'){ const row=(state.payments||[]).find(x=>x.id===id&&x.business_id===state.currentBusinessId); if(!row)throw new Error('Pembayaran tidak ditemukan'); const sale=state.sales.find(s=>s.id===row.sale_id); localAudit('DELETE','payments',row.id,`${sale?.invoice_no||'Invoice'} · Pembayaran #${row.payment_no}`,row,null); state.payments=state.payments.filter(x=>x.id!==id); recalcLocalSalePaid(row.sale_id); }
  else throw new Error('Jenis data tidak dikenal');
  persist();
}

async function addBusiness(name){
  if(state.mode==='cloud'){
    const rows=await cloudRequest('/rest/v1/rpc/create_business',{method:'POST',body:{p_name:String(name||'').trim()}});
    const b=Array.isArray(rows)?rows[0]:rows;
    if(!b?.id)throw new Error('Bisnis gagal dibuat. Coba login ulang lalu ulangi.');
    state.businesses.push(b);state.currentBusinessId=b.id;await cloudLoadBusinessData();
  }
  else { const b={id:uid(),name,owner_id:'local',allow_negative_stock:false};state.businesses.push(b);state.currentBusinessId=b.id;localAudit('CREATE','business',b.id,b.name,null,b);persist(); }
  toast('Bisnis ditambahkan');
}


function supportWhatsApp(){
  const raw=String((window.BIZCONTROL_CONFIG||{}).supportWhatsApp||'628117199210').replace(/\D/g,'');
  return raw.startsWith('0')?'62'+raw.slice(1):raw;
}
function contactSystemAdmin(){
  const phone=supportWhatsApp();
  if(!phone)return toast('Nomor Admin BizControl belum dikonfigurasi','error');
  const msg=encodeURIComponent('Halo Admin BizControl, saya ingin mendaftar / mengaktifkan akun Owner BizControl.');
  window.open(`https://wa.me/${phone}?text=${msg}`,'_blank','noopener,noreferrer');
}

async function invokeAccountAdmin(action,payload={}){
  const c=state.cloudConfig||loadCloudConfig();if(!c?.url||!c?.key)throw new Error('Layanan Cloud belum tersedia pada deployment ini');
  if(!state.session?.access_token)throw new Error('Sesi login tidak tersedia');
  const call=async(retry=true)=>{
    const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),15000);
    try{
      const url=new URL('/functions/v1/account-admin',c.url).toString();
      const res=await fetch(url,{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+state.session.access_token,'Content-Type':'application/json'},body:JSON.stringify({action,...payload}),signal:controller.signal});
      let data={};try{data=await res.json()}catch{}
      if(res.status===401&&retry&&state.session?.refresh_token){await refreshCloudSession();return call(false)}
      if(!res.ok)throw new Error(data.error||data.message||`Account Admin HTTP ${res.status}`);
      return data;
    }catch(err){
      if(err.name==='AbortError')throw new Error('Layanan akun timeout. Coba lagi.');
      if(err instanceof TypeError&&/fetch/i.test(String(err.message||'')))throw new Error('Edge Function account-admin tidak dapat dijangkau. Pastikan function sudah Deploy dan CORS benar.');
      throw err;
    }finally{clearTimeout(timeout)}
  };
  return call(true);
}
async function checkSystemAdmin(){
  if(state.mode!=='cloud'||!state.session?.access_token){state.isSystemAdmin=false;return false;}
  try{
    const r=await invokeAccountAdmin('status');
    if(r?.is_system_admin&&r?.server_ready===false)throw new Error(r?.server_error||'Backend Admin Sistem belum siap');
    state.isSystemAdmin=Boolean(r?.is_system_admin);
    return state.isSystemAdmin;
  }catch(e){
    console.warn('System admin status:',e.message);
    state.isSystemAdmin=false;
    return false;
  }
}
async function loadManagedOwners(){
  if(!state.isSystemAdmin){state.managedOwners=[];return []}
  const r=await invokeAccountAdmin('list-owners');state.managedOwners=Array.isArray(r?.owners)?r.owners:[];return state.managedOwners;
}
async function sendMemberPasswordReset(userId,email){
  if(state.mode!=='cloud'||currentRole()!=='owner')return toast('Hanya Owner yang dapat mengirim reset password karyawan','error');
  if(!confirm(`Kirim link reset password ke ${email||'karyawan ini'}?`))return;
  try{const r=await invokeAccountAdmin('reset-member',{business_id:state.currentBusinessId,user_id:userId,redirect_to:recoveryRedirectUrl()});toast(r?.message||'Link reset password dikirim','success',6000)}catch(e){toast(e.message,'error')}
}
async function sendOwnerPasswordReset(email){
  if(!state.isSystemAdmin)return toast('Hanya Admin Sistem yang dapat mengirim reset password Owner','error');
  if(!confirm(`Kirim link reset password ke Owner ${email}?`))return;
  try{const r=await invokeAccountAdmin('reset-owner',{email,redirect_to:recoveryRedirectUrl()});toast(r?.message||'Link reset password Owner dikirim','success',6000)}catch(e){toast(e.message,'error')}
}
function openChangePasswordModal(){
  if(state.mode!=='cloud'||!state.session?.access_token)return toast('Silakan login ke akun Cloud terlebih dahulu','error');
  openModal(`<div class="modal-title"><h2>Ganti Password</h2><button class="modal-close">×</button></div><form id="changePasswordForm" class="form-grid single"><div class="form-note">Password baru minimal 8 karakter. Setelah berhasil, Anda akan diminta login ulang.</div><label>Password Baru<input name="password" type="password" minlength="8" required autocomplete="new-password" placeholder="Minimal 8 karakter"></label><label>Ulangi Password Baru<input name="confirm" type="password" minlength="8" required autocomplete="new-password" placeholder="Ulangi password"></label><div class="modal-actions"><button type="button" class="ghost modal-close">Batal</button><button type="submit" class="primary">Simpan Password Baru</button></div></form>`);
  const form=$('#changePasswordForm');form.onsubmit=async e=>{e.preventDefault();const f=new FormData(form);const password=String(f.get('password')||''),confirmPassword=String(f.get('confirm')||'');if(password.length<8)return toast('Password minimal 8 karakter','error');if(password!==confirmPassword)return toast('Ulangi password harus sama','error');await withSubmitBusy(form,async()=>{try{
    const c=state.cloudConfig||loadCloudConfig();const token=state.session?.access_token;
    const res=await fetch(c.url+'/auth/v1/user',{method:'PUT',headers:{apikey:c.key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({password})});let data={};try{data=await res.json()}catch{};if(!res.ok)throw new Error(data.msg||data.error_description||data.message||'Gagal mengubah password');
    try{await fetch(c.url+'/auth/v1/logout',{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+token}})}catch{}
    closeModal();stopPolling();clearSession();state.mode='local';state.isSystemAdmin=false;state.managedOwners=[];setAuthMode('login');showAuth();toast('Password berhasil diubah. Silakan login kembali.','success',7000);
  }catch(err){toast(err.message,'error');throw err}})};
}

async function invokeTeamInvite(email,role){
  const c=state.cloudConfig||loadCloudConfig();if(!c?.url||!c?.key)throw new Error('Layanan Cloud belum tersedia pada deployment ini');
  if(!state.session?.access_token)throw new Error('Sesi login tidak tersedia');
  const payload={business_id:state.currentBusinessId,email:String(email||'').trim(),role,redirect_to:recoveryRedirectUrl()};
  const call=async(retry=true)=>{
    const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),15000);
    try{
      const functionUrl=new URL('/functions/v1/team-invite',c.url).toString();
      const res=await fetch(functionUrl,{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+state.session.access_token,'Content-Type':'application/json'},body:JSON.stringify(payload),signal:controller.signal});
      let data={};try{data=await res.json()}catch{}
      if(res.status===401&&retry&&state.session?.refresh_token){await refreshCloudSession();return call(false)}
      if(!res.ok)throw new Error(data.error||data.message||`Edge Function HTTP ${res.status}`);
      return data;
    }catch(err){
      if(err.name==='AbortError')throw new Error('Undangan timeout. Coba lagi.');
      if(err instanceof TypeError&&/fetch/i.test(String(err.message||'')))throw new Error('Edge Function team-invite tidak dapat dijangkau. Pastikan function sudah Deploy, Verify JWT sesuai panduan, dan CORS/URL function benar.');
      throw err
    }finally{clearTimeout(timeout)}
  };
  return call(true);
}
function openMemberModal(existing=null){
  if(state.mode!=='cloud'){toast('Kelola anggota tersedia pada Cloud','error');return}if(currentRole()!=='owner'){toast('Hanya owner yang dapat mengubah anggota','error');return}
  const editing=Boolean(existing);const roles=['admin','cashier','finance','warehouse','staff'];
  openModal(`<div class="modal-title"><h2>${editing?'Ubah Role':'Undang Anggota'}</h2><button class="modal-close">×</button></div><form id="memberForm" class="form-grid single"><div class="form-note">${editing?'Ubah hak akses anggota ini.':'Karyawan tidak perlu daftar manual. Jika email belum punya akun, sistem mengirim undangan untuk membuat password. Jika akun sudah ada, akses langsung diaktifkan.'}</div><label>Email<input name="email" type="email" value="${escapeAttr(existing?.email||'')}" ${editing?'readonly':''} required autocomplete="email"></label><label>Role<select name="role">${roles.map(r=>`<option value="${r}" ${r===(existing?.role||'cashier')?'selected':''}>${ROLE_LABELS[r]}</option>`).join('')}</select></label><div class="modal-actions"><button type="button" class="ghost modal-close">Batal</button><button type="submit" class="primary">${editing?'Simpan Role':'Kirim Undangan'}</button></div></form>`);
  const form=$('#memberForm');form.onsubmit=async e=>{e.preventDefault();const f=new FormData(form);await withSubmitBusy(form,async()=>{try{
    let result=null;
    if(editing)await cloudRequest('/rest/v1/rpc/update_business_member_role',{method:'POST',body:{bid:state.currentBusinessId,member_user_id:existing.user_id,new_role:f.get('role')}});
    else result=await invokeTeamInvite(f.get('email'),f.get('role'));
    await cloudLoadTeam();closeModal();navigate('team');
    toast(editing?'Role berhasil diperbarui':(result?.message||'Undangan diproses'),'success',6000);
  }catch(err){toast(err.message,'error');throw err}})}
}
async function removeMember(userId,email){
  if(currentRole()!=='owner')return toast('Hanya owner','error');
  if(!confirm(`Hapus / cabut akses ${email||'anggota'} dari bisnis ini?\n\nSetelah dicabut, user tidak dapat membaca atau mengubah data bisnis ini lagi.`))return;
  try{
    await cloudRequest('/rest/v1/rpc/remove_business_member',{method:'POST',body:{bid:state.currentBusinessId,member_user_id:userId}});
    await cloudLoadTeam();render();toast('Akses anggota berhasil dicabut','success',5000);
  }catch(e){toast(e.message,'error')}
}
async function logoutCloud(){try{stopPolling();clearSession();state.mode='local';state.currentRole='owner';state.isSystemAdmin=false;state.managedOwners=[];setAuthMode('login');showAuth();toast('Berhasil keluar','success')}catch(e){toast(e.message,'error')}}

// -------- Cloud / Supabase REST --------
function loadCloudConfig(){
  // Production config is deployment-managed. It is intentionally not editable from the Owner UI.
  const r=window.BIZCONTROL_CONFIG||{};
  const runtimeUrl=String(r.supabaseUrl||'').trim().replace(/\/+$/,'');
  const runtimeKey=String(r.publishableKey||'').trim();
  if(runtimeUrl&&runtimeKey)return {url:runtimeUrl,key:runtimeKey,turnstileSiteKey:String(r.turnstileSiteKey||'').trim(),supportWhatsApp:String(r.supportWhatsApp||'').trim(),managed:true};
  return null;
}
function deploymentConfigStatus(){
  const c=loadCloudConfig();
  return {
    configured:Boolean(c?.url&&c?.key),
    supabaseUrl:c?.url||'',
    publishableKeyPresent:Boolean(c?.key),
    source:'runtime-config.js'
  };
}
window.BizControlDeploymentStatus=deploymentConfigStatus;

function loadSession(){ try{let raw=sessionStorage.getItem('bc_session');if(!raw){const legacy=localStorage.getItem('bc_session');if(legacy){sessionStorage.setItem('bc_session',legacy);localStorage.removeItem('bc_session');raw=legacy;}}return JSON.parse(raw||'null')}catch{return null} }
function saveSession(s){ sessionStorage.setItem('bc_session',JSON.stringify(s)); localStorage.removeItem('bc_session'); state.session=s; }
function clearSession(){sessionStorage.removeItem('bc_session');localStorage.removeItem('bc_session');state.session=null;}
let refreshPromise=null; let turnstileWidgetId=null;
async function refreshCloudSession(){
  if(refreshPromise)return refreshPromise;const c=state.cloudConfig||loadCloudConfig();const rt=state.session?.refresh_token;if(!c||!rt)throw new Error('Sesi berakhir. Silakan login kembali.');
  refreshPromise=(async()=>{const res=await fetch(c.url+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:c.key,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:rt})});const data=await res.json();if(!res.ok)throw new Error(data.message||'Gagal memperbarui sesi');saveSession(data);return data})().finally(()=>refreshPromise=null);return refreshPromise;
}
async function cloudRequest(path,{method='GET',body=null,prefer=false,retry=true}={}){
  const c=state.cloudConfig||loadCloudConfig(); if(!c?.url||!c?.key) throw new Error('Layanan Cloud belum tersedia pada deployment ini'); if(!isOnline())throw new Error('Tidak ada koneksi internet. Data belum dikirim.');
  setSyncState('syncing'); const controller=new AbortController();const timeout=setTimeout(()=>controller.abort(),12000);
  try{
    const token=state.session?.access_token||c.key;const headers={'apikey':c.key,'Authorization':`Bearer ${token}`,'Content-Type':'application/json'};if(prefer)headers.Prefer='return=representation';
    const res=await fetch(c.url+path,{method,headers,body:body?JSON.stringify(body):undefined,signal:controller.signal});const text=await res.text();let data=null;try{data=text?JSON.parse(text):null}catch{data=text}
    if(res.status===401&&retry&&state.session?.refresh_token){await refreshCloudSession();return cloudRequest(path,{method,body,prefer,retry:false})}
    if(!res.ok)throw new Error(data?.message||data?.msg||data?.error_description||data?.hint||`HTTP ${res.status}`);setSyncState('idle');return data;
  }catch(err){const msg=err.name==='AbortError'?'Koneksi timeout. Coba lagi.':err.message;setSyncState('error',msg);throw new Error(msg)}finally{clearTimeout(timeout)}
}
async function ensureTurnstile(){
  const key=(state.cloudConfig||loadCloudConfig())?.turnstileSiteKey; const box=$('#turnstileBox');
  if(!box) return; if(authMode==='reset'){box.classList.add('hidden');box.innerHTML='';turnstileWidgetId=null;return;} if(!key){box.classList.add('hidden');box.innerHTML='';turnstileWidgetId=null;return;}
  box.classList.remove('hidden');
  if(!window.turnstile){
    await new Promise((resolve,reject)=>{const existing=document.querySelector('script[data-bc-turnstile]');if(existing){existing.addEventListener('load',resolve,{once:true});existing.addEventListener('error',reject,{once:true});return;}const sc=document.createElement('script');sc.src='https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';sc.async=true;sc.defer=true;sc.dataset.bcTurnstile='1';sc.onload=resolve;sc.onerror=()=>reject(new Error('CAPTCHA gagal dimuat'));document.head.appendChild(sc);});
  }
  box.innerHTML=''; turnstileWidgetId=window.turnstile.render(box,{sitekey:key,theme:'light'});
}
function captchaToken(){const key=(state.cloudConfig||loadCloudConfig())?.turnstileSiteKey;if(!key)return null;if(!window.turnstile||turnstileWidgetId===null)throw new Error('CAPTCHA belum siap. Coba beberapa detik lagi.');const token=window.turnstile.getResponse(turnstileWidgetId);if(!token)throw new Error('Selesaikan CAPTCHA terlebih dahulu.');return token;}
function resetCaptcha(){try{if(window.turnstile&&turnstileWidgetId!==null)window.turnstile.reset(turnstileWidgetId)}catch{}}
async function authSubmit(email,password){
  const c=state.cloudConfig||loadCloudConfig(); if(!c) throw new Error('Layanan Cloud belum tersedia pada deployment ini');
  if(String(password||'').length<8)throw new Error('Password minimal 8 karakter');
  const token=captchaToken();const payload={email,password};if(token)payload.gotrue_meta_security={captcha_token:token};
  const res=await fetch(c.url+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'apikey':c.key,'Content-Type':'application/json'},body:JSON.stringify(payload)});
  let data={};try{data=await res.json()}catch{}
  resetCaptcha();
  if(!res.ok){if(res.status===429)throw new Error('Terlalu banyak percobaan login. Tunggu sebentar lalu coba lagi.');throw new Error(data.msg||data.error_description||data.message||'Autentikasi gagal');}
  saveSession(data); return data;
}

function recoveryRedirectUrl(){
  if(!/^https?:$/.test(location.protocol))throw new Error('Reset password hanya tersedia pada deployment HTTPS/HTTP, bukan file lokal.');
  return location.origin+location.pathname;
}
async function sendPasswordRecovery(email){
  const c=state.cloudConfig||loadCloudConfig();if(!c?.url||!c?.key)throw new Error('Layanan Cloud belum tersedia pada deployment ini');
  email=String(email||'').trim();if(!email||!email.includes('@'))throw new Error('Masukkan email yang valid');
  const token=captchaToken();const payload={email};if(token)payload.gotrue_meta_security={captcha_token:token};
  const redirectTo=recoveryRedirectUrl();
  const res=await fetch(c.url+'/auth/v1/recover?redirect_to='+encodeURIComponent(redirectTo),{method:'POST',headers:{apikey:c.key,'Content-Type':'application/json'},body:JSON.stringify(payload)});
  let data={};try{data=await res.json()}catch{}
  resetCaptcha();
  if(!res.ok){if(res.status===429)throw new Error('Permintaan reset terlalu sering. Tunggu sebentar lalu coba lagi.');throw new Error(data.msg||data.error_description||data.message||'Gagal mengirim email reset password');}
  // Deliberately generic: do not reveal whether the email is registered.
  toast('Jika email terdaftar, link reset password akan dikirim.','success',5000);
  return true;
}
async function loadRecoverySessionFromUrl(){
  const hash=new URLSearchParams((location.hash||'').replace(/^#/,''));
  if(hash.get('error_description')){toast(decodeURIComponent(hash.get('error_description')),'error',6000);history.replaceState({},document.title,location.pathname+location.search);return false;}
  const linkType=hash.get('type');
  if(!['recovery','invite'].includes(linkType)||!hash.get('access_token'))return false;
  const c=state.cloudConfig||loadCloudConfig();if(!c?.url||!c?.key){showAuth();setAuthMode('login');toast('Link Auth valid, tetapi layanan Cloud belum tersedia pada deployment ini.','error',7000);return true;}
  const accessToken=hash.get('access_token');const refreshToken=hash.get('refresh_token')||'';
  const userRes=await fetch(c.url+'/auth/v1/user',{headers:{apikey:c.key,Authorization:'Bearer '+accessToken}});
  let user={};try{user=await userRes.json()}catch{}
  if(!userRes.ok)throw new Error(user?.message||'Link tidak valid atau sudah kedaluwarsa');
  saveSession({access_token:accessToken,refresh_token:refreshToken,token_type:hash.get('token_type')||'bearer',expires_in:Number(hash.get('expires_in')||3600),user});
  authLinkType=linkType;authInviteKind=String(user?.user_metadata?.bizcontrol_account_type||'employee');state.cloudConfig=c;state.mode='cloud';setAuthMode('reset');showAuth();
  if(linkType==='invite')toast(authInviteKind==='owner'?'Undangan Owner diterima. Buat password untuk mengaktifkan akun BizControl.':'Undangan karyawan diterima. Buat password untuk mengaktifkan akun.','success',7000);
  return true;
}
async function updateRecoveredPassword(password){
  const c=state.cloudConfig||loadCloudConfig();const token=state.session?.access_token;
  if(!c?.url||!c?.key||!token)throw new Error('Sesi reset password tidak tersedia');
  if(String(password||'').length<8)throw new Error('Password baru minimal 8 karakter');
  const res=await fetch(c.url+'/auth/v1/user',{method:'PUT',headers:{apikey:c.key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({password})});
  let data={};try{data=await res.json()}catch{}
  if(!res.ok)throw new Error(data.msg||data.error_description||data.message||'Gagal mengubah password');
  // End the recovery session and require a normal sign-in with the new password.
  try{await fetch(c.url+'/auth/v1/logout',{method:'POST',headers:{apikey:c.key,Authorization:'Bearer '+token}})}catch{}
  const wasInvite=authLinkType==='invite';const inviteKind=authInviteKind;authLinkType=null;authInviteKind=null;clearSession();history.replaceState({},document.title,location.pathname+location.search);setAuthMode('login');showAuth();toast(wasInvite?(inviteKind==='owner'?'Akun Owner aktif. Silakan login dengan password baru.':'Akun karyawan aktif. Silakan login dengan password baru.'):'Password berhasil diubah. Silakan login dengan password baru.','success',7000);return true;
}
function setAuthMode(mode){
  authMode=mode;const tabs=$('#authTabs'),emailLabel=$('#authEmailLabel'),passwordLabel=$('#authPasswordLabel'),confirmLabel=$('#authPasswordConfirmLabel');
  const email=$('#authEmail'),password=$('#authPassword'),confirm=$('#authPasswordConfirm'),forgot=$('#forgotPasswordBtn'),back=$('#authBackLogin'),subtitle=$('#authSubtitle'),contact=$('#contactAdminBtn'),demo=$('#backToDemo');
  tabs?.classList.toggle('hidden',mode==='recover'||mode==='reset');
  emailLabel.classList.toggle('hidden',mode==='reset');passwordLabel.classList.toggle('hidden',mode==='recover');confirmLabel.classList.toggle('hidden',mode!=='reset');
  email.disabled=mode==='reset';email.required=mode!=='reset';password.disabled=mode==='recover';password.required=mode!=='recover';confirm.disabled=mode!=='reset';confirm.required=mode==='reset';
  password.autocomplete=mode==='reset'?'new-password':'current-password';
  forgot.classList.toggle('hidden',mode!=='login');back.classList.toggle('hidden',mode==='login'||mode==='reset');
  contact?.classList.toggle('hidden',mode!=='login');demo?.classList.toggle('hidden',mode==='reset');
  $('#authPasswordLabelText').textContent=mode==='reset'?'Password Baru':'Password';
  $('#authSubmit').textContent=mode==='login'?'Masuk':mode==='recover'?'Kirim Link Reset':'Simpan Password Baru';
  subtitle.textContent=mode==='recover'?'Masukkan email akun. Demi keamanan, sistem tidak akan memberi tahu apakah email terdaftar.':mode==='reset'?(authLinkType==='invite'?(authInviteKind==='owner'?'Undangan Owner diterima. Buat password baru minimal 8 karakter, lalu login.':'Undangan diterima. Buat password baru minimal 8 karakter, lalu login untuk mulai bekerja.'):'Buat password baru minimal 8 karakter. Setelah berhasil, Anda akan diminta login kembali.'):'Masuk ke akun BizControl. Pendaftaran Owner baru hanya melalui Admin BizControl.';
  if(mode!=='reset')confirm.value='';
  ensureTurnstile().catch(()=>{});
}
async function cloudBootstrap(){
  try{
    state.mode='cloud'; state.cloudConfig=loadCloudConfig()||state.cloudConfig; state.session=loadSession()||state.session;
    if(!state.session?.access_token){showAuth();return;}

    // First successful login activates trusted invitations.
    await cloudRequest('/rest/v1/rpc/activate_pending_memberships',{method:'POST'}).catch(e=>console.warn('activate membership:',e.message));
    await cloudRequest('/rest/v1/rpc/activate_owner_account',{method:'POST'}).catch(e=>console.warn('activate owner:',e.message));
    await checkSystemAdmin();
    await cloudLoadBusinesses();

    if(!state.businesses.length){
      let canCreate=false;try{canCreate=Boolean(await cloudRequest('/rest/v1/rpc/can_create_business',{method:'POST'}))}catch(e){console.warn('can create business:',e.message)}
      if(canCreate){
        await addBusiness('Bisnis Saya');
        await cloudLoadBusinesses();
      }else if(state.isSystemAdmin){
        state.currentBusinessId=null;state.currentRole='staff';state.products=[];state.sales=[];state.saleItems=[];state.payments=[];state.expenses=[];state.auditLogs=[];state.teamMembers=[];state.page='systemAdmin';
        await loadManagedOwners().catch(e=>console.warn('managed owners:',e.message));hideAuth();startPolling();render();toast('Admin Sistem tersambung');return;
      }else{
        stopPolling();state.currentBusinessId=null;state.currentRole='staff';state.products=[];state.sales=[];state.saleItems=[];state.payments=[];state.expenses=[];state.auditLogs=[];state.teamMembers=[];
        clearSession();setAuthMode('login');showAuth();toast('Akun ini tidak memiliki akses aktif. Hubungi Owner atau Admin BizControl.','error',8000);return;
      }
    }

    if(!state.currentBusinessId || !state.businesses.some(b=>b.id===state.currentBusinessId)) state.currentBusinessId=state.businesses[0]?.id;
    await cloudLoadBusinessData(); if(state.isSystemAdmin)await loadManagedOwners().catch(e=>console.warn('managed owners:',e.message)); hideAuth(); startPolling(); render(); toast('Cloud tersambung');
  }catch(err){
    console.error('Cloud bootstrap gagal:',err);
    stopPolling();
    // Never leave the user on a half-loaded/blank application shell.
    // Keep the session for non-auth errors so the user can retry after deployment/database is fixed.
    if(/JWT|token|session|401/i.test(String(err.message||''))) clearSession();
    setAuthMode('login');
    showAuth();
    toast('Cloud gagal dimuat: '+(err.message||'Unknown error'),'error',9000);
  }
}
async function cloudLoadBusinesses(){
  const rows=await cloudRequest('/rest/v1/businesses?select=*&order=created_at.asc');state.businesses=rows||[];
  const memberships=await cloudRequest('/rest/v1/business_members?select=business_id,user_id,role,status&user_id=eq.'+encodeURIComponent(state.session.user.id)).catch(()=>[]);state.memberships=memberships||[];
  if(state.currentBusinessId&&!state.businesses.some(b=>b.id===state.currentBusinessId))state.currentBusinessId=state.businesses[0]?.id||null;
}
function resolveCloudRole(){const b=activeBusiness();if(!b)return'staff';if(b.owner_id===state.session?.user?.id)return'owner';return state.memberships?.find(m=>m.business_id===b.id&&m.user_id===state.session?.user?.id&&m.status!=='pending')?.role||'staff'}
async function cloudLoadTeam(){if(!can('team_view')){state.teamMembers=[];return}try{state.teamMembers=await cloudRequest('/rest/v1/rpc/list_business_members',{method:'POST',body:{bid:state.currentBusinessId}})||[]}catch(e){console.warn('Team RPC:',e.message);state.teamMembers=[]}}

async function cloudLoadBusinessData(){
  if(!state.currentBusinessId)return;state.currentRole=resolveCloudRole();const b=encodeURIComponent(state.currentBusinessId);
  const queries=[];
  queries.push(cloudRequest('/rest/v1/rpc/list_products_for_business',{method:'POST',body:{p_bid:state.currentBusinessId}}));
  queries.push(can('sales_view')?cloudRequest('/rest/v1/rpc/list_sales_for_business',{method:'POST',body:{bid:state.currentBusinessId}}):Promise.resolve([]));
  queries.push(can('sales_view')?cloudRequest('/rest/v1/rpc/list_sale_items_for_business',{method:'POST',body:{p_bid:state.currentBusinessId}}):Promise.resolve([]));
  queries.push(can('payments_manage')?cloudRequest(`/rest/v1/payments?select=*&business_id=eq.${b}&order=payment_date.asc,payment_no.asc`).catch(()=>[]):Promise.resolve([]));
  queries.push(can('expenses_view')?cloudRequest(`/rest/v1/expenses?select=*&business_id=eq.${b}&order=date.desc,created_at.desc`):Promise.resolve([]));
  queries.push(can('audit')?cloudRequest(`/rest/v1/audit_logs?select=*&business_id=eq.${b}&order=created_at.desc&limit=250`).catch(()=>[]):Promise.resolve([]));
  const [products,sales,saleItems,payments,expenses,auditLogs]=await Promise.all(queries);state.products=products||[];state.sales=sales||[];state.saleItems=saleItems||[];state.payments=payments||[];state.expenses=expenses||[];state.auditLogs=auditLogs||[];await cloudLoadTeam();state.lastSync=new Date().toISOString();setSyncState('idle');
}
async function refreshAuditLog(){
  if(state.mode==='cloud'){ try{await cloudLoadBusinessData();navigate('audit');toast('Audit Log diperbarui');}catch(err){toast(err.message);} }
  else { navigate('audit'); toast('Audit Log lokal sudah terbaru'); }
}
function startPolling(){stopPolling();pollTimer=setInterval(async()=>{if(state.mode==='cloud'&&state.session&&isOnline()){try{
  await cloudLoadBusinesses();
  if(!state.businesses.length){
    if(state.isSystemAdmin){state.page='systemAdmin';await loadManagedOwners().catch(()=>{});render();return;}
    stopPolling();clearSession();state.currentBusinessId=null;state.currentRole='staff';showAuth();toast('Akses bisnis Anda sudah tidak aktif. Hubungi Owner.','error',8000);return;
  }
  await cloudLoadBusinessData();if($('#modalBackdrop').classList.contains('hidden'))render();else renderSyncBadge();
}catch(e){console.warn(e)}}},8000);}
function startRealtime(){startPolling();}
function stopRealtime(){}
function stopPolling(){if(pollTimer){clearInterval(pollTimer);pollTimer=null;}}

function showAuth(){ $('#authView').classList.remove('hidden'); $('#appShell').classList.add('hidden'); ensureTurnstile().catch(e=>toast(e.message,'error')); }
function hideAuth(){ $('#authView').classList.add('hidden'); $('#appShell').classList.remove('hidden'); }

// -------- Backup / Export helpers --------
function downloadBlob(content,type,filename){const blob=new Blob([content],{type});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=filename;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(a.href),500)}
function exportJson(){const b=state.currentBusinessId;const data={version:'1.8.7.2',exported_at:new Date().toISOString(),business:activeBusiness(),products:businessData(state.products),sales:businessData(state.sales),saleItems:businessData(state.saleItems||[]),payments:businessData(state.payments||[]),expenses:businessData(state.expenses),auditLogs:can('audit')?businessData(state.auditLogs||[]):[]};downloadBlob(JSON.stringify(data,null,2),'application/json',`bizcontrol-backup-${slug(activeBusiness()?.name||'bisnis')}-${today()}.json`);toast('Backup JSON dibuat','success')}
function csvEscape(v){if(v===null||v===undefined)return'';let x=typeof v==='object'?JSON.stringify(v):String(v);return /[",\n]/.test(x)?'"'+x.replace(/"/g,'""')+'"':x}
function exportCsv(name,rows){if(!rows?.length){toast('Tidak ada data untuk diexport','error');return}const keys=[...new Set(rows.flatMap(r=>Object.keys(r)))].filter(k=>!['before_data','after_data'].includes(k));const csv='\uFEFF'+[keys.join(','),...rows.map(r=>keys.map(k=>csvEscape(r[k])).join(','))].join('\r\n');downloadBlob(csv,'text/csv;charset=utf-8',`bizcontrol-${name}-${slug(activeBusiness()?.name||'bisnis')}-${today()}.csv`);toast(`CSV ${name} dibuat`,'success')}
function exportAllCsv(){if(!can('export')&&state.mode!=='local'){toast('Role ini tidak diizinkan export','error');return}exportCsv('produk',businessData(state.products));setTimeout(()=>exportCsv('penjualan',businessData(state.sales)),250);setTimeout(()=>exportCsv('item-penjualan',businessData(state.saleItems||[])),500);setTimeout(()=>exportCsv('pembayaran',businessData(state.payments||[])),750);setTimeout(()=>exportCsv('biaya',businessData(state.expenses)),1000)}
function importJson(){const i=document.createElement('input');i.type='file';i.accept='application/json';i.onchange=()=>{const f=i.files[0];if(!f)return;const r=new FileReader();r.onload=()=>{try{const data=JSON.parse(r.result);state={...defaultState(),...data,mode:'local',session:null,saleItems:Array.isArray(data.saleItems)?data.saleItems:[]};(state.sales||[]).forEach(sale=>{if(state.saleItems.some(x=>x.sale_id===sale.id&&x.business_id===sale.business_id))return;const p=(state.products||[]).find(x=>x.id===sale.product_id)||{};state.saleItems.push({id:uid(),business_id:sale.business_id,sale_id:sale.id,line_no:1,product_id:sale.product_id,product_name:sale.product_name||p.name||'Produk',unit:p.unit||'pcs',qty:Number(sale.qty||0),unit_price:Number(sale.unit_price||0),unit_cost:Number(sale.unit_cost||0),line_total:Number(sale.qty||0)*Number(sale.unit_price||0),line_gross_profit:Number(sale.qty||0)*(Number(sale.unit_price||0)-Number(sale.unit_cost||0))})});persist();render();toast('Backup diimport','success')}catch{toast('File backup tidak valid','error')}};r.readAsText(f)};i.click()}
function slug(s=''){return String(s).toLowerCase().trim().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')||'bisnis'}
function escapeHtml(s=''){return String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}
function escapeAttr(s=''){return escapeHtml(s)}
function fmtDate(d){if(!d)return'-';return new Date(d+'T00:00:00').toLocaleDateString('id-ID',{day:'2-digit',month:'short',year:'numeric'})}

function openCloudAuth(){
  stopPolling();
  clearSession();
  setAuthMode('login');
  showAuth();
}
function enterDemoSandbox(){
  stopPolling();
  clearSession();
  state.mode='local';
  state.currentRole='owner';
  state.isSystemAdmin=false;state.managedOwners=[];
  if(!state.businesses?.length){state=defaultState();}
  hideAuth();
  render();
  toast('Mode Demo aktif — data hanya simulasi di browser','success',4500);
}

// -------- Global bindings --------
$('#quickSaleBtn').onclick=()=>requirePermission('sales_create')&&openSaleModal();
$('#openSettingsBtn').onclick=()=>navigate('settings');
$('#accountSettingsBtn').onclick=()=>navigate('settings');
$('#logoutBtn').onclick=()=>logoutCloud();
$('#openAuthBtn').onclick=()=>openCloudAuth();
$('#newBusinessBtn').onclick=openBusinessModal;
$('#syncNowBtn').onclick=async()=>{if(state.mode==='cloud'){try{await cloudLoadBusinesses();await cloudLoadBusinessData();render();toast('Data tersinkron','success')}catch(e){toast(e.message,'error')}}else toast('Mode demo tersimpan di perangkat ini')};
$('#modalBackdrop').classList.add('hidden');

$('#forgotPasswordBtn').onclick=()=>setAuthMode('recover');
$('#contactAdminBtn').onclick=()=>contactSystemAdmin();
$('#authBackLogin').onclick=()=>setAuthMode('login');
$('#authForm').onsubmit=async e=>{e.preventDefault();try{
  if(authMode==='recover'){await sendPasswordRecovery($('#authEmail').value);setAuthMode('login');return;}
  if(authMode==='reset'){
    const p=$('#authPassword').value,c=$('#authPasswordConfirm').value;if(p!==c)throw new Error('Ulangi password harus sama');await updateRecoveredPassword(p);return;
  }
  const session=await authSubmit($('#authEmail').value,$('#authPassword').value);if(session)await cloudBootstrap();
}catch(err){toast(err.message,'error')}};
$('#backToDemo').onclick=()=>enterDemoSandbox();
$('#demoLoginBtn').onclick=()=>openCloudAuth();

window.addEventListener('online',async()=>{toast('Koneksi kembali. Menyinkronkan...','success');if(state.mode==='cloud'){try{await cloudLoadBusinesses();await cloudLoadBusinessData();startPolling();render()}catch(e){toast(e.message,'error')}}});
window.addEventListener('offline',()=>{setSyncState('offline');toast('Internet terputus. Jangan tutup form yang belum tersimpan.','error',5000)});
document.addEventListener('visibilitychange',async()=>{if(document.visibilityState==='visible'&&state.mode==='cloud'&&isOnline()){try{await cloudLoadBusinesses();await cloudLoadBusinessData();render()}catch(e){console.warn(e)}}});

// -------- Boot --------
(async()=>{
  // Remove legacy user-editable cloud configuration from older builds.
  localStorage.removeItem('bc_cloud_config');
  state.cloudConfig=loadCloudConfig();state.session=loadSession();setAuthMode('login');
  try{if(await loadRecoverySessionFromUrl())return;}catch(err){clearSession();setAuthMode('login');showAuth();toast(err.message,'error',7000);return;}
  if(state.cloudConfig&&state.session){state.mode='cloud';cloudBootstrap();}
  else {state.mode='local';setAuthMode('login');showAuth();}
})();
if('serviceWorker' in navigator && location.protocol.startsWith('http')) navigator.serviceWorker.register('./sw.js').catch(()=>{});
