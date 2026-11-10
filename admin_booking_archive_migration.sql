-- ANI DRIVE: admin archive, manual booking and booking cancellation
-- Run once in Supabase SQL Editor.
alter table public.students
  add column if not exists archived_at timestamptz;

-- Permit admin-created appointments for people who are not registered accounts.
alter table public.lesson_bookings
  alter column student_id drop not null;

alter table public.lesson_bookings
  drop constraint if exists lesson_bookings_student_id_fkey;
alter table public.lesson_bookings
  add constraint lesson_bookings_student_id_fkey
  foreign key (student_id) references public.students(id) on delete set null;

-- A student can cancel their own booking; admins can cancel any booking.
drop policy if exists "Students cancel own bookings" on public.lesson_bookings;
create policy "Students cancel own bookings"
on public.lesson_bookings for delete to authenticated
using (
  student_id = auth.uid()
  or exists (select 1 from public.admins a where a.user_id = auth.uid())
);

-- Existing admin update policy already permits confirmation/rejection.
