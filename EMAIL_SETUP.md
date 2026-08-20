# Email delivery setup

The Supabase email warning shown in the screenshots says the project has a high bounce rate and email sending privileges are at risk. The frontend cannot remove that restriction.

1. In Supabase, open Authentication settings.
2. Configure a custom SMTP/email provider approved for your project.
3. Set the Site URL to `https://shopora-mauve-two.vercel.app/`.
4. Add `https://shopora-mauve-two.vercel.app/` to the allowed redirect URLs.
5. Verify the sender/domain with the email provider.
6. Test with a real, valid mailbox; do not repeatedly test with fake/nonexistent addresses.

The application already sends the Vercel URL as `emailRedirectTo`.
