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

