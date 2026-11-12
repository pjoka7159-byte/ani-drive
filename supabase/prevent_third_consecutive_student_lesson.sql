-- ANI DRIVE: enforce the maximum of two consecutive lessons per student per day.
-- Run this migration in Supabase SQL Editor after reviewing it.

create or replace function public.prevent_third_consecutive_student_lesson()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_date date;
  v_target_time time;
begin
  if new.status not in ('pending','approved') or new.archived_at is not null then
    return new;
  end if;

  -- A requested new time is checked too, before an administrator approves it.
  select slot_date, slot_time::time
    into v_target_date, v_target_time
  from public.lesson_slots
  where id = coalesce(new.requested_slot_id, new.slot_id);

  if v_target_date is null or v_target_time is null then
    return new;
  end if;

  if exists (
    with lesson_starts as (
      select ls.slot_time::time as start_time
      from public.lesson_bookings b
      join public.lesson_slots ls on ls.id = b.slot_id
      where b.student_id = new.student_id
        and b.id is distinct from new.id
        and b.archived_at is null
        and b.status in ('pending','approved')
        and ls.slot_date = v_target_date

      union

      select v_target_time
    )
    select 1
    from lesson_starts a
    join lesson_starts b on b.start_time = a.start_time + interval '60 minutes'
    join lesson_starts c on c.start_time = b.start_time + interval '60 minutes'
    where v_target_time in (a.start_time, b.start_time, c.start_time)
  ) then
    raise exception 'Չի թույլատրվում նույն օրը ամրագրել իրար հաջորդող երեք կամ ավելի դասաժամ։ Առավելագույնը՝ երկու։'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_third_consecutive_student_lesson
  on public.lesson_bookings;

create trigger trg_prevent_third_consecutive_student_lesson
before insert or update of student_id, slot_id, requested_slot_id, status, archived_at
on public.lesson_bookings
for each row
execute function public.prevent_third_consecutive_student_lesson();
