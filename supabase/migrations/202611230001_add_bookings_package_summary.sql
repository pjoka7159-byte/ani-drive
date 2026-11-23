-- Fix package booking metadata column used by the website and student-booking-calendar function.
-- Safe to run more than once; existing bookings and data are preserved.
alter table public.bookings
  add column if not exists package_summary text;

-- Refresh PostgREST's schema cache so the new column is immediately visible.
notify pgrst, 'reload schema';
