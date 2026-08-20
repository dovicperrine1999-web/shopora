# Shopora — final production package

Production URL: https://shopora-mauve-two.vercel.app/

## Password reset

The application now uses a dedicated production reset route:

`https://shopora-mauve-two.vercel.app/reset-password`

The reset URL is explicitly configured in `config.js` and is not derived from localhost.

You must also configure the same URL under Supabase Authentication → URL Configuration and make sure the Supabase Reset Password email template uses `{{ .ConfirmationURL }}`.

## Local development

If you run the project locally, add your local URL as an additional Supabase Redirect URL. Do not replace the production Site URL with localhost.

## Security

No default super-admin password is included. Administrative access must use Supabase Auth and the database role checks supplied with the project.


## Password reset production hardening

The application sends `https://shopora-mauve-two.vercel.app/reset-password` as the Supabase recovery `redirectTo` URL. The reset page validates the Supabase recovery session before allowing a password change.

Ready-to-paste Supabase email templates are included in `supabase/email-templates/`. They use `{{ .ConfirmationURL }}` so the generated link carries the application's requested production redirect instead of a hard-coded localhost address.

For a hosted Supabase project, the project's Auth URL Configuration and Email Templates live in the Supabase dashboard and cannot be changed by a Vercel upload alone.
