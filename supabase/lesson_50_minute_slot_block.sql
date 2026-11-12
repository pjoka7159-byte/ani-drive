-- ANI DRIVE: a 50-minute lesson occupies two consecutive 30-minute slots.
-- Run once in Supabase SQL Editor for project eechxgtbvtxqfetjcrfg.
-- Existing lesson-bookings trigger continues to manage the directly booked slot;
-- this trigger additionally reserves/releases the following half-hour.

create or replace function public.sync_lesson_50_minute_following_slot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  old_date date;
  old_time time;
  new_date date;
  new_time time;
  following_slot_id uuid;
begin
  -- Release the previous booking's second half-hour when it is moved,
  -- cancelled/rejected, or archived. Do not reopen it if another active
  -- lesson still occupies that half-hour.
  if tg_op = 'UPDATE'
     and old.slot_id is not null
     and (
       old.slot_id is distinct from new.slot_id
       or new.status not in ('pending', 'approved')
       or new.archived_at is not null
     ) then
    select slot_date, slot_time
      into old_date, old_time
      from public.lesson_slots
      where id = old.slot_id;

    if found then
      select id into following_slot_id
        from public.lesson_slots
        where slot_date = old_date
          and slot_time = old_time + interval '30 minutes'
        limit 1;

      if following_slot_id is not null
         and not exists (
           select 1
             from public.lesson_bookings b
             join public.lesson_slots s on s.id = b.slot_id
            where b.id <> new.id
              and b.status in ('pending', 'approved')
              and b.archived_at is null
              and s.slot_date = old_date
              and s.slot_time in (
                old_time,
                old_time + interval '30 minutes'
              )
         ) then
        update public.lesson_slots
           set is_available = true
         where id = following_slot_id;
      end if;
    end if;
  end if;

  -- Every active 50-minute lesson also reserves the next 30-minute slot.
  if new.slot_id is not null
     and new.status in ('pending', 'approved')
     and new.archived_at is null then
    select slot_date, slot_time
      into new_date, new_time
      from public.lesson_slots
      where id = new.slot_id;

    if found then
      update public.lesson_slots
         set is_available = false
       where slot_date = new_date
         and slot_time = new_time + interval '30 minutes'
         and is_available is distinct from false;
    end if;
  end if;

  return new;
end;
$$;

-- Apply the rule to active bookings that already exist.
update public.lesson_slots next_slot
   set is_available = false
  from public.lesson_bookings b
  join public.lesson_slots booked_slot on booked_slot.id = b.slot_id
 where b.status in ('pending', 'approved')
   and b.archived_at is null
   and next_slot.slot_date = booked_slot.slot_date
   and next_slot.slot_time = booked_slot.slot_time + interval '30 minutes';

drop trigger if exists lesson_booking_50_minute_following_slot
  on public.lesson_bookings;

create trigger lesson_booking_50_minute_following_slot
after insert or update of slot_id, status, archived_at
on public.lesson_bookings
for each row
execute function public.sync_lesson_50_minute_following_slot();
