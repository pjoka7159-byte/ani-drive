-- ANI DRIVE: լրացուցիչ գրանցման դաշտեր
alter table public.students
  add column if not exists registration_category text,
  add column if not exists age integer,
  add column if not exists exam_location text;

-- Սահմանափակել քննական վայրերի թույլատրելի արժեքները
alter table public.students
  drop constraint if exists students_exam_location_check;

alter table public.students
  add constraint students_exam_location_check
  check (
    exam_location is null or
    exam_location in ('ՀՀ','Արմավիր','Աշտարակ','Երևան','Աբովյան','Արտաշատ','Հովտաշեն')
  );

-- Տարիքի ողջամիտ միջակայք
alter table public.students
  drop constraint if exists students_age_check;

alter table public.students
  add constraint students_age_check
  check (age is null or age between 16 and 100);
