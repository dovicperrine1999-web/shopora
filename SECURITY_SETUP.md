# Shopora Security Hardening

This build is hardened so the browser never receives or stores user passwords. Authentication is handled by Supabase Auth.

## What was hardened

- No Supabase `service_role`/secret key is present in the frontend.
- Public product/store RPCs no longer return the seller's private `payment_methods` JSON.
- Public Data API function execution is closed by default; only required RPCs are granted.
- Customer and seller RPCs remain protected by `auth.uid()` ownership checks.
- RLS remains enabled on user/order/notification tables.
- New account UI requires a 12-character password containing uppercase, lowercase, number and symbol.
- The Vercel authentication redirect remains `https://shopora-mauve-two.vercel.app/`.

## Supabase Auth settings you MUST enable

The SQL/frontend cannot configure every Auth security control. In Supabase Dashboard:

1. Authentication → Providers → Email
   - Keep **Confirm email** enabled.
2. Authentication → Password Security
   - Set minimum password length to **12**.
   - Require uppercase, lowercase, number and symbol.
   - Enable **Leaked password protection** if available on your plan.
3. Authentication → Bot and Abuse Protection
   - Enable CAPTCHA (Cloudflare Turnstile or hCaptcha).
4. Authentication → Rate Limits
   - Keep the authentication rate limits enabled.
5. Authentication → Multi-Factor Authentication
   - For the strongest protection, enable/require MFA for accounts that need it.
6. Authentication → URL Configuration
   - Site URL: `https://shopora-mauve-two.vercel.app/`
   - Add that exact URL to the allowed redirect URLs.
7. Authentication → Emails → SMTP
   - Use a proper production SMTP provider rather than relying on the default test mail service.

## Important

A publishable/anon key is allowed in a browser application. A `service_role` or `sb_secret_...` key must NEVER be placed in `index.html`, `config.js`, Vercel client-side environment variables, or any other browser-delivered file.

No security system can honestly guarantee that an application is impossible to hack. The goal is defense in depth: Supabase Auth for password storage, RLS for row authorization, restricted RPC execution, secure storage policies, strong password rules, CAPTCHA/rate limits, and MFA.
