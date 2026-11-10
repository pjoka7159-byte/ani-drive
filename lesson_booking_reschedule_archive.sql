-- ANI DRIVE: lesson booking archive and safe rescheduling
-- Run this script once in Supabase SQL Editor.

alter table public.lesson_bookings
  add column if not exists archived_at timestamptz,
  add column if not exists requested_slot_id uuid references public.lesson_slots(id) on delete set null,
  add column if not exists cancelled_at timestamptz;

-- Authenticated students must be able to see busy slots too, so they can request a time change.
drop policy if exists "Read available lesson slots" on public.lesson_slots;
create policy "Read lesson slots for signed-in users" on public.lesson_slots
for select to authenticated
using (true);

-- Students may change only their own booking row (the app updates slot_id or requested_slot_id).
drop policy if exists "Students request own booking changes" on public.lesson_bookings;
create policy "Students request own booking changes"
on public.lesson_bookings for update to authenticated
using (student_id = auth.uid())
with check (student_id = auth.uid());

-- Keep availability in sync when a booking is moved, rejected, archived, or deleted.
create or replace function public.sync_lesson_slot_availability()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.lesson_slots set is_available = false where id = new.slot_id;
    return new;
  elsif tg_op = 'DELETE' then
    update public.lesson_slots sl
      set is_available = not exists (
        select 1 from public.lesson_bookings b
        where b.slot_id = old.slot_id and b.status in ('pending','approved')
      )
      where sl.id = old.slot_id;
    return old;
  elsif tg_op = 'UPDATE' then
    if old.slot_id is distinct from new.slot_id then
      update public.lesson_slots sl
        set is_available = not exists (
          select 1 from public.lesson_bookings b
          where b.slot_id = old.slot_id and b.id <> new.id and b.status in ('pending','approved')
        )
        where sl.id = old.slot_id;
      update public.lesson_slots set is_available = false where id = new.slot_id;
    end if;
    if old.status is distinct from new.status then
      if new.status in ('rejected','cancelled') then
        update public.lesson_slots sl
          set is_available = not exists (
            select 1 from public.lesson_bookings b
            where b.slot_id = new.slot_id and b.id <> new.id and b.status in ('pending','approved')
          )
          where sl.id = new.slot_id;
      elsif new.status in ('pending','approved') then
        update public.lesson_slots set is_available = false where id = new.slot_id;
      end if;
    end if;
    return new;
  end if;
  return new;
end;
$$;

drop trigger if exists lesson_booking_slot_sync on public.lesson_bookings;
create trigger lesson_booking_slot_sync
after insert or update of status, slot_id or delete on public.lesson_bookings
for each row execute function public.sync_lesson_slot_availability();

create index if not exists lesson_bookings_archive_idx
  on public.lesson_bookings(archived_at, created_at desc);
