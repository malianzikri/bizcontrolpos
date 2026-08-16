from pathlib import Path
from playwright.sync_api import sync_playwright
import re, json
root=Path(__file__).resolve().parent
html=(root/'index.html').read_text(); css=(root/'styles.css').read_text(); js=(root/'app.js').read_text()
poly='''<script>const __ls={},__ss={};const mk=s=>({getItem:k=>(k in s?s[k]:null),setItem:(k,v)=>{s[k]=String(v)},removeItem:k=>{delete s[k]},clear:()=>{for(const k in s)delete s[k]}});Object.defineProperty(window,"localStorage",{value:mk(__ls)});Object.defineProperty(window,"sessionStorage",{value:mk(__ss)});window.BIZCONTROL_CONFIG={supabaseUrl:"",publishableKey:"",turnstileSiteKey:""};</script>'''
html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]*>','',html)
html=html.replace('<link rel="stylesheet" href="styles.css" />',f'<style>{css}</style>')
html=html.replace('<script src="runtime-config.js"></script>',poly)
html=html.replace('<script src="app.js"></script>',f'<script>{js}</script>')
checks=[]
def ok(name, cond):
    checks.append((name,bool(cond)))
    if not cond: raise AssertionError(name)
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    page=browser.new_page(viewport={'width':390,'height':844})
    errors=[]; page.on('pageerror',lambda e: errors.append(str(e)))
    page.set_content(html); page.wait_for_timeout(150)
    ok('Landing auth tampil',page.locator('#authView').is_visible())
    page.click('#backToDemo');page.wait_for_timeout(120)
    ok('Demo one-click masuk',page.locator('#appShell').is_visible())
    ok('Logout tersembunyi di demo','hidden' in (page.locator('#logoutBtn').get_attribute('class') or ''))
    # Multi item create
    before_sales=page.evaluate('state.sales.length')
    page.click('#quickSaleBtn');ok('Kasir modal tampil',page.locator('#saleForm').is_visible())
    ok('Cart awal 1 baris',page.locator('.sale-cart-row').count()==1)
    page.click('#addCartItemBtn');rows=page.locator('.sale-cart-row');ok('Tambah barang menjadi 2 baris',rows.count()==2)
    rows.nth(1).locator('.cart-product').select_option('p2');rows.nth(1).locator('.cart-qty').fill('2');page.locator('input[name="customer"]').fill('Tester Multi')
    ok('Preview total multi-item benar','295.000' in page.locator('#salePreview').inner_text())
    page.locator('#saleForm button[type="submit"]').click();page.wait_for_timeout(300)
    st=page.evaluate('({sale:state.sales.find(s=>s.customer==="Tester Multi"),items:state.saleItems.filter(i=>i.sale_id===state.sales.find(s=>s.customer==="Tester Multi")?.id),p1:state.products.find(p=>p.id==="p1").stock,p2:state.products.find(p=>p.id==="p2").stock})')
    ok('Satu invoice tercipta',page.evaluate('state.sales.length')==before_sales+1)
    ok('Invoice punya 2 item',len(st['items'])==2)
    ok('Total invoice Rp295.000',st['sale']['total']==295000)
    ok('Stok dua produk berkurang',st['p1']==27 and st['p2']==12)
    ok('Ringkasan tabel multi-item','+1 item' in page.locator('table tbody tr',has_text='Tester Multi').first.inner_text())
    # Edit multi item
    page.locator('table tbody tr',has_text='Tester Multi').first.locator('button[data-action="edit-sale"]').click();page.wait_for_timeout(60)
    ok('Edit memuat 2 item',page.locator('.sale-cart-row').count()==2)
    page.locator('.sale-cart-row').nth(0).locator('.cart-qty').fill('2');page.locator('#saleForm button[type="submit"]').click();page.wait_for_timeout(250)
    st2=page.evaluate('({sale:state.sales.find(s=>s.customer==="Tester Multi"),p1:state.products.find(p=>p.id==="p1").stock,p2:state.products.find(p=>p.id==="p2").stock,items:state.saleItems.filter(i=>i.sale_id===state.sales.find(s=>s.customer==="Tester Multi")?.id)})')
    ok('Edit total menjadi Rp370.000',st2['sale']['total']==370000)
    ok('Edit stok konsisten',st2['p1']==26 and st2['p2']==12)
    # Documents
    inv=page.evaluate('buildSaleDocumentHtml(state.sales.find(s=>s.customer==="Tester Multi"),"invoice")')
    sj=page.evaluate('buildSaleDocumentHtml(state.sales.find(s=>s.customer==="Tester Multi"),"delivery")')
    ok('Invoice cetak memuat semua barang','Produk A' in inv and 'Produk B' in inv)
    ok('Surat jalan memuat semua barang','Produk A' in sj and 'Produk B' in sj)
    ok('Surat jalan tanpa harga','Harga</th>' not in sj and 'Rp\u00a0' not in sj)
    # Duplicate protection UI
    page.evaluate('closeModal();navigate("sales")');page.click('#quickSaleBtn');page.click('#addCartItemBtn');r=page.locator('.sale-cart-row');r.nth(1).locator('.cart-product').select_option('p1');count0=page.evaluate('state.sales.length');page.locator('#saleForm button[type="submit"]').click();page.wait_for_timeout(80)
    ok('Produk duplikat ditolak',page.evaluate('state.sales.length')==count0 and 'cukup satu baris' in page.locator('#toast').inner_text())
    page.evaluate('closeModal()')
    # Stock protection UI
    page.click('#quickSaleBtn');page.locator('.sale-cart-row').nth(0).locator('.cart-product').select_option('p3');page.locator('.sale-cart-row').nth(0).locator('.cart-qty').fill('999');count0=page.evaluate('state.sales.length');page.locator('#saleForm button[type="submit"]').click();page.wait_for_timeout(80)
    ok('Stok tidak cukup ditolak',page.evaluate('state.sales.length')==count0 and 'tidak cukup' in page.locator('#toast').inner_text())
    page.evaluate('closeModal()')
    # Mobile fit
    page.click('#quickSaleBtn');page.click('#addCartItemBtn');overflow=page.evaluate('document.querySelector("#modalCard").scrollWidth <= document.querySelector("#modalCard").clientWidth + 2')
    ok('Cart mobile tidak overflow horizontal',overflow)
    page.evaluate('closeModal();navigate("settings")');page.wait_for_timeout(30)
    ok('Logout tidak ada di Pengaturan','Keluar dari Akun' not in page.locator('#pageContent').inner_text())
    # Simulate cloud UI only
    page.evaluate("hideAuth();state.mode='cloud';state.currentRole='owner';state.session={user:{id:'u1',email:'owner@test.id'}};render()")
    ok('Logout tampil di topbar saat cloud',page.locator('#logoutBtn').is_visible())
    ok('Tidak ada page error',not errors)
    browser.close()

sql=(root/'migration-v1.8.6-multi-item-cashier.sql').read_text()
static=[
 ('SQL membuat sale_items','create table if not exists public.sale_items' in sql),
 ('SQL backfill transaksi lama','insert into public.sale_items' in sql and 'where not exists' in sql),
 ('Legacy stock trigger dimatikan','drop trigger if exists trg_apply_sale_stock on public.sales' in sql),
 ('Stock pindah ke sale_items','trg_apply_sale_item_stock_v186' in sql),
 ('Create RPC multi-item','create function public.create_sale_with_items' in sql),
 ('Update RPC multi-item','create function public.update_sale_with_items' in sql),
 ('RPC list item role-filtered','list_sale_items_for_business' in sql),
 ('Harga HPP item dimask untuk role','case when v_role in (\'owner\',\'admin\',\'finance\') then si.unit_cost else null end' in sql),
 ('Produk historis dilindungi sale_items','exists(select 1 from public.sale_items si' in sql),
 ('Audit item aktif','trg_audit_sale_item_v186' in sql),
 ('Transaction migration punya begin/commit',sql.count('begin;')>=1 and sql.rstrip().endswith('commit;')),
]
checks.extend(static)
passed=sum(v for _,v in checks)
report=['BizControl Online V1.8.6 — QA Report','',f'Result: {passed}/{len(checks)} PASS','']
report += [f"{'PASS' if v else 'FAIL'} — {n}" for n,v in checks]
(root/'QA_V1_8_6.txt').write_text('\n'.join(report)+'\n')
print('\n'.join(report))
