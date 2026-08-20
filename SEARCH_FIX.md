# Shopora Search Fix

- Search runs while the customer types, with a short 300ms debounce.
- Typing `m` searches products containing `m` and stores containing `m`.
- Typing `mo` immediately narrows the results to matches containing `mo`.
- Typing `mou` narrows again, and so on.
- The Search button and Enter key perform the same search explicitly.
- Store matches are shown above product results and can be opened directly.
- Product search remains powered by the existing `get_shopora_catalog` RPC, preserving server-side filtering and RLS.
- Empty search restores the normal popular-products view.
