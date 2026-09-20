-- =====================================================================
-- buahmurah.id — Skema Supabase v5
-- Project: https://uuorhkhpubkvsilsybvw.supabase.co
--
-- Jalankan SELURUH isi berkas ini di Supabase Dashboard > SQL Editor > Run.
-- Aman dijalankan berulang kali.
--
-- Berkas ini sekaligus MEMBUAT DUA AKUN LOGIN:
--   panglima@gmail.com      -> manajemen   (kata sandi: Panglima2026)
--   buahmurah.id@gmail.com  -> kasir       (kata sandi: Kasir2026)
-- Ganti kata sandi di bagian 3 sebelum Run kalau mau kata sandi lain.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. PROFIL PENGGUNA
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  nama       text not null default '',
  role       text not null default 'kasir',
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists email     text;
alter table public.profiles add column if not exists jabatan   text not null default '';
alter table public.profiles add column if not exists hak_akses text[] not null default '{}';
alter table public.profiles add column if not exists aktif     boolean not null default true;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('kasir','manajemen'));

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id and (p.email is null or p.email = '');

-- ---------------------------------------------------------------------
-- 2. PROFIL OTOMATIS SAAT USER BARU DIBUAT
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare hak text[];
begin
  if new.raw_user_meta_data ? 'hak_akses' then
    hak := array(select jsonb_array_elements_text(new.raw_user_meta_data->'hak_akses'));
  else
    hak := '{}';
  end if;

  insert into public.profiles (id, email, nama, jabatan, role, hak_akses)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'nama',''), split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'jabatan',''),
    coalesce(nullif(new.raw_user_meta_data->>'role',''), 'kasir'),
    hak
  )
  on conflict (id) do update
    set email   = excluded.email,
        nama    = excluded.nama,
        jabatan = excluded.jabatan,
        role    = excluded.role;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_user_email_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set email = new.email where id = new.id;
  return new;
end $$;

drop trigger if exists on_auth_user_email_change on auth.users;
create trigger on_auth_user_email_change
  after update of email on auth.users
  for each row execute function public.handle_user_email_change();

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_manajemen()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'manajemen', false)
$$;

-- ---------------------------------------------------------------------
-- 3. >>> MEMBUAT DUA AKUN LOGIN <<<
-- ---------------------------------------------------------------------
create or replace function public.buat_akun_awal(
  p_email text, p_sandi text, p_nama text, p_jabatan text, p_role text)
returns uuid
language plpgsql security definer
set search_path = public, auth, extensions as $$
declare uid uuid;
begin
  select id into uid from auth.users where lower(email) = lower(p_email);

  if uid is null then
    uid := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      lower(p_email), crypt(p_sandi, gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('nama', p_nama, 'jabatan', p_jabatan, 'role', p_role),
      '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), uid, uid::text,
      jsonb_build_object('sub', uid::text, 'email', lower(p_email),
                         'email_verified', true, 'phone_verified', false),
      'email', now(), now(), now()
    );
  else
    -- Akun sudah ada: setel ulang kata sandi dan pastikan emailnya terkonfirmasi
    update auth.users set
      encrypted_password = crypt(p_sandi, gen_salt('bf')),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      raw_user_meta_data = jsonb_build_object('nama', p_nama, 'jabatan', p_jabatan, 'role', p_role),
      updated_at = now()
    where id = uid;
  end if;

  insert into public.profiles (id, email, nama, jabatan, role)
  values (uid, lower(p_email), p_nama, p_jabatan, p_role)
  on conflict (id) do update
    set email = excluded.email, nama = excluded.nama,
        jabatan = excluded.jabatan, role = excluded.role;

  return uid;
end $$;

--        email                  kata sandi      nama              jabatan   role
select public.buat_akun_awal('panglima@gmail.com',     'Panglima2026', 'Panglima',      'Pemilik', 'manajemen');
select public.buat_akun_awal('buahmurah.id@gmail.com', 'Kasir2026',    'Kasir Toko',    'Kasir',   'kasir');

drop function public.buat_akun_awal(text, text, text, text, text);

-- Cek hasilnya:
--   select email, nama, jabatan, role from public.profiles order by role;

-- ---------------------------------------------------------------------
-- 4. MASTER BUAH — satu tabel untuk stok sekaligus daftar pilihan kasir
--    (v4: tabel jenis_buah dihapus supaya kasir dan manajemen tidak beda data)
-- ---------------------------------------------------------------------
create table if not exists public.stock_buah (
  id         bigint generated always as identity primary key,
  jenis_buah text not null,
  jumlah     numeric(14,2) not null default 0,
  satuan     text not null default 'Kg',
  updated_at timestamptz not null default now()
);

alter table public.stock_buah add column if not exists harga numeric(14,2) not null default 0;
alter table public.stock_buah add column if not exists aktif boolean not null default true;

-- Pindahkan harga dari tabel lama (kalau masih ada), lalu buang tabelnya.
do $$
begin
  if to_regclass('public.jenis_buah') is not null then
    update public.stock_buah s
    set harga = j.harga
    from public.jenis_buah j
    where s.jenis_buah = j.nama and s.harga = 0;

    drop table public.jenis_buah cascade;
  end if;
end $$;

-- Satu nama buah cukup satu baris: buang kembaran dulu, baru dikunci.
delete from public.stock_buah a
using public.stock_buah b
where a.jenis_buah = b.jenis_buah and a.id > b.id;

create unique index if not exists stock_buah_nama_uniq on public.stock_buah (jenis_buah);

-- ---------------------------------------------------------------------
-- 5. TRANSAKSI KASIR
-- ---------------------------------------------------------------------
create table if not exists public.penjualan (
  id         bigint generated always as identity primary key,
  tanggal    date not null default current_date,
  jenis_buah text not null,
  qty        numeric(14,2) not null default 0,
  satuan     text not null default 'Kg',
  harga      numeric(14,2) not null default 0,
  total      numeric(14,2) generated always as (qty * harga) stored,
  pembayaran text,
  user_id    uuid not null default auth.uid() references auth.users on delete set default,
  created_at timestamptz not null default now()
);

alter table public.penjualan add column if not exists bukti_url text;
update public.penjualan set pembayaran = 'Cash' where pembayaran is null;
alter table public.penjualan drop constraint if exists penjualan_pembayaran_check;
alter table public.penjualan alter column pembayaran set not null;
alter table public.penjualan add constraint penjualan_pembayaran_check
  check (pembayaran in ('Cash','Transfer'));

create table if not exists public.pengeluaran (
  id         bigint generated always as identity primary key,
  tanggal    date not null default current_date,
  keterangan text not null,
  nominal    numeric(14,2) not null default 0,
  user_id    uuid not null default auth.uid() references auth.users on delete set default,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 6. PEMBUKUAN MANAJEMEN
-- ---------------------------------------------------------------------
create table if not exists public.cashflow (
  id         bigint generated always as identity primary key,
  nomor      integer not null default 1,
  tanggal    date not null default current_date,
  keterangan text not null default '',
  debit      numeric(14,2) not null default 0,
  kredit     numeric(14,2) not null default 0,
  bukti_url  text,
  created_at timestamptz not null default now()
);

-- Kulakan hanya berisi pengeluaran belanja, jadi tidak memakai debit/kredit.
create table if not exists public.kulakan (
  id         bigint generated always as identity primary key,
  nomor      integer not null default 1,
  tanggal    date not null default current_date,
  keterangan text not null default '',
  bukti_url  text,
  created_at timestamptz not null default now()
);

alter table public.kulakan add column if not exists jumlah numeric(14,2) not null default 0;
alter table public.kulakan add column if not exists satuan text not null default 'Kg';
alter table public.kulakan add column if not exists harga  numeric(14,2) not null default 0;

-- Data lama: nilai kredit dipindah jadi harga, lalu kolom debit/kredit dibuang.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='kulakan' and column_name='kredit') then
    update public.kulakan
    set jumlah = case when jumlah = 0 then 1 else jumlah end,
        harga  = case when harga = 0 then kredit else harga end
    where kredit > 0;

    alter table public.kulakan drop column kredit;
    alter table public.kulakan drop column debit;
  end if;
end $$;

create table if not exists public.gaji (
  id         bigint generated always as identity primary key,
  nomor      integer not null default 1,
  nama       text not null default '',
  bulan      text not null default to_char(current_date,'YYYY-MM'),
  absensi    integer not null default 0,
  total_hari integer not null default 0,
  kasbon     numeric(14,2) not null default 0,
  total      numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_opname (
  id         bigint generated always as identity primary key,
  nomor      integer not null default 1,
  tanggal    date not null default current_date,
  keterangan text not null default '',
  kondisi    text not null default 'Baik' check (kondisi in ('Baik','Rusak')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7. NOTIFIKASI — kabar dari kasir untuk manajemen
-- ---------------------------------------------------------------------
create table if not exists public.notifikasi (
  id         bigint generated always as identity primary key,
  judul      text not null,
  pesan      text not null default '',
  jenis      text not null default 'umum',
  nominal    numeric(14,2),
  untuk_role text not null default 'manajemen',
  ref_tabel  text,
  ref_id     bigint,
  dari_nama  text,
  dibaca     boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifikasi_baru_idx
  on public.notifikasi (untuk_role, dibaca, created_at desc);

-- Penjualan masuk -> kabari manajemen
create or replace function public.notif_penjualan()
returns trigger language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  select coalesce(nullif(nama,''), email, 'Kasir') into nm
  from public.profiles where id = new.user_id;

  insert into public.notifikasi (judul, pesan, jenis, nominal, untuk_role, ref_tabel, ref_id, dari_nama)
  values (
    'Penjualan baru',
    coalesce(nm,'Kasir') || ' menjual ' || new.jenis_buah || ' (' || new.pembayaran || ')',
    'penjualan', new.qty * new.harga, 'manajemen', 'penjualan', new.id, nm
  );
  return new;
end $$;

drop trigger if exists on_penjualan_notif on public.penjualan;
create trigger on_penjualan_notif
  after insert on public.penjualan
  for each row execute function public.notif_penjualan();

-- Pengeluaran masuk -> kabari manajemen
create or replace function public.notif_pengeluaran()
returns trigger language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  select coalesce(nullif(nama,''), email, 'Kasir') into nm
  from public.profiles where id = new.user_id;

  insert into public.notifikasi (judul, pesan, jenis, nominal, untuk_role, ref_tabel, ref_id, dari_nama)
  values (
    'Pengeluaran baru',
    coalesce(nm,'Kasir') || ': ' || new.keterangan,
    'pengeluaran', new.nominal, 'manajemen', 'pengeluaran', new.id, nm
  );
  return new;
end $$;

drop trigger if exists on_pengeluaran_notif on public.pengeluaran;
create trigger on_pengeluaran_notif
  after insert on public.pengeluaran
  for each row execute function public.notif_pengeluaran();

-- ---------------------------------------------------------------------
-- 7b. STOK OTOMATIS — sisa buah ikut berkurang saat kasir menjual
-- ---------------------------------------------------------------------
create or replace function public.stok_dari_penjualan()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (TG_OP = 'INSERT') then
    update public.stock_buah
      set jumlah = jumlah - new.qty, updated_at = now()
      where jenis_buah = new.jenis_buah;

  elsif (TG_OP = 'DELETE') then
    update public.stock_buah
      set jumlah = jumlah + old.qty, updated_at = now()
      where jenis_buah = old.jenis_buah;

  elsif (TG_OP = 'UPDATE') then
    if old.jenis_buah is distinct from new.jenis_buah then
      -- buah diganti: kembalikan ke yang lama, potong dari yang baru
      update public.stock_buah
        set jumlah = jumlah + old.qty, updated_at = now()
        where jenis_buah = old.jenis_buah;
      update public.stock_buah
        set jumlah = jumlah - new.qty, updated_at = now()
        where jenis_buah = new.jenis_buah;
    elsif old.qty is distinct from new.qty then
      update public.stock_buah
        set jumlah = jumlah - (new.qty - old.qty), updated_at = now()
        where jenis_buah = new.jenis_buah;
    end if;
  end if;
  return null;
end $$;

drop trigger if exists on_penjualan_stok on public.penjualan;
create trigger on_penjualan_stok
  after insert or update or delete on public.penjualan
  for each row execute function public.stok_dari_penjualan();

-- Menyamakan stok dengan riwayat penjualan yang SUDAH ada sebelum trigger dipasang.
-- Jalankan HANYA SEKALI, dan hanya kalau angka stokmu belum memperhitungkan penjualan lama.
-- Hapus tanda komentar di bawah kalau memang mau dipakai.
--
-- update public.stock_buah s
-- set jumlah = s.jumlah - coalesce((
--       select sum(p.qty) from public.penjualan p where p.jenis_buah = s.jenis_buah), 0),
--     updated_at = now();

-- Realtime: supaya notifikasi langsung muncul tanpa muat ulang
do $$ begin
  alter publication supabase_realtime add table public.notifikasi;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

-- ---------------------------------------------------------------------
-- 8. ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.stock_buah   enable row level security;
alter table public.penjualan    enable row level security;
alter table public.pengeluaran  enable row level security;
alter table public.cashflow     enable row level security;
alter table public.kulakan      enable row level security;
alter table public.gaji         enable row level security;
alter table public.stock_opname enable row level security;
alter table public.notifikasi   enable row level security;

drop policy if exists profiles_self on public.profiles;
create policy profiles_self on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_manajemen());
drop policy if exists profiles_kelola on public.profiles;
create policy profiles_kelola on public.profiles
  for update to authenticated using (public.is_manajemen()) with check (public.is_manajemen());
drop policy if exists profiles_tambah on public.profiles;
create policy profiles_tambah on public.profiles
  for insert to authenticated with check (public.is_manajemen());
drop policy if exists profiles_hapus on public.profiles;
create policy profiles_hapus on public.profiles
  for delete to authenticated using (public.is_manajemen() and id <> auth.uid());

drop policy if exists stok_read on public.stock_buah;
create policy stok_read on public.stock_buah for select to authenticated using (true);
drop policy if exists stok_write on public.stock_buah;
create policy stok_write on public.stock_buah
  for all to authenticated using (public.is_manajemen()) with check (public.is_manajemen());

drop policy if exists jual_read on public.penjualan;
create policy jual_read on public.penjualan
  for select to authenticated using (user_id = auth.uid() or public.is_manajemen());
drop policy if exists jual_insert on public.penjualan;
create policy jual_insert on public.penjualan
  for insert to authenticated with check (user_id = auth.uid() or public.is_manajemen());
drop policy if exists jual_update on public.penjualan;
create policy jual_update on public.penjualan
  for update to authenticated
  using (public.is_manajemen()) with check (public.is_manajemen());
drop policy if exists jual_delete on public.penjualan;
create policy jual_delete on public.penjualan
  for delete to authenticated
  using (public.is_manajemen() or (user_id = auth.uid() and created_at > now() - interval '1 day'));

drop policy if exists keluar_read on public.pengeluaran;
create policy keluar_read on public.pengeluaran
  for select to authenticated using (user_id = auth.uid() or public.is_manajemen());
drop policy if exists keluar_insert on public.pengeluaran;
create policy keluar_insert on public.pengeluaran
  for insert to authenticated with check (user_id = auth.uid() or public.is_manajemen());
drop policy if exists keluar_update on public.pengeluaran;
create policy keluar_update on public.pengeluaran
  for update to authenticated
  using (public.is_manajemen()) with check (public.is_manajemen());
drop policy if exists keluar_delete on public.pengeluaran;
create policy keluar_delete on public.pengeluaran
  for delete to authenticated
  using (public.is_manajemen() or (user_id = auth.uid() and created_at > now() - interval '1 day'));

drop policy if exists cf_all on public.cashflow;
create policy cf_all on public.cashflow
  for all to authenticated using (public.is_manajemen()) with check (public.is_manajemen());
drop policy if exists kl_all on public.kulakan;
create policy kl_all on public.kulakan
  for all to authenticated using (public.is_manajemen()) with check (public.is_manajemen());
drop policy if exists gj_all on public.gaji;
create policy gj_all on public.gaji
  for all to authenticated using (public.is_manajemen()) with check (public.is_manajemen());
drop policy if exists so_all on public.stock_opname;
create policy so_all on public.stock_opname
  for all to authenticated using (public.is_manajemen()) with check (public.is_manajemen());

-- Notifikasi hanya bisa dibaca oleh role yang dituju.
-- Barisnya dibuat oleh trigger (security definer), jadi kasir tidak perlu izin insert.
drop policy if exists notif_read on public.notifikasi;
create policy notif_read on public.notifikasi
  for select to authenticated using (untuk_role = public.my_role());
drop policy if exists notif_update on public.notifikasi;
create policy notif_update on public.notifikasi
  for update to authenticated
  using (untuk_role = public.my_role()) with check (untuk_role = public.my_role());
drop policy if exists notif_hapus on public.notifikasi;
create policy notif_hapus on public.notifikasi
  for delete to authenticated using (public.is_manajemen());

-- ---------------------------------------------------------------------
-- 9. STORAGE BUKTI TRANSAKSI
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('bukti','bukti', true)
on conflict (id) do nothing;

drop policy if exists bukti_read on storage.objects;
create policy bukti_read on storage.objects
  for select using (bucket_id = 'bukti');
drop policy if exists bukti_upload on storage.objects;
create policy bukti_upload on storage.objects
  for insert to authenticated with check (bucket_id = 'bukti');

-- ---------------------------------------------------------------------
-- 10. CATATAN
-- ---------------------------------------------------------------------
-- Tidak ada data buah bawaan. Isi sendiri lewat menu Stock Buah di akun
-- manajemen; daftar itulah yang muncul sebagai pilihan di layar kasir.
--
-- Cek isi daftar buah:
--   select jenis_buah, jumlah, satuan, harga, aktif from public.stock_buah order by jenis_buah;
