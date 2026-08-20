
-- ---------------------------------------------------------------------------
-- V42 PRODUCT PRICE COMPATIBILITY
-- Older Shopora databases used products.price_mur while the current API uses
-- products.price. Rename the legacy column when necessary so saving a product
-- cannot fail with "column price_mur ... not-null constraint".
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='products' and column_name='price_mur'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='products' and column_name='price'
  ) then
    execute 'alter table public.products rename column price_mur to price';
  end if;
end $$;


do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema='public' and table_name='products'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='products' and column_name='updated_at'
  ) then
    alter table public.products add column updated_at timestamptz not null default now();
  end if;
end $$;


-- SHOPORA V40 — CLEAN ECOMMERCE DATABASE
-- Run this as a fresh migration in a test project first.
-- Designed for Supabase Auth + Postgres + Storage + RLS.

create extension if not exists pgcrypto;
-- Shopora V57.3 compatibility cleanup: remove legacy RPC signatures before recreation.
-- These RPCs are called only by the application; they are not trigger/policy helper functions.
drop function if exists public.create_shopora_order_v52(jsonb,jsonb,jsonb,text,text,text);
drop function if exists public.customer_confirm_shopora_received(uuid);
drop function if exists public.delete_shopora_address(uuid);
drop function if exists public.delete_shopora_product(uuid);
drop function if exists public.get_shopora_catalog(text,uuid,uuid,text,numeric,numeric,integer,integer);
drop function if exists public.get_shopora_checkout_payment_options(jsonb);
drop function if exists public.get_shopora_customer_orders(text);
drop function if exists public.get_shopora_notifications();
drop function if exists public.get_shopora_product(uuid);
drop function if exists public.get_shopora_seller_orders(text,text);
drop function if exists public.get_shopora_seller_products();
drop function if exists public.get_shopora_shop(uuid);
drop function if exists public.mark_all_shopora_notifications_read();
drop function if exists public.mark_shopora_notification_read(uuid);
drop function if exists public.save_shopora_address(uuid,text,text,text,text,text,text,text,boolean);
drop function if exists public.save_shopora_payment_methods(jsonb);
drop function if exists public.save_shopora_product_v46(uuid,text,uuid,numeric,numeric,integer,text,text,text,jsonb);
drop function if exists public.save_shopora_shop(text,text,text,text,text,text,numeric,numeric);
drop function if exists public.seller_confirm_shopora_payment(uuid);
drop function if exists public.seller_set_shopora_order_status(uuid,text,text,text,text);
drop function if exists public.toggle_shopora_wishlist(uuid);

-- ---------- cleanup of previous Shopora routines ----------
do $$
declare r record;
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) args
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like '%shopora%'
  loop
    execute format('drop function if exists public.%I(%s) cascade', r.proname, r.args);
  end loop;
end $$;

-- ---------- base tables ----------
create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '',
 phone text not null default '',
 avatar_url text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.categories(
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 slug text not null unique,
 image_url text,
 active boolean not null default true,
 sort_order int not null default 0
);

create table if not exists public.shops(
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null unique references auth.users(id) on delete cascade,
 name text not null,
 slug text not null unique,
 description text not null default '',
 address text not null default '',
 logo_url text,
 cover_url text,
 phone text not null default '',
 payment_methods jsonb not null default '[]'::jsonb,
 shipping_fee numeric(12,2) not null default 0,
 free_shipping_from numeric(12,2),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.products(
 id uuid primary key default gen_random_uuid(),
 shop_id uuid not null references public.shops(id) on delete cascade,
 category_id uuid references public.categories(id) on delete set null,
 name text not null,
 slug text not null,
 description text not null default '',
 price numeric(12,2) not null check(price>=0),
 compare_price numeric(12,2),
 stock int not null default 0 check(stock>=0),
 status text not null default 'active' check(status in('draft','active','out_of_stock','archived')),
 brand text,
 sku text,
 weight_grams int,
 rating numeric(3,2) not null default 0,
 review_count int not null default 0,
 sales_count int not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(shop_id,slug)
);

create table if not exists public.product_images(
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id) on delete cascade,
 image_url text not null,
 sort_order int not null default 0
);

create table if not exists public.addresses(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 label text not null default 'Home',
 recipient_name text not null,
 phone text not null,
 line1 text not null,
 line2 text not null default '',
 city text not null,
 postal_code text not null default '',
 country text not null default 'Mauritius',
 is_default boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.wishlists(
 user_id uuid not null references auth.users(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(user_id,product_id)
);

create table if not exists public.coupons(
 id uuid primary key default gen_random_uuid(),
 shop_id uuid references public.shops(id) on delete cascade,
 code text not null unique,
 discount_type text not null check(discount_type in('percent','fixed')),
 discount_value numeric(12,2) not null check(discount_value>0),
 min_spend numeric(12,2) not null default 0,
 max_uses int,
 used_count int not null default 0,
 starts_at timestamptz not null default now(),
 ends_at timestamptz,
 active boolean not null default true
);

create table if not exists public.orders(
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id) on delete restrict,
 order_number text not null unique,
 subtotal numeric(12,2) not null default 0,
 shipping_total numeric(12,2) not null default 0,
 discount_total numeric(12,2) not null default 0,
 total numeric(12,2) not null default 0,
 status text not null default 'payment_pending'
   check(status in('payment_pending','processing','packed','shipped','delivered','completed','cancelled','refunded','return_requested','returned')),
 payment_status text not null default 'pending'
   check(payment_status in('pending','paid','failed','refunded')),
 payment_method text,
 payment_reference text,
 payment_proof_url text,
 delivery_snapshot jsonb not null default '{}'::jsonb,
 notes text not null default '',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.order_items(
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete restrict,
 shop_id uuid not null references public.shops(id) on delete restrict,
 product_name text not null,
 image_url text,
 unit_price numeric(12,2) not null,
 quantity int not null check(quantity>0),
 line_total numeric(12,2) not null,
 created_at timestamptz not null default now()
);

create table if not exists public.seller_orders(
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 shop_id uuid not null references public.shops(id) on delete cascade,
 seller_id uuid not null references auth.users(id) on delete cascade,
 subtotal numeric(12,2) not null default 0,
 shipping numeric(12,2) not null default 0,
 total numeric(12,2) not null default 0,
 status text not null default 'payment_pending'
   check(status in('payment_pending','processing','packed','shipped','delivered','completed','cancelled','refunded','return_requested','returned')),
 payment_status text not null default 'pending'
   check(payment_status in('pending','paid','failed','refunded')),
 payment_method_snapshot text,
 payment_details_snapshot text,
 tracking_number text,
 carrier text,
 seller_note text not null default '',
 packed_at timestamptz,
 shipped_at timestamptz,
 delivered_at timestamptz,
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(order_id,shop_id)
);

create table if not exists public.notifications(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 order_id uuid references public.orders(id) on delete cascade,
 seller_order_id uuid references public.seller_orders(id) on delete cascade,
 type text not null,
 title text not null,
 message text not null,
 read_at timestamptz,
 created_at timestamptz not null default now()
);

create table if not exists public.reviews(
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id) on delete cascade,
 order_item_id uuid unique references public.order_items(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 rating int not null check(rating between 1 and 5),
 title text not null default '',
 body text not null default '',
 images jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(customer_id,product_id)
);

create table if not exists public.return_requests(
 id uuid primary key default gen_random_uuid(),
 seller_order_id uuid not null references public.seller_orders(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 reason text not null,
 details text not null default '',
 status text not null default 'requested'
   check(status in('requested','approved','rejected','received','refunded')),
 refund_amount numeric(12,2) not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);


-- ============================================================
-- SHOPORA V40 EXISTING-SCHEMA COMPATIBILITY
-- CREATE TABLE IF NOT EXISTS does NOT add columns to an older
-- table. Add every V40-required column before indexes/functions.
-- ============================================================

-- Shops
-- Shops: core columns must also be present on legacy Shopora installs.
alter table public.shops add column if not exists name text default 'My Shop';
alter table public.shops add column if not exists owner_id uuid;
alter table public.shops add column if not exists slug text;
alter table public.shops add column if not exists description text default '';
alter table public.shops add column if not exists address text default '';
alter table public.shops add column if not exists logo_url text;
alter table public.shops add column if not exists cover_url text;
alter table public.shops add column if not exists phone text default '';
alter table public.shops add column if not exists payment_methods jsonb default '[]'::jsonb;
alter table public.shops add column if not exists shipping_fee numeric(12,2) default 0;
alter table public.shops add column if not exists free_shipping_from numeric(12,2);
alter table public.shops add column if not exists active boolean default true;
alter table public.shops add column if not exists created_at timestamptz default now();
alter table public.shops add column if not exists updated_at timestamptz default now();

update public.shops
set slug=trim(both '-' from regexp_replace(lower(coalesce(name,'shop')),'[^a-z0-9]+','-','g')) || '-' || left(md5(id::text),8)
where slug is null or btrim(slug)='';

update public.shops set description='' where description is null;
update public.shops set address='' where address is null;
update public.shops set phone='' where phone is null;
update public.shops set payment_methods='[]'::jsonb where payment_methods is null;
update public.shops set shipping_fee=0 where shipping_fee is null;
update public.shops set active=true where active is null;
update public.shops set created_at=now() where created_at is null;
update public.shops set updated_at=now() where updated_at is null;

-- Categories
alter table public.categories add column if not exists name text default 'Category';
alter table public.categories add column if not exists slug text;
alter table public.categories add column if not exists image_url text;
alter table public.categories add column if not exists active boolean default true;
alter table public.categories add column if not exists sort_order int default 0;

update public.categories
set slug=trim(both '-' from regexp_replace(lower(coalesce(name,'category')),'[^a-z0-9]+','-','g')) || '-' || left(md5(id::text),8)
where slug is null or btrim(slug)='';

update public.categories set active=true where active is null;
update public.categories set sort_order=0 where sort_order is null;

-- Legacy core fields required by V40 functions/indexes.
alter table public.products add column if not exists name text default 'Product';
alter table public.products add column if not exists price numeric(12,2) default 0;
alter table public.products add column if not exists shop_id uuid;

-- Products
alter table public.products add column if not exists category_id uuid;
alter table public.products add column if not exists slug text;
alter table public.products add column if not exists description text default '';
alter table public.products add column if not exists compare_price numeric(12,2);
alter table public.products add column if not exists stock int default 0;
alter table public.products add column if not exists status text default 'active';
alter table public.products add column if not exists brand text default '';
alter table public.products add column if not exists sku text;
alter table public.products add column if not exists weight_grams int;
alter table public.products add column if not exists rating numeric(3,2) default 0;
alter table public.products add column if not exists review_count int default 0;
alter table public.products add column if not exists sales_count int default 0;
alter table public.products add column if not exists created_at timestamptz default now();
alter table public.products add column if not exists updated_at timestamptz default now();

update public.products
set slug=trim(both '-' from regexp_replace(lower(coalesce(name,'product')),'[^a-z0-9]+','-','g')) || '-' || left(md5(id::text),8)
where slug is null or btrim(slug)='';

update public.products set description='' where description is null;
update public.products set stock=0 where stock is null;
update public.products set status=case when coalesce(stock,0)>0 then 'active' else 'out_of_stock' end where status is null or status='';
update public.products set brand='' where brand is null;
update public.products set rating=0 where rating is null;
update public.products set review_count=0 where review_count is null;
update public.products set sales_count=0 where sales_count is null;
update public.products set created_at=now() where created_at is null;
update public.products set updated_at=now() where updated_at is null;

-- Profiles
alter table public.profiles add column if not exists full_name text default '';
alter table public.profiles add column if not exists phone text default '';
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists created_at timestamptz default now();
alter table public.profiles add column if not exists updated_at timestamptz default now();

-- Addresses
alter table public.addresses add column if not exists label text default 'Home';
alter table public.addresses add column if not exists recipient_name text default '';
alter table public.addresses add column if not exists phone text default '';
alter table public.addresses add column if not exists line1 text default '';
alter table public.addresses add column if not exists line2 text default '';
alter table public.addresses add column if not exists city text default '';
alter table public.addresses add column if not exists postal_code text default '';
alter table public.addresses add column if not exists country text default 'Mauritius';
alter table public.addresses add column if not exists is_default boolean default false;
alter table public.addresses add column if not exists created_at timestamptz default now();
alter table public.addresses add column if not exists updated_at timestamptz default now();

-- Orders
alter table public.orders add column if not exists customer_id uuid;
alter table public.orders add column if not exists order_number text;
alter table public.orders add column if not exists subtotal numeric(12,2) default 0;
alter table public.orders add column if not exists shipping_total numeric(12,2) default 0;
alter table public.orders add column if not exists discount_total numeric(12,2) default 0;
alter table public.orders add column if not exists total numeric(12,2) default 0;
alter table public.orders add column if not exists status text default 'payment_pending';
alter table public.orders add column if not exists payment_status text default 'pending';
alter table public.orders add column if not exists payment_method text;
alter table public.orders add column if not exists payment_reference text;
alter table public.orders add column if not exists payment_proof_url text;
alter table public.orders add column if not exists delivery_snapshot jsonb default '{}'::jsonb;
alter table public.orders add column if not exists notes text default '';
alter table public.orders add column if not exists created_at timestamptz default now();
alter table public.orders add column if not exists updated_at timestamptz default now();


update public.orders
set order_number='SHP-'||to_char(coalesce(created_at,now()),'YYYYMMDDHH24MISS')||'-'||upper(substr(md5(id::text),1,6))
where order_number is null or btrim(order_number)='';

-- Order items
alter table public.order_items add column if not exists shop_id uuid;
alter table public.order_items add column if not exists product_name text default '';
alter table public.order_items add column if not exists image_url text;
alter table public.order_items add column if not exists unit_price numeric(12,2) default 0;
alter table public.order_items add column if not exists quantity int default 1;
alter table public.order_items add column if not exists line_total numeric(12,2) default 0;
alter table public.order_items add column if not exists created_at timestamptz default now();

-- Product images
alter table public.product_images add column if not exists image_url text;
alter table public.product_images add column if not exists sort_order int default 0;

-- Reviews
alter table public.reviews add column if not exists order_item_id uuid;
alter table public.reviews add column if not exists rating int default 5;
alter table public.reviews add column if not exists title text default '';
alter table public.reviews add column if not exists body text default '';
alter table public.reviews add column if not exists images jsonb default '[]'::jsonb;
alter table public.reviews add column if not exists created_at timestamptz default now();
alter table public.reviews add column if not exists updated_at timestamptz default now();

-- Notifications
alter table public.notifications add column if not exists order_id uuid;
alter table public.notifications add column if not exists seller_order_id uuid;
alter table public.notifications add column if not exists type text default 'system';
alter table public.notifications add column if not exists title text default '';
alter table public.notifications add column if not exists message text default '';
alter table public.notifications add column if not exists read_at timestamptz;
alter table public.notifications add column if not exists created_at timestamptz default now();

-- Seller packages
alter table public.seller_orders add column if not exists seller_id uuid;
alter table public.seller_orders add column if not exists subtotal numeric(12,2) default 0;
alter table public.seller_orders add column if not exists shipping numeric(12,2) default 0;
alter table public.seller_orders add column if not exists total numeric(12,2) default 0;
alter table public.seller_orders add column if not exists status text default 'payment_pending';
alter table public.seller_orders add column if not exists payment_status text default 'pending';
alter table public.seller_orders add column if not exists payment_method_snapshot text;
alter table public.seller_orders add column if not exists payment_details_snapshot text;
alter table public.seller_orders add column if not exists tracking_number text;
alter table public.seller_orders add column if not exists carrier text;
alter table public.seller_orders add column if not exists seller_note text;
alter table public.seller_orders add column if not exists packed_at timestamptz;
alter table public.seller_orders add column if not exists shipped_at timestamptz;
alter table public.seller_orders add column if not exists delivered_at timestamptz;
alter table public.seller_orders add column if not exists completed_at timestamptz;
alter table public.seller_orders add column if not exists created_at timestamptz default now();
alter table public.seller_orders add column if not exists updated_at timestamptz default now();

-- Coupons
alter table public.coupons add column if not exists discount_type text default 'fixed';
alter table public.coupons add column if not exists discount_value numeric(12,2) default 0;
alter table public.coupons add column if not exists min_spend numeric(12,2) default 0;
alter table public.coupons add column if not exists max_uses int;
alter table public.coupons add column if not exists used_count int default 0;
alter table public.coupons add column if not exists starts_at timestamptz;
alter table public.coupons add column if not exists ends_at timestamptz;
alter table public.coupons add column if not exists active boolean default true;

-- ---------- indexes ----------
create index if not exists products_shop_idx on public.products(shop_id);
create index if not exists products_category_idx on public.products(category_id);
create index if not exists products_status_idx on public.products(status);
create index if not exists products_search_idx
on public.products using gin(
  to_tsvector(
    'simple',
    coalesce(name,'') || ' ' || coalesce(description,'')
  )
);
create index if not exists order_customer_idx on public.orders(customer_id,created_at desc);
create index if not exists seller_orders_seller_idx on public.seller_orders(seller_id,created_at desc);
create index if not exists notifications_user_idx on public.notifications(user_id,created_at desc);

-- ---------- helpers ----------
create or replace function public.shopora_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end $$;

drop trigger if exists profiles_touch on public.profiles;
drop trigger if exists profiles_touch on public.profiles;
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles for each row execute function public.shopora_touch_updated_at();
drop trigger if exists shops_touch on public.shops;
drop trigger if exists shops_touch on public.shops;
drop trigger if exists shops_touch on public.shops;
create trigger shops_touch before update on public.shops for each row execute function public.shopora_touch_updated_at();
drop trigger if exists products_touch on public.products;
drop trigger if exists products_touch on public.products;
drop trigger if exists products_touch on public.products;
create trigger products_touch before update on public.products for each row execute function public.shopora_touch_updated_at();
drop trigger if exists addresses_touch on public.addresses;
drop trigger if exists addresses_touch on public.addresses;
drop trigger if exists addresses_touch on public.addresses;
create trigger addresses_touch before update on public.addresses for each row execute function public.shopora_touch_updated_at();
drop trigger if exists reviews_touch on public.reviews;
drop trigger if exists reviews_touch on public.reviews;
drop trigger if exists reviews_touch on public.reviews;
create trigger reviews_touch before update on public.reviews for each row execute function public.shopora_touch_updated_at();
drop trigger if exists return_touch on public.return_requests;
drop trigger if exists return_touch on public.return_requests;
drop trigger if exists return_touch on public.return_requests;
create trigger return_touch before update on public.return_requests for each row execute function public.shopora_touch_updated_at();

create or replace function public.shopora_handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.profiles(id,full_name,phone)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),coalesce(new.raw_user_meta_data->>'phone',''))
 on conflict(id) do nothing;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.shopora_handle_new_user();

create or replace function public.shopora_is_shop_owner(p_shop uuid,p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.shops where id=p_shop and owner_id=p_user);
$$;

create or replace function public.shopora_make_slug(t text)
returns text language sql immutable as $$
 select trim(both '-' from regexp_replace(lower(coalesce(t,'')),'[^a-z0-9]+','-','g'));
$$;

-- ---------- public catalog ----------
create or replace function public.get_shopora_catalog(
 p_search text default '',
 p_category uuid default null,
 p_shop uuid default null,
 p_sort text default 'newest',
 p_min numeric default null,
 p_max numeric default null,
 p_limit int default 40,
 p_offset int default 0
)
returns table(
 id uuid,name text,description text,price numeric,compare_price numeric,stock int,
 rating numeric,review_count int,sales_count int,shop_id uuid,shop_name text,
 shop_slug text,category_id uuid,category_name text,image_url text,image_count int
)
language sql stable security definer set search_path=public as $$
 select p.id,p.name,p.description,p.price,p.compare_price,p.stock,p.rating,p.review_count,p.sales_count,
        s.id,s.name,s.slug,c.id,c.name,
        (select pi.image_url from public.product_images pi where pi.product_id=p.id order by pi.sort_order,pi.id limit 1),
        (select count(*)::int from public.product_images pi where pi.product_id=p.id)
 from public.products p join public.shops s on s.id=p.shop_id and s.active
 left join public.categories c on c.id=p.category_id
 where p.status='active' and p.stock>0
   and (p_search='' or to_tsvector('simple',p.name||' '||p.description||' '||coalesce(p.brand,'')) @@ plainto_tsquery('simple',p_search))
   and (p_category is null or p.category_id=p_category)
   and (p_shop is null or p.shop_id=p_shop)
   and (p_min is null or p.price>=p_min) and (p_max is null or p.price<=p_max)
 order by
   case when p_sort='price_asc' then p.price end asc,
   case when p_sort='price_desc' then p.price end desc,
   case when p_sort='popular' then p.sales_count end desc,
   case when p_sort='rating' then p.rating end desc,
   p.created_at desc
 limit greatest(1,least(p_limit,100)) offset greatest(0,p_offset);
$$;

create or replace function public.get_shopora_product(p_product uuid)
returns jsonb language sql stable security invoker as $$
 select jsonb_build_object(
   'product',to_jsonb(p),
   'shop',to_jsonb(s),
   'category',to_jsonb(c),
   'images',coalesce((select jsonb_agg(to_jsonb(pi) order by pi.sort_order,pi.id) from public.product_images pi where pi.product_id=p.id),'[]'::jsonb),
   'reviews',coalesce((
                         select jsonb_agg(x.review_json order by x.created_at desc)
                         from (
                           select jsonb_build_object(
                             'rating',r.rating,
                             'title',r.title,
                             'body',r.body,
                             'created_at',r.created_at,
                             'customer',coalesce(pr.full_name,'Customer')
                           ) as review_json,
                           r.created_at
                           from public.reviews r
                           left join public.profiles pr on pr.id=r.customer_id
                           where r.product_id=p.id
                           order by r.created_at desc
                           limit 50
                         ) x
                       ),'[]'::jsonb)
 )
 from public.products p join public.shops s on s.id=p.shop_id
 left join public.categories c on c.id=p.category_id
 where p.id=p_product and p.status<>'archived';
$$;

create or replace function public.get_shopora_shop(p_shop uuid)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('shop',to_jsonb(s),
   'products',coalesce((select jsonb_agg(x) from public.get_shopora_catalog('',null,s.id,'newest',null,null,100,0) x),'[]'::jsonb))
 from public.shops s where s.id=p_shop and s.active;
$$;

-- ---------- seller product/shop ----------
create or replace function public.save_shopora_shop(
 p_name text,p_description text,p_address text,p_phone text,p_logo text,p_cover text,p_shipping numeric,p_free numeric
) returns public.shops
language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); outrow public.shops;
begin
 if u is null then raise exception 'Login required'; end if;
 insert into public.shops(owner_id,name,slug,description,address,phone,logo_url,cover_url,shipping_fee,free_shipping_from)
 values(u,trim(p_name),public.shopora_make_slug(p_name)||'-'||substr(u::text,1,6),coalesce(p_description,''),coalesce(p_address,''),coalesce(p_phone,''),nullif(p_logo,''),nullif(p_cover,''),greatest(0,coalesce(p_shipping,0)),p_free)
 on conflict(owner_id) do update set name=excluded.name,description=excluded.description,address=excluded.address,phone=excluded.phone,logo_url=coalesce(excluded.logo_url,public.shops.logo_url),cover_url=coalesce(excluded.cover_url,public.shops.cover_url),shipping_fee=excluded.shipping_fee,free_shipping_from=excluded.free_shipping_from
 returning * into outrow;
 return outrow;
end $$;

create or replace function public.save_shopora_payment_methods(p_methods jsonb)
returns public.shops language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); r public.shops;
begin
 update public.shops set payment_methods=coalesce(p_methods,'[]'::jsonb) where owner_id=u returning * into r;
 if not found then raise exception 'Seller shop not found'; end if;
 return r;
end $$;

drop function if exists public.save_shopora_product(uuid,text,uuid,numeric,numeric,integer,text,text,text,jsonb);
create or replace function public.save_shopora_product(
 p_product uuid,p_name text,p_category uuid,p_price numeric,p_compare numeric,p_stock int,
 p_description text,p_brand text,p_sku text,p_images jsonb
) returns public.products language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); sh uuid; r public.products; slug text;
begin
 select id into sh from public.shops where owner_id=u and active;
 if p_product is null and jsonb_array_length(coalesce(p_images,'[]'::jsonb)) not between 2 and 5 then
   raise exception 'A new product must have between 2 and 5 pictures';
 end if;
 if p_product is not null and jsonb_array_length(coalesce(p_images,'[]'::jsonb)) not in (0,2,3,4,5) then
   raise exception 'Product pictures must be between 2 and 5';
 end if;
 if sh is null then raise exception 'Create your shop first'; end if;
 if p_price<0 or p_stock<0 then raise exception 'Invalid price or stock'; end if;
 slug := public.shopora_make_slug(p_name)||'-'||substr(gen_random_uuid()::text,1,8);
 if p_product is null then
   insert into public.products(shop_id,category_id,name,slug,price,compare_price,stock,description,brand,sku,status)
   values(sh,p_category,trim(p_name),slug,p_price,p_compare,p_stock,coalesce(p_description,''),coalesce(p_brand,''),coalesce(p_sku,''),case when p_stock>0 then 'active' else 'out_of_stock' end)
   returning * into r;
 else
   update public.products set category_id=p_category,name=trim(p_name),price=p_price,compare_price=p_compare,stock=p_stock,
     description=coalesce(p_description,''),brand=coalesce(p_brand,''),sku=coalesce(p_sku,''),
     status=case when p_stock>0 then 'active' else 'out_of_stock' end
   where id=p_product and shop_id=sh returning * into r;
   if not found then raise exception 'Product not found'; end if;
   if jsonb_array_length(coalesce(p_images,'[]'::jsonb))>0 then
     delete from public.product_images where product_id=r.id;
   end if;
 end if;
 if jsonb_array_length(coalesce(p_images,'[]'::jsonb))>0 then
   insert into public.product_images(product_id,image_url,sort_order)
   select r.id,value::text,ord::int-1 from jsonb_array_elements_text(p_images) with ordinality;
 end if;
 return r;
end $$;

create or replace function public.delete_shopora_product(p_product uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 delete from public.products p using public.shops s where p.id=p_product and p.shop_id=s.id and s.owner_id=auth.uid();
end $$;

create or replace function public.get_shopora_seller_products()
returns table(id uuid,name text,price numeric,stock int,status text,description text,image_url text,sales_count int)
language sql security invoker as $$
 select p.id,p.name,p.price,p.stock,p.status,p.description,
   (select pi.image_url from public.product_images pi where pi.product_id=p.id order by pi.sort_order,pi.id limit 1),p.sales_count
 from public.products p join public.shops s on s.id=p.shop_id where s.owner_id=auth.uid() order by p.created_at desc;
$$;

-- ---------- addresses/wishlist ----------
create or replace function public.save_shopora_address(p_id uuid,p_label text,p_name text,p_phone text,p_line1 text,p_line2 text,p_city text,p_postal text,p_default boolean)
returns public.addresses language plpgsql security definer set search_path=public as $$
declare r public.addresses;
begin
 if p_default then update public.addresses set is_default=false where user_id=auth.uid(); end if;
 if p_id is null then
  insert into public.addresses(user_id,label,recipient_name,phone,line1,line2,city,postal_code,is_default)
  values(auth.uid(),p_label,p_name,p_phone,p_line1,p_line2,p_city,p_postal,p_default) returning * into r;
 else
  update public.addresses set label=p_label,recipient_name=p_name,phone=p_phone,line1=p_line1,line2=p_line2,city=p_city,postal_code=p_postal,is_default=p_default
  where id=p_id and user_id=auth.uid() returning * into r;
 end if;
 return r;
end $$;


-- ---------------------------------------------------------------------------
-- ADDRESS DELETE FIX / ORDER HISTORY SAFETY
-- If an existing Shopora database has orders.address_id (or another FK)
-- pointing to addresses, deleting an address used by an old order used to
-- fail with orders_address_id_fkey. Historical orders already contain their
-- delivery snapshot, so the address reference can safely be cleared.
-- This block is dynamic so it also works with older Shopora schema versions.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  local_col text;
  constraint_name text;
begin
  for r in
    select
      c.oid as constraint_oid,
      c.conname,
      a.attname as local_column
    from pg_constraint c
    join pg_class child on child.oid=c.conrelid
    join pg_namespace child_ns on child_ns.oid=child.relnamespace
    join pg_class parent on parent.oid=c.confrelid
    join pg_namespace parent_ns on parent_ns.oid=parent.relnamespace
    join lateral unnest(c.conkey) with ordinality ck(attnum,ord) on true
    join pg_attribute a on a.attrelid=child.oid and a.attnum=ck.attnum
    where c.contype='f'
      and child_ns.nspname='public'
      and child.relname='orders'
      and parent_ns.nspname='public'
      and parent.relname='addresses'
  loop
    local_col := r.local_column;
    constraint_name := r.conname;

    execute format('alter table public.orders alter column %I drop not null', local_col);

    begin
      execute format(
        'alter table public.orders drop constraint %I',
        constraint_name
      );
    exception when undefined_object then
      null;
    end;

    execute format(
      'alter table public.orders add constraint %I foreign key (%I) references public.addresses(id) on delete set null',
      constraint_name,
      local_col
    );
  end loop;
end $$;

create or replace function public.delete_shopora_address(p_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then
    raise exception 'You must be logged in';
  end if;

  delete from public.addresses
  where id=p_id and user_id=auth.uid();

  if not found then
    raise exception 'Address not found or you do not own this address';
  end if;
end;
$$;

create or replace function public.toggle_shopora_wishlist(p_product uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare
  u uuid := auth.uid();
  existsrow boolean;
  product_name text;
  product_shop uuid;
  seller_user uuid;
  customer_name text;
begin
  if u is null then raise exception 'Login required'; end if;
  select p.name,p.shop_id,s.owner_id into product_name,product_shop,seller_user
  from public.products p join public.shops s on s.id=p.shop_id
  where p.id=p_product and p.status <> 'archived';
  if product_name is null then raise exception 'Product not found'; end if;
  select exists(select 1 from public.wishlists where user_id=u and product_id=p_product) into existsrow;
  if existsrow then
    delete from public.wishlists where user_id=u and product_id=p_product;
    return false;
  end if;
  insert into public.wishlists(user_id,product_id) values(u,p_product);
  if seller_user is not null and seller_user <> u then
    select coalesce(nullif(trim(full_name),''),'A customer') into customer_name from public.profiles where id=u;
    insert into public.notifications(user_id,type,title,message)
    values(
      seller_user,
      'wishlist_added',
      'Product added to wishlist',
      coalesce(customer_name,'A customer') || ' added "' || product_name || '" to their wishlist.'
    );
  end if;
  return true;
end $$;

create or replace function public.get_shopora_wishlist()
returns table(
  id uuid,name text,description text,price numeric,compare_price numeric,stock int,
  shop_id uuid,shop_name text,image_url text,image_count int,created_at timestamptz
)
language sql stable security definer set search_path=public as $$
  select p.id,p.name,p.description,p.price,p.compare_price,p.stock,p.shop_id,s.name,
    (select pi.image_url from public.product_images pi where pi.product_id=p.id order by pi.sort_order,pi.id limit 1),
    (select count(*)::int from public.product_images pi where pi.product_id=p.id),p.created_at
  from public.wishlists w
  join public.products p on p.id=w.product_id
  join public.shops s on s.id=p.shop_id
  where w.user_id=auth.uid() and p.status='active'
  order by w.created_at desc;
$$;

-- ---------- checkout ----------
create or replace function public.get_shopora_checkout_payment_options(p_items jsonb)
returns table(shop_id uuid,shop_name text,methods jsonb,shipping numeric)
language sql stable security invoker as $$
 select s.id,s.name,s.payment_methods,
   case when s.free_shipping_from is not null and
      (select coalesce(sum((x->>'price')::numeric*(x->>'quantity')::int),0) from jsonb_array_elements(p_items) x where (x->>'shop_id')::uuid=s.id)>=s.free_shipping_from
     then 0 else s.shipping_fee end
 from public.shops s where s.id in(select distinct (x->>'shop_id')::uuid from jsonb_array_elements(p_items) x);
$$;

create or replace function public.create_shopora_order(
 p_items jsonb,p_address jsonb,p_payment_method text,p_payment_reference text,p_payment_proof text default null,p_coupon text default null
) returns public.orders
language plpgsql security definer set search_path=public as $$
declare
 u uuid:=auth.uid(); o public.orders; x jsonb; p public.products; sh public.shops;
 subtotal numeric:=0; shipping numeric:=0; discount numeric:=0; q int; method jsonb;
 order_no text;
begin
 if u is null then raise exception 'Login required'; end if;
 if coalesce(jsonb_array_length(p_items),0)=0 then raise exception 'Cart is empty'; end if;
 for x in select * from jsonb_array_elements(p_items) loop
   q := (x->>'quantity')::int;
   if q<=0 then raise exception 'Invalid quantity'; end if;
   select * into p from public.products where id=(x->>'product_id')::uuid and status='active' for update;
   if not found then raise exception 'Product is unavailable'; end if;
   if p.stock<q then raise exception 'Not enough stock for %',p.name; end if;
   select * into sh from public.shops where id=p.shop_id and active;
   if sh.owner_id=u then raise exception 'You cannot buy from your own shop'; end if;
   subtotal := subtotal + p.price*q;
 end loop;
 if p_coupon is not null and p_coupon<>'' then
   select case when c.discount_type='percent' then least(subtotal,subtotal*c.discount_value/100) else least(subtotal,c.discount_value) end
   into discount from public.coupons c where upper(c.code)=upper(p_coupon) and c.active
     and c.starts_at<=now() and (c.ends_at is null or c.ends_at>=now()) and subtotal>=c.min_spend
     and (c.max_uses is null or c.used_count<c.max_uses);
   discount := coalesce(discount,0);
 end if;
 for sh in select distinct s.* from public.shops s join public.products p on p.shop_id=s.id join jsonb_array_elements(p_items) x on (x->>'product_id')::uuid=p.id loop
   shipping := shipping + case when sh.free_shipping_from is not null and subtotal-discount>=sh.free_shipping_from then 0 else sh.shipping_fee end;
 end loop;
 order_no := 'SHP-'||to_char(now(),'YYYYMMDDHH24MISS')||'-'||upper(substr(gen_random_uuid()::text,1,6));
 insert into public.orders(customer_id,order_number,subtotal,shipping_total,discount_total,total,payment_method,payment_reference,payment_proof_url,delivery_snapshot)
 values(u,order_no,subtotal,shipping,discount,subtotal+shipping-discount,p_payment_method,p_payment_reference,p_payment_proof,p_address)
 returning * into o;
 for x in select * from jsonb_array_elements(p_items) loop
   q := (x->>'quantity')::int;
   select * into p from public.products where id=(x->>'product_id')::uuid for update;
   update public.products set stock=stock-q,sales_count=sales_count+q,status=case when stock-q<=0 then 'out_of_stock' else 'active' end where id=p.id;
   insert into public.order_items(order_id,product_id,shop_id,product_name,image_url,unit_price,quantity,line_total)
   values(o.id,p.id,p.shop_id,p.name,(select image_url from public.product_images where product_id=p.id order by sort_order,id limit 1),p.price,q,p.price*q);
 end loop;
 for sh in select distinct s.* from public.shops s join public.order_items oi on oi.shop_id=s.id where oi.order_id=o.id loop
   insert into public.seller_orders(order_id,shop_id,seller_id,subtotal,shipping,total,status,payment_status,payment_method_snapshot,payment_details_snapshot)
   select o.id,sh.id,sh.owner_id,sum(oi.line_total),
     case when sh.free_shipping_from is not null and sum(oi.line_total)>=sh.free_shipping_from then 0 else sh.shipping_fee end,
     sum(oi.line_total)+case when sh.free_shipping_from is not null and sum(oi.line_total)>=sh.free_shipping_from then 0 else sh.shipping_fee end,
     'payment_pending','pending',p_payment_method,coalesce((select (m->>'details') from jsonb_array_elements(sh.payment_methods) m where lower(m->>'name')=lower(p_payment_method) limit 1),'')
   from public.order_items oi where oi.order_id=o.id and oi.shop_id=sh.id group by sh.id,sh.owner_id,sh.shipping_fee,sh.free_shipping_from;
   insert into public.notifications(user_id,order_id,seller_order_id,type,title,message)
   select sh.owner_id,o.id,so.id,'new_order','New order','You received a new Shopora order.' from public.seller_orders so where so.order_id=o.id and so.shop_id=sh.id;
 end loop;
 insert into public.notifications(user_id,order_id,type,title,message)
 values(u,o.id,'order','Order placed','Your Shopora order has been placed and is awaiting payment confirmation.');
 if p_coupon is not null and p_coupon<>'' then
   update public.coupons set used_count=used_count+1 where upper(code)=upper(p_coupon);
 end if;
 return o;
end $$;

-- ---------- seller/customer order lifecycle ----------
create or replace function public.get_shopora_seller_orders(p_status text default null,p_search text default '')
returns table(
 seller_order_id uuid,order_id uuid,order_number text,customer_id uuid,customer_name text,customer_phone text,
 delivery jsonb,subtotal numeric,shipping numeric,total numeric,status text,payment_status text,payment_method text,
 payment_details text,payment_proof text,tracking_number text,carrier text,created_at timestamptz,items jsonb
) language sql security invoker as $$
 select so.id,o.id,o.order_number,o.customer_id,coalesce(pr.full_name,'Customer'),coalesce(pr.phone,''),
 o.delivery_snapshot,so.subtotal,so.shipping,so.total,so.status,so.payment_status,so.payment_method_snapshot,
 so.payment_details_snapshot,o.payment_proof_url,so.tracking_number,so.carrier,so.created_at,
 coalesce((select jsonb_agg(jsonb_build_object('id',oi.id,'name',oi.product_name,'quantity',oi.quantity,'price',oi.unit_price,'image',oi.image_url))
           from public.order_items oi where oi.order_id=o.id and oi.shop_id=so.shop_id),'[]'::jsonb)
 from public.seller_orders so join public.orders o on o.id=so.order_id
 left join public.profiles pr on pr.id=o.customer_id
 where so.seller_id=auth.uid() and (p_status is null or so.status=p_status)
 and (p_search='' or o.order_number ilike '%'||p_search||'%' or pr.full_name ilike '%'||p_search||'%')
 order by so.created_at desc;
$$;

create or replace function public.seller_set_shopora_order_status(
 p_seller_order uuid,p_status text,p_tracking text default null,p_carrier text default null,p_note text default null
) returns public.seller_orders language plpgsql security definer set search_path=public as $$
declare r public.seller_orders; u uuid:=auth.uid(); customer uuid; msg text;
begin
 select * into r from public.seller_orders where id=p_seller_order and seller_id=u for update;
 if not found then raise exception 'Order not found'; end if;
 if p_status not in('processing','packed','shipped','delivered','cancelled') then raise exception 'Invalid status'; end if;
 if p_status='processing' and r.payment_status<>'paid' then raise exception 'Confirm payment first'; end if;
 if p_status='shipped' and r.status not in('packed','shipped') then raise exception 'Pack the order before shipping'; end if;
 update public.seller_orders set status=p_status,tracking_number=coalesce(p_tracking,tracking_number),carrier=coalesce(p_carrier,carrier),seller_note=coalesce(p_note,seller_note),
 packed_at=case when p_status='packed' then now() else packed_at end,
 shipped_at=case when p_status='shipped' then now() else shipped_at end,
 delivered_at=case when p_status='delivered' then now() else delivered_at end
 where id=r.id returning * into r;
 select o.customer_id into customer from public.orders o where o.id=r.order_id;
 msg=case p_status when 'processing' then 'Payment confirmed. The seller is preparing your package.'
   when 'packed' then 'Your package has been packed.'
   when 'shipped' then 'Your package has shipped.' when 'delivered' then 'Your package was marked delivered. Please open My Orders and confirm that you received it.'
   when 'cancelled' then 'Your package was cancelled.' end;
 insert into public.notifications(user_id,order_id,seller_order_id,type,title,message)
 values(customer,r.order_id,r.id,'order_update','Order update',msg);
 if p_status='delivered' then
   update public.orders set status='delivered' where id=r.order_id and not exists(select 1 from public.seller_orders where order_id=r.order_id and status not in('delivered','completed'));
 end if;
 return r;
end $$;

create or replace function public.seller_confirm_shopora_payment(p_seller_order uuid)
returns public.seller_orders language plpgsql security definer set search_path=public as $$
declare r public.seller_orders; u uuid:=auth.uid(); customer uuid;
begin
 select * into r from public.seller_orders where id=p_seller_order and seller_id=u for update;
 if not found then raise exception 'Order not found'; end if;
 if r.payment_status='refunded' then raise exception 'Refunded payment cannot be confirmed'; end if;
 update public.seller_orders set payment_status='paid',status=case when status='payment_pending' then 'processing' else status end where id=r.id returning * into r;
 select customer_id into customer from public.orders where id=r.order_id;
 insert into public.notifications(user_id,order_id,seller_order_id,type,title,message)
 values(customer,r.order_id,r.id,'payment','Payment confirmed','The seller confirmed your payment.');
 return r;
end $$;

create or replace function public.customer_confirm_shopora_received(p_seller_order uuid)
returns public.seller_orders language plpgsql security definer set search_path=public as $$
declare r public.seller_orders; u uuid:=auth.uid(); seller uuid;
begin
 select so.* into r from public.seller_orders so join public.orders o on o.id=so.order_id
 where so.id=p_seller_order and o.customer_id=u for update;
 if not found then raise exception 'Order not found'; end if;
 if r.status not in('delivered','shipped') then raise exception 'This package is not ready to confirm'; end if;
 update public.seller_orders set status='completed',completed_at=now() where id=r.id returning * into r;
 seller=r.seller_id;
 insert into public.notifications(user_id,order_id,seller_order_id,type,title,message)
 values(seller,r.order_id,r.id,'completed','Customer confirmed receipt','The customer confirmed that the package was received.');
 if not exists(select 1 from public.seller_orders where order_id=r.order_id and status<>'completed') then
   update public.orders set status='completed' where id=r.order_id;
 end if;
 return r;
end $$;

create or replace function public.get_shopora_customer_orders(p_status text default null)
returns table(order_id uuid,order_number text,total numeric,status text,payment_status text,created_at timestamptz,delivery jsonb,packages jsonb)
language sql security invoker as $$
 select o.id,o.order_number,o.total,o.status,o.payment_status,o.created_at,o.delivery_snapshot,
 coalesce((select jsonb_agg(jsonb_build_object('id',so.id,'shop_id',so.shop_id,'shop_name',s.name,'total',so.total,'status',so.status,'payment_status',so.payment_status,'tracking',so.tracking_number,'carrier',so.carrier,
 'items',(select jsonb_agg(jsonb_build_object('name',oi.product_name,'quantity',oi.quantity,'price',oi.unit_price,'image',oi.image_url)) from public.order_items oi where oi.order_id=o.id and oi.shop_id=so.shop_id)))
 from public.seller_orders so join public.shops s on s.id=so.shop_id where so.order_id=o.id),'[]'::jsonb)
 from public.orders o where o.customer_id=auth.uid() and (p_status is null or o.status=p_status) order by o.created_at desc;
$$;

-- ---------- reviews/returns ----------
create or replace function public.add_shopora_review(p_product uuid,p_order_item uuid,p_rating int,p_title text,p_body text)
returns public.reviews language plpgsql security definer set search_path=public as $$
declare r public.reviews;
begin
 if not exists(select 1 from public.order_items oi join public.orders o on o.id=oi.order_id where oi.id=p_order_item and oi.product_id=p_product and o.customer_id=auth.uid()) then
   raise exception 'You can only review products you purchased';
 end if;
 insert into public.reviews(product_id,order_item_id,customer_id,rating,title,body)
 values(p_product,p_order_item,auth.uid(),p_rating,coalesce(p_title,''),coalesce(p_body,''))
 on conflict(customer_id,product_id) do update set rating=excluded.rating,title=excluded.title,body=excluded.body
 returning * into r;
 update public.products set rating=(select avg(rating)::numeric(3,2) from public.reviews where product_id=p_product),
 review_count=(select count(*) from public.reviews where product_id=p_product) where id=p_product;
 return r;
end $$;

create or replace function public.request_shopora_return(p_seller_order uuid,p_reason text,p_details text)
returns public.return_requests language plpgsql security definer set search_path=public as $$
declare r public.return_requests; oid uuid; total numeric;
begin
 select so.order_id,so.total into oid,total from public.seller_orders so join public.orders o on o.id=so.order_id where so.id=p_seller_order and o.customer_id=auth.uid();
 if oid is null then raise exception 'Order not found'; end if;
 insert into public.return_requests(seller_order_id,customer_id,reason,details,refund_amount) values(p_seller_order,auth.uid(),p_reason,p_details,total) returning * into r;
 update public.seller_orders set status='return_requested' where id=p_seller_order;
 return r;
end $$;

-- ---------- notifications ----------
create or replace function public.get_shopora_notifications()
returns table(id uuid,type text,title text,message text,read_at timestamptz,created_at timestamptz,order_id uuid,seller_order_id uuid)
language sql security invoker as $$
 select id,type,title,message,read_at,created_at,order_id,seller_order_id from public.notifications
 where user_id=auth.uid() order by created_at desc limit 100;
$$;

create or replace function public.mark_shopora_notification_read(p_id uuid)
returns void language sql security definer set search_path=public as $$
 update public.notifications set read_at=coalesce(read_at,now()) where id=p_id and user_id=auth.uid();
$$;

create or replace function public.mark_all_shopora_notifications_read()
returns void language sql security definer set search_path=public as $$
 update public.notifications set read_at=coalesce(read_at,now()) where user_id=auth.uid();
$$;

create or replace function public.clear_shopora_notifications()
returns void language sql security definer set search_path=public as $$
 delete from public.notifications where user_id=auth.uid();
$$;

-- ---------- RLS ----------
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.shops enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.addresses enable row level security;
alter table public.wishlists enable row level security;
alter table public.coupons enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.seller_orders enable row level security;
alter table public.notifications enable row level security;
alter table public.reviews enable row level security;
alter table public.return_requests enable row level security;

do $$
declare r record;
begin
 for r in select schemaname,tablename,policyname from pg_policies where schemaname='public' and tablename in
 ('profiles','categories','shops','products','product_images','addresses','wishlists','coupons','orders','order_items','seller_orders','notifications','reviews','return_requests')
 loop execute format('drop policy if exists %I on public.%I',r.policyname,r.tablename); end loop;
end $$;

drop policy if exists profiles_self on public.profiles;
drop policy if exists profiles_self on public.profiles;
create policy profiles_self on public.profiles for select using(id=auth.uid());
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());

drop policy if exists categories_public on public.categories;
drop policy if exists categories_public on public.categories;
create policy categories_public on public.categories for select using(active);
drop policy if exists shops_public on public.shops;
drop policy if exists shops_public on public.shops;
create policy shops_public on public.shops for select using(active);
drop policy if exists shops_owner on public.shops;
drop policy if exists shops_owner on public.shops;
create policy shops_owner on public.shops for all using(owner_id=auth.uid()) with check(owner_id=auth.uid());

drop policy if exists products_public on public.products;
drop policy if exists products_public on public.products;
create policy products_public on public.products for select using(status='active' and stock>0);
drop policy if exists products_owner on public.products;
drop policy if exists products_owner on public.products;
create policy products_owner on public.products for all using(public.shopora_is_shop_owner(shop_id)) with check(public.shopora_is_shop_owner(shop_id));

drop policy if exists images_public on public.product_images;
drop policy if exists images_public on public.product_images;
create policy images_public on public.product_images for select using(exists(select 1 from public.products p where p.id=product_id and p.status<>'archived'));
drop policy if exists images_owner on public.product_images;
drop policy if exists images_owner on public.product_images;
create policy images_owner on public.product_images for all using(exists(select 1 from public.products p where p.id=product_id and public.shopora_is_shop_owner(p.shop_id)));

drop policy if exists addresses_self on public.addresses;
drop policy if exists addresses_self on public.addresses;
create policy addresses_self on public.addresses for all using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists wishlist_self on public.wishlists;
drop policy if exists wishlist_self on public.wishlists;
create policy wishlist_self on public.wishlists for all using(user_id=auth.uid()) with check(user_id=auth.uid());

drop policy if exists orders_customer on public.orders;
drop policy if exists orders_customer on public.orders;
create policy orders_customer on public.orders for select using(customer_id=auth.uid());
drop policy if exists order_items_customer on public.order_items;
drop policy if exists order_items_customer on public.order_items;
create policy order_items_customer on public.order_items for select using(exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()));
drop policy if exists seller_orders_seller on public.seller_orders;
drop policy if exists seller_orders_seller on public.seller_orders;
create policy seller_orders_seller on public.seller_orders for select using(seller_id=auth.uid());
drop policy if exists notifications_self on public.notifications;
drop policy if exists notifications_self on public.notifications;
create policy notifications_self on public.notifications for select using(user_id=auth.uid());
drop policy if exists notifications_update on public.notifications;
drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications for delete using(user_id=auth.uid());
drop policy if exists reviews_public on public.reviews;
drop policy if exists reviews_public on public.reviews;
create policy reviews_public on public.reviews for select using(true);
drop policy if exists reviews_self on public.reviews;
drop policy if exists reviews_self on public.reviews;
create policy reviews_self on public.reviews for insert with check(customer_id=auth.uid());
drop policy if exists reviews_self_update on public.reviews;
drop policy if exists reviews_self_update on public.reviews;
create policy reviews_self_update on public.reviews for update using(customer_id=auth.uid()) with check(customer_id=auth.uid());
drop policy if exists returns_customer on public.return_requests;
drop policy if exists returns_customer on public.return_requests;
create policy returns_customer on public.return_requests for select using(customer_id=auth.uid());
drop policy if exists returns_seller on public.return_requests;
drop policy if exists returns_seller on public.return_requests;
create policy returns_seller on public.return_requests for select using(exists(select 1 from public.seller_orders so where so.id=seller_order_id and so.seller_id=auth.uid()));

-- ---------- grants ----------
grant select on public.categories,public.shops,public.products,public.product_images,public.reviews to anon,authenticated;
grant select,insert,update,delete on public.profiles,public.addresses,public.wishlists to authenticated;
grant select on public.orders,public.order_items,public.seller_orders,public.notifications,public.return_requests to authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public.shopora_is_shop_owner(uuid,uuid) from anon;

-- ---------- seed categories ----------
insert into public.categories(name,slug,sort_order) values
('Electronics','electronics',1),('Phones & Accessories','phones-accessories',2),('Computers','computers',3),
('Gaming','gaming',4),('Motorcycles & Accessories','motorcycles-accessories',5),('Cars & Accessories','cars-accessories',6),
('Fashion - Men','fashion-men',7),('Fashion - Women','fashion-women',8),('Shoes','shoes',9),
('Beauty & Personal Care','beauty-personal-care',10),('Home & Living','home-living',11),('Kitchen','kitchen',12),
('Sports & Fitness','sports-fitness',13),('Baby & Kids','baby-kids',14),('Toys','toys',15),
('Food & Grocery','food-grocery',16),('Books & Stationery','books-stationery',17),('Tools & Hardware','tools-hardware',18),
('Services','services',19),('Other','other',20)
on conflict(name) do update set slug=excluded.slug,sort_order=excluded.sort_order;

-- ---------- Storage buckets ----------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values
('profile-photos','profile-photos',true,5242880,array['image/jpeg','image/png','image/webp']),
('shop-media','shop-media',true,10485760,array['image/jpeg','image/png','image/webp']),
('product-images','product-images',true,10485760,array['image/jpeg','image/png','image/webp']),
('payment-proofs','payment-proofs',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do nothing;

-- Storage policies; do not directly alter storage metadata.
drop policy if exists profile_public_read on storage.objects;
drop policy if exists profile_public_read on storage.objects;
drop policy if exists profile_public_read on storage.objects;
create policy profile_public_read on storage.objects for select using(bucket_id='profile-photos');
drop policy if exists profile_owner_write on storage.objects;
drop policy if exists profile_owner_write on storage.objects;
drop policy if exists profile_owner_write on storage.objects;
create policy profile_owner_write on storage.objects for all to authenticated using(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists shop_media_public_read on storage.objects;
drop policy if exists shop_media_public_read on storage.objects;
drop policy if exists shop_media_public_read on storage.objects;
create policy shop_media_public_read on storage.objects for select using(bucket_id='shop-media');
drop policy if exists product_public_read on storage.objects;
drop policy if exists product_public_read on storage.objects;
drop policy if exists product_public_read on storage.objects;
create policy product_public_read on storage.objects for select using(bucket_id='product-images');
drop policy if exists payment_proof_owner on storage.objects;
drop policy if exists payment_proof_owner on storage.objects;
drop policy if exists payment_proof_owner on storage.objects;
create policy payment_proof_owner on storage.objects for all to authenticated using(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);

notify pgrst,'reload schema';


-- V43 PROFILE PICTURE PERSISTENCE
insert into public.profiles(id,full_name,phone)
select id,coalesce(raw_user_meta_data->>'full_name',''),coalesce(raw_user_meta_data->>'phone','')
from auth.users
where not exists (select 1 from public.profiles p where p.id=auth.users.id);

alter table public.profiles add column if not exists avatar_url text;

do $$
begin
  if not exists (select 1 from storage.buckets where id='profile-photos') then
    insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
    values('profile-photos','profile-photos',true,5242880,array['image/jpeg','image/png','image/webp']);
  else
    update storage.buckets set public=true,file_size_limit=5242880,
      allowed_mime_types=array['image/jpeg','image/png','image/webp']
    where id='profile-photos';
  end if;
end $$;

drop policy if exists profile_public_read on storage.objects;
drop policy if exists profile_public_read on storage.objects;
drop policy if exists profile_public_read on storage.objects;
create policy profile_public_read on storage.objects for select using(bucket_id='profile-photos');

drop policy if exists profile_owner_write on storage.objects;
drop policy if exists profile_owner_write on storage.objects;
drop policy if exists profile_owner_write on storage.objects;
create policy profile_owner_write on storage.objects for all to authenticated
using(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='profile-photos' and (storage.foldername(name))[1]=auth.uid()::text);


-- V44 SHOP SEARCH indexes
create index if not exists shops_name_lower_idx on public.shops(lower(name));
create index if not exists shops_slug_lower_idx on public.shops(lower(slug));
notify pgrst,'reload schema';


-- =====================================================================
-- V46 PRODUCT SAVE COMPATIBILITY FIX
-- Existing Shopora installations may still have a legacy products.price_mur
-- column marked NOT NULL. The modern frontend uses products.price.
-- Keep both columns synchronized so old databases cannot reject a product.
-- =====================================================================

alter table public.products
  add column if not exists price_mur numeric(12,2);

update public.products
set price_mur = price
where price_mur is null;

-- Keep legacy and current price columns synchronized for older integrations.
create or replace function public.shopora_sync_product_price()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.price is null and new.price_mur is not null then
    new.price := new.price_mur;
  elsif new.price_mur is null and new.price is not null then
    new.price_mur := new.price;
  elsif new.price is not null then
    new.price_mur := new.price;
  end if;
  return new;
end $$;

drop trigger if exists shopora_sync_product_price on public.products;
drop trigger if exists shopora_sync_product_price on public.products;
drop trigger if exists shopora_sync_product_price on public.products;
create trigger shopora_sync_product_price before insert or update of price,price_mur on public.products
for each row execute function public.shopora_sync_product_price();

-- Use a NEW RPC name to avoid any stale/legacy overloaded
-- save_shopora_product() function in an existing database.
drop function if exists public.save_shopora_product_v46(uuid,text,uuid,numeric,numeric,integer,text,text,text,jsonb);

create function public.save_shopora_product_v46(
  p_product uuid,
  p_name text,
  p_category uuid,
  p_price numeric,
  p_compare numeric,
  p_stock integer,
  p_description text,
  p_brand text,
  p_sku text,
  p_images jsonb
)
returns public.products
language plpgsql
security definer
set search_path=public
as $$
declare
  u uuid := auth.uid();
  sh uuid;
  r public.products;
  slug text;
  image_count integer := jsonb_array_length(coalesce(p_images,'[]'::jsonb));
begin
  if u is null then
    raise exception 'You must be logged in';
  end if;

  select id into sh
  from public.shops
  where owner_id=u and active=true
  limit 1;

  if sh is null then
    raise exception 'Create your shop first';
  end if;

  if nullif(trim(coalesce(p_name,'')),'') is null then
    raise exception 'Product name is required';
  end if;

  if p_price is null or p_price <= 0 then
    raise exception 'Enter a valid price greater than 0 MUR';
  end if;

  if p_stock is null or p_stock < 0 then
    raise exception 'Enter a valid stock quantity';
  end if;

  if p_product is null and image_count not between 2 and 5 then
    raise exception 'A new product must have between 2 and 5 pictures';
  end if;

  if p_product is not null and image_count not in (0,2,3,4,5) then
    raise exception 'Product pictures must be between 2 and 5';
  end if;

  if p_product is null then
    slug := public.shopora_make_slug(trim(p_name)) || '-' ||
            substr(gen_random_uuid()::text,1,8);

    insert into public.products(
      shop_id,category_id,name,slug,price,price_mur,compare_price,stock,
      description,brand,sku,status
    )
    values(
      sh,p_category,trim(p_name),slug,p_price,p_price,p_compare,p_stock,
      coalesce(p_description,''),coalesce(p_brand,''),coalesce(p_sku,''),
      case when p_stock>0 then 'active' else 'out_of_stock' end
    )
    returning * into r;

  else
    update public.products
    set category_id=p_category,
        name=trim(p_name),
        price=p_price,
        price_mur=p_price,
        compare_price=p_compare,
        stock=p_stock,
        description=coalesce(p_description,''),
        brand=coalesce(p_brand,''),
        sku=coalesce(p_sku,''),
        status=case when p_stock>0 then 'active' else 'out_of_stock' end
    where id=p_product and shop_id=sh
    returning * into r;

    if not found then
      raise exception 'Product not found';
    end if;

    if image_count > 0 then
      delete from public.product_images where product_id=r.id;
    end if;
  end if;

  if image_count > 0 then
    insert into public.product_images(product_id,image_url,sort_order)
    select r.id,t.image_url,t.position::int-1
    from jsonb_array_elements_text(coalesce(p_images,'[]'::jsonb))
         with ordinality as t(image_url,position);
  end if;

  return r;
end $$;

grant execute on function public.save_shopora_product_v46(
  uuid,text,uuid,numeric,numeric,integer,text,text,text,jsonb
) to authenticated;



-- =====================================================================
-- V48 PRODUCT IMAGE STORAGE PATH COMPATIBILITY
-- Some existing Shopora databases have product_images.storage_path NOT NULL.
-- The original schema did not have that legacy column, so inserts that only
-- supplied image_url failed. Keep both values synchronized.
-- =====================================================================

alter table public.product_images
  add column if not exists storage_path text;

update public.product_images
set storage_path = image_url
where storage_path is null;

create or replace function public.save_shopora_product_v46(
  p_product uuid,
  p_name text,
  p_category uuid,
  p_price numeric,
  p_compare numeric,
  p_stock integer,
  p_description text,
  p_brand text,
  p_sku text,
  p_images jsonb
)
returns public.products
language plpgsql
security definer
set search_path=public
as $$
declare
  u uuid := auth.uid();
  sh uuid;
  r public.products;
  slug text;
  image_count integer := jsonb_array_length(coalesce(p_images,'[]'::jsonb));
begin
  if u is null then raise exception 'You must be logged in'; end if;

  select id into sh from public.shops
  where owner_id=u and active=true limit 1;

  if sh is null then raise exception 'Create your shop first'; end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Product name is required'; end if;
  if p_price is null or p_price <= 0 then raise exception 'Enter a valid price greater than 0 MUR'; end if;
  if p_stock is null or p_stock < 0 then raise exception 'Enter a valid stock quantity'; end if;

  if p_product is null and image_count not between 2 and 5 then
    raise exception 'A new product must have between 2 and 5 pictures';
  end if;

  if p_product is not null and image_count not in (0,2,3,4,5) then
    raise exception 'Product pictures must be between 2 and 5';
  end if;

  if p_product is null then
    slug := public.shopora_make_slug(trim(p_name)) || '-' ||
            substr(gen_random_uuid()::text,1,8);

    insert into public.products(
      shop_id,category_id,name,slug,price,price_mur,compare_price,stock,
      description,brand,sku,status
    )
    values(
      sh,p_category,trim(p_name),slug,p_price,p_price,p_compare,p_stock,
      coalesce(p_description,''),coalesce(p_brand,''),coalesce(p_sku,''),
      case when p_stock>0 then 'active' else 'out_of_stock' end
    )
    returning * into r;
  else
    update public.products
    set category_id=p_category,
        name=trim(p_name),
        price=p_price,
        price_mur=p_price,
        compare_price=p_compare,
        stock=p_stock,
        description=coalesce(p_description,''),
        brand=coalesce(p_brand,''),
        sku=coalesce(p_sku,''),
        status=case when p_stock>0 then 'active' else 'out_of_stock' end
    where id=p_product and shop_id=sh
    returning * into r;

    if not found then raise exception 'Product not found'; end if;
    if image_count > 0 then
      delete from public.product_images where product_id=r.id;
    end if;
  end if;

  if image_count > 0 then
    insert into public.product_images(product_id,image_url,storage_path,sort_order)
    select r.id,t.image_url,t.image_url,t.position::int-1
    from jsonb_array_elements_text(coalesce(p_images,'[]'::jsonb))
         with ordinality as t(image_url,position);
  end if;

  return r;
end $$;

grant execute on function public.save_shopora_product_v46(
  uuid,text,uuid,numeric,numeric,integer,text,text,text,jsonb
) to authenticated;


-- =====================================================================
-- SHOPORA V49 CHECKOUT / ADDRESS COMPATIBILITY
-- Fixes legacy databases where addresses.address_text is NOT NULL.
-- Also makes checkout reject an empty payment method instead of sending
-- a blank value to the order RPC.
-- =====================================================================

alter table public.addresses
  add column if not exists address_text text;

-- Existing legacy rows: derive a readable address string.
update public.addresses
set address_text = trim(
  both ', ' from
  concat_ws(', ',
    nullif(trim(line1),''),
    nullif(trim(line2),''),
    nullif(trim(city),''),
    nullif(trim(postal_code),''),
    nullif(trim(country),'')
  )
)
where address_text is null or btrim(address_text)='';

create or replace function public.save_shopora_address(
  p_id uuid,
  p_label text,
  p_name text,
  p_phone text,
  p_line1 text,
  p_line2 text,
  p_city text,
  p_postal text,
  p_default boolean
)
returns public.addresses
language plpgsql
security definer
set search_path=public
as $$
declare
  r public.addresses;
  v_text text;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if nullif(trim(coalesce(p_name,'')),'') is null then raise exception 'Recipient name is required'; end if;
  if nullif(trim(coalesce(p_phone,'')),'') is null then raise exception 'Phone number is required'; end if;
  if nullif(trim(coalesce(p_line1,'')),'') is null then raise exception 'Delivery address is required'; end if;
  if nullif(trim(coalesce(p_city,'')),'') is null then raise exception 'City is required'; end if;

  v_text := trim(
    both ', ' from
    concat_ws(', ',
      nullif(trim(coalesce(p_line1,'')),''),
      nullif(trim(coalesce(p_line2,'')),''),
      nullif(trim(coalesce(p_city,'')),''),
      nullif(trim(coalesce(p_postal,'')),''),
      'Mauritius'
    )
  );

  if p_default then
    update public.addresses set is_default=false where user_id=auth.uid();
  end if;

  if p_id is null then
    insert into public.addresses(
      user_id,label,recipient_name,phone,line1,line2,city,postal_code,
      country,address_text,is_default
    )
    values(
      auth.uid(),coalesce(nullif(trim(p_label),''),'Home'),trim(p_name),
      trim(p_phone),trim(p_line1),coalesce(trim(p_line2),''),
      trim(p_city),coalesce(trim(p_postal),''),'Mauritius',v_text,p_default
    )
    returning * into r;
  else
    update public.addresses
    set label=coalesce(nullif(trim(p_label),''),'Home'),
        recipient_name=trim(p_name),
        phone=trim(p_phone),
        line1=trim(p_line1),
        line2=coalesce(trim(p_line2),''),
        city=trim(p_city),
        postal_code=coalesce(trim(p_postal),''),
        country='Mauritius',
        address_text=v_text,
        is_default=p_default,
        updated_at=now()
    where id=p_id and user_id=auth.uid()
    returning * into r;

    if not found then raise exception 'Address not found'; end if;
  end if;

  return r;
end $$;

grant execute on function public.save_shopora_address(
  uuid,text,text,text,text,text,text,text,boolean
) to authenticated;

-- Keep address_text synchronized when old/new clients write directly.
create or replace function public.shopora_sync_address_text()
returns trigger
language plpgsql
as $$
begin
  new.address_text := trim(
    both ', ' from
    concat_ws(', ',
      nullif(trim(coalesce(new.line1,'')),''),
      nullif(trim(coalesce(new.line2,'')),''),
      nullif(trim(coalesce(new.city,'')),''),
      nullif(trim(coalesce(new.postal_code,'')),''),
      nullif(trim(coalesce(new.country,'Mauritius')),'')
    )
  );
  return new;
end $$;

drop trigger if exists shopora_sync_address_text on public.addresses;
drop trigger if exists shopora_sync_address_text on public.addresses;
drop trigger if exists shopora_sync_address_text on public.addresses;
create trigger shopora_sync_address_text before insert or update on public.addresses
for each row execute function public.shopora_sync_address_text();

-- Safer order RPC: require a real payment method and a complete address.
-- The existing stock locking and seller-order creation remain unchanged.
create or replace function public.create_shopora_order(
 p_items jsonb,
 p_address jsonb,
 p_payment_method text,
 p_payment_reference text,
 p_payment_proof text default null,
 p_coupon text default null
) returns public.orders
language plpgsql security definer set search_path=public as $$
declare
 u uuid:=auth.uid(); o public.orders; x jsonb; p public.products; sh public.shops;
 subtotal numeric:=0; shipping numeric:=0; discount numeric:=0; q int;
 order_no text; method_name text:=trim(coalesce(p_payment_method,''));
 v_address jsonb;
begin
 if u is null then raise exception 'Login required'; end if;
 if coalesce(jsonb_array_length(p_items),0)=0 then raise exception 'Cart is empty'; end if;
 if method_name='' then raise exception 'Please select a payment method'; end if;
 if p_address is null or jsonb_typeof(p_address)<>'object' then raise exception 'Please select a delivery address'; end if;

 v_address := jsonb_build_object(
   'id',p_address->>'id',
   'label',coalesce(p_address->>'label','Home'),
   'recipient_name',p_address->>'recipient_name',
   'phone',p_address->>'phone',
   'line1',p_address->>'line1',
   'line2',coalesce(p_address->>'line2',''),
   'city',p_address->>'city',
   'postal_code',coalesce(p_address->>'postal_code',''),
   'country',coalesce(p_address->>'country','Mauritius'),
   'address_text',coalesce(
      nullif(p_address->>'address_text',''),
      trim(both ', ' from concat_ws(', ',
        nullif(p_address->>'line1',''),
        nullif(p_address->>'line2',''),
        nullif(p_address->>'city',''),
        nullif(p_address->>'postal_code',''),
        coalesce(p_address->>'country','Mauritius')
      ))
   )
 );

 if nullif(trim(coalesce(v_address->>'recipient_name','')),'') is null
    or nullif(trim(coalesce(v_address->>'phone','')),'') is null
    or nullif(trim(coalesce(v_address->>'line1','')),'') is null
    or nullif(trim(coalesce(v_address->>'city','')),'') is null
 then raise exception 'Please select a complete delivery address'; end if;

 for x in select * from jsonb_array_elements(p_items) loop
   q := (x->>'quantity')::int;
   if q<=0 then raise exception 'Invalid quantity'; end if;
   select * into p from public.products
   where id=(x->>'product_id')::uuid and status='active' for update;
   if not found then raise exception 'Product is unavailable'; end if;
   if p.stock<q then raise exception 'Not enough stock for %',p.name; end if;
   select * into sh from public.shops where id=p.shop_id and active;
   if not found then raise exception 'Seller shop is unavailable'; end if;
   if sh.owner_id=u then raise exception 'You cannot buy from your own shop'; end if;
   subtotal := subtotal + p.price*q;
 end loop;

 if p_coupon is not null and p_coupon<>'' then
   select case when c.discount_type='percent'
     then least(subtotal,subtotal*c.discount_value/100)
     else least(subtotal,c.discount_value) end
   into discount
   from public.coupons c
   where upper(c.code)=upper(p_coupon) and c.active
     and c.starts_at<=now() and (c.ends_at is null or c.ends_at>=now())
     and subtotal>=c.min_spend
     and (c.max_uses is null or c.used_count<c.max_uses);
   discount:=coalesce(discount,0);
 end if;

 for sh in
   select distinct s.* from public.shops s
   join public.products pp on pp.shop_id=s.id
   join jsonb_array_elements(p_items) xx on (xx->>'product_id')::uuid=pp.id
 loop
   shipping:=shipping+case
     when sh.free_shipping_from is not null
       and subtotal-discount>=sh.free_shipping_from then 0
     else sh.shipping_fee end;
 end loop;

 order_no:='SHP-'||to_char(now(),'YYYYMMDDHH24MISS')||'-'||upper(substr(gen_random_uuid()::text,1,6));

 insert into public.orders(
   customer_id,order_number,subtotal,shipping_total,discount_total,total,
   payment_method,payment_reference,payment_proof_url,delivery_snapshot
 )
 values(
   u,order_no,subtotal,shipping,discount,subtotal+shipping-discount,
   method_name,nullif(trim(p_payment_reference),''),p_payment_proof,v_address
 )
 returning * into o;

 for x in select * from jsonb_array_elements(p_items) loop
   q:=(x->>'quantity')::int;
   select * into p from public.products
   where id=(x->>'product_id')::uuid for update;

   update public.products
   set stock=stock-q,
       sales_count=sales_count+q,
       status=case when stock-q<=0 then 'out_of_stock' else 'active' end
   where id=p.id;

   insert into public.order_items(
     order_id,product_id,shop_id,product_name,image_url,
     unit_price,quantity,line_total
   )
   values(
     o.id,p.id,p.shop_id,p.name,
     (select image_url from public.product_images
      where product_id=p.id order by sort_order,id limit 1),
     p.price,q,p.price*q
   );
 end loop;

 for sh in
   select distinct s.* from public.shops s
   join public.order_items oi on oi.shop_id=s.id
   where oi.order_id=o.id
 loop
   insert into public.seller_orders(
     order_id,shop_id,seller_id,subtotal,shipping,total,status,
     payment_status,payment_method_snapshot,payment_details_snapshot
   )
   select
     o.id,sh.id,sh.owner_id,sum(oi.line_total),
     case when sh.free_shipping_from is not null
       and sum(oi.line_total)>=sh.free_shipping_from then 0
       else sh.shipping_fee end,
     sum(oi.line_total)+case when sh.free_shipping_from is not null
       and sum(oi.line_total)>=sh.free_shipping_from then 0
       else sh.shipping_fee end,
     'payment_pending','pending',method_name,
     coalesce(
       (select m->>'details'
        from jsonb_array_elements(coalesce(sh.payment_methods,'[]'::jsonb)) m
        where lower(coalesce(m->>'name',''))=lower(method_name)
        limit 1),''
     )
   from public.order_items oi
   where oi.order_id=o.id and oi.shop_id=sh.id
   group by sh.id,sh.owner_id,sh.shipping_fee,sh.free_shipping_from;

   insert into public.notifications(
     user_id,order_id,seller_order_id,type,title,message
   )
   select sh.owner_id,o.id,so.id,'new_order','New order',
          'You received a new Shopora order.'
   from public.seller_orders so
   where so.order_id=o.id and so.shop_id=sh.id;
 end loop;

 insert into public.notifications(user_id,order_id,type,title,message)
 values(
   u,o.id,'order','Order placed',
   'Your Shopora order has been placed and is awaiting payment confirmation.'
 );

 if p_coupon is not null and p_coupon<>'' then
   update public.coupons set used_count=used_count+1
   where upper(code)=upper(p_coupon);
 end if;

 return o;
end $$;

grant execute on function public.create_shopora_order(
 jsonb,jsonb,text,text,text,text
) to authenticated;

drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert with check(id=auth.uid());

-- V50 profile picture persistence hardening
do $$
begin
  if not exists(select 1 from storage.buckets where id='profile-photos') then
    insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
    values('profile-photos','profile-photos',true,5242880,
           array['image/jpeg','image/png','image/webp']);
  else
    update storage.buckets
    set public=true,file_size_limit=5242880,
        allowed_mime_types=array['image/jpeg','image/png','image/webp']
    where id='profile-photos';
  end if;
end $$;

drop policy if exists profile_public_read on storage.objects;
drop policy if exists profile_public_read on storage.objects;
drop policy if exists profile_public_read on storage.objects;
create policy profile_public_read on storage.objects
for select using(bucket_id='profile-photos');

drop policy if exists profile_owner_write on storage.objects;
drop policy if exists profile_owner_write on storage.objects;
drop policy if exists profile_owner_write on storage.objects;
create policy profile_owner_write on storage.objects
for all to authenticated
using(bucket_id='profile-photos'
      and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='profile-photos'
      and (storage.foldername(name))[1]=auth.uid()::text);

notify pgrst,'reload schema';


-- =====================================================================
-- SHOPORA V51 — LEGACY ORDERS MONEY-COLUMN COMPATIBILITY
--
-- The live database contains a legacy NOT NULL column named subtotal_mur,
-- while the current order RPC writes subtotal. PostgreSQL therefore rejects
-- the insert before the order can be created.
--
-- This migration keeps both schemas compatible and synchronizes the legacy
-- *_mur fields automatically.
-- =====================================================================

alter table public.orders
  add column if not exists subtotal_mur numeric(12,2) not null default 0;

alter table public.orders
  add column if not exists shipping_mur numeric(12,2) not null default 0;

alter table public.orders
  add column if not exists discount_mur numeric(12,2) not null default 0;

alter table public.orders
  add column if not exists total_mur numeric(12,2) not null default 0;

-- Back-fill legacy values from the current canonical columns.
update public.orders
set subtotal_mur=coalesce(subtotal,0),
    shipping_mur=coalesce(shipping_total,0),
    discount_mur=coalesce(discount_total,0),
    total_mur=coalesce(total,0)
where subtotal_mur=0
   or shipping_mur=0
   or discount_mur=0
   or total_mur=0;

create or replace function public.shopora_sync_order_money_columns()
returns trigger
language plpgsql
as $$
begin
  new.subtotal := coalesce(new.subtotal, new.subtotal_mur, 0);
  new.shipping_total := coalesce(new.shipping_total, new.shipping_mur, 0);
  new.discount_total := coalesce(new.discount_total, new.discount_mur, 0);
  new.total := coalesce(new.total, new.total_mur, 0);

  new.subtotal_mur := coalesce(new.subtotal, new.subtotal_mur, 0);
  new.shipping_mur := coalesce(new.shipping_total, new.shipping_mur, 0);
  new.discount_mur := coalesce(new.discount_total, new.discount_mur, 0);
  new.total_mur := coalesce(new.total, new.total_mur, 0);

  return new;
end $$;

drop trigger if exists shopora_sync_order_money_columns on public.orders;
drop trigger if exists shopora_sync_order_money_columns on public.orders;
drop trigger if exists shopora_sync_order_money_columns on public.orders;
create trigger shopora_sync_order_money_columns before insert or update on public.orders
for each row execute function public.shopora_sync_order_money_columns();

-- Make sure existing rows are fully synchronized after migration.
update public.orders
set subtotal_mur=coalesce(subtotal,subtotal_mur,0),
    shipping_mur=coalesce(shipping_total,shipping_mur,0),
    discount_mur=coalesce(discount_total,discount_mur,0),
    total_mur=coalesce(total,total_mur,0);

notify pgrst,'reload schema';


-- =====================================================================
-- SHOPORA V52 — FULL CHECKOUT / LEGACY-SCHEMA HARDENING
-- =====================================================================

-- Legacy installs have used several names for the same order fields.
-- Keep them nullable/defaulted so an older NOT NULL column cannot break a
-- modern checkout insert.
alter table public.orders add column if not exists address_id uuid;
alter table public.addresses add column if not exists address_text text;

alter table public.orders add column if not exists subtotal_mur numeric(12,2) not null default 0;
alter table public.orders add column if not exists shipping_mur numeric(12,2) not null default 0;
alter table public.orders add column if not exists discount_mur numeric(12,2) not null default 0;
alter table public.orders add column if not exists total_mur numeric(12,2) not null default 0;

-- Some very old databases may have made an address reference mandatory.
-- The order stores a complete delivery snapshot, so the legacy FK must not
-- block checkout when an address row is later removed.
do $$
declare r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid='public.orders'::regclass
      and c.contype='f'
      and pg_get_constraintdef(c.oid) ilike '%address%'
  loop
    begin
      execute format('alter table public.orders drop constraint %I',r.conname);
    exception when undefined_object then null;
    end;
  end loop;
end $$;

-- Backfill address text for legacy rows.
update public.addresses
set address_text=trim(both ', ' from concat_ws(', ',
  nullif(trim(coalesce(line1,'')),''),
  nullif(trim(coalesce(line2,'')),''),
  nullif(trim(coalesce(city,'')),''),
  nullif(trim(coalesce(postal_code,'')),''),
  nullif(trim(coalesce(country,'Mauritius')),'')
))
where address_text is null or btrim(address_text)='';

create or replace function public.shopora_sync_address_text_v52()
returns trigger language plpgsql as $$
begin
  new.address_text=trim(both ', ' from concat_ws(', ',
    nullif(trim(coalesce(new.line1,'')),''),
    nullif(trim(coalesce(new.line2,'')),''),
    nullif(trim(coalesce(new.city,'')),''),
    nullif(trim(coalesce(new.postal_code,'')),''),
    nullif(trim(coalesce(new.country,'Mauritius')),'')
  ));
  return new;
end $$;

drop trigger if exists shopora_sync_address_text_v52 on public.addresses;
drop trigger if exists shopora_sync_address_text_v52 on public.addresses;
drop trigger if exists shopora_sync_address_text_v52 on public.addresses;
create trigger shopora_sync_address_text_v52 before insert or update on public.addresses
for each row execute function public.shopora_sync_address_text_v52();

-- Canonical + legacy money fields always stay identical.
create or replace function public.shopora_sync_order_money_v52()
returns trigger language plpgsql as $$
begin
  new.subtotal=coalesce(new.subtotal,new.subtotal_mur,0);
  new.shipping_total=coalesce(new.shipping_total,new.shipping_mur,0);
  new.discount_total=coalesce(new.discount_total,new.discount_mur,0);
  new.total=coalesce(new.total,new.total_mur,0);

  new.subtotal_mur=coalesce(new.subtotal,0);
  new.shipping_mur=coalesce(new.shipping_total,0);
  new.discount_mur=coalesce(new.discount_total,0);
  new.total_mur=coalesce(new.total,0);
  return new;
end $$;

drop trigger if exists shopora_sync_order_money_v52 on public.orders;
drop trigger if exists shopora_sync_order_money_v52 on public.orders;
drop trigger if exists shopora_sync_order_money_v52 on public.orders;
create trigger shopora_sync_order_money_v52 before insert or update on public.orders
for each row execute function public.shopora_sync_order_money_v52();

update public.orders
set subtotal=coalesce(subtotal,subtotal_mur,0),
    shipping_total=coalesce(shipping_total,shipping_mur,0),
    discount_total=coalesce(discount_total,discount_mur,0),
    total=coalesce(total,total_mur,0),
    subtotal_mur=coalesce(subtotal,subtotal_mur,0),
    shipping_mur=coalesce(shipping_total,shipping_mur,0),
    discount_mur=coalesce(discount_total,discount_mur,0),
    total_mur=coalesce(total,total_mur,0);

-- Payment-proof storage must exist for checkout uploads.
do $$
begin
  if not exists(select 1 from storage.buckets where id='payment-proofs') then
    insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
    values('payment-proofs','payment-proofs',false,10485760,
      array['image/jpeg','image/png','image/webp','application/pdf']);
  else
    update storage.buckets
    set file_size_limit=10485760,
        allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf']
    where id='payment-proofs';
  end if;
end $$;

drop policy if exists payment_proof_owner on storage.objects;
drop policy if exists payment_proof_owner on storage.objects;
drop policy if exists payment_proof_owner on storage.objects;
create policy payment_proof_owner on storage.objects
for all to authenticated
using(bucket_id='payment-proofs'
  and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='payment-proofs'
  and (storage.foldername(name))[1]=auth.uid()::text);

-- Server-side checkout pricing. Never trust the price/stock sent by the browser.
drop function if exists public.get_shopora_checkout_payment_options(jsonb);
create function public.get_shopora_checkout_payment_options(p_items jsonb)
returns table(
 shop_id uuid,
 shop_name text,
 methods jsonb,
 shipping numeric,
 subtotal numeric
)
language plpgsql
security definer
set search_path=public
as $$
begin
 if auth.uid() is null then
   raise exception 'Login required';
 end if;

 return query
 with requested as (
   select
     (x->>'product_id')::uuid as product_id,
     sum(greatest(1,(x->>'quantity')::int))::int as quantity
   from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
   group by 1
 ),
 priced as (
   select
     p.shop_id,
     p.id as product_id,
     p.price,
     r.quantity
   from requested r
   join public.products p on p.id=r.product_id
   where p.status='active'
     and p.stock >= r.quantity
 ),
 grouped as (
   select
     p.shop_id,
     sum(p.price*p.quantity)::numeric as subtotal
   from priced p
   group by p.shop_id
 )
 select
   s.id,
   s.name,
   coalesce(s.payment_methods,'[]'::jsonb),
   case
     when s.free_shipping_from is not null
      and g.subtotal >= s.free_shipping_from
       then 0::numeric
     else coalesce(s.shipping_fee,0)::numeric
   end,
   g.subtotal
 from public.shops s
 join grouped g on g.shop_id=s.id
 where coalesce(s.active,true)=true;
end
$$;

grant execute on function public.get_shopora_checkout_payment_options(jsonb)
to authenticated;

-- New order RPC supports multiple sellers correctly: one payment method per
-- seller. It also merges duplicate cart lines, uses database prices, locks
-- inventory, blocks buying from your own shop, and writes both legacy/new
-- order-money columns.
drop function if exists public.create_shopora_order_v52(jsonb,jsonb,jsonb,text,text,text);
create function public.create_shopora_order_v52(
  p_items jsonb,
  p_address jsonb,
  p_payment_methods jsonb,
  p_payment_reference text,
  p_payment_proof text default null,
  p_coupon text default null
) returns public.orders
language plpgsql security definer set search_path=public as $$
declare
  u uuid:=auth.uid();
  o public.orders;
  r record;
  s record;
  m jsonb;
  subtotal numeric:=0;
  shipping numeric:=0;
  discount numeric:=0;
  shop_subtotal numeric:=0;
  shop_shipping numeric:=0;
  method_name text;
  method_details text;
  order_no text;
  v_address jsonb;
  q int;
begin
  if u is null then raise exception 'Login required'; end if;
  if coalesce(jsonb_array_length(p_items),0)=0 then raise exception 'Cart is empty'; end if;

  if p_address is null or jsonb_typeof(p_address)<>'object'
     or nullif(trim(coalesce(p_address->>'id','')),'') is null then
    raise exception 'Please select a delivery address';
  end if;

  if not exists(
    select 1 from public.addresses a
    where a.id=(p_address->>'id')::uuid and a.user_id=u
  ) then
    raise exception 'Delivery address is invalid or no longer available';
  end if;

  v_address=jsonb_build_object(
    'id',p_address->>'id',
    'label',coalesce(p_address->>'label','Home'),
    'recipient_name',p_address->>'recipient_name',
    'phone',p_address->>'phone',
    'line1',p_address->>'line1',
    'line2',coalesce(p_address->>'line2',''),
    'city',p_address->>'city',
    'postal_code',coalesce(p_address->>'postal_code',''),
    'country',coalesce(p_address->>'country','Mauritius'),
    'address_text',coalesce(
      nullif(p_address->>'address_text',''),
      trim(both ', ' from concat_ws(', ',
        nullif(p_address->>'line1',''),
        nullif(p_address->>'line2',''),
        nullif(p_address->>'city',''),
        nullif(p_address->>'postal_code',''),
        coalesce(p_address->>'country','Mauritius')
      ))
    )
  );

  create temp table if not exists shopora_cart_v52(
    product_id uuid primary key,
    quantity int not null
  ) on commit drop;
  truncate shopora_cart_v52;

  insert into shopora_cart_v52(product_id,quantity)
  select (x->>'product_id')::uuid,sum((x->>'quantity')::int)::int
  from jsonb_array_elements(p_items) x
  group by (x->>'product_id')::uuid;

  if exists(select 1 from shopora_cart_v52 where quantity<=0)
    then raise exception 'Invalid quantity'; end if;

  if (select count(*) from shopora_cart_v52)=0
    then raise exception 'Cart is empty'; end if;

  -- Lock every product before calculating totals.
  for r in
    select c.product_id,c.quantity,p.shop_id,p.price,p.stock,p.name,p.status,
           sh.owner_id,sh.name shop_name
    from shopora_cart_v52 c
    join public.products p on p.id=c.product_id
    join public.shops sh on sh.id=p.shop_id
    for update of p
  loop
    if r.status<>'active' then raise exception 'Product "%" is no longer available',r.name; end if;
    if r.stock<r.quantity then raise exception 'Not enough stock for %',r.name; end if;
    if r.owner_id=u then raise exception 'You cannot buy from your own shop'; end if;
    subtotal:=subtotal+(r.price*r.quantity);
  end loop;

  if (select count(*) from shopora_cart_v52 c join public.products p on p.id=c.product_id)
     <> (select count(*) from shopora_cart_v52) then
    raise exception 'One or more products are unavailable';
  end if;

  -- Validate one seller payment method for every seller in the cart.
  for s in
    select sh.id,sh.name,sh.payment_methods,sh.shipping_fee,sh.free_shipping_from,
           coalesce(sum(p.price*c.quantity),0) shop_subtotal
    from shopora_cart_v52 c
    join public.products p on p.id=c.product_id
    join public.shops sh on sh.id=p.shop_id
    group by sh.id,sh.name,sh.payment_methods,sh.shipping_fee,sh.free_shipping_from
  loop
    method_name:=trim(coalesce(p_payment_methods->>s.id::text,''));
    if method_name='' then
      raise exception 'Select a payment method for %',s.name;
    end if;

    select x into m
    from jsonb_array_elements(coalesce(s.payment_methods,'[]'::jsonb)) x
    where lower(trim(coalesce(x->>'name','')))=lower(method_name)
    limit 1;

    if m is null then
      raise exception 'Payment method "%" is not available for %',method_name,s.name;
    end if;
  end loop;

  if p_coupon is not null and btrim(p_coupon)<>'' then
    select case when c.discount_type='percent'
      then least(subtotal,subtotal*c.discount_value/100)
      else least(subtotal,c.discount_value) end
    into discount
    from public.coupons c
    where upper(c.code)=upper(btrim(p_coupon))
      and c.active
      and c.starts_at<=now()
      and (c.ends_at is null or c.ends_at>=now())
      and subtotal>=c.min_spend
      and (c.max_uses is null or c.used_count<c.max_uses);
    discount:=coalesce(discount,0);
  end if;

  for s in
    select sh.id,sh.name,sh.payment_methods,sh.shipping_fee,sh.free_shipping_from,
           coalesce(sum(p.price*c.quantity),0) shop_subtotal
    from shopora_cart_v52 c
    join public.products p on p.id=c.product_id
    join public.shops sh on sh.id=p.shop_id
    group by sh.id,sh.name,sh.payment_methods,sh.shipping_fee,sh.free_shipping_from
  loop
    shop_shipping:=case
      when s.free_shipping_from is not null
       and s.shop_subtotal>=s.free_shipping_from then 0
      else coalesce(s.shipping_fee,0) end;
    shipping:=shipping+shop_shipping;
  end loop;

  order_no:='SHP-'||to_char(now(),'YYYYMMDDHH24MISS')||'-'||upper(substr(gen_random_uuid()::text,1,6));

  insert into public.orders(
    customer_id,order_number,address_id,
    subtotal,subtotal_mur,shipping_total,shipping_mur,
    discount_total,discount_mur,total,total_mur,
    status,payment_status,payment_method,payment_reference,
    payment_proof_url,delivery_snapshot
  )
  values(
    u,order_no,(p_address->>'id')::uuid,
    subtotal,subtotal,shipping,shipping,
    discount,discount,subtotal+shipping-discount,subtotal+shipping-discount,
    'payment_pending','pending','Multiple seller payment methods',
    nullif(trim(p_payment_reference),''),
    p_payment_proof,v_address
  )
  returning * into o;

  -- Decrease stock once per unique product and make sold-out products
  -- disappear from the public catalogue.
  for r in
    select c.product_id,c.quantity,p.shop_id,p.price,p.name
    from shopora_cart_v52 c
    join public.products p on p.id=c.product_id
  loop
    update public.products
    set stock=stock-r.quantity,
        sales_count=sales_count+r.quantity,
        status=case when stock-r.quantity<=0 then 'out_of_stock' else 'active' end,
        updated_at=now()
    where id=r.product_id;

    insert into public.order_items(
      order_id,product_id,shop_id,product_name,image_url,
      unit_price,quantity,line_total
    )
    values(
      o.id,r.product_id,r.shop_id,r.name,
      (select pi.image_url from public.product_images pi
       where pi.product_id=r.product_id order by pi.sort_order,pi.id limit 1),
      r.price,r.quantity,r.price*r.quantity
    );
  end loop;

  for s in
    select sh.id,sh.name,sh.owner_id,sh.payment_methods,sh.shipping_fee,sh.free_shipping_from,
           coalesce(sum(p.price*c.quantity),0) shop_subtotal
    from shopora_cart_v52 c
    join public.products p on p.id=c.product_id
    join public.shops sh on sh.id=p.shop_id
    group by sh.id,sh.name,sh.owner_id,sh.payment_methods,sh.shipping_fee,sh.free_shipping_from
  loop
    method_name:=trim(p_payment_methods->>s.id::text);
    select x into m from jsonb_array_elements(coalesce(s.payment_methods,'[]'::jsonb)) x
      where lower(trim(coalesce(x->>'name','')))=lower(method_name) limit 1;
    method_details:=coalesce(m->>'details','');

    shop_shipping:=case when s.free_shipping_from is not null
      and s.shop_subtotal>=s.free_shipping_from then 0
      else coalesce(s.shipping_fee,0) end;

    insert into public.seller_orders(
      order_id,shop_id,seller_id,subtotal,shipping,total,status,payment_status,
      payment_method_snapshot,payment_details_snapshot
    )
    values(
      o.id,s.id,s.owner_id,s.shop_subtotal,shop_shipping,
      s.shop_subtotal+shop_shipping,'payment_pending','pending',
      method_name,method_details
    )
    returning id into r;

    insert into public.notifications(
      user_id,order_id,seller_order_id,type,title,message
    )
    values(
      s.owner_id,o.id,r.id,'new_order','New order received',
      'A customer placed an order containing products from your shop.'
    );
  end loop;

  insert into public.notifications(user_id,order_id,type,title,message)
  values(
    u,o.id,'order','Order placed',
    'Your order was placed successfully and is waiting for seller payment confirmation.'
  );

  if p_coupon is not null and btrim(p_coupon)<>'' then
    update public.coupons set used_count=used_count+1
    where upper(code)=upper(btrim(p_coupon));
  end if;

  return o;
end $$;

grant execute on function public.create_shopora_order_v52(jsonb,jsonb,jsonb,text,text,text) to authenticated;

-- Keep the old RPC usable for older frontend copies. It maps the one selected
-- method to every seller; the V52 frontend uses the per-seller method map.
drop function if exists public.create_shopora_order(jsonb,jsonb,text,text,text,text);
create function public.create_shopora_order(
 p_items jsonb,p_address jsonb,p_payment_method text,
 p_payment_reference text,p_payment_proof text default null,p_coupon text default null
) returns public.orders
language plpgsql security definer set search_path=public as $$
declare methods jsonb:='{}'::jsonb; x jsonb; sid text;
begin
 for x in
   select distinct p.shop_id::text sid
   from jsonb_array_elements(p_items) i
   join public.products p on p.id=(i->>'product_id')::uuid
 loop
   methods:=jsonb_set(methods,array[x.sid],to_jsonb(trim(p_payment_method)),true);
 end loop;
 return public.create_shopora_order_v52(
   p_items,p_address,methods,p_payment_reference,p_payment_proof,p_coupon
 );
end $$;

grant execute on function public.create_shopora_order(jsonb,jsonb,text,text,text,text) to authenticated;

notify pgrst,'reload schema';

notify pgrst,'reload schema';


-- V54 public store browsing: anonymous/customers may open active seller stores.
grant execute on function public.get_shopora_shop(uuid) to anon, authenticated;
grant execute on function public.get_shopora_catalog(text,uuid,uuid,text,numeric,numeric,int,int) to anon, authenticated;
notify pgrst,'reload schema';


-- =====================================================================
-- SHOPORA V56
-- 1) Explicit seller cover-photo support / storage hardening
-- 2) Legacy order_items.unit_price_mur compatibility
-- =====================================================================

alter table public.shops add column if not exists cover_url text;
alter table public.shops add column if not exists logo_url text;

do $$
begin
  if exists(select 1 from storage.buckets where id='shop-media') then
    update storage.buckets
    set public=true,
        file_size_limit=10485760,
        allowed_mime_types=array['image/jpeg','image/png','image/webp']
    where id='shop-media';
  else
    insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
    values('shop-media','shop-media',true,10485760,
           array['image/jpeg','image/png','image/webp']);
  end if;
end $$;

drop policy if exists shop_media_public_read on storage.objects;
drop policy if exists shop_media_public_read on storage.objects;
drop policy if exists shop_media_public_read on storage.objects;
create policy shop_media_public_read on storage.objects
for select using(bucket_id='shop-media');

drop policy if exists shop_media_owner_write on storage.objects;
drop policy if exists shop_media_owner_write on storage.objects;
drop policy if exists shop_media_owner_write on storage.objects;
create policy shop_media_owner_write on storage.objects
for all to authenticated
using(bucket_id='shop-media'
      and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='shop-media'
      and (storage.foldername(name))[1]=auth.uid()::text);

-- Some earlier Shopora database versions used unit_price_mur.
-- Keep both names synchronized so old rows/functions cannot break checkout.
alter table public.order_items
  add column if not exists unit_price_mur numeric(12,2) default 0;

alter table public.order_items
  alter column unit_price_mur set default 0;

update public.order_items
set unit_price_mur=coalesce(unit_price,unit_price_mur,0)
where unit_price_mur is null;

create or replace function public.shopora_sync_order_item_price()
returns trigger
language plpgsql
as $$
begin
  if new.unit_price is null and new.unit_price_mur is not null then
    new.unit_price := new.unit_price_mur;
  end if;
  if new.unit_price_mur is null and new.unit_price is not null then
    new.unit_price_mur := new.unit_price;
  end if;
  return new;
end $$;

drop trigger if exists shopora_sync_order_item_price on public.order_items;
drop trigger if exists shopora_sync_order_item_price on public.order_items;
drop trigger if exists shopora_sync_order_item_price on public.order_items;
create trigger shopora_sync_order_item_price before insert or update on public.order_items
for each row execute function public.shopora_sync_order_item_price();

notify pgrst,'reload schema';


-- =====================================================================
-- SHOPORA V57
-- Orders visibility + seller onboarding + seller order management
-- =====================================================================

-- Customer order history must include seller packages. The old SQL
-- function used SECURITY INVOKER, so customer RLS hid seller_orders rows.
create or replace function public.get_shopora_customer_orders(p_status text default null)
returns table(
  order_id uuid, order_number text, total numeric, status text,
  payment_status text, created_at timestamptz, delivery jsonb, packages jsonb
)
language sql
stable
security definer
set search_path=public
as $$
  select
    o.id,o.order_number,o.total,o.status,o.payment_status,o.created_at,o.delivery_snapshot,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',so.id,
          'shop_id',so.shop_id,
          'shop_name',s.name,
          'total',so.total,
          'status',so.status,
          'payment_status',so.payment_status,
          'tracking',so.tracking_number,
          'carrier',so.carrier,
          'items',coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id',oi.id,
                'name',oi.product_name,
                'quantity',oi.quantity,
                'price',oi.unit_price,
                'image',oi.image_url
              ) order by oi.created_at
            )
            from public.order_items oi
            where oi.order_id=o.id and oi.shop_id=so.shop_id
          ),'[]'::jsonb)
        ) order by so.created_at
      )
      from public.seller_orders so
      join public.shops s on s.id=so.shop_id
      where so.order_id=o.id
    ),'[]'::jsonb)
  from public.orders o
  where o.customer_id=auth.uid()
    and (p_status is null or o.status=p_status)
  order by o.created_at desc;
$$;

-- Seller order management is also security-definer, while still restricting
-- every result and mutation to the authenticated shop owner.
create or replace function public.get_shopora_seller_orders(
  p_status text default null,
  p_search text default ''
)
returns table(
  seller_order_id uuid, order_id uuid, order_number text,
  customer_id uuid, customer_name text, customer_phone text,
  delivery jsonb, subtotal numeric, shipping numeric, total numeric,
  status text, payment_status text, payment_method text,
  payment_details text, payment_proof text, tracking_number text,
  carrier text, created_at timestamptz, items jsonb
)
language sql
stable
security definer
set search_path=public
as $$
  select
    so.id,o.id,o.order_number,o.customer_id,
    coalesce(pr.full_name,'Customer'),coalesce(pr.phone,''),
    o.delivery_snapshot,so.subtotal,so.shipping,so.total,
    so.status,so.payment_status,so.payment_method_snapshot,
    so.payment_details_snapshot,o.payment_proof_url,
    so.tracking_number,so.carrier,so.created_at,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',oi.id,'name',oi.product_name,
          'quantity',oi.quantity,'price',oi.unit_price,'image',oi.image_url
        ) order by oi.created_at
      )
      from public.order_items oi
      where oi.order_id=o.id and oi.shop_id=so.shop_id
    ),'[]'::jsonb)
  from public.seller_orders so
  join public.orders o on o.id=so.order_id
  left join public.profiles pr on pr.id=o.customer_id
  where so.seller_id=auth.uid()
    and (p_status is null or so.status=p_status)
    and (
      coalesce(p_search,'')=''
      or o.order_number ilike '%'||p_search||'%'
      or coalesce(pr.full_name,'') ilike '%'||p_search||'%'
      or coalesce(pr.phone,'') ilike '%'||p_search||'%'
    )
  order by so.created_at desc;
$$;

-- Explicit RPC permissions. Without these PostgREST can reject the calls
-- even when the functions themselves are correct.
grant execute on function public.get_shopora_customer_orders(text) to authenticated;
grant execute on function public.get_shopora_seller_orders(text,text) to authenticated;
grant execute on function public.seller_set_shopora_order_status(uuid,text,text,text,text) to authenticated;
grant execute on function public.seller_confirm_shopora_payment(uuid) to authenticated;
grant execute on function public.customer_confirm_shopora_received(uuid) to authenticated;
grant execute on function public.save_shopora_shop(text,text,text,text,text,text,numeric,numeric) to authenticated;

notify pgrst,'reload schema';


-- Shopora V57.4 seller profile compatibility fix.
-- Some existing Shopora databases use shops.shop_name while newer code uses shops.name.
-- This function supports either/both columns and avoids the NOT NULL shop_name failure.
drop function if exists public.save_shopora_shop(text,text,text,text,text,text,numeric,numeric);

create or replace function public.save_shopora_shop(
 p_name text,
 p_description text,
 p_address text,
 p_phone text,
 p_logo text,
 p_cover text,
 p_shipping numeric,
 p_free numeric
) returns public.shops
language plpgsql
security definer
set search_path=public
as $$
declare
 u uuid := auth.uid();
 existing_id uuid;
 outrow public.shops;
 has_name boolean;
 has_shop_name boolean;
 has_slug boolean;
 has_description boolean;
 has_address boolean;
 has_phone boolean;
 has_logo boolean;
 has_cover boolean;
 has_shipping boolean;
 has_free boolean;
 q text;
 setq text := '';
 cols text := 'owner_id';
 vals text := '$1';
begin
 if u is null then raise exception 'Login required'; end if;
 if nullif(trim(coalesce(p_name,'')),'') is null then
   raise exception 'Shop name is required';
 end if;

 select exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='name'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='shop_name'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='slug'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='description'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='address'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='phone'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='logo_url'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='cover_url'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='shipping_fee'),
        exists(select 1 from information_schema.columns where table_schema='public' and table_name='shops' and column_name='free_shipping_from')
 into has_name,has_shop_name,has_slug,has_description,has_address,has_phone,has_logo,has_cover,has_shipping,has_free;

 select id into existing_id from public.shops where owner_id=u limit 1;

 if existing_id is null then
   if has_name then cols:=cols||',name'; vals:=vals||',$2'; end if;
   if has_shop_name then cols:=cols||',shop_name'; vals:=vals||',$2'; end if;
   if has_slug then cols:=cols||',slug'; vals:=vals||',$3'; end if;
   if has_description then cols:=cols||',description'; vals:=vals||',$4'; end if;
   if has_address then cols:=cols||',address'; vals:=vals||',$5'; end if;
   if has_phone then cols:=cols||',phone'; vals:=vals||',$6'; end if;
   if has_logo then cols:=cols||',logo_url'; vals:=vals||',$7'; end if;
   if has_cover then cols:=cols||',cover_url'; vals:=vals||',$8'; end if;
   if has_shipping then cols:=cols||',shipping_fee'; vals:=vals||',$9'; end if;
   if has_free then cols:=cols||',free_shipping_from'; vals:=vals||',$10'; end if;

   q:=format('insert into public.shops(%s) values(%s) returning *',cols,vals);
   execute q into outrow
     using u,trim(p_name),public.shopora_make_slug(p_name)||'-'||substr(u::text,1,6),
           coalesce(p_description,''),coalesce(p_address,''),coalesce(p_phone,''),
           nullif(p_logo,''),nullif(p_cover,''),greatest(0,coalesce(p_shipping,0)),p_free;
 else
   if has_name then setq:=setq||format('%I=$2,', 'name'); end if;
   if has_shop_name then setq:=setq||format('%I=$2,', 'shop_name'); end if;
   if has_slug then setq:=setq||format('%I=$3,', 'slug'); end if;
   if has_description then setq:=setq||format('%I=$4,', 'description'); end if;
   if has_address then setq:=setq||format('%I=$5,', 'address'); end if;
   if has_phone then setq:=setq||format('%I=$6,', 'phone'); end if;
   if has_logo then setq:=setq||format('%I=coalesce(nullif($7,''''),%I),','logo_url','logo_url'); end if;
   if has_cover then setq:=setq||format('%I=coalesce(nullif($8,''''),%I),','cover_url','cover_url'); end if;
   if has_shipping then setq:=setq||format('%I=$9,','shipping_fee'); end if;
   if has_free then setq:=setq||format('%I=$10,','free_shipping_from'); end if;
   setq:=rtrim(setq,',');
   q:=format('update public.shops set %s where id=$11 returning *',setq);
   execute q into outrow
     using u,trim(p_name),public.shopora_make_slug(p_name)||'-'||substr(u::text,1,6),
           coalesce(p_description,''),coalesce(p_address,''),coalesce(p_phone,''),
           nullif(p_logo,''),nullif(p_cover,''),greatest(0,coalesce(p_shipping,0)),p_free,existing_id;
 end if;

 return outrow;
end $$;



-- SHOPORA V58 — ACCOUNT DELETION HARDENING
-- Called from the client as: rpc('delete_my_shopora_account')
-- Customer data is deleted. Seller accounts with sales history are blocked so
-- historical customer orders/products are not accidentally destroyed.
drop function if exists public.delete_my_shopora_account();
create or replace function public.delete_my_shopora_account()
returns void
language plpgsql
security definer
set search_path=public,auth
as $$
declare
  u uuid:=auth.uid();
  seller_shop uuid;
  seller_history boolean:=false;
begin
  if u is null then raise exception 'Login required'; end if;

  select id into seller_shop from public.shops where owner_id=u limit 1;
  if seller_shop is not null then
    select exists(select 1 from public.seller_orders where seller_id=u)
        or exists(select 1 from public.products p join public.order_items oi on oi.product_id=p.id where p.shop_id=seller_shop)
      into seller_history;
    if seller_history then
      raise exception 'This seller account has sales history and cannot be deleted automatically. Contact support to close the seller account safely.';
    end if;
    delete from public.shops where id=seller_shop;
  end if;

  -- Customer-owned records. Orders cascade into their items/seller packages/notifications.
  delete from public.orders where customer_id=u;
  delete from public.return_requests where customer_id=u;
  delete from public.reviews where customer_id=u;
  delete from public.wishlists where user_id=u;
  delete from public.addresses where user_id=u;
  delete from public.notifications where user_id=u;
  delete from public.profiles where id=u;

  delete from auth.users where id=u;
end;
$$;

grant execute on function public.delete_my_shopora_account() to authenticated;
notify pgrst,'reload schema';
-- SHOPORA SECURITY HARDENING
-- Run this AFTER the main SHOPORA.sql migration.
-- This migration is designed to reduce the public Data API attack surface,
-- keep seller/customer authorization inside the database, and prevent public
-- shop RPCs from leaking private seller payment-method JSON.

begin;

-- ---------------------------------------------------------------------------
-- 1) Never expose seller payment methods through public shop/product RPCs.
--    Checkout already has a dedicated RPC that returns only the methods needed
--    for the authenticated buyer's checkout flow.
-- ---------------------------------------------------------------------------
create or replace function public.get_shopora_product(p_product uuid)
returns jsonb
language sql stable security invoker
as $$
  select jsonb_build_object(
    'product', jsonb_build_object(
      'id',p.id,'name',p.name,'description',p.description,
      'price',p.price,'price_mur',p.price_mur,'compare_price',p.compare_price,
      'stock',p.stock,'rating',p.rating,'review_count',p.review_count,
      'sales_count',p.sales_count,'shop_id',p.shop_id,'category_id',p.category_id,
      'brand',p.brand,'sku',p.sku,'status',p.status,'slug',p.slug,
      'created_at',p.created_at,'updated_at',p.updated_at
    ),
    'shop', jsonb_build_object(
      'id',s.id,'name',s.name,'slug',s.slug,'description',s.description,
      'address',s.address,'phone',s.phone,'logo_url',s.logo_url,
      'cover_url',s.cover_url,'shipping_fee',s.shipping_fee,
      'free_shipping_from',s.free_shipping_from,'active',s.active
    ),
    'category',to_jsonb(c),
    'images',coalesce((
      select jsonb_agg(to_jsonb(pi) order by pi.sort_order,pi.id)
      from public.product_images pi where pi.product_id=p.id
    ),'[]'::jsonb),
    'reviews',coalesce((
      select jsonb_agg(x.review_json order by x.created_at desc)
      from (
        select jsonb_build_object(
          'rating',r.rating,'title',r.title,'body',r.body,
          'created_at',r.created_at,
          'customer',coalesce(pr.full_name,'Customer')
        ) as review_json,r.created_at
        from public.reviews r
        left join public.profiles pr on pr.id=r.customer_id
        where r.product_id=p.id
        order by r.created_at desc
        limit 50
      ) x
    ),'[]'::jsonb)
  )
  from public.products p
  join public.shops s on s.id=p.shop_id
  left join public.categories c on c.id=p.category_id
  where p.id=p_product and p.status<>'archived';
$$;

create or replace function public.get_shopora_shop(p_shop uuid)
returns jsonb
language sql stable security definer
set search_path=public
as $$
  select jsonb_build_object(
    'shop',jsonb_build_object(
      'id',s.id,'name',s.name,'slug',s.slug,'description',s.description,
      'address',s.address,'phone',s.phone,'logo_url',s.logo_url,
      'cover_url',s.cover_url,'shipping_fee',s.shipping_fee,
      'free_shipping_from',s.free_shipping_from,'active',s.active
    ),
    'products',coalesce((
      select jsonb_agg(x)
      from public.get_shopora_catalog('',null,s.id,'newest',null,null,100,0) x
    ),'[]'::jsonb)
  )
  from public.shops s
  where s.id=p_shop and s.active;
$$;

-- ---------------------------------------------------------------------------
-- 2) Close the default EXECUTE surface.
--    Supabase recommends granting function execution only where needed.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
revoke execute on all functions in schema public from authenticated;

-- Public catalog functions.
grant execute on function public.get_shopora_catalog(text,uuid,uuid,text,numeric,numeric,int,int) to anon, authenticated;
grant execute on function public.get_shopora_shop(uuid) to anon, authenticated;
grant execute on function public.get_shopora_product(uuid) to anon, authenticated;

-- Authenticated customer functions.
grant execute on function public.create_shopora_order_v52(jsonb,jsonb,jsonb,text,text,text) to authenticated;
grant execute on function public.create_shopora_order(jsonb,jsonb,text,text,text,text) to authenticated;
grant execute on function public.get_shopora_checkout_payment_options(jsonb) to authenticated;
grant execute on function public.get_shopora_customer_orders(text) to authenticated;
grant execute on function public.get_shopora_notifications() to authenticated;
grant execute on function public.mark_shopora_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_shopora_notifications_read() to authenticated;
grant execute on function public.clear_shopora_notifications() to authenticated;
grant execute on function public.customer_confirm_shopora_received(uuid) to authenticated;
grant execute on function public.save_shopora_address(uuid,text,text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.delete_shopora_address(uuid) to authenticated;
grant execute on function public.toggle_shopora_wishlist(uuid) to authenticated;
grant execute on function public.get_shopora_wishlist() to authenticated;
grant execute on function public.delete_my_shopora_account() to authenticated;

-- Authenticated seller functions.
grant execute on function public.shopora_is_shop_owner(uuid,uuid) to authenticated;
grant execute on function public.get_shopora_seller_products() to authenticated;
grant execute on function public.get_shopora_seller_orders(text,text) to authenticated;
grant execute on function public.save_shopora_shop(text,text,text,text,text,text,numeric,numeric) to authenticated;
grant execute on function public.save_shopora_payment_methods(jsonb) to authenticated;
grant execute on function public.save_shopora_product_v46(uuid,text,uuid,numeric,numeric,integer,text,text,text,jsonb) to authenticated;
grant execute on function public.delete_shopora_product(uuid) to authenticated;
grant execute on function public.seller_confirm_shopora_payment(uuid) to authenticated;
grant execute on function public.seller_set_shopora_order_status(uuid,text,text,text,text) to authenticated;

-- Prevent future functions from automatically becoming callable through the
-- Data API. Explicit grants above are then required for each new RPC.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges in schema public revoke execute on functions from authenticated;

-- ---------------------------------------------------------------------------
-- 3) Defense-in-depth: make sure the important user-owned tables have RLS.
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.addresses enable row level security;
alter table public.wishlists enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.seller_orders enable row level security;
alter table public.notifications enable row level security;
alter table public.return_requests enable row level security;
alter table public.reviews enable row level security;

notify pgrst,'reload schema';
commit;
