
// Optional configuration for demo-sales-layer.js.
// Load this BEFORE demo-sales-layer.js.
//
// CTA does NOT fire InitiateCheckout because it sends the visitor back to
// the BizControl sales landing page. InitiateCheckout remains correctly
// fired only when the buyer clicks the actual checkout button there.
window.BIZCONTROL_DEMO_SALES = {
  landingUrl: 'https://wa.me/628117199210?text=Halo%20Admin%20BizControl%2C%20saya%20tertarik%20paket%20Rp79rb%2Fbulan.%20Bisa%20dibantu%20info%20aktivasi%3F',
  monthlyLabel: 'Rp79.000/bulan',
  pixelId: '1081611444299321'
};
