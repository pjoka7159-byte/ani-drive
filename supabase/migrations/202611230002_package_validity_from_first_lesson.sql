-- Package validity starts from the first booked lesson, not enrollment creation.
alter table public.student_package_enrollments
  add column if not exists validity_days integer not null default 30
    check (validity_days between 20 and 30),
  add column if not exists first_lesson_date date,
  add column if not exists expires_on date;
notify pgrst, 'reload schema';
