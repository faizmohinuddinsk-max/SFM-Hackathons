/* =====================================================================
   SFM-Hackathons: app.js
   What this file does:
     1. Loads the events from hackathons.json
     2. Applies the search box and filters
     3. Draws the cards and the details popup
     4. Remembers saved events on the visitor's own device
   ===================================================================== */

/* ---------- 1. Small helpers ---------- */
const $ = s => document.querySelector(s);           // shortcut: $("#grid") finds the element with id "grid"

// Makes text safe before placing it in the page (stops stray HTML from breaking the layout)
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// Only allow real web links on the Register button
const safeUrl = u => /^https?:\/\//i.test(u || "") ? u : "";

// The topic chips. These match the "domain" values the collector writes.
const DOMAINS = ["Software", "Hardware", "Cybersecurity", "Web", "AI/ML", "Other"];

// Small icons used on the cards
const ICON = {
  cal: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>',
  pin: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="10" r="3"/><path d="M12 21s7-6.5 7-11a7 7 0 1 0-14 0c0 4.5 7 11 7 11z"/></svg>',
  star: '<svg width="19" height="19" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="m12 2 3 7h7l-5.5 4.5L18.5 21 12 16.5 5.5 21l2-7.5L2 9h7z"/></svg>',
  starO: '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="m12 2 3 7h7l-5.5 4.5L18.5 21 12 16.5 5.5 21l2-7.5L2 9h7z"/></svg>'
};

/* ---------- 2. State: everything the page currently remembers ---------- */
// Saved events live in the browser's localStorage, so they stay private to each visitor.
let saved = new Set();
try { saved = new Set(JSON.parse(localStorage.getItem("saved") || "[]")); } catch (e) {}

const S = {
  all: [],            // every event loaded from hackathons.json
  list: [],           // the events currently shown (after filters)
  q: "",              // text in the search box
  kol: false,         // is the Kolkata chip on?
  mode: "All",        // All, Online or Offline
  domain: "All",      // All or one of DOMAINS
  org: "All",         // organiser type from the Filters panel
  from: "", to: "",   // date range from the Filters panel
  savedOnly: false    // is the Saved chip on?
};

/* ---------- 3. Little functions that answer questions about an event ---------- */
const id = h => h.title + "|" + h.event_date;                         // unique name used for saving
const isOnline = h => (h.mode || "").toLowerCase() === "online";
const isKol = h => ((h.city || "") + " " + (h.location || "")).toLowerCase().includes("kolkata");

// How many days until the event starts (null if the date is missing or invalid)
const daysTo = d => {
  const t = new Date(d + "T00:00:00");
  return isNaN(t) ? null : Math.round((t - new Date().setHours(0, 0, 0, 0)) / 864e5);
};

// Turns 2026-11-05 into "5 Nov 2026"
const fmtDate = d => {
  const t = new Date(d + "T00:00:00");
  return isNaN(t) ? "Date to be announced" : t.toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
};

// Date colour: red inside 7 days, amber inside 14, grey otherwise
const urgency = h => {
  const n = daysTo(h.event_date);
  return n === null ? "#6B7280" : n <= 7 ? "#E2664F" : n <= 14 ? "#E2A23D" : "#6B7280";
};

const toast = m => { const t = $("#toast"); t.textContent = m; t.classList.add("show"); setTimeout(() => t.classList.remove("show"), 1800); };
const notice = m => { const n = $("#notice"); n.textContent = m; n.classList.toggle("show", !!m); };

/* ---------- 4. Load the events ---------- */
async function load() {
  try {
    // "no-store" makes sure visitors always get the newest file, not an old copy
    const res = await fetch("hackathons.json", { cache: "no-store" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    S.all = data.hackathons || [];
    if (data.updated) $("#updated").textContent = "Last updated " + new Date(data.updated).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" });
    if (!S.all.length) notice("No hackathons yet. The first daily update fills this in, or run the workflow by hand from the Actions tab.");
  } catch (e) {
    notice("Could not load hackathons.json (" + e.message + "). If you opened index.html directly from a folder, use the GitHub Pages link instead.");
  }
}

/* ---------- 5. Filtering ---------- */
function filtered() {
  const q = S.q.toLowerCase();
  return S.all.filter(h => {
    const n = daysTo(h.event_date);
    if (n !== null && n < 0) return false;                                            // hide events that already started
    if (S.kol && !isKol(h)) return false;                                             // Kolkata chip
    if (S.mode !== "All" && (isOnline(h) ? "Online" : "Offline") !== S.mode) return false;
    if (S.domain !== "All" && (h.domain || "Other").toLowerCase() !== S.domain.toLowerCase()) return false;
    if (S.org !== "All" && h.category !== S.org) return false;                        // organiser type
    if (S.from && h.event_date < S.from) return false;                                // date range
    if (S.to && h.event_date > S.to) return false;
    if (S.savedOnly && !saved.has(id(h))) return false;                               // Saved chip
    // Search box looks in the title, organiser, place, topic and summary
    if (q && ![h.title, h.organizer, h.city, h.location, h.domain, h.summary].join(" ").toLowerCase().includes(q)) return false;
    return true;
  }).sort((a, b) => (a.event_date || "9999").localeCompare(b.event_date || "9999"));  // soonest first
}

/* ---------- 6. Drawing the page ---------- */
function buildChips() {
  const chip = (label, attr, on, cls = "") => `<button class="chip ${cls} ${on ? "on" : ""}" ${attr}>${label}</button>`;
  $("#chips").innerHTML =
    chip(ICON.pin + "Kolkata", 'data-k="kol"', S.kol, "kol") + '<span class="sep"></span>' +
    ["All", "Online", "Offline"].map(m => chip(m, `data-k="mode" data-v="${m}"`, S.mode === m)).join("") + '<span class="sep"></span>' +
    ["All", ...DOMAINS].map(m => chip(m, `data-k="domain" data-v="${m}"`, S.domain === m)).join("") + '<span class="sep"></span>' +
    chip("Saved", 'data-k="saved"', S.savedOnly);
}

function render() {
  buildChips();

  // Summary numbers (count only events that have not started yet)
  const up = S.all.filter(h => { const n = daysTo(h.event_date); return n === null || n >= 0; });
  $("#s-all").textContent = up.length;
  $("#s-on").textContent = up.filter(isOnline).length;
  $("#s-off").textContent = up.filter(h => !isOnline(h)).length;
  $("#s-kol").textContent = up.filter(isKol).length;

  // Cards
  S.list = filtered();
  $("#count").textContent = S.list.length + (S.list.length === 1 ? " hackathon" : " hackathons") + ", soonest first";
  $("#grid").innerHTML = S.list.length ? S.list.map((h, i) => `
    <article class="card" data-i="${i}" tabindex="0">
      <div class="card-top">
        <div class="tags">
          <span class="tag">${esc(h.domain || "Other")}</span>
          <span class="tag ${isOnline(h) ? "online" : "offline"}">${isOnline(h) ? "Online" : "Offline"}</span>
        </div>
        <button class="star ${saved.has(id(h)) ? "on" : ""}" data-star="${i}" aria-label="Save ${esc(h.title)}">${saved.has(id(h)) ? ICON.star : ICON.starO}</button>
      </div>
      <h3>${esc(h.title)}</h3>
      <div class="org">${esc(h.organizer)}</div>
      <div class="meta" style="color:${urgency(h)}">${ICON.cal}${fmtDate(h.event_date)}${h.days_left ? " · " + esc(h.days_left) : ""}</div>
      <div class="meta">${ICON.pin}${esc(h.location || (isOnline(h) ? "Online" : "India"))}</div>
      <div class="card-foot"><span class="prize">${esc(h.prize || "TBA")}</span><span class="more">View details</span></div>
    </article>`).join("")
    : `<div class="empty">No hackathons match these filters. Try clearing a filter or searching something broader.</div>`;
}

/* ---------- 7. Details popup ---------- */
function openModal(h) {
  const url = safeUrl(h.url);
  $("#modal").innerHTML = `
    <div class="modal-head"><h2 id="m-title">${esc(h.title)}</h2><button class="x" id="mx" aria-label="Close">✕</button></div>
    <div class="org" style="margin-top:4px">${esc(h.organizer)}</div>
    <div class="kv">
      <div><small>Date</small><b>${fmtDate(h.event_date)}</b></div>
      <div><small>Mode</small><b>${isOnline(h) ? "Online" : "Offline"}</b></div>
      <div><small>Location</small><b>${esc(h.location || (isOnline(h) ? "Online" : "India"))}</b></div>
      <div><small>Prize</small><b style="color:#2FA35A">${esc(h.prize || "TBA")}</b></div>
      <div class="wide"><small>Who can join</small><b>${esc(h.eligibility || "CSE students")}</b></div>
    </div>
    <p class="summary">${esc(h.summary || "No summary available.")}</p>
    <div class="actions">
      ${url ? `<a class="go" href="${esc(url)}" target="_blank" rel="noopener">Register on official site</a>` : `<button class="go" disabled>No link yet</button>`}
      <button id="share" style="flex:0 0 auto">Share</button>
    </div>`;
  $("#overlay").classList.add("open");
  $("#mx").onclick = closeModal;
  // Share copies a short text the visitor can paste anywhere
  $("#share").onclick = async () => {
    try { await navigator.clipboard.writeText(`${h.title}, ${fmtDate(h.event_date)}\n${h.location || ""}\n${url}`); toast("Copied. Paste it to share."); }
    catch (e) { toast("Could not copy. Try again."); }
  };
}
const closeModal = () => $("#overlay").classList.remove("open");

/* ---------- 8. Wiring up clicks and typing ---------- */
// Clicking a card opens details; clicking its star saves or unsaves it
$("#grid").addEventListener("click", e => {
  const star = e.target.closest("[data-star]");
  if (star) {
    e.stopPropagation();
    const key = id(S.list[+star.dataset.star]);
    saved.has(key) ? saved.delete(key) : saved.add(key);
    try { localStorage.setItem("saved", JSON.stringify([...saved])); } catch (err) {}
    return render();
  }
  const card = e.target.closest(".card");
  if (card) openModal(S.list[+card.dataset.i]);
});
$("#grid").addEventListener("keydown", e => { if (e.key === "Enter" && e.target.classList.contains("card")) openModal(S.list[+e.target.dataset.i]); });

// Close the popup by clicking the dark area or pressing Escape
$("#overlay").addEventListener("click", e => { if (e.target.id === "overlay") closeModal(); });
document.addEventListener("keydown", e => { if (e.key === "Escape") closeModal(); });

// Chips: Kolkata and Saved switch on/off, the others pick one value
$("#chips").addEventListener("click", e => {
  const b = e.target.closest(".chip"); if (!b) return;
  const k = b.dataset.k;
  if (k === "kol") S.kol = !S.kol; else if (k === "saved") S.savedOnly = !S.savedOnly; else S[k] = b.dataset.v;
  render();
});

// Search box and the Filters panel
$("#q").addEventListener("input", e => { S.q = e.target.value.trim(); render(); });
$("#advBtn").addEventListener("click", e => {
  const open = $("#adv").classList.toggle("open");
  e.currentTarget.classList.toggle("on", open);
  e.currentTarget.setAttribute("aria-expanded", open);
});
$("#f-org").addEventListener("change", e => { S.org = e.target.value; render(); });
$("#f-from").addEventListener("change", e => { S.from = e.target.value; render(); });
$("#f-to").addEventListener("change", e => { S.to = e.target.value; render(); });
$("#clear").addEventListener("click", () => {
  Object.assign(S, { q: "", kol: false, mode: "All", domain: "All", org: "All", from: "", to: "", savedOnly: false });
  $("#q").value = ""; $("#f-org").value = "All"; $("#f-from").value = ""; $("#f-to").value = "";
  render();
});

/* ---------- 9. Start ---------- */
load().then(render);
