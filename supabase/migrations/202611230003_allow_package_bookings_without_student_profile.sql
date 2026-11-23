-- Allow admin-created package bookings without a linked student account.
-- Contact details are kept in package_snapshot and copied to each booking.
alter table public.student_package_enrollments
  alter column student_user_id drop not null;

alter table public.student_package_days
  alter column student_user_id drop not null;

-- Whole-package rejection is a supported admin action in the application.
alter table public.student_package_enrollments
  drop constraint if exists student_package_enrollments_status_check;

alter table public.student_package_enrollments
  add constraint student_package_enrollments_status_check
  check (status in ('active','completed','cancelled','rejected'));

notify pgrst, 'reload schema';
