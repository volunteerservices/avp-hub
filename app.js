"use strict";

// AVP Hub. One file, no outside libraries, in four parts:
//   1. PAGES       - what each page shows (the part most likely to be edited)
//   2. Database    - talking to Supabase (sign-in and data)
//   3. Sign-in     - the sign in / sign up / reset password screens
//   4. Drawing     - turning the PAGES list into lists and forms

const REMINDER =
  "Never write passwords, door or lockbox codes, or volunteer performance reviews here.";

let session = null;   // the signed-in person's access tokens
let me = null;        // the signed-in person's row in the volunteers table
let programs = [];    // [{code, name, calendar_only}]
let names = [];       // [{id, name, status, program_year}] for every volunteer
const filters = {};   // the filter chosen on each page

// Dot colour beside each program code. A code not listed here gets grey.
const COLOURS = {
  AVP: "#b5122f", VS: "#6b4fa0", CFB: "#2f7d4f", ICLF: "#1f6fa8", Q: "#c2410c",
  VTP: "#0f766e", SSP: "#a16207", RSP: "#7c3aed", CVS: "#57534e", SU: "#9f1239",
  University: "#64748b", C10K: "#4d7c0f", "Pride Scholarship": "#db2777",
};

const isCoordinator = () => me && me.role === "coordinator";
const today = () => new Date().toLocaleDateString("en-CA");          // 2026-11-14
function schoolYear() {                                              // 2026-2027
  const d = new Date(), y = d.getFullYear();
  return d.getMonth() >= 6 ? y + "-" + (y + 1) : (y - 1) + "-" + y;
}

// =====================================================================
// 1. PAGES
//    Field types: text, longtext, steps, email, number, date, datetime,
//    yesno, choice (with options), program, volunteer.
// =====================================================================

const PAGES = {
  announcements: {
    title: "Announcements", singular: "announcement", group: "Day to day",
    lede: "Start every shift here: read the announcements, check what the last shift left for you, then pick up a task. Close your shift by writing a handover note.",
    table: "announcements", order: "pinned.desc,date.desc", layout: "cards",
    flag: row => row.pinned,
    fields: [
      { name: "message", label: "Announcement", type: "longtext", required: true },
      { name: "date", label: "Date", type: "date", required: true, initial: today },
      { name: "pinned", label: "Pinned", type: "yesno" },
    ],
  },

  notes: {
    title: "Handover notes", singular: "handover note",
    lede: "Shifts are solo, so write a note at the end of every shift: what you finished, what's left, and whether anything is urgent. At the start of a shift, read the latest notes first. Anything urgent comes before new tasks.",
    table: "handover_notes", order: "resolved.asc,urgent.desc,written_at.desc", layout: "cards",
    reminder: true,
    flag: row => row.urgent && !row.resolved,
    canAdd: () => true,
    canEdit: row => isCoordinator() || row.written_by === me.id,
    fixed: () => ({ written_by: me.id }),
    actions: row => [{
      label: row.resolved ? "Reopen" : "Mark resolved",
      patch: { resolved: !row.resolved },
    }],
    fields: [
      { name: "finished", label: "What I finished", type: "longtext", required: true },
      { name: "left_for_next", label: "What's left for the next shift", type: "longtext" },
      { name: "urgent", label: "Urgent", type: "yesno" },
      { name: "resolved", label: "Resolved", type: "yesno" },
      { name: "written_by", label: "Written by", type: "volunteer", readOnly: true },
      { name: "written_at", label: "When", type: "datetime", readOnly: true },
    ],
  },

  tasks: {
    title: "Tasks", singular: "task",
    lede: "Claim a task before you start so nobody doubles up. Downtime projects are longer jobs for quiet weeks, especially November to January and after the Appreciation Party.",
    table: "tasks", order: "program.asc,title.asc", filters: [{ field: "program" }, { field: "type" }],
    sort: rows => {
      const rank = { "in progress": 0, "to do": 1, "done": 2 };
      return rows.sort((a, b) => rank[a.status] - rank[b.status]);
    },
    actions: row => {
      const list = [];
      if (!row.claimed_by && row.status !== "done")
        list.push({ label: "Claim", patch: { claimed_by: me.id, status: "in progress" } });
      if (row.claimed_by === me.id && row.status !== "done") {
        list.push({ label: "Mark done", patch: { status: "done" } });
        list.push({ label: "Release", patch: { claimed_by: null, status: "to do" } });
      }
      return list;
    },
    fields: [
      { name: "title", label: "Title", type: "text", required: true },
      { name: "program", label: "Program", type: "program" },
      { name: "type", label: "Type", type: "choice", options: ["regular", "downtime project"] },
      { name: "status", label: "Status", type: "choice", options: ["to do", "in progress", "done"] },
      { name: "claimed_by", label: "Claimed by", type: "volunteer" },
    ],
  },

  guides: {
    title: "Front desk guides", singular: "guide",
    lede: "How to handle what walks up to the desk, including other programs' requests. Each guide is short on purpose; longer versions with screenshots live in the Guides & Templates folder on the shared drive.",
    table: "guides", order: "program.asc,title.asc", layout: "guides", filters: [{ field: "program" }],
    reminder: true,
    fields: [
      { name: "title", label: "Title", type: "text", required: true },
      { name: "program", label: "Program", type: "program" },
      { name: "steps", label: "Steps (one per line)", type: "steps", required: true },
    ],
  },

  calendar: {
    title: "Calendar", singular: "calendar date", group: "Plan & remember",
    lede: "Every program's key dates from the Volunteer Services master calendar, so you can see what's coming and when other programs will need AVP's help.",
    table: "calendar_dates", order: "date.asc.nullslast",
    filters: [{ field: "school_year", latest: true }, { field: "program" }],
    fields: [
      { name: "date", label: "Date", type: "date" },   // leave empty if still "TBD"
      { name: "program", label: "Program", type: "program", all: true },
      { name: "what_happens", label: "What happens", type: "text", required: true },
      { name: "notes", label: "Notes", type: "longtext" },
      { name: "school_year", label: "School year", type: "text", required: true, initial: schoolYear },
    ],
  },

  events: {
    title: "Events", singular: "event",
    lede: "AVP runs two signature events for all of Volunteer Services: the Volunteer Fair and the Volunteer Appreciation Party. Each has a checklist with due dates.",
    table: "events", order: "date.asc", layout: "cards",
    fields: [
      { name: "name", label: "Event", type: "text", required: true },
      { name: "date", label: "Date", type: "date" },
      { name: "location", label: "Location", type: "text" },
    ],
  },

  partners: {
    title: "Partners and sponsors", singular: "organization",
    lede: "Volunteer Fair partner organizations and Appreciation Party sponsors, by year. Start next year's list from these, and thank them again when you ask.",
    table: "organizations", order: "year.desc,name.asc", filters: [{ field: "year", latest: true }, { field: "type" }],
    fields: [
      { name: "name", label: "Organization", type: "text", required: true },
      { name: "type", label: "Type", type: "choice", options: ["fair partner", "sponsor"] },
      { name: "year", label: "Year", type: "number", required: true, initial: () => new Date().getFullYear() },
      { name: "notes", label: "Notes", type: "longtext" },
    ],
  },

  volunteers: {
    title: "Volunteers", singular: "volunteer",
    lede: "Everyone with an AVP Hub account. New sign-ups wait here until the coordinator approves them.",
    table: "volunteers", order: "approved.asc,name.asc", filters: [{ field: "program_year" }],
    flag: row => !row.approved,
    canDelete: row => isCoordinator() && row.id !== me.id,
    actions: row => row.approved ? [] : [{ label: "Approve", patch: { approved: true } }],
    check: (values, row) =>
      row && row.id === me.id &&
      (values.role !== "coordinator" || values.status !== "active" || !values.approved)
        ? "You can't remove your own coordinator access. Make the new coordinator first, then ask them to change your account."
        : "",
    fields: [
      { name: "name", label: "Name", type: "text", required: true },
      { name: "email", label: "UCalgary email", type: "email", required: true },
      { name: "status", label: "Status", type: "choice", options: ["active", "inactive"] },
      { name: "program_year", label: "Program year", type: "text", required: true, initial: schoolYear },
      { name: "role", label: "Role", type: "choice", options: ["volunteer", "coordinator"] },
      { name: "approved", label: "Approved", type: "yesno" },
    ],
  },
};

// What volunteers (not the coordinator) see on the Volunteers page: names only.
const VOLUNTEER_NAMES = {
  title: "Volunteers", table: "volunteer_names", order: "name.asc", filters: [{ field: "program_year" }],
  lede: "The AVP team.",
  canAdd: () => false, canEdit: () => false, canDelete: () => false,
  fields: [
    { name: "name", label: "Name", type: "text" },
    { name: "status", label: "Status", type: "text" },
    { name: "program_year", label: "Program year", type: "text" },
  ],
};

// The checklist shown under each event.
const EVENT_TASKS = {
  singular: "checklist item", table: "event_tasks",
  flag: row => !row.done && row.due_date && row.due_date < today(),
  actions: row => isCoordinator()
    ? [{ label: row.done ? "Not done" : "Mark done", patch: { done: !row.done } }] : [],
  fields: [
    { name: "title", label: "Task", type: "text", required: true },
    { name: "due_date", label: "Due date", type: "date" },
    { name: "done", label: "Done", type: "yesno" },
  ],
};

// =====================================================================
// 2. Database (Supabase)
// =====================================================================

const PAUSED_HELP =
  "AVP Hub can't reach its database right now. Check your internet connection. " +
  "If it still doesn't work, tell the coordinator: the database may be paused.";

function setSession(s) {
  session = s && {
    access_token: s.access_token,
    refresh_token: s.refresh_token,
    expires_at: s.expires_at || Math.floor(Date.now() / 1000) + Number(s.expires_in || 3600),
  };
  try {
    if (session) localStorage.setItem("avp-session", JSON.stringify(session));
    else localStorage.removeItem("avp-session");
  } catch (e) { /* private browsing: stay signed in until the tab closes */ }
}

async function request(url, method, body, token) {
  const headers = { apikey: SUPABASE_KEY, "Content-Type": "application/json", Prefer: "return=representation" };
  if (token) headers.Authorization = "Bearer " + token;
  let res;
  try {
    res = await fetch(SUPABASE_URL + url, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch (e) {
    throw new Error(PAUSED_HELP);
  }
  let data = null;
  try { data = await res.json(); } catch (e) { /* empty answer */ }
  if (!res.ok) {
    const err = new Error(res.status >= 500 ? PAUSED_HELP : friendly(data, res.status));
    err.status = res.status;
    throw err;
  }
  return data;
}

function friendly(data, status) {
  data = data || {};
  if (data.code === "42501") return "You don't have permission to do that.";
  if (data.code === "23505") return "That already exists (for example, the same email twice).";
  if (data.code === "23503") return "That is still used somewhere else, so it can't be removed.";
  if (data.code === "23514") return "One of the values isn't allowed. Emails must end in @ucalgary.ca.";
  return data.msg || data.error_description || data.message || "Something went wrong (error " + status + ").";
}

// Sign-in service calls.
const auth = (method, path, body, token) => request("/auth/v1/" + path, method, body, token);

// Tokens last about an hour; swap for a new one shortly before that.
let refreshing = null;
async function freshToken() {
  if (!session) throw new Error("Please sign in again.");
  if (session.expires_at - 60 > Date.now() / 1000) return session.access_token;
  if (!refreshing) {
    refreshing = auth("POST", "token?grant_type=refresh_token", { refresh_token: session.refresh_token })
      .then(setSession, err => {
        if (err.status >= 400 && err.status < 500) {
          setSession(null);
          throw new Error("Please sign in again.");
        }
        throw err;
      })
      .finally(() => { refreshing = null; });
  }
  await refreshing;
  return session.access_token;
}

// Data calls. Examples:
//   api("GET", "tasks?select=*")        api("POST", "tasks", {title: "..."})
//   api("PATCH", "tasks?id=eq.5", {...}) api("DELETE", "tasks?id=eq.5")
async function api(method, path, body) {
  const token = await freshToken();
  let data;
  try {
    data = await request("/rest/v1/" + path, method, body, token);
  } catch (err) {
    if (err.status === 401) { setSession(null); throw new Error("Please sign in again."); }
    throw err;
  }
  if (method !== "GET" && Array.isArray(data) && data.length === 0)
    throw new Error("You don't have permission to change that.");
  return data;
}

// The signed-in person's ID, read from inside the access token.
function userId() {
  const part = session.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(part)).sub;
}

// =====================================================================
// 3. Sign-in screens
// =====================================================================

const $ = id => document.getElementById(id);

// Build a page element: el("p", {className: "x"}, "text", otherElement)
function el(tag, props, ...children) {
  const node = Object.assign(document.createElement(tag), props || {});
  for (const child of children.flat()) {
    if (child !== null && child !== undefined && child !== false) node.append(child);
  }
  return node;
}

function signedOutScreen(...content) {
  $("nav").replaceChildren();
  $("who").replaceChildren();
  $("main").replaceChildren(el("section", { className: "panel signin" }, content));
}

function renderSignIn(mode, message) {
  mode = mode || "signin";
  const titles = { signin: "Sign in", signup: "Create your account", forgot: "Reset your password" };
  const name = el("input", { type: "text", required: true, autocomplete: "name" });
  const email = el("input", { type: "email", required: true, autocomplete: "email", placeholder: "you@ucalgary.ca" });
  const password = el("input", {
    type: "password", required: true, minLength: 8,
    autocomplete: mode === "signup" ? "new-password" : "current-password",
  });
  const note = el("p", { className: message ? "error" : "small muted" }, message || "");
  const button = el("button", { className: "primary", type: "submit" },
    mode === "forgot" ? "Send reset link" : titles[mode]);
  const here = encodeURIComponent(location.origin + location.pathname);

  const form = el("form", {},
    mode === "signup" && el("label", {}, "Your name", name),
    el("label", {}, "UCalgary email", email),
    mode !== "forgot" && el("label", {}, mode === "signup" ? "Choose a password (8 or more characters)" : "Password", password),
    button, note);

  form.onsubmit = async e => {
    e.preventDefault();
    const address = email.value.trim().toLowerCase();
    note.className = "error";
    if (mode !== "signin" && !address.endsWith("@ucalgary.ca")) {
      note.textContent = "Please use your @ucalgary.ca email address.";
      return;
    }
    button.disabled = true;
    try {
      if (mode === "signin") {
        setSession(await auth("POST", "token?grant_type=password", { email: address, password: password.value }));
        return start();
      }
      if (mode === "signup") {
        const data = await auth("POST", "signup?redirect_to=" + here,
          { email: address, password: password.value, data: { name: name.value.trim() } });
        if (data.access_token) { setSession(data); return start(); }
        return signedOutScreen(
          el("h2", {}, "Check your email"),
          el("p", {}, "We sent a confirmation link to " + address + ". Click it, then wait for the coordinator to approve your account."),
          el("button", { className: "link", onclick: () => renderSignIn() }, "Back to sign in"));
      }
      await auth("POST", "recover?redirect_to=" + here, { email: address });
      note.className = "small muted";
      note.textContent = "If that email has an account, a reset link is on its way.";
    } catch (err) {
      note.textContent = err.message;
    }
    button.disabled = false;
  };

  const link = (label, target) =>
    el("p", {}, el("button", { className: "link", type: "button", onclick: () => renderSignIn(target) }, label));

  signedOutScreen(
    el("h2", {}, titles[mode]), form,
    mode !== "signin" && link("Back to sign in", "signin"),
    mode === "signin" && link("New volunteer? Create your account", "signup"),
    mode === "signin" && link("Forgot your password?", "forgot"));
}

// Shown after clicking the reset link in the email.
function renderNewPassword() {
  const password = el("input", { type: "password", required: true, minLength: 8, autocomplete: "new-password" });
  const note = el("p", { className: "error" });
  const form = el("form", {},
    el("label", {}, "New password (8 or more characters)", password),
    el("button", { className: "primary", type: "submit" }, "Save password"), note);
  form.onsubmit = async e => {
    e.preventDefault();
    try {
      await auth("PUT", "user", { password: password.value }, await freshToken());
      start();
    } catch (err) { note.textContent = err.message; }
  };
  signedOutScreen(el("h2", {}, "Choose a new password"), form);
}

function renderWaiting() {
  const text = !me || !me.approved
    ? "Your account is waiting for the coordinator's approval. Check back after they let you know."
    : "Your account is inactive. Please contact the coordinator.";
  signedOutScreen(
    el("h2", {}, "Almost there"), el("p", {}, text),
    el("div", { className: "row" },
      el("button", { onclick: start }, "Check again"),
      el("button", { onclick: signOut }, "Sign out")));
}

async function signOut() {
  const token = session && session.access_token;
  setSession(null);
  me = null;
  if (token) auth("POST", "logout", {}, token).catch(() => {});
  location.hash = "";
  renderSignIn();
}

// Runs when the site opens, and again after signing in.
async function start() {
  if (SUPABASE_URL.startsWith("PASTE")) {
    return signedOutScreen(el("h2", {}, "Not connected yet"),
      el("p", {}, "The database address has not been added to config.js."));
  }

  // Arriving from a link in a confirmation or reset email.
  const link = new URLSearchParams(location.hash.slice(1) || location.search.slice(1));
  if (link.get("access_token") || link.get("error_description")) {
    history.replaceState(null, "", location.pathname);
    if (link.get("error_description")) return renderSignIn("signin", link.get("error_description"));
    setSession({
      access_token: link.get("access_token"),
      refresh_token: link.get("refresh_token"),
      expires_in: link.get("expires_in"),
    });
    if (link.get("type") === "recovery") return renderNewPassword();
  }

  if (!session) return renderSignIn();

  try {
    me = (await api("GET", "volunteers?select=*&user_id=eq." + userId()))[0] || null;
    if (!me || !me.approved || me.status !== "active") return renderWaiting();
    await loadLookups();
  } catch (err) {
    if (!session) return renderSignIn("signin", err.message);
    return signedOutScreen(el("h2", {}, "Something went wrong"), el("p", { className: "error" }, err.message),
      el("button", { onclick: start }, "Try again"));
  }

  $("who").replaceChildren(
    el("span", {}, me.name + (isCoordinator() ? " (coordinator)" : "")),
    el("button", { className: "link", onclick: signOut }, "Sign out"));
  route();
}

async function loadLookups() {
  const [p, n] = await Promise.all([
    api("GET", "programs?select=*&order=code.asc"),
    api("GET", "volunteer_names?select=*&order=name.asc"),
  ]);
  programs = p;
  names = n;
}

// =====================================================================
// 4. Drawing pages
// =====================================================================

function currentPage() {
  const key = location.hash.slice(1);
  return PAGES[key] ? key : "announcements";
}

async function route() {
  if (!me) return;
  const key = currentPage();
  $("nav").replaceChildren(...Object.keys(PAGES).flatMap(k => [
    PAGES[k].group && el("div", { className: "navgroup" }, PAGES[k].group),
    el("a", { href: "#" + k, ariaCurrent: k === key ? "page" : null }, PAGES[k].title),
  ]).filter(Boolean));
  document.title = PAGES[key].title + " · AVP Hub";

  const def = key === "volunteers" && !isCoordinator() ? VOLUNTEER_NAMES : PAGES[key];
  const head = el("div", { className: "head" },
    el("h1", {}, def.title), el("p", { className: "lede" }, def.lede));
  const main = $("main");
  if (main.dataset.page !== key)               // first visit to this page: show "Loading"
    main.replaceChildren(head, el("p", { className: "muted" }, "Loading…"));
  main.dataset.page = key;
  try {
    const content = key === "events" ? await drawEvents() : await drawPage(key, def);
    if (key !== currentPage()) return;          // they moved on while it loaded
    main.replaceChildren(head, ...content);
  } catch (err) {
    if (!session) return renderSignIn("signin", err.message);
    main.replaceChildren(head, el("p", { className: "error" }, err.message));
  }
}

// Permission checks, with "coordinator only" as the default.
const canAdd = def => def.canAdd ? def.canAdd() : isCoordinator();
const canEdit = (def, row) => def.canEdit ? def.canEdit(row) : isCoordinator();
const canDelete = (def, row) => def.canDelete ? def.canDelete(row) : isCoordinator();

async function drawPage(key, def) {
  let rows = await api("GET", def.table + "?select=*&order=" + def.order);
  if (def.sort) rows = def.sort(rows);

  const toolbar = el("div", { className: "row" });
  if (canAdd(def))
    toolbar.append(el("button", { className: "primary", onclick: () => openForm(def) }, "Add " + def.singular));

  // The drop-downs that narrow the list ("All" shows everything).
  for (const filter of def.filters || []) {
    const field = def.fields.find(f => f.name === filter.field);
    const values = [...new Set(rows.map(row => row[filter.field]))].sort();
    if (filter.latest) values.reverse();
    const memory = key + ":" + filter.field;
    let chosen = memory in filters ? filters[memory] : (filter.latest && values.length ? String(values[0]) : "");
    if (!values.map(String).includes(chosen)) chosen = "";
    const select = el("select", {},
      el("option", { value: "" }, "All"),
      values.map(v => el("option", { value: String(v), selected: String(v) === chosen }, String(v))));
    select.onchange = () => { filters[memory] = select.value; route(); };
    toolbar.append(el("label", {}, field.label, select));
    if (chosen) rows = rows.filter(row => String(row[filter.field]) === chosen);
  }

  return [toolbar, drawRows(def, rows)];
}

async function drawEvents() {
  const def = PAGES.events;
  const [events, tasks] = await Promise.all([
    api("GET", "events?select=*&order=date.asc.nullslast,name.asc"),
    api("GET", "event_tasks?select=*&order=due_date.asc.nullslast,title.asc"),
  ]);
  const out = [];
  if (canAdd(def))
    out.push(el("div", { className: "row" },
      el("button", { className: "primary", onclick: () => openForm(def) }, "Add event")));
  if (!events.length) out.push(el("p", { className: "empty" }, "Nothing here yet."));

  for (const event of events) {
    const mine = tasks.filter(task => task.event_id === event.id);
    out.push(el("section", { className: "panel" },
      el("h2", {}, event.name),
      el("p", { className: "muted" },
        (event.date ? show(def.fields[1], event) : "Date not set") + " · " + (event.location || "Location not set")),
      rowButtons(def, event),
      el("h3", {}, "Checklist"),
      mine.length ? drawTable(EVENT_TASKS, mine) : el("p", { className: "empty" }, "No checklist items yet."),
      isCoordinator() && el("div", { className: "row" },
        el("button", { onclick: () => openForm(EVENT_TASKS, null, { event_id: event.id }) }, "Add checklist item"))));
  }
  return out;
}

// A list of rows: a table, cards, or guides that open and close.
function drawRows(def, rows) {
  if (!rows.length) return el("p", { className: "empty" }, "Nothing here yet.");

  if (def.layout === "guides") {
    return el("div", { className: "grid" }, rows.map(row =>
      el("details", {},
        el("summary", {}, el("span", {}, row.title), chip(row.program)),
        el("div", { className: "body" }, show(def.fields[2], row), rowButtons(def, row)))));
  }

  if (def.layout === "cards") {
    return el("div", { className: "grid" }, rows.map(row => {
      const [first, ...rest] = def.fields;
      return el("section", { className: "panel" + (def.flag && def.flag(row) ? " flag" : "") },
        first.type === "text" ? el("h3", {}, show(first, row)) : el("p", {}, show(first, row)),
        rest.map(f => el("p", { className: "small" },
          el("span", { className: "muted" }, f.label + ": "), show(f, row))),
        rowButtons(def, row));
    }));
  }

  return el("section", { className: "panel" }, drawTable(def, rows));
}

function drawTable(def, rows) {
  return el("div", { className: "tablewrap" }, el("table", {},
    el("thead", {}, el("tr", {}, def.fields.map(f => el("th", {}, f.label)), el("th", {}))),
    el("tbody", {}, rows.map(row =>
      el("tr", { className: def.flag && def.flag(row) ? "flag" : "" },
        def.fields.map(f => el("td", {}, show(f, row))),
        el("td", {}, rowButtons(def, row)))))));
}

// A small coloured label for a program code.
function chip(code) {
  const program = programs.find(p => p.code === code);
  return el("span", { className: "chip" + (code === "AVP" ? " avp" : ""), title: program ? program.name : code },
    el("i", { style: "background:" + (COLOURS[code] || "#888") }), code);
}

// One value, ready to display.
function show(field, row) {
  const value = row[field.name];
  if (field.type === "yesno") return value ? "Yes" : "No";
  if (value === null || value === undefined || value === "") return "—";
  if (field.type === "date")
    return new Date(value + "T00:00").toLocaleDateString("en-CA", { year: "numeric", month: "short", day: "numeric" });
  if (field.type === "datetime")
    return new Date(value).toLocaleString("en-CA", { dateStyle: "medium", timeStyle: "short" });
  if (field.type === "volunteer") {
    const person = names.find(n => n.id === value);
    return person ? person.name : "Former volunteer";
  }
  if (field.type === "program") return chip(value);
  if (field.type === "steps")
    return el("ol", {}, String(value).split("\n").filter(line => line.trim()).map(line => el("li", {}, line.trim())));
  return String(value);
}

// The buttons beside one row.
function rowButtons(def, row) {
  const buttons = [];
  for (const action of (def.actions ? def.actions(row) : [])) {
    buttons.push(el("button", { onclick: () => change(() =>
      api("PATCH", def.table + "?id=eq." + row.id, action.patch)) }, action.label));
  }
  if (canEdit(def, row)) buttons.push(el("button", { onclick: () => openForm(def, row) }, "Edit"));
  if (canDelete(def, row)) {
    buttons.push(el("button", { onclick: () => {
      if (confirm("Delete this " + def.singular + "? This cannot be undone."))
        change(() => api("DELETE", def.table + "?id=eq." + row.id));
    } }, "Delete"));
  }
  return buttons.length ? el("div", { className: "row" }, buttons) : "";
}

// Make a change, then redraw the page. Problems are shown in a pop-up.
async function change(action) {
  try {
    await action();
    if (currentPage() === "volunteers") await loadLookups();
  } catch (err) {
    alert(err.message);
  }
  route();
}

// The add / edit window. "row" is empty when adding.
function openForm(def, row, extra) {
  const dialog = $("dialog");
  const inputs = {};
  const note = el("p", { className: "error" });

  const form = el("form", {},
    el("h2", {}, (row ? "Edit " : "Add ") + def.singular),
    def.reminder && el("p", { className: "note gold" }, REMINDER),
    def.fields.filter(f => !f.readOnly).map(f => {
      const start = row ? row[f.name] : (f.initial ? f.initial() : null);
      inputs[f.name] = makeInput(f, start);
      return el("label", {}, f.label, inputs[f.name]);
    }),
    note,
    el("div", { className: "row" },
      el("button", { className: "primary", type: "submit" }, "Save"),
      el("button", { type: "button", onclick: () => dialog.close() }, "Cancel")));

  form.onsubmit = async e => {
    e.preventDefault();
    const values = {};
    for (const f of def.fields) if (inputs[f.name]) values[f.name] = readInput(f, inputs[f.name]);
    const problem = def.check ? def.check(values, row) : "";
    if (problem) { note.textContent = problem; return; }
    try {
      if (row) await api("PATCH", def.table + "?id=eq." + row.id, values);
      else await api("POST", def.table, { ...values, ...(def.fixed ? def.fixed() : {}), ...(extra || {}) });
      if (def.table === "volunteers") await loadLookups();
      dialog.close();
      route();
    } catch (err) {
      note.textContent = err.message;
    }
  };

  dialog.replaceChildren(form);
  dialog.showModal();
}

function makeInput(field, value) {
  const options = list => list.map(([v, label]) =>
    el("option", { value: v, selected: String(value === null || value === undefined ? "" : value) === v }, label));

  if (field.type === "longtext" || field.type === "steps")
    return el("textarea", { value: value || "", required: !!field.required });
  if (field.type === "yesno")
    return el("select", {}, options([["false", "No"], ["true", "Yes"]]));
  if (field.type === "choice")
    return el("select", {}, options(field.options.map(o => [o, o])));
  if (field.type === "program")
    return el("select", {}, options(programs
      .filter(p => field.all || !p.calendar_only || p.code === value)
      .map(p => [p.code, p.code === p.name ? p.code : p.code + " · " + p.name])));
  if (field.type === "volunteer")
    return el("select", {}, options([["", "Nobody"]].concat(
      names.filter(n => n.status === "active" || n.id === value).map(n => [String(n.id), n.name]))));

  const type = { email: "email", number: "number", date: "date" }[field.type] || "text";
  return el("input", { type, value: value === null || value === undefined ? "" : value, required: !!field.required });
}

function readInput(field, input) {
  const value = input.value.trim();
  if (field.type === "yesno") return value === "true";
  if (field.type === "number") return Number(value);
  if (field.type === "volunteer") return value ? Number(value) : null;
  if (field.type === "date") return value || null;
  if (field.type === "email") return value.toLowerCase();
  return value;
}

// =====================================================================
// Go
// =====================================================================

try { session = JSON.parse(localStorage.getItem("avp-session")); } catch (e) { session = null; }
window.addEventListener("hashchange", route);
start();
