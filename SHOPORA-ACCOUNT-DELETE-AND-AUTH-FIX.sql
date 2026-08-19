-- Shopora account deletion + email/account cleanup fix
-- Run THIS FILE ONCE in Supabase SQL Editor.
-- It is intentionally idempotent: existing customer FK/function names are handled safely.

begin;

-- Orders must survive customer-account deletion, while retaining their delivery/order history.
alter table public.orders alter column customer_id drop not null;

do $$
declare
  r record;
begin
  for r in
    select
      c.conname
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname='orders'
      and c.contype='f'
      and pg_get_constraintdef(c.oid) ilike '%(customer_id)%'
      and pg_get_constraintdef(c.oid) ilike '%auth.users%';
  loop
    execute format('alter table public.orders drop constraint if exists %I', r.conname);
  end loop;
end $$;

alter table public.orders
  add constraint orders_customer_id_fkey
  foreign key(customer_id) references auth.users(id) on delete set null;

drop function if exists public.delete_my_shopora_account();

create or replace function public.delete_my_shopora_account()
returns void
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'You must be signed in to delete your account';
  end if;

  -- Preserve seller order history. A seller with completed/order history
  -- must close/settle that store before deleting the account.
  if exists(select 1 from public.seller_orders where seller_id=uid) then
    raise exception 'This account has seller order history. Close the seller account and settle its orders before deleting the account.';
  end if;

  -- Preserve customer order history without retaining the user's identity.
  update public.orders
  set customer_id=null, updated_at=now()
  where customer_id=uid;

  -- profiles, addresses, wishlists, notifications, reviews and other
  -- user-owned rows with ON DELETE CASCADE are removed with auth.users.
  delete from auth.users where id=uid;

  if not found then
    raise exception 'Account not found';
  end if;
end;
$$;

revoke all on function public.delete_my_shopora_account() from public;
grant execute on function public.delete_my_shopora_account() to authenticated;

commit;
