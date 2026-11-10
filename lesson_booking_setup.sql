-- ANI DRIVE: օնլայն դասաժամերի ամրագրում
create table if not exists public.lesson_slots (
  id uuid primary key default gen_random_uuid(),
  slot_date date not null,
  slot_time time not null,
  is_available boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(slot_date, slot_time)
);

create table if not exists public.lesson_bookings (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.lesson_slots(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  student_name text not null,
  student_email text not null,
  student_phone text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  unique(slot_id)
);

create index if not exists lesson_bookings_student_idx
  on public.lesson_bookings(student_id, created_at desc);

alter table public.lesson_slots enable row level security;
alter table public.lesson_bookings enable row level security;

drop policy if exists "Read available lesson slots" on public.lesson_slots;
create policy "Read available lesson slots" on public.lesson_slots
for select to authenticated
using (is_available = true or exists (
  select 1 from public.admins a where a.user_id = auth.uid()
));

drop policy if exists "Admins manage lesson slots" on public.lesson_slots;
create policy "Admins manage lesson slots" on public.lesson_slots
for all to authenticated
using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));

drop policy if exists "Students read own bookings and admins read all" on public.lesson_bookings;
create policy "Students read own bookings and admins read all" on public.lesson_bookings
for select to authenticated
using (student_id = auth.uid() or exists (
  select 1 from public.admins a where a.user_id = auth.uid()
));

drop policy if exists "Students create own bookings" on public.lesson_bookings;
create policy "Students create own bookings" on public.lesson_bookings
for insert to authenticated
with check (
  student_id = auth.uid()
  and exists (select 1 from public.students s where s.id = auth.uid())
  and exists (
    select 1 from public.lesson_slots sl
    where sl.id = slot_id and sl.is_available = true
  )
);

drop policy if exists "Admins update bookings" on public.lesson_bookings;
create policy "Admins update bookings" on public.lesson_bookings
for update to authenticated
using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));

-- Նոր հայտը ժամանակավորապես զբաղեցնում է ժամը, մերժման դեպքում ազատում է։
create or replace function public.sync_lesson_slot_availability()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.lesson_slots set is_available = false where id = new.slot_id;
    return new;
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    if new.status = 'rejected' then
      update public.lesson_slots set is_available = true where id = new.slot_id;
    elsif new.status in ('pending','approved') then
      update public.lesson_slots set is_available = false where id = new.slot_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    update public.lesson_slots set is_available = true where id = old.slot_id;
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists lesson_booking_slot_sync on public.lesson_bookings;
create trigger lesson_booking_slot_sync
after insert or update of status or delete on public.lesson_bookings
for each row execute function public.sync_lesson_slot_availability();
