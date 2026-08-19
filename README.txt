SHOPORA V60 — STRUCTURAL FRONTEND FIX

This version moves the entire application JavaScript out of index.html into app.js.
This specifically prevents JavaScript/template source from ever being interpreted as visible HTML.

Install:
1. Replace index.html, config.js, and add app.js from this package.
2. Keep your existing Supabase database; do NOT rerun SHOPORA.sql for this frontend issue.
3. Restart the local web server.
4. Hard refresh with Ctrl+F5.

The script is loaded as app.js?v=60 to bypass the old browser cache.


V61 PRODUCT SAVE FIX
The current product-save error `new row for relation products violates check constraint products_status_check` is caused by a legacy status check in the database. V61 includes an idempotent migration that normalizes invalid product statuses, removes the legacy products_status_check, and recreates it with the statuses used by the application.

After installing the frontend, run the updated SHOPORA.sql in Supabase. If your database already contains the rest of the Shopora schema, this V61 status block is the specific database fix required for the screenshot error.
