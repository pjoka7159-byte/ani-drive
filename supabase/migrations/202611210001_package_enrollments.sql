-- ANI DRIVE package enrollment support
create table if not exists public.student_package_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_user_id uuid not null references auth.users(id) on delete cascade,
  package_name text not null,
  package_snapshot jsonb not null default '{}'::jsonb,
  min_required_days integer not null default 0 check (min_required_days between 0 and 30),
  change_limit integer not null default 1 check (change_limit between 0 and 30),
  changes_used integer not null default 0 check (changes_used between 0 and 30),
  status text not null default 'active' check (status in ('active','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.student_package_days (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.student_package_enrollments(id) on delete cascade,
  student_user_id uuid not null references auth.users(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,
  lesson_date date not null,
  status text not null default 'booked' check (status in ('booked','changed','cancelled','completed')),
  change_count integer not null default 0,
  created_at timestamptz not null default now(),
  unique(enrollment_id, lesson_date)
);
alter table public.bookings add column if not exists package_enrollment_id uuid references public.student_package_enrollments(id) on delete set null;
alter table public.bookings add column if not exists package_name text;
alter table public.student_package_enrollments enable row level security;
alter table public.student_package_days enable row level security;
drop policy if exists "student package read own or admin" on public.student_package_enrollments;
create policy "student package read own or admin" on public.student_package_enrollments for select to authenticated using (student_user_id = auth.uid() or lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com'));
drop policy if exists "admin manage package enrollments" on public.student_package_enrollments;
create policy "admin manage package enrollments" on public.student_package_enrollments for all to authenticated using (lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com')) with check (lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com'));
drop policy if exists "student package days read own or admin" on public.student_package_days;
create policy "student package days read own or admin" on public.student_package_days for select to authenticated using (student_user_id = auth.uid() or lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com'));
drop policy if exists "student package days insert own or admin" on public.student_package_days;
create policy "student package days insert own or admin" on public.student_package_days for insert to authenticated with check (student_user_id = auth.uid() or lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com'));
drop policy if exists "admin update package days" on public.student_package_days;
create policy "admin update package days" on public.student_package_days for update to authenticated using (lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com')) with check (lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com'));

drop policy if exists "student update own package days" on public.student_package_days;
create policy "student update own package days" on public.student_package_days for update to authenticated using (student_user_id = auth.uid()) with check (student_user_id = auth.uid());

alter table public.student_package_days add column if not exists lesson_starts_at timestamptz;
create or replace function public.enforce_package_day_change_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  allowed_changes integer;
  admin_user boolean;
begin
  admin_user := lower(coalesce(auth.jwt()->>'email','')) in ('pjoka7159@gmail.com','graergrigoryan1986@gmail.com');
  if old.lesson_starts_at is distinct from new.lesson_starts_at and not admin_user then
    select change_limit into allowed_changes from public.student_package_enrollments where id = old.enrollment_id;
    if old.lesson_starts_at is not null and old.lesson_starts_at <= now() + interval '24 hours' then
      raise exception 'Փաթեթի դասաժամը կարելի է փոխել միայն առնվազն 24 ժամ առաջ։';
    end if;
    if old.change_count >= coalesce(allowed_changes,0) then
      raise exception 'Փաթեթի փոփոխությունների թույլատրելի քանակը սպառվել է։';
    end if;
    new.change_count := old.change_count + 1;
    new.status := 'changed';
  end if;
  return new;
end;
$$;
drop trigger if exists student_package_day_change_guard on public.student_package_days;
create trigger student_package_day_change_guard before update on public.student_package_days
for each row execute function public.enforce_package_day_change_rules();
