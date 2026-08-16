# BizControl Online V1.8.1 — Browser Regression QA

**Result: 24/24 PASS**

Chromium regression harness validated:
- app boot and V1.8.1 label;
- local app rendering;
- Forgot Password UI state;
- recovery request to `/auth/v1/recover`;
- generic recovery response;
- password update through `/auth/v1/user`;
- recovery-session logout and return to login;
- Kasir mobile layout at 390×844 with no horizontal overflow;
- responsive table/card and touch-friendly actions;
- stored-XSS regression for business name;
- recovery functions available;
- no uncaught runtime exceptions in the tested flow.

Note: the harness injected the application into an `about:blank` Chromium page because the managed browser environment blocks local HTTP/file navigation. Network/Auth calls were mocked for deterministic frontend regression testing. This is a frontend test, not a substitute for real Supabase staging validation.
