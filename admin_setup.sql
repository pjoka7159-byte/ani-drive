-- ANI DRIVE admin dashboard extensions
-- Run this complete script in Supabase SQL Editor.
create table if not exists public.site_content (
 id uuid primary key default gen_random_uuid(),
 content_key text not null unique,
 label text not null,
 content_type text not null default 'text',
 content_value text not null,
 updated_at timestamptz not null default now()
);
alter table public.site_content
 add column if not exists is_published boolean not null default true;
alter table public.site_content
 drop constraint if exists site_content_content_type_check;
alter table public.site_content
 add constraint site_content_content_type_check
 check (content_type in ('text','image','video','link'));

create table if not exists public.admin_messages (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 body text not null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
create table if not exists public.media_assets (
 id uuid primary key default gen_random_uuid(),
 file_name text not null,
 title text,
 mime_type text not null,
 storage_path text not null unique,
 public_url text not null,
 uploaded_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);

alter table public.site_content enable row level security;
alter table public.admin_messages enable row level security;
alter table public.media_assets enable row level security;

drop policy if exists "Admins manage site content" on public.site_content;
create policy "Admins manage site content" on public.site_content
 for all to authenticated
 using (exists(select 1 from public.admins a where a.user_id=auth.uid()))
 with check (exists(select 1 from public.admins a where a.user_id=auth.uid()));

drop policy if exists "Public read published site content" on public.site_content;
create policy "Public read published site content" on public.site_content
 for select to anon, authenticated using (is_published = true);

drop policy if exists "Admins manage messages" on public.admin_messages;
create policy "Admins manage messages" on public.admin_messages
 for all to authenticated
 using (exists(select 1 from public.admins a where a.user_id=auth.uid()))
 with check (exists(select 1 from public.admins a where a.user_id=auth.uid()));

drop policy if exists "Admins manage media assets" on public.media_assets;
create policy "Admins manage media assets" on public.media_assets
 for all to authenticated
 using (exists(select 1 from public.admins a where a.user_id=auth.uid()))
 with check (exists(select 1 from public.admins a where a.user_id=auth.uid()));

drop policy if exists "Public read media assets" on public.media_assets;
create policy "Public read media assets" on public.media_assets
 for select to anon, authenticated using (true);

-- Public bucket for website images/videos. Upload/delete remains admin-only.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('site-media','site-media',true,52428800,
 array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set public=true,
 file_size_limit=excluded.file_size_limit,
 allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Public read ANI DRIVE media" on storage.objects;
create policy "Public read ANI DRIVE media" on storage.objects
 for select to anon, authenticated using (bucket_id='site-media');

drop policy if exists "Admins upload ANI DRIVE media" on storage.objects;
create policy "Admins upload ANI DRIVE media" on storage.objects
 for insert to authenticated with check (
  bucket_id='site-media' and exists(select 1 from public.admins a where a.user_id=auth.uid())
);

drop policy if exists "Admins update ANI DRIVE media" on storage.objects;
create policy "Admins update ANI DRIVE media" on storage.objects
 for update to authenticated using (
  bucket_id='site-media' and exists(select 1 from public.admins a where a.user_id=auth.uid())
 ) with check (
  bucket_id='site-media' and exists(select 1 from public.admins a where a.user_id=auth.uid())
);

drop policy if exists "Admins delete ANI DRIVE media" on storage.objects;
create policy "Admins delete ANI DRIVE media" on storage.objects
 for delete to authenticated using (
  bucket_id='site-media' and exists(select 1 from public.admins a where a.user_id=auth.uid())
);

-- Add the two administrator accounts, if they already exist in Supabase Auth.
insert into public.admins(user_id,email)
select id,email from auth.users
where lower(email) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com')
on conflict do nothing;
