-- ANI DRIVE: student profile fields and student-admin messaging
-- Run this script in Supabase SQL Editor.

alter table public.students
  add column if not exists gender text,
  add column if not exists study_type text,
  add column if not exists residence text;

create table if not exists public.student_messages (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_role text not null check (sender_role in ('student','admin')),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists student_messages_student_created_idx
  on public.student_messages(student_id, created_at);

alter table public.student_messages enable row level security;

drop policy if exists "Students and admins read student messages" on public.student_messages;
create policy "Students and admins read student messages"
on public.student_messages for select to authenticated
using (
  student_id = auth.uid()
  or exists (select 1 from public.admins a where a.user_id = auth.uid())
);

drop policy if exists "Students and admins send messages" on public.student_messages;
create policy "Students and admins send messages"
on public.student_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and (
    (sender_role = 'student' and student_id = auth.uid())
    or
    (sender_role = 'admin' and exists (
      select 1 from public.admins a where a.user_id = auth.uid()
    ))
  )
);

drop policy if exists "Students update own profile" on public.students;
create policy "Students update own profile"
on public.students for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists "Admins update student profiles" on public.students;
create policy "Admins update student profiles"
on public.students for update to authenticated
using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));
