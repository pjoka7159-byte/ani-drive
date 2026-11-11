-- ANI DRIVE: allow administrator to book a lesson for a person without a website account.
-- Run once in Supabase SQL Editor.
alter table public.lesson_bookings
  alter column student_id drop not null;
