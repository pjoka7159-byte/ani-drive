-- ANI DRIVE admin extensions
-- Run in Supabase SQL Editor after the existing admins and students tables are created.
create table if not exists public.site_content (
 id uuid primary key default gen_random_uuid(),
 content_key text not null unique,
 label text not null,
 content_type text not null default 'text' check (content_type in ('text','image')),
 content_value text not null,
 updated_at timestamptz not null default now()
);
create table if not exists public.admin_messages (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 body text not null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
alter table public.site_content enable row level security;
alter table public.admin_messages enable row level security;
drop policy if exists "Admins manage site content" on public.site_content;
create policy "Admins manage site content" on public.site_content
 for all to authenticated
 using (exists(select 1 from public.admins a where a.user_id=auth.uid()))
 with check (exists(select 1 from public.admins a where a.user_id=auth.uid()));
drop policy if exists "Admins manage messages" on public.admin_messages;
create policy "Admins manage messages" on public.admin_messages
 for all to authenticated
 using (exists(select 1 from public.admins a where a.user_id=auth.uid()))
 with check (exists(select 1 from public.admins a where a.user_id=auth.uid()));
-- Add the two approved administrator accounts (only accounts already registered in Supabase Auth):
insert into public.admins(user_id,email)
select id,email from auth.users
where lower(email) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com')
on conflict do nothing;
