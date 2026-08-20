# Shopora — Final Vercel package

This package is the complete static Shopora frontend plus the Supabase SQL migrations used by the final UI.

## 1. Upload to GitHub / Vercel

Upload the contents of this folder to your repository. Vercel can deploy it as a static site; no Node server is required.

`index.html` is the application entry point.

## 2. Supabase SQL

Run these in order in Supabase SQL Editor:

1. `SHOPORA.sql`
2. `sql/01_super_admin.sql`
3. `sql/02_social_reviews_messages.sql`

Do not run the same migration repeatedly if your database already has the objects. The migration uses `create ... if not exists`, `create or replace`, and explicit grants where appropriate.

## 3. Password reset

The frontend now sends reset links to:

`https://shopora-mauve-two.vercel.app/#reset-password`

The recovery token remains in the Supabase recovery URL. The page validates the active recovery session and then lets the user set a new password.

In Supabase Authentication → URL Configuration:

- Site URL: `https://shopora-mauve-two.vercel.app/`
- Redirect URL: `https://shopora-mauve-two.vercel.app/**`

Request a new reset email after changing the URL configuration.

## 4. Security

Never put a Supabase `service_role` key in this project. The browser only uses the publishable/anon key. Sensitive operations are implemented as authenticated database functions.

The super-admin email configured by the existing project is `ludovicperrine@icloud.com`. There is intentionally **no hard-coded default password**. The account uses Supabase Auth and its normal password-reset flow.

## 5. Final UI changes

- Seller store cover is wider and consistently framed.
- Seller Centre has consistent rounded cards and a redesigned header.
- Products use Category → Product selection → Edit flow.
- Payment methods use professional MCB/MauBank-style bank marks and structured account cards.
- Orders show customer/WhatsApp, payment method, payment status, delivery status, tracking and address.
- WhatsApp buttons have no unwanted underline.
- Buyer/seller messaging supports delete-for-me only.
- Complaints are available after delivery/completion.
- Reviews are gated to completed/received seller orders.
- Reports default to the latest transaction day and support date/status/payment/search filters.
- Excel export is real `.xlsx`, with `Total(MUR)` as a numeric column and a filtered Pending Delivery sheet.
