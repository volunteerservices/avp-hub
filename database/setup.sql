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

-- ---------------------------------------------------------------
-- 10. ACTIVITY LOG (coordinator only)
--     The database itself writes an entry for every add, edit and
--     delete on the tables below, and for every sign-in, however the
--     change was made. Entries can never be edited or deleted, except
--     by the coordinator's yearly clean-up of entries older than last
--     school year. No passwords or sign-in details are ever stored:
--     user_id is removed from every saved row.
-- ---------------------------------------------------------------

create table activity_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  actor_id    bigint,                 -- volunteers.id of who did it (null: the database itself)
  actor_name  text not null,          -- their name at the time
  action      text not null check (action in ('added', 'edited', 'deleted', 'signed in', 'log clean-up')),
  detail      text not null default '',   -- e.g. claimed, completed, approved, marked resolved
  item_type   text not null,          -- the table, e.g. tasks
  item_id     bigint,
  item_label  text not null default '',
  old_row     jsonb,                  -- before (edits and deletes)
  new_row     jsonb,                  -- after (adds and edits)
  search_text text generated always as (lower(
    actor_name || ' ' || detail || ' ' || item_label || ' ' ||
    coalesce(old_row::text, '') || ' ' || coalesce(new_row::text, ''))) stored
);
create index activity_log_at on activity_log (at desc);
create index activity_log_item on activity_log (item_type, item_id, at desc);
create index activity_log_actor on activity_log (actor_id, at desc);

-- Writes one entry. Runs after every change to a logged table.
create function log_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  raw_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  raw_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  o jsonb := raw_old - 'user_id';
  n jsonb := raw_new - 'user_id';
  r jsonb := coalesce(raw_new, raw_old);
  who_id bigint; who text; what text := '';
  act text := case tg_op when 'INSERT' then 'added' when 'UPDATE' then 'edited' else 'deleted' end;
begin
  select id, name into who_id, who from volunteers where user_id = auth.uid();

  if tg_op = 'UPDATE' and o = n then
    if tg_table_name = 'volunteers' and raw_old ->> 'user_id' is null and raw_new ->> 'user_id' is not null then
      what := 'signed up';
      who_id := (n ->> 'id')::bigint; who := n ->> 'name';
    else
      return null;                                   -- nothing visible changed
    end if;
  end if;

  if current_setting('avp.restoring', true) = 'on' and tg_op = 'INSERT' then
    what := 'restored from the activity log';
  elsif tg_table_name = 'volunteers' then
    if tg_op = 'INSERT' and auth.uid() is null and raw_new ->> 'user_id' is not null then
      what := 'signed up'; who_id := (n ->> 'id')::bigint; who := n ->> 'name';
    elsif tg_op = 'DELETE' then what := 'removed';
    elsif tg_op = 'UPDATE' and what = '' then
      if (o ->> 'approved')::boolean is not true and (n ->> 'approved')::boolean then what := 'approved';
      elsif n ->> 'role' = 'coordinator' and o ->> 'role' <> 'coordinator' then what := 'made coordinator';
      elsif o ->> 'role' = 'coordinator' and n ->> 'role' <> 'coordinator' then what := 'removed as coordinator';
      elsif o ->> 'status' = 'active' and n ->> 'status' = 'inactive' then what := 'set inactive (removed)';
      elsif o ->> 'status' = 'inactive' and n ->> 'status' = 'active' then what := 'set active';
      elsif o ->> 'program_year' <> n ->> 'program_year' then what := 'marked returning for ' || (n ->> 'program_year');
      end if;
    end if;
  elsif tg_table_name = 'tasks' and tg_op = 'UPDATE' then
    if n ->> 'status' = 'done' and o ->> 'status' <> 'done' then what := 'completed';
    elsif o ->> 'claimed_by' is null and n ->> 'claimed_by' is not null then what := 'claimed';
    elsif o ->> 'claimed_by' is not null and n ->> 'claimed_by' is null then what := 'put back';
    end if;
  elsif tg_table_name = 'handover_notes' and tg_op = 'UPDATE' then
    if (n ->> 'resolved')::boolean and not (o ->> 'resolved')::boolean then what := 'marked resolved';
    elsif (o ->> 'resolved')::boolean and not (n ->> 'resolved')::boolean then what := 'reopened';
    end if;
  elsif tg_table_name = 'event_tasks' and tg_op = 'UPDATE' and o ->> 'done' <> n ->> 'done' then
    what := case when (n ->> 'done')::boolean then 'marked done' else 'marked not done' end;
  elsif tg_table_name = 'reminders' and tg_op = 'UPDATE' then
    if (o - 'due_date' - 'date_confirmed') = (n - 'due_date' - 'date_confirmed') then
      if n ->> 'due_date' > o ->> 'due_date' then what := 'ticked off';
      elsif (n ->> 'date_confirmed')::boolean and not (o ->> 'date_confirmed')::boolean then what := 'confirmed the date of';
      end if;
    end if;
  end if;

  insert into activity_log (actor_id, actor_name, action, detail, item_type, item_id, item_label, old_row, new_row)
  values (
    who_id,
    coalesce(who, case when auth.uid() is null then 'Supabase dashboard (directly in the database)' else 'Unknown account' end),
    act, what, tg_table_name, (r ->> 'id')::bigint,
    left(coalesce(r ->> 'title', r ->> 'name', r ->> 'what_happens', r ->> 'message', r ->> 'finished', r ->> 'code', ''), 140),
    o, n);
  return null;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['announcements', 'calendar_dates', 'corner_pages', 'event_tasks', 'events',
                           'guides', 'handover_notes', 'howto_cards', 'organizations', 'programs',
                           'reminders', 'tasks', 'volunteers']
  loop
    execute format('create trigger log_changes after insert or update or delete on %I
                    for each row execute function log_change()', t);
  end loop;
end;
$$;

-- Sign-ins: every new sign-in session. Only who and when; nothing about the device.
create function log_sign_in() returns trigger
language plpgsql security definer set search_path = public as $$
declare vid bigint; vname text;
begin
  begin
    select id, name into vid, vname from volunteers where user_id = new.user_id;
    insert into activity_log (actor_id, actor_name, action, item_type, item_id, item_label)
    values (vid, coalesce(vname, 'Unknown account'), 'signed in', 'volunteers', vid, coalesce(vname, ''));
  exception when others then null;     -- never let the log stop someone signing in
  end;
  return null;
end;
$$;

create trigger log_sign_in
  after insert on auth.sessions
  for each row execute function log_sign_in();

-- Entries are permanent: no edits, no deletes, no emptying the table.
-- The only exception is remove_old_activity() below.
create function activity_log_is_permanent() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' and current_setting('avp.log_cleanup', true) = 'on' then
    return old;
  end if;
  raise exception 'Activity log entries cannot be changed or deleted.' using errcode = 'P0001';
end;
$$;

create trigger activity_log_is_permanent
  before update or delete on activity_log
  for each row execute function activity_log_is_permanent();
create trigger activity_log_no_emptying
  before truncate on activity_log
  for each statement execute function activity_log_is_permanent();

alter table activity_log enable row level security;
create policy "coordinator reads" on activity_log for select to authenticated
  using (is_coordinator());

-- For the "Last edited by" line on each item: names and dates only,
-- for signed-in members. No content from the log.
create view last_edits as
  select distinct on (item_type, item_id) item_type, item_id, actor_name, action, detail, at
  from activity_log
  where is_member() and action in ('added', 'edited') and item_id is not null
  order by item_type, item_id, at desc;

-- Coordinator: put back an item that was deleted, from its log entry.
create function restore_from_log(entry bigint) returns text
language plpgsql security definer set search_path = public as $$
declare e activity_log;
begin
  if not is_coordinator() then
    raise exception 'Only the coordinator can restore items.' using errcode = 'P0001';
  end if;
  select * into e from activity_log where id = entry;
  if e.id is null or e.action <> 'deleted' or e.old_row is null then
    raise exception 'This entry is not a deleted item.' using errcode = 'P0001';
  end if;
  if e.item_type not in ('announcements', 'calendar_dates', 'corner_pages', 'event_tasks', 'events', 'guides',
                         'handover_notes', 'howto_cards', 'organizations', 'reminders', 'tasks', 'volunteers') then
    raise exception 'This kind of item cannot be restored here.' using errcode = 'P0001';
  end if;
  perform set_config('avp.restoring', 'on', true);
  begin
    execute format('insert into %I overriding system value select * from jsonb_populate_record(null::%I, $1)',
                   e.item_type, e.item_type) using e.old_row;
  exception
    when unique_violation then
      raise exception 'This item is already back.' using errcode = 'P0001';
    when foreign_key_violation then
      raise exception 'This item belonged to something that was also deleted. Restore that first, then try again.' using errcode = 'P0001';
  end;
  perform set_config('avp.restoring', 'off', true);
  return e.item_label;
end;
$$;

-- Coordinator: remove entries from before last school year (after downloading them).
create function remove_old_activity() returns integer
language plpgsql security definer set search_path = public as $$
declare
  cutoff date := make_date(split_part(current_school_year(), '-', 1)::int - 1, 6, 1);
  removed integer;
begin
  if not is_coordinator() then
    raise exception 'Only the coordinator can remove old log entries.' using errcode = 'P0001';
  end if;
  perform set_config('avp.log_cleanup', 'on', true);
  delete from activity_log where at < cutoff;
  get diagnostics removed = row_count;
  perform set_config('avp.log_cleanup', 'off', true);
  insert into activity_log (actor_id, actor_name, action, item_type, item_label)
  select id, name, 'log clean-up', 'activity_log',
         format('Removed %s entries from before %s', removed, to_char(cutoff, 'Mon DD, YYYY'))
  from volunteers where user_id = auth.uid();
  return removed;
end;
$$;

revoke all on activity_log, last_edits from anon, public, authenticated;
grant select on activity_log, last_edits to authenticated;
revoke execute on function log_change(), log_sign_in(), activity_log_is_permanent(),
  restore_from_log(bigint), remove_old_activity() from public, anon, authenticated;
grant execute on function restore_from_log(bigint), remove_old_activity() to authenticated;
