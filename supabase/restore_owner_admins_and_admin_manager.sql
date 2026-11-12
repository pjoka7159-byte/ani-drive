-- ANI DRIVE: restore the two owner administrators and enable owner-managed admin accounts.
-- Run this script once in Supabase SQL Editor.

alter table public.admins
  add column if not exists email text;

-- Fill email values for owner rows that may already exist.
update public.admins a
set email = lower(u.email)
from auth.users u
where a.user_id = u.id
  and lower(u.email) in ('pjoka7519@gmail.com', 'graergrigoryan1986@gmail.com');

-- Ensure the two original owner accounts are present in public.admins.
insert into public.admins (user_id, email)
select u.id, lower(u.email)
from auth.users u
where lower(u.email) in ('pjoka7519@gmail.com', 'graergrigoryan1986@gmail.com')
  and not exists (
    select 1 from public.admins a where a.user_id = u.id
  );

-- Only the two owner accounts can read the full admin list and add admins.
alter table public.admins enable row level security;

drop policy if exists "ANI DRIVE owners can view admins" on public.admins;
create policy "ANI DRIVE owners can view admins"
on public.admins
for select
to authenticated
using (
  lower(coalesce(auth.jwt() ->> 'email', '')) in
  ('pjoka7519@gmail.com', 'graergrigoryan1986@gmail.com')
  or user_id = auth.uid()
);

drop policy if exists "ANI DRIVE owners can add admins" on public.admins;
create policy "ANI DRIVE owners can add admins"
on public.admins
for insert
to authenticated
with check (
  lower(coalesce(auth.jwt() ->> 'email', '')) in
  ('pjoka7519@gmail.com', 'graergrigoryan1986@gmail.com')
);

-- Confirm both owner accounts were found and added:
select a.user_id, a.email
from public.admins a
where lower(coalesce(a.email, '')) in
  ('pjoka7519@gmail.com', 'graergrigoryan1986@gmail.com')
order by a.email;
