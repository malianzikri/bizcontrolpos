
// Optional configuration for demo-sales-layer.js.
// Load this BEFORE demo-sales-layer.js.
//
// CTA does NOT fire InitiateCheckout because it sends the visitor back to
// the BizControl sales landing page. InitiateCheckout remains correctly
// fired only when the buyer clicks the actual checkout button there.
window.BIZCONTROL_DEMO_SALES = {
  landingUrl: 'https://bizcontrol-landing.vercel.app/?utm_source=pos_demo&utm_medium=product&utm_campaign=demo_to_sales#harga',
  monthlyLabel: 'Rp79.000/bulan',
  pixelId: '1081611444299321'
};
