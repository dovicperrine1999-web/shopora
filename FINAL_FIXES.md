# Shopora Final Product Fix

This build fixes the product/category and image-layout issues shown in the latest screenshots.

## Fixed
- The category chosen on the previous step is preserved as its UUID.
- The product editor no longer shows a second category dropdown after a category has been selected.
- Prevents the `invalid input syntax for type uuid: "Electronics"` error by sending the category UUID to the database.
- Product editor now has a clearly visible, sticky Save product / Cancel action bar.
- Product image previews are constrained and cannot stretch the form.
- Product detail gallery is responsive and prevents large images from forcing the modal wider/taller than the viewport.
- Seller Centre navigation remains stable while the content area scrolls.
- The Seller Centre content does not create unwanted horizontal scrolling.

## Upload
Upload the contents of this ZIP as the complete project. Do not mix old `index.html` files with this version.

## V9 Account/Profile UI Fix
- Account panel is centered and wider on desktop while remaining responsive on mobile.
- Profile picture is shown once, larger, centered, with a pencil edit control visible only on hover/focus.
- Profile picture upload is triggered from the hover pencil and is saved immediately; the duplicate avatar/file-preview block was removed.
- Full name is displayed under the profile picture with a small pencil. Name editing is separate from phone editing.
- Phone number editing requires Supabase phone-change OTP verification before the profile phone number is written.
- Phone verification status is displayed as Verified / Not verified.
- Phone numbers are never silently changed in the profile database before successful verification.

### Supabase requirement for phone editing
Enable Phone authentication and configure an SMS provider in Supabase Auth. Without an SMS provider, the secure phone-change flow will show the provider/configuration error rather than saving an unverified number.

- Header controls are click-only: Account, Notifications, and Cart never open on hover. Their dialogs open smoothly centered. Notifications include Mark all read and Clear notifications.


## V13 notification/account interaction fix
- Notification Clear now deletes only the signed-in user's rows through RLS instead of depending only on a cached RPC schema.
- `sql/03_notifications_clear.sql` adds the required `notifications_delete` policy.
- Account, notification, and cart hover previews now have a no-gap hover bridge, so they remain open while the cursor moves from the header control into the preview.
- Clicking a preview header opens its full centered panel.
- Account modal title is centered; profile name and phone number remain centered independently of their edit pencils.
