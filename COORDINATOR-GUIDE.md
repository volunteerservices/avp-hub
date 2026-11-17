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

## What volunteers can do

- **Read** everything except other people's emails.
- **Handover notes:** write notes, edit their own, mark any note resolved.
- **Tasks:** claim a task, mark it done, release it.
- **Partners and sponsors:** add and correct organizations, but not delete them.
- Everything else (announcements, calendar, events, guides, How To cards) is view-only
  for volunteers.

The coordinator can add, edit and delete everything.

## Coordinator Corner

The full, up-to-date coordinator manual now lives on the website itself: sign in as the
coordinator and open **Coordinator Corner** (last item in the menu). It has three tabs:

- **Website manual:** step-by-step instructions for every everyday job.
- **Reminders:** recurring jobs with due dates. Tick one and it moves to its next date.
  Overdue and due-this-week reminders also show at the top of the coordinator's Today page.
- **About this website:** how the services connect, the free-plan rules (checked
  November 16, 2026), summer, backups, costs, accounts and troubleshooting.

Volunteers cannot see Coordinator Corner, and the database refuses to give its contents
to anyone but the coordinator. Its text is stored in the database, not in these public
files. A private copy for rebuilding is in `private-content/corner-content.sql` on the
computer used to build the site.

## How To cards

The How To page holds the how-to cards from the front desk binder. Volunteers pick a
card from the list to open it. Only the coordinator sees Add, Edit and Delete.

To change a card, open it and press Edit. The card text uses a few marks at the start
of a line to set the layout:

| Type this at the start of a line | You get |
|---|---|
| `# Heading` | A big heading |
| `## HEADING` | A small heading, like STEPS |
| `1. First step` | A numbered step. Lines right under it (no empty line) belong to that step |
| `- An item` | A bullet |
| `> Some text` | A highlighted box |
| `\| one \| two \|` | A table row. Put `\|---\|---\|` under the first row to make it the headings |

Inside a line, `**words**` makes bold text, and backticks around a folder path
(`` `Drive › Guides` ``) show it as a label. Leave an empty line between sections.

- **Two-part cards:** on part 1, choose part 2 under "Next card" and type the words for
  the link (for example "Next: Good Food Box 2 of 2").
- **Order:** "Place in the list" sets where the card appears; 1 is first.
- **Dates:** change "Last updated" whenever you change a card.
- The same content rules apply: no passwords, door codes or lockbox codes.

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

## One program year at a time (the yearly hold)

Each volunteer has a program year, for example 2026-2027.

- **On June 1 every year**, volunteers from the year that just ended are put **on hold**
  automatically. Their sign-in is kept, but they cannot get in or see anything.
- **If someone is returning:** Volunteers page > their row > **Returning for (this year)**.
  They can sign in again with the same email and password.
- **Sign-ins are kept for 3 years** after the program year ends. After that the row
  shows "Past the 3-year limit" and a button appears at the top of the Volunteers page:
  **Delete N past the 3-year limit**. Click it once a year. Nothing is deleted on its own.
- The coordinator account is never put on hold.

## The coordinator account

There is one shared coordinator account, signed in with the office mailbox
`volunteer@su.ucalgary.ca`. Every coordinator uses it; it is handed over each year.
Volunteers sign up for their own accounts and can never become coordinators by signing up.

- Notes written from this account show "Coordinator" as the author.
- Its password is kept in the office's password storage, never in AVP Hub.
- It is the only account allowed to use an address that does not end in @ucalgary.ca.

## Yearly handover checklist

1. Hand over access to the shared mailbox and the AVP Hub coordinator password.
2. The new coordinator signs in to AVP Hub, then changes the password:
   sign out > "Forgot your password?" > follow the email sent to the shared mailbox.
3. Save the new password in the office's password storage.
4. Hand over the GitHub and Supabase passwords too.
5. After June 1: mark returning volunteers as returning, and click
   "Delete N past the 3-year limit" if it appears.
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

The free plan keeps no automatic backups, so we make our own. Every Sunday a free
GitHub job copies every table into the **private** GitHub project
`volunteerservices/avp-hub-backups`, one dated folder per week. Check it monthly:
that project > Actions > Weekly backup > the newest run has a green tick. Its README
explains failures and restoring. The job reads the database with a Supabase secret key
stored only in that project's encrypted secrets.

If the automatic backup ever stops working: Supabase > Table Editor > open each table >
Export > CSV, and save the files in a staff-only folder on the office shared drive.

## Changes made in Supabase (rare)

- **Add or rename a program:** Supabase > Table Editor > programs. Set `calendar_only`
  to `true` for labels that are only used on the Calendar (like "University").
- **If the coordinator account is lost or locked out:** Supabase > Table Editor >
  volunteers > check the "Coordinator" row has role `coordinator`, approved `true`
  and status `active`. If the password is lost and the reset email does not work,
  delete that row, add it again with the same email and role `coordinator`, then
  sign up on the site with that email to set a new password.

## If something needs rebuilding

- `database/setup.sql` recreates every table and access rule in a new Supabase project.
- The content itself (guides, How To cards, calendar, notes) is only in the database and in your CSV
  backups. It is deliberately not kept on GitHub, because the files there are public.
- `config.js` holds the database address and public key. Never put a "secret" or
  "service_role" key in it.
- `app.js` lists every page and its fields at the top, under "PAGES".

## Costs

Everything is on free plans. Nothing should ever ask for a credit card. If a
service starts to, stop and ask before agreeing.
