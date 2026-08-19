
(function(){
  'use strict';

  const VERSION = '1.0.0';
  const PIXEL_ID = '1081611444299321';
  const DEFAULT_LANDING = 'https://bizcontrol-landing.vercel.app/?utm_source=pos_demo&utm_medium=product&utm_campaign=demo_to_sales#harga';
  const GUIDE_KEY = 'bc_demo_conversion_guide_v1';
  const SESSION_TRACK_KEY = 'bc_demo_pos_started_v1';

  const getCfg = () => Object.assign({
    landingUrl: DEFAULT_LANDING,
    monthlyLabel: 'Rp79.000/bulan',
    pixelId: PIXEL_ID
  }, window.BIZCONTROL_DEMO_SALES || {});

  function isDemo(){
    try { return typeof state !== 'undefined' && state && state.mode === 'local'; }
    catch(_) { return false; }
  }

  function safeJSON(raw, fallback){
    try { return JSON.parse(raw || '') || fallback; } catch(_) { return fallback; }
  }

  function guideState(){
    return Object.assign({sale:false,stock:false,report:false,dismissed:false}, safeJSON(localStorage.getItem(GUIDE_KEY), {}));
  }

  function saveGuide(patch){
    const next = Object.assign(guideState(), patch || {});
    localStorage.setItem(GUIDE_KEY, JSON.stringify(next));
    refreshAll();
    return next;
  }

  function loadPixel(){
    const cfg = getCfg();
    if(typeof window.fbq === 'function') return;
    !function(f,b,e,v,n,t,s){
      if(f.fbq)return;n=f.fbq=function(){n.callMethod?n.callMethod.apply(n,arguments):n.queue.push(arguments)};
      if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];
      t=b.createElement(e);t.async=!0;t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)
    }(window,document,'script','https://connect.facebook.net/en_US/fbevents.js');
    window.fbq('init', String(cfg.pixelId || PIXEL_ID));
  }

  function trackCustom(name, params){
    try{
      loadPixel();
      if(typeof window.fbq === 'function') window.fbq('trackCustom', name, Object.assign({
        product:'BizControl Online',
        source:'pos_demo'
      }, params || {}));
    }catch(_){}
  }

  function trackDemoStartOnce(){
    if(!isDemo()) return;
    if(sessionStorage.getItem(SESSION_TRACK_KEY)) return;
    sessionStorage.setItem(SESSION_TRACK_KEY, '1');
    trackCustom('POSDemoStart', {version:VERSION});
  }

  function goLanding(source){
    const cfg = getCfg();
    trackCustom('DemoPurchaseIntent', {cta_source:source || 'unknown', price_plan:'monthly_79000'});
    window.location.href = cfg.landingUrl || DEFAULT_LANDING;
  }

  function nav(page){
    if(!isDemo()) return;
    try{
      if(typeof navigate === 'function'){
        navigate(page);
      }else{
        const btn = document.querySelector('[data-nav="'+page+'"]');
        if(btn) btn.click();
      }
    }catch(_){
      const btn = document.querySelector('[data-nav="'+page+'"]');
      if(btn) btn.click();
    }
  }

  function openSale(){
    nav('sales');
    setTimeout(()=>{
      const q = document.querySelector('#quickSaleBtn');
      if(q && !q.classList.contains('hidden')) { q.click(); return; }
      const b = document.querySelector('[data-action="add-sale"]');
      if(b) b.click();
    }, 180);
  }

  function progressHTML(){
    const g = guideState();
    const item = (done, active, n, label) =>
      '<span class="'+(done?'done':active?'active':'')+'"><i>'+(done?'✓':n)+'</i>'+label+'</span>';
    const activeSale = !g.sale;
    const activeStock = g.sale && !g.stock;
    const activeReport = g.sale && g.stock && !g.report;
    return item(g.sale,activeSale,'1','Coba transaksi') +
           item(g.stock,activeStock,'2','Lihat stok') +
           item(g.report,activeReport,'3','Buka laporan');
  }

  function bannerHTML(){
    const cfg = getCfg();
    return `
      <div class="bc-demo-conversion-copy">
        <b>Mode Demo — coba alur BizControl sebelum membeli</b>
        <span>Data di sini hanya simulasi. Ikuti 3 langkah singkat untuk melihat transaksi, stok, dan laporan saling terhubung.</span>
        <div class="bc-demo-progress">${progressHTML()}</div>
      </div>
      <div class="bc-demo-conversion-actions">
        <button type="button" class="bc-demo-guide-btn" data-bc-demo-action="guide">Panduan Demo</button>
        <button type="button" class="bc-demo-buy-btn" data-bc-demo-action="buy">Aktifkan ${cfg.monthlyLabel}</button>
      </div>`;
  }

  function ensureBanner(){
    const content = document.querySelector('#pageContent');
    if(!content) return;
    let el = document.querySelector('#bcDemoConversionBanner');
    if(!isDemo()){
      if(el) el.remove();
      return;
    }
    if(!el){
      el = document.createElement('section');
      el.id = 'bcDemoConversionBanner';
      el.className = 'bc-demo-conversion-banner';
      content.prepend(el);
    }
    el.innerHTML = bannerHTML();
  }

  function ensureTopCTA(){
    const actions = document.querySelector('.top-actions');
    let btn = document.querySelector('#bcDemoTopBuy');
    if(!isDemo()){
      if(btn) btn.remove();
      return;
    }
    if(actions && !btn){
      btn = document.createElement('button');
      btn.id = 'bcDemoTopBuy';
      btn.type = 'button';
      btn.className = 'ghost bc-demo-top-buy';
      btn.dataset.bcDemoAction = 'buy-top';
      btn.textContent = 'Aktifkan — Rp79rb';
      actions.appendChild(btn);
    }
  }

  function ensureMobileCTA(){
    let el = document.querySelector('#bcDemoMobileCTA');
    if(!isDemo()){
      if(el) el.remove();
      return;
    }
    if(!el){
      el = document.createElement('div');
      el.id = 'bcDemoMobileCTA';
      el.className = 'bc-demo-mobile-cta';
      el.innerHTML = `
        <button type="button" class="bc-demo-guide-btn" data-bc-demo-action="guide">Panduan</button>
        <button type="button" class="bc-demo-buy-btn" data-bc-demo-action="buy-mobile">Aktifkan Rp79rb</button>`;
      document.body.appendChild(el);
    }
  }

  function onboardingHTML(){
    return `
      <div class="bc-demo-onboarding-card" role="dialog" aria-modal="true" aria-labelledby="bcDemoGuideTitle">
        <div class="bc-demo-onboarding-head">
          <div class="bc-demo-onboarding-kicker">COBA BIZCONTROL DALAM ±2 MENIT</div>
          <h2 id="bcDemoGuideTitle">Jangan cuma lihat dashboard. Coba alurnya.</h2>
          <p>Tujuannya sederhana: buat satu transaksi, lihat stok berubah, lalu lihat dampaknya di laporan. Setelah itu kamu sudah tahu apakah BizControl cocok untuk operasional bisnis kamu.</p>
        </div>
        <div class="bc-demo-onboarding-steps">
          <div class="bc-demo-onboarding-step"><span>1</span><b>Buat transaksi</b><small>Masuk Kasir dan pilih produk simulasi. Selesaikan satu transaksi.</small></div>
          <div class="bc-demo-onboarding-step"><span>2</span><b>Cek stok</b><small>Lihat jumlah stok setelah transaksi agar terasa hubungan kasir dan inventory.</small></div>
          <div class="bc-demo-onboarding-step"><span>3</span><b>Buka laporan</b><small>Lihat omzet, biaya, piutang, dan performa bisnis dari data yang sudah tercatat.</small></div>
        </div>
        <div class="bc-demo-onboarding-actions">
          <button type="button" class="bc-demo-skip" data-bc-demo-action="skip">Saya lihat sendiri</button>
          <button type="button" class="bc-demo-start" data-bc-demo-action="start-sale">Mulai dari Transaksi →</button>
        </div>
      </div>`;
  }

  function openGuide(force){
    if(!isDemo()) return;
    const g = guideState();
    if(!force && g.dismissed) return;
    closeGuide();
    const overlay = document.createElement('div');
    overlay.id = 'bcDemoOnboarding';
    overlay.className = 'bc-demo-onboarding';
    overlay.innerHTML = onboardingHTML();
    document.body.appendChild(overlay);
    trackCustom('DemoGuideOpened', {forced:Boolean(force)});
  }

  function closeGuide(){
    document.querySelector('#bcDemoOnboarding')?.remove();
  }

  function coach(title, text, label, action){
    document.querySelector('#bcDemoCoach')?.remove();
    if(!isDemo()) return;
    const el = document.createElement('div');
    el.id = 'bcDemoCoach';
    el.className = 'bc-demo-coach';
    el.innerHTML = `
      <button class="bc-demo-coach-close" type="button" aria-label="Tutup" data-bc-demo-action="coach-close">×</button>
      <div class="bc-demo-coach-title">${title}</div>
      <div class="bc-demo-coach-text">${text}</div>
      <div class="bc-demo-coach-actions">
        <button type="button" class="bc-demo-coach-btn" data-bc-demo-action="${action}">${label}</button>
      </div>`;
    document.body.appendChild(el);
  }

  function markStep(step){
    const g = guideState();
    if(g[step]) return;
    saveGuide({[step]:true});
    trackCustom('DemoGuideStep', {step:step});
    if(step === 'sale'){
      trackCustom('DemoSaleCreated');
      coach(
        'Transaksi berhasil.',
        'Sekarang lihat menu Produk & Stok. Jumlah stok mengikuti transaksi yang baru kamu buat.',
        'Lihat Perubahan Stok →',
        'next-stock'
      );
    }else if(step === 'stock'){
      coach(
        'Stok sudah kamu lihat.',
        'Langkah terakhir: buka Laporan untuk melihat bagaimana data transaksi menjadi informasi untuk owner.',
        'Buka Laporan →',
        'next-report'
      );
    }else if(step === 'report'){
      coach(
        'Kamu sudah melihat alur utamanya.',
        'Kalau alurnya cocok untuk bisnis kamu, aktifkan BizControl Online mulai Rp79.000/bulan.',
        'Aktifkan BizControl →',
        'buy-complete'
      );
      trackCustom('DemoGuideCompleted');
    }
  }

  function observeToast(){
    const toast = document.querySelector('#toast');
    if(!toast) return;
    const read = ()=>{
      if(!isDemo()) return;
      const t = (toast.textContent || '').trim().toLowerCase();
      if(t.includes('penjualan tersimpan')) markStep('sale');
    };
    new MutationObserver(read).observe(toast,{childList:true,subtree:true,characterData:true,attributes:true});
  }

  function handleClicks(e){
    const target = e.target.closest('[data-bc-demo-action]');
    if(target){
      const a = target.dataset.bcDemoAction;
      if(a === 'guide') openGuide(true);
      else if(a === 'skip'){ saveGuide({dismissed:true}); closeGuide(); }
      else if(a === 'start-sale'){ saveGuide({dismissed:true}); closeGuide(); trackCustom('DemoGuideStart'); openSale(); }
      else if(a === 'buy' || a === 'buy-top' || a === 'buy-mobile' || a === 'buy-complete') goLanding(a);
      else if(a === 'next-stock'){ document.querySelector('#bcDemoCoach')?.remove(); nav('products'); markStep('stock'); }
      else if(a === 'next-report'){ document.querySelector('#bcDemoCoach')?.remove(); nav('reports'); markStep('report'); }
      else if(a === 'coach-close') document.querySelector('#bcDemoCoach')?.remove();
      return;
    }

    if(!isDemo()) return;

    const navBtn = e.target.closest('[data-nav]');
    if(navBtn){
      const page = navBtn.dataset.nav;
      if(page === 'products' && guideState().sale) setTimeout(()=>markStep('stock'),120);
      if(page === 'reports' && guideState().sale) setTimeout(()=>markStep('report'),120);
    }

    const actionBtn = e.target.closest('[data-action]');
    if(actionBtn){
      const a = actionBtn.dataset.action || '';
      if((a === 'open-low-stock' || a === 'open-product-detail') && guideState().sale) markStep('stock');
      if((a === 'open-weekly-sales' || a === 'open-health-summary') && guideState().sale) markStep('report');
    }
  }

  function refreshAll(){
    ensureBanner();
    ensureTopCTA();
    ensureMobileCTA();
  }

  function observeRenders(){
    const content = document.querySelector('#pageContent');
    if(!content) return;
    let queued = false;
    new MutationObserver(()=>{
      if(queued) return;
      queued = true;
      requestAnimationFrame(()=>{
        queued = false;
        refreshAll();
      });
    }).observe(content,{childList:true,subtree:false});
  }

  function boot(){
    document.addEventListener('click', handleClicks, true);
    observeToast();
    observeRenders();
    refreshAll();
    trackDemoStartOnce();

    // Show onboarding only on the first Demo experience.
    setTimeout(()=>{
      if(isDemo() && !guideState().dismissed) openGuide(false);
    }, 650);

    // Handle mode changes local <-> cloud.
    setInterval(()=>{
      refreshAll();
      if(isDemo()) trackDemoStartOnce();
      else{
        closeGuide();
        document.querySelector('#bcDemoCoach')?.remove();
      }
    }, 1200);
  }

  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded',()=>setTimeout(boot,0));
  else setTimeout(boot,0);

  window.BizControlDemoConversion = {
    version: VERSION,
    openGuide: ()=>openGuide(true),
    resetGuide: ()=>{
      localStorage.removeItem(GUIDE_KEY);
      sessionStorage.removeItem(SESSION_TRACK_KEY);
      refreshAll();
      openGuide(true);
    }
  };
})();
