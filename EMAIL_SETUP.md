# Shopora production email / password-reset setup

Production website:

`https://shopora-mauve-two.vercel.app/`

## 1. Supabase Authentication → URL Configuration

Set **Site URL** exactly to:

`https://shopora-mauve-two.vercel.app/`

Add this exact redirect URL:

`https://shopora-mauve-two.vercel.app/reset-password`

You may also keep the development URL separately if you still develop locally:

`http://localhost:3000/**`

Do **not** use localhost as the production Site URL.

## 2. Supabase Authentication → Email Templates

For **Reset Password**, use the Supabase-provided confirmation URL rather than a hard-coded localhost address:

```html
<h2>Reset your Shopora password</h2>
<p>We received a request to reset your Shopora password.</p>
<p><a href="{{ .ConfirmationURL }}">Reset my password</a></p>
<p>If you did not request this, you can safely ignore this email.</p>
```

For **Confirm signup**, use:

```html
<h2>Confirm your Shopora account</h2>
<p>Click the button below to confirm your email address.</p>
<p><a href="{{ .ConfirmationURL }}">Confirm my email</a></p>
```

Do not put `http://localhost:3000` directly into either template.

## 3. Why the old email went to localhost

The application code now explicitly sends password-reset requests to:

`https://shopora-mauve-two.vercel.app/reset-password`

If the email still contains `localhost:3000`, that value is coming from the **Supabase Auth URL/template configuration**, not from Vercel hosting. Supabase documents that the Site URL is the default redirect and that `redirectTo` must be on the allowed Redirect URLs list.

## 4. Important testing rule

After changing the Supabase settings, request a **new** reset email. Old reset emails can still contain the old redirect URL.

## 5. Production behavior

The reset flow is now:

1. User taps **Forgot password**.
2. Shopora requests a reset email with the production redirect URL.
3. User taps the email link.
4. Vercel serves `/reset-password` through the application.
5. Shopora validates the recovery session.
6. User chooses a new password.
7. Password is changed through Supabase Auth.
8. User is returned to the Shopora production site.
