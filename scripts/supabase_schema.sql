-- ==============================================================================
-- JazzPOS - Supabase Cloud Synchronization Schema
-- Execute this script in the Supabase Dashboard SQL Editor
-- ==============================================================================

-- 1. Enable UUID extension if needed
create extension if not exists "uuid-ossp";

-- 2. Products Table (Master Catalog)
create table if not exists public.products (
    id text primary key,
    name text not null,
    description text,
    default_price_millimes bigint not null default 0,
    default_cost_millimes bigint not null default 0,
    status text not null default 'ACTIVE',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 3. Product Variants Table
create table if not exists public.product_variants (
    id text primary key,
    product_id text not null references public.products(id) on delete cascade,
    sku text not null,
    barcode text not null,
    sale_price_override_millimes bigint,
    cost_price_override_millimes bigint,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint uq_product_variants_sku unique (sku),
    constraint uq_product_variants_barcode unique (barcode)
);

-- 4. Stock Levels Table (Physical store stock count)
create table if not exists public.stock_levels (
    id text primary key,
    variant_id text not null references public.product_variants(id) on delete cascade,
    location_id text not null,
    quantity integer not null default 0,
    updated_at timestamptz not null default now()
);

-- 5. Sales Table (POS Register authoritative)
create table if not exists public.sales (
    id text primary key,
    receipt_number text not null,
    store_id text not null,
    register_id text not null,
    shift_id text not null,
    cashier_id text not null,
    customer_id text,
    subtotal_millimes bigint not null default 0,
    discount_millimes bigint not null default 0,
    tax_millimes bigint not null default 0,
    total_millimes bigint not null default 0,
    status text not null default 'COMPLETED',
    notes text,
    idempotency_key text not null,
    created_at timestamptz not null default now(),
    synced_at timestamptz not null default now(),
    constraint uq_sales_receipt_number unique (receipt_number),
    constraint uq_sales_idempotency unique (idempotency_key)
);

-- 6. Sale Line Items Table
create table if not exists public.sale_lines (
    id text primary key,
    sale_id text not null references public.sales(id) on delete cascade,
    variant_id text not null,
    product_name text not null,
    variant_description text not null default '',
    sku text not null,
    barcode text not null,
    quantity integer not null default 1,
    unit_price_millimes bigint not null default 0,
    total_millimes bigint not null default 0
);

-- 7. Sale Payments Table
create table if not exists public.sale_payments (
    id text primary key,
    sale_id text not null references public.sales(id) on delete cascade,
    payment_method text not null,
    amount_millimes bigint not null default 0,
    tendered_millimes bigint not null default 0,
    change_millimes bigint not null default 0,
    created_at timestamptz not null default now()
);

-- 8. Returns Table
create table if not exists public.returns (
    id text primary key,
    return_number text not null,
    store_id text not null,
    register_id text not null,
    shift_id text not null,
    cashier_id text not null,
    reason text not null,
    total_refund_millimes bigint not null default 0,
    refund_method text not null,
    created_at timestamptz not null default now(),
    constraint uq_returns_number unique (return_number)
);

-- 9. Indexes for High-Performance Queries
create index if not exists idx_products_updated_at on public.products(updated_at);
create index if not exists idx_product_variants_updated_at on public.product_variants(updated_at);
create index if not exists idx_sales_created_at on public.sales(created_at);
create index if not exists idx_sales_store_id on public.sales(store_id);
create index if not exists idx_sale_lines_sale_id on public.sale_lines(sale_id);
create index if not exists idx_sale_payments_sale_id on public.sale_payments(sale_id);

-- 10. Enable Row Level Security (RLS)
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.stock_levels enable row level security;
alter table public.sales enable row level security;
alter table public.sale_lines enable row level security;
alter table public.sale_payments enable row level security;
alter table public.returns enable row level security;

-- Permissive policies for authenticated/anon POS client access
create policy "Allow all for anon and authenticated on products"
    on public.products for all using (true) with check (true);

create policy "Allow all for anon and authenticated on product_variants"
    on public.product_variants for all using (true) with check (true);

create policy "Allow all for anon and authenticated on stock_levels"
    on public.stock_levels for all using (true) with check (true);

create policy "Allow all for anon and authenticated on sales"
    on public.sales for all using (true) with check (true);

create policy "Allow all for anon and authenticated on sale_lines"
    on public.sale_lines for all using (true) with check (true);

create policy "Allow all for anon and authenticated on sale_payments"
    on public.sale_payments for all using (true) with check (true);

create policy "Allow all for anon and authenticated on returns"
    on public.returns for all using (true) with check (true);
