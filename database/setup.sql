-- AVP Hub database setup
-- Run this ONCE in a new Supabase project (SQL Editor > paste > Run).
-- It creates the tables, the sign-up link to volunteers, and the rules
-- about who may read and change what.

-- ---------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------

create table programs (
  code          text primary key,
  name          text not null,
  calendar_only boolean not null default false  -- true = offered on the Calendar only,
);                                              -- not for tasks or guides

insert into programs (code, name, calendar_only) values
  ('AVP',  'Administrative Volunteer Program',   false),
  ('CFB',  'Campus Food Bank',                   false),
  ('ICLF', 'Information Centre / Lost & Found',  false),
  ('VTP',  'Volunteer Tax Program',              false),
  ('Q',    'Q Centre',                           false),
  ('SSP',  'Student Support Program',            false),
  ('RSP',  'Refugee Student Program',            false),
  ('VS',   'Volunteer Services (all programs)',  true),
  ('CVS',  'Coordinator, Volunteer Services',    true),
  ('SU',   'Students'' Union',                   true),
  ('University', 'University dates',             true),
  ('C10K', 'Committee of 10,000',                true),
  ('Pride Scholarship', 'Pride Scholarship',     true);

create table volunteers (
  id           bigint generated always as identity primary key,
  user_id      uuid unique references auth.users (id) on delete set null, -- their sign-in
  name         text not null,
  email        text not null unique check (email = lower(email)),
  status       text not null default 'active'
               check (status in ('active', 'inactive')),
  program_year text not null                        -- for example 2026-2027
               check (program_year ~ '^[0-9]{4}-[0-9]{4}$'),
  role         text not null default 'volunteer'
               check (role in ('volunteer', 'coordinator')),
  approved     boolean not null default false,
  -- Volunteers must use a UCalgary address. Only the coordinator account
  -- (the shared office mailbox) may use a different one.
  constraint volunteers_email_domain_check
    check (email like '%_@ucalgary.ca' or role = 'coordinator')
);

create table announcements (
  id      bigint generated always as identity primary key,
  message text not null,
  date    date not null default current_date,
  pinned  boolean not null default false
);

create table handover_notes (
  id            bigint generated always as identity primary key,
  finished      text not null,
  left_for_next text not null default '',
  urgent        boolean not null default false,
  resolved      boolean not null default false,
  written_by    bigint references volunteers (id) on delete set null,
  written_at    timestamptz not null default now()
);

create table tasks (
  id         bigint generated always as identity primary key,
  title      text not null,
  program    text not null references programs (code) on update cascade,
  type       text not null default 'regular'
             check (type in ('regular', 'downtime project')),
  status     text not null default 'to do'
             check (status in ('to do', 'in progress', 'done')),
  claimed_by bigint references volunteers (id) on delete set null
);

create table calendar_dates (
  id           bigint generated always as identity primary key,
  program      text not null references programs (code) on update cascade,
  what_happens text not null,
  date         date,                                -- empty while the date is still "TBD"
  notes        text not null default '',
  school_year  text not null                        -- for example 2025-2026
);

create table events (
  id       bigint generated always as identity primary key,
  name     text not null,
  date     date,
  location text not null default ''
);

create table event_tasks (
  id       bigint generated always as identity primary key,
  event_id bigint not null references events (id) on delete cascade,
  title    text not null,
  due_date date,
  done     boolean not null default false
);

create table organizations (
  id    bigint generated always as identity primary key,
  name  text not null,
  type  text not null check (type in ('fair partner', 'sponsor')),
  year  integer not null,
  notes text not null default ''
);

create table guides (
  id      bigint generated always as identity primary key,
  title   text not null,
  program text not null references programs (code) on update cascade,
  steps   text not null                             -- one step per line
);

-- ---------------------------------------------------------------
-- 2. "WHO IS ASKING?" HELPERS
-- ---------------------------------------------------------------

-- School year for today's date. A new year starts on June 1.
create or replace function current_school_year() returns text
language sql stable as $$
  select case when extract(month from current_date) >= 6
    then extract(year from current_date)::int || '-' || (extract(year from current_date)::int + 1)
    else (extract(year from current_date)::int - 1) || '-' || extract(year from current_date)::int
  end;
$$;

-- The signed-in person may use AVP Hub: approved, active, and either the
-- coordinator or a volunteer whose program year has not ended. On June 1 a
-- volunteer from the year that just ended is ON HOLD until the coordinator
-- sets their program year to the new year.
create or replace function is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from volunteers
    where user_id = auth.uid() and approved and status = 'active'
      and (role = 'coordinator' or program_year >= current_school_year())
  );
$$;

-- The signed-in person is an approved, active coordinator.
create or replace function is_coordinator() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from volunteers
    where user_id = auth.uid() and approved and status = 'active'
      and role = 'coordinator'
  );
$$;

-- The volunteers.id of the signed-in person (empty if they may not use AVP Hub).
create or replace function my_volunteer_id() returns bigint
language sql stable security definer set search_path = public as $$
  select id from volunteers
  where user_id = auth.uid() and approved and status = 'active'
    and (role = 'coordinator' or program_year >= current_school_year());
$$;

alter table handover_notes alter column written_by set default my_volunteer_id();

-- ---------------------------------------------------------------
-- 3. SIGN-UP: connect a new sign-in to the volunteers table
-- ---------------------------------------------------------------

-- When someone signs up: refuse non-UCalgary emails, then either connect
-- them to the row the coordinator already added for that email, or create
-- a new row that waits for approval.
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- The one exception: an address already listed in volunteers as a coordinator
  -- (the shared office mailbox, added from the Supabase dashboard).
  if lower(new.email) not like '%_@ucalgary.ca' and not exists (
       select 1 from volunteers
       where email = lower(new.email) and role = 'coordinator' and user_id is null) then
    raise exception 'Only @ucalgary.ca email addresses can sign up.';
  end if;

  update volunteers set user_id = new.id
  where email = lower(new.email) and user_id is null;

  if not found then
    insert into volunteers (user_id, name, email, program_year)
    values (
      new.id,
      coalesce(nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
               split_part(new.email, '@', 1)),
      lower(new.email),
      current_school_year()
    );
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Deleting a volunteer also deletes their sign-in.
create function remove_login() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.user_id is not null then
    delete from auth.users where id = old.user_id;
  end if;
  return old;
end;
$$;

create trigger on_volunteer_deleted
  after delete on volunteers
  for each row execute function remove_login();

-- ---------------------------------------------------------------
-- 4. LIMITS ON WHAT VOLUNTEERS MAY CHANGE
--    (These do not apply to the coordinator, or to edits made
--     directly in the Supabase dashboard.)
-- ---------------------------------------------------------------

-- Tasks: a volunteer may only change the status and who claimed it.
create function guard_task_update() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not is_coordinator() then
    new.title   := old.title;
    new.program := old.program;
    new.type    := old.type;
  end if;
  return new;
end;
$$;

create trigger guard_task_update
  before update on tasks
  for each row execute function guard_task_update();

-- Handover notes: a volunteer may edit their own note. On someone
-- else's note they may only change "resolved".
create function guard_note_update() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and not is_coordinator() then
    new.written_by := old.written_by;
    new.written_at := old.written_at;
    if old.written_by is distinct from my_volunteer_id() then
      new.finished      := old.finished;
      new.left_for_next := old.left_for_next;
      new.urgent        := old.urgent;
    end if;
  end if;
  return new;
end;
$$;

create trigger guard_note_update
  before update on handover_notes
  for each row execute function guard_note_update();

-- ---------------------------------------------------------------
-- 5. ACCESS RULES (row level security)
--    Nobody sees anything unless a rule below allows it.
-- ---------------------------------------------------------------

-- Tables every member can read and only the coordinator can change.
do $$
declare t text;
begin
  foreach t in array array['programs', 'announcements', 'calendar_dates',
                           'events', 'event_tasks', 'organizations', 'guides']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy "members read" on %I for select to authenticated using (is_member())', t);
    execute format('create policy "coordinator changes" on %I for all to authenticated using (is_coordinator()) with check (is_coordinator())', t);
  end loop;
end;
$$;

-- Volunteers: the coordinator sees and changes everything.
-- Everyone else sees only their own row (to check if they are approved).
alter table volunteers enable row level security;
create policy "own row or coordinator read" on volunteers for select to authenticated
  using (user_id = (select auth.uid()) or is_coordinator());
create policy "coordinator changes" on volunteers for all to authenticated
  using (is_coordinator()) with check (is_coordinator());

-- Names only (no emails) for members, used to show who wrote or claimed something.
create view volunteer_names as
  select id, name, status, program_year from volunteers where is_member();

-- Handover notes: members read and write; see the limits in section 4.
alter table handover_notes enable row level security;
create policy "members read" on handover_notes for select to authenticated
  using (is_member());
create policy "members write their own" on handover_notes for insert to authenticated
  with check (is_member() and written_by = my_volunteer_id());
create policy "members update" on handover_notes for update to authenticated
  using (is_member()) with check (is_member());
create policy "coordinator deletes" on handover_notes for delete to authenticated
  using (is_coordinator());

-- Tasks: members read. A volunteer may update a task that is unclaimed or
-- theirs, and may only leave it unclaimed or theirs; see section 4.
alter table tasks enable row level security;
create policy "members read" on tasks for select to authenticated
  using (is_member());
create policy "coordinator changes" on tasks for all to authenticated
  using (is_coordinator()) with check (is_coordinator());
create policy "volunteers claim and complete" on tasks for update to authenticated
  using (is_member() and (claimed_by is null or claimed_by = my_volunteer_id()))
  with check (is_member() and (claimed_by is null or claimed_by = my_volunteer_id()));

-- ---------------------------------------------------------------
-- 6. PERMISSIONS: signed-in people only, never the public
-- ---------------------------------------------------------------

revoke all on all tables in schema public from anon, public;
revoke execute on all functions in schema public from anon, public;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke insert, update, delete on volunteer_names from authenticated;
grant execute on function is_member(), is_coordinator(), my_volunteer_id()
  to authenticated;

-- Partners and sponsors: volunteers may also add and correct organizations.
-- Only the coordinator may delete them (rule from section 5 above).
create policy "members add" on organizations for insert to authenticated
  with check (is_member());
create policy "members correct" on organizations for update to authenticated
  using (is_member()) with check (is_member());

-- ---------------------------------------------------------------
-- 7. HOW-TO CARDS (the How To page)
--    Members read; only the coordinator adds, edits or deletes.
--    The card text itself is private content and is not in this file.
-- ---------------------------------------------------------------

create table howto_cards (
  id           bigint generated always as identity primary key,
  position     integer not null default 0,        -- place in the list, 1 is first
  label        text not null default '',          -- small heading above the title
  title        text not null,
  last_updated date,
  body         text not null,                     -- the card, with simple layout marks
  footer       text not null default '',          -- small print at the bottom
  next_card    bigint references howto_cards (id) on delete set null,   -- part 2 of a two-part card
  next_label   text not null default ''
);

alter table howto_cards enable row level security;
create policy "members read" on howto_cards for select to authenticated
  using (is_member());
create policy "coordinator changes" on howto_cards for all to authenticated
  using (is_coordinator()) with check (is_coordinator());

revoke all on howto_cards from anon, public;
grant select, insert, update, delete on howto_cards to authenticated;

-- ---------------------------------------------------------------
-- 8. COORDINATOR CORNER (coordinator only)
--    The website manual, the "about this website" guide and the
--    coordinator's reminders. Volunteers cannot read or change any
--    of it: every rule below asks is_coordinator().
--    The text itself is private content and is not in this file.
-- ---------------------------------------------------------------

create table corner_pages (
  id           bigint generated always as identity primary key,
  part         text not null check (part in ('Website manual', 'About this website')),
  position     integer not null default 0,        -- place in the list, 1 is first
  title        text not null,
  body         text not null,                     -- same layout marks as the how-to cards
  last_updated date
);

create table reminders (
  id             bigint generated always as identity primary key,
  title          text not null,
  notes          text not null default '',
  due_date       date not null,
  repeats        text not null default 'yearly' check (repeats in ('daily', 'weekly', 'monthly', 'yearly')),
  date_confirmed boolean not null default false   -- yearly dates: confirmed with the CVS for this year?
);

alter table corner_pages enable row level security;
alter table reminders enable row level security;
create policy "coordinator only" on corner_pages for all to authenticated
  using (is_coordinator()) with check (is_coordinator());
create policy "coordinator only" on reminders for all to authenticated
  using (is_coordinator()) with check (is_coordinator());

revoke all on corner_pages, reminders from anon, public;
grant select, insert, update, delete on corner_pages, reminders to authenticated;

-- ---------------------------------------------------------------
-- 9. BACKUPS
--    The weekly backup job (private GitHub project avp-hub-backups)
--    signs in with a Supabase secret key, role service_role. It may
--    READ every table, now and in future, and change nothing.
-- ---------------------------------------------------------------

grant usage on schema public to service_role;
grant select on all tables in schema public to service_role;
alter default privileges in schema public grant select on tables to service_role;
