# AVP Hub: coordinator guide

For the Volunteer Administration Coordinator. No programming needed.

## What AVP Hub is made of

| Part | Where it lives | What it does |
|---|---|---|
| The pages | GitHub (free) | Stores the website files and publishes them |
| The data and sign-in | Supabase (free) | PostgreSQL database, accounts, and the access rules |

- Site address: https://volunteerservices.github.io/avp-hub/
- GitHub: account `volunteerservices`, repository `avp-hub` (github.com/volunteerservices/avp-hub)
- Supabase: organization "SU Volunteer Services", project "AVP Hub", Canada (Central), Free plan

Both accounts must belong to the shared office mailbox, never a personal email.
Keep their passwords in the office's usual password storage, not in AVP Hub.

## Content rules

- Never store passwords, door or lockbox codes, or volunteer performance reviews.
- Personal information is limited to name and UCalgary email.

## Everyday jobs (all done on the site itself)

- **Approve a new volunteer:** Volunteers page > their row is highlighted > Approve.
- **Remove access:** Volunteers page > Edit > set Status to inactive. Their notes stay.
- **Delete a volunteer:** also deletes their sign-in. Notes they wrote show "Former volunteer".
- **Add a volunteer before they sign up:** Volunteers page > Add volunteer. When they
  create an account with the same email, it connects to that row. They still need Approve.
- Volunteers can only sign up with an @ucalgary.ca email and must click a confirmation
  link. The free plan sends only a few of these emails per hour, so spread sign-ups out.

- **"That link was already used or has expired":** UCalgary's email system opens links
  before the person does, which uses up the confirmation link. The account is still
  confirmed, so the volunteer just signs in with their password.
- **Only approve people you expect.** Because of the above, a confirmed email does not
  prove the person owns that address. Approve a sign-up only when that volunteer has
  told you they signed up.

## Yearly handover checklist

1. The new coordinator creates an account on the site and is approved.
2. The outgoing coordinator opens Volunteers > Edit on the new coordinator > Role: coordinator.
3. The new coordinator sets the outgoing coordinator's Role to volunteer (or Status to inactive).
4. Hand over access to the shared mailbox and the GitHub and Supabase passwords.
5. Set last year's volunteers to inactive.
6. Download a backup (see below).

## Summer: the database can pause

The free Supabase plan pauses a database after about a week with no visits.
A robot visits it twice a week to prevent this (GitHub > Actions > "Keep database awake"),
but GitHub turns that robot off after about 60 quiet days.

- **Once a month from May to August:** sign in to AVP Hub. If GitHub emails that a
  workflow was disabled, open GitHub > Actions > "Keep database awake" > Enable.
- **If the site says it can't reach its database:** sign in to Supabase, open the
  project, and click Restore. This takes a few minutes.
- **Do not leave it paused for more than 90 days.** After that, one-click restore
  is gone and the data has to be reloaded from a downloaded backup.

## Backups

The free plan keeps no automatic backups. Once a term, and at handover:
Supabase > Table Editor > open each table > Export > CSV. Save the files in the
office shared drive.

## Changes made in Supabase (rare)

- **Add or rename a program:** Supabase > Table Editor > programs. Set `calendar_only`
  to `true` for labels that are only used on the Calendar (like "University").
- **The very first coordinator** (or if every coordinator is locked out):
  Supabase > Table Editor > volunteers > set that person's role to `coordinator`
  and approved to `true`.

## If something needs rebuilding

- `database/setup.sql` recreates every table and access rule in a new Supabase project.
- The content itself (guides, calendar, notes) is only in the database and in your CSV
  backups. It is deliberately not kept on GitHub, because the files there are public.
- `config.js` holds the database address and public key. Never put a "secret" or
  "service_role" key in it.
- `app.js` lists every page and its fields at the top, under "PAGES".

## Costs

Everything is on free plans. Nothing should ever ask for a credit card. If a
service starts to, stop and ask before agreeing.
