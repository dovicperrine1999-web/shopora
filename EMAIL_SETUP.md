# Shopora email reset URL

The production site is:

https://shopora-mauve-two.vercel.app/

## Supabase settings

In Supabase Dashboard:

1. Go to **Authentication → URL Configuration**.
2. Set **Site URL** to:
   `https://shopora-mauve-two.vercel.app/`
3. Add this to **Redirect URLs**:
   `https://shopora-mauve-two.vercel.app/**`
4. Save.

The reset email must redirect to the production Vercel URL, not `localhost:3000`.

If your email template contains a hard-coded localhost URL, remove it and use Supabase's recovery redirect URL instead.

## Important

Vercel hosting does not make `localhost:3000` available to a phone. `localhost` means the device itself. Your phone therefore tries to open a server that is not running on the phone.

After changing Supabase URL Configuration, request a **new** password-reset email. Do not reuse an old reset email.
