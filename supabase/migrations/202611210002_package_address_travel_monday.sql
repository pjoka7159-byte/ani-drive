-- ANI DRIVE package address, admin package booking, travel buffer and Monday closure
alter table public.student_package_enrollments
  add column if not exists address text not null default '',
  add column if not exists address_change_count integer not null default 0,
  add column if not exists address_change_limit integer not null default 2;
alter table public.bookings
  add column if not exists package_address text;

create table if not exists public.package_travel_blocks (
  booking_id uuid not null references public.bookings(id) on delete cascade,
  slot_id uuid not null references public.booking_slots(id) on delete cascade,
  was_available boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (booking_id, slot_id)
);
alter table public.package_travel_blocks enable row level security;
drop policy if exists "admin manage package travel blocks" on public.package_travel_blocks;
create policy "admin manage package travel blocks" on public.package_travel_blocks
for all to authenticated
using (lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com'))
with check (lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com'));

-- Mondays are non-working days.
update public.booking_slots
set is_available = false
where extract(isodow from starts_at at time zone 'Asia/Yerevan') = 1
  and is_available = true;

create or replace function public.ani_reject_monday_bookings()
returns trigger language plpgsql security definer set search_path = public as $$
declare slot_start timestamptz;
begin
  select starts_at into slot_start from public.booking_slots where id = new.slot_id;
  if slot_start is not null and extract(isodow from slot_start at time zone 'Asia/Yerevan') = 1 then
    raise exception 'Երկուշաբթի օրը ոչ աշխատանքային է։ Ընտրեք երեքշաբթիից կիրակի օր։';
  end if;
  return new;
end;
$$;
drop trigger if exists ani_reject_monday_booking on public.bookings;
create trigger ani_reject_monday_booking
before insert or update of slot_id on public.bookings
for each row execute function public.ani_reject_monday_bookings();

-- A package lesson reserves the next 30-minute travel interval after the lesson.
create or replace function public.ani_apply_package_travel_buffer()
returns trigger language plpgsql security definer set search_path = public as $$
declare lesson_end timestamptz;
declare next_slot record;
begin
  if new.package_enrollment_id is null or (tg_op = 'UPDATE' and old.package_enrollment_id is not distinct from new.package_enrollment_id) then
    return new;
  end if;
  select ends_at into lesson_end from public.booking_slots where id = new.slot_id;
  if lesson_end is null then return new; end if;
  for next_slot in
    select id, is_available from public.booking_slots
    where starts_at >= lesson_end and starts_at < lesson_end + interval '30 minutes'
      and is_available = true
  loop
    insert into public.package_travel_blocks(booking_id,slot_id,was_available)
    values(new.id,next_slot.id,next_slot.is_available)
    on conflict (booking_id,slot_id) do nothing;
    update public.booking_slots set is_available = false where id = next_slot.id;
  end loop;
  return new;
end;
$$;
drop trigger if exists ani_package_travel_buffer on public.bookings;
create trigger ani_package_travel_buffer
after insert or update of package_enrollment_id on public.bookings
for each row execute function public.ani_apply_package_travel_buffer();

create or replace function public.ani_release_package_travel_buffer()
returns trigger language plpgsql security definer set search_path = public as $$
declare block_row record;
begin
  if new.status in ('cancelled','rejected') and old.status not in ('cancelled','rejected') then
    for block_row in
      select slot_id, was_available from public.package_travel_blocks where booking_id = new.id
    loop
      if block_row.was_available and not exists (
        select 1 from public.bookings b
        where b.slot_id = block_row.slot_id and b.id <> new.id
          and b.status in ('pending','confirmed')
      ) then
        update public.booking_slots set is_available = true where id = block_row.slot_id;
      end if;
    end loop;
    delete from public.package_travel_blocks where booking_id = new.id;
  end if;
  return new;
end;
$$;
drop trigger if exists ani_package_release_travel_buffer on public.bookings;
create trigger ani_package_release_travel_buffer
after update of status on public.bookings
for each row execute function public.ani_release_package_travel_buffer();

create or replace function public.ani_limit_package_address_changes()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.address is distinct from new.address then
    if old.address_change_count >= coalesce(old.address_change_limit,2) then
      raise exception 'Փաթեթի հասցեն կարելի է փոխել առավելագույնը 2 անգամ։';
    end if;
    new.address_change_count := old.address_change_count + 1;
  end if;
  return new;
end;
$$;
drop trigger if exists ani_package_address_change_guard on public.student_package_enrollments;
create trigger ani_package_address_change_guard
before update of address on public.student_package_enrollments
for each row execute function public.ani_limit_package_address_changes();

drop policy if exists "student update own package address" on public.student_package_enrollments;
create policy "student update own package address" on public.student_package_enrollments
for update to authenticated
using (student_user_id = auth.uid())
with check (student_user_id = auth.uid());


-- Prevent students from editing package ownership, limits, or enrollment status.
create or replace function public.ani_limit_package_address_changes()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(coalesce(auth.jwt()->>'email','')) not in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com') then
    if new.student_user_id is distinct from old.student_user_id
      or new.package_name is distinct from old.package_name
      or new.package_snapshot is distinct from old.package_snapshot
      or new.min_required_days is distinct from old.min_required_days
      or new.change_limit is distinct from old.change_limit
      or new.status is distinct from old.status
      or new.address_change_limit is distinct from old.address_change_limit
      or new.address_change_count is distinct from old.address_change_count then
      raise exception 'Աշակերտը կարող է փոխել միայն փաթեթի հանդիպման հասցեն։';
    end if;
  end if;
  if old.address is distinct from new.address then
    if old.address_change_count >= coalesce(old.address_change_limit,2) then
      raise exception 'Փաթեթի հասցեն կարելի է փոխել առավելագույնը 2 անգամ։';
    end if;
    new.address_change_count := old.address_change_count + 1;
  else
    new.address_change_count := old.address_change_count;
  end if;
  return new;
end;
$$;

-- Students may only reschedule their package day; they cannot forge completion or change ownership.
create or replace function public.enforce_package_day_change_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare allowed_changes integer;
declare admin_user boolean;
begin
  admin_user := lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com');
  if not admin_user then
    if new.enrollment_id is distinct from old.enrollment_id
      or new.student_user_id is distinct from old.student_user_id
      or new.booking_id is distinct from old.booking_id
      or new.created_at is distinct from old.created_at then
      raise exception 'Փաթեթի ամրագրման կապակցված տվյալները փոփոխել չի կարելի։';
    end if;
    if old.lesson_starts_at is distinct from new.lesson_starts_at then
      select change_limit into allowed_changes from public.student_package_enrollments where id = old.enrollment_id;
      if old.lesson_starts_at is not null and old.lesson_starts_at <= now() + interval '24 hours' then
        raise exception 'Փաթեթի դասաժամը կարելի է փոխել միայն առնվազն 24 ժամ առաջ։';
      end if;
      if old.change_count >= coalesce(allowed_changes,0) then
        raise exception 'Փաթեթի փոփոխությունների թույլատրելի քանակը սպառվել է։';
      end if;
      new.change_count := old.change_count + 1;
      new.status := 'changed';
    else
      if new.lesson_date is distinct from old.lesson_date then
        raise exception 'Օրը փոխելու համար ընտրեք նոր ազատ դասաժամ։';
      end if;
      if new.change_count is distinct from old.change_count then
        raise exception 'Փոփոխությունների հաշվիչը ձեռքով փոխել չի կարելի։';
      end if;
      if new.status is distinct from old.status and new.status <> 'cancelled' then
        raise exception 'Աշակերտը կարող է միայն չեղարկել փաթեթի օրը։';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.ani_require_minimum_package_days_before_completion()
returns trigger language plpgsql security definer set search_path = public as $$
declare day_count integer;
begin
  if new.status = 'completed' and old.status is distinct from new.status then
    select count(*) into day_count from public.student_package_days
    where enrollment_id = new.id and status <> 'cancelled';
    if day_count < new.min_required_days then
      raise exception 'Փաթեթը ավարտելու համար անհրաժեշտ է ամրագրել առնվազն % տարբեր օր։', new.min_required_days;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists ani_minimum_package_days_before_completion on public.student_package_enrollments;
create trigger ani_minimum_package_days_before_completion
before update of status on public.student_package_enrollments
for each row execute function public.ani_require_minimum_package_days_before_completion();

-- Recalculate the 30-minute travel block when an admin or student reschedules a package booking.
create or replace function public.ani_apply_package_travel_buffer()
returns trigger language plpgsql security definer set search_path = public as $$
declare lesson_end timestamptz;
declare next_slot record;
declare old_block record;
begin
  if tg_op = 'UPDATE' and old.slot_id is distinct from new.slot_id and old.package_enrollment_id is not null then
    for old_block in
      select slot_id, was_available from public.package_travel_blocks where booking_id = old.id
    loop
      if old_block.was_available and not exists (
        select 1 from public.bookings b
        where b.slot_id = old_block.slot_id and b.id <> old.id
          and b.status in ('pending','confirmed')
      ) then
        update public.booking_slots set is_available = true where id = old_block.slot_id;
      end if;
    end loop;
    delete from public.package_travel_blocks where booking_id = old.id;
  elsif tg_op = 'UPDATE'
    and old.package_enrollment_id is not distinct from new.package_enrollment_id
    and old.slot_id is not distinct from new.slot_id then
    return new;
  end if;
  if new.package_enrollment_id is null then return new; end if;
  select ends_at into lesson_end from public.booking_slots where id = new.slot_id;
  if lesson_end is null then return new; end if;
  for next_slot in
    select id, is_available from public.booking_slots
    where starts_at >= lesson_end and starts_at < lesson_end + interval '30 minutes'
      and is_available = true
  loop
    insert into public.package_travel_blocks(booking_id,slot_id,was_available)
    values(new.id,next_slot.id,next_slot.is_available)
    on conflict (booking_id,slot_id) do nothing;
    update public.booking_slots set is_available = false where id = next_slot.id;
  end loop;
  return new;
end;
$$;
drop trigger if exists ani_package_travel_buffer on public.bookings;
create trigger ani_package_travel_buffer
after insert or update of package_enrollment_id, slot_id on public.bookings
for each row execute function public.ani_apply_package_travel_buffer();
