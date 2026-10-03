import { readFile, writeFile } from "node:fs/promises";

const MODEL = "gemini-2.5-flash";      //Model id
const WINDOW_DAYS = 182;               //looks 6 months ahead
const FILE = "hackathons.json";         

const SEARCHES = [
  "online hackathons of any kind that CSE / computer science students can join",
  "offline hackathons in India focused on software, web development or AI/ML",
  "offline hackathons in India focused on hardware, IoT, robotics or embedded systems",
  "cybersecurity hackathons and CTF competitions, online or offline in India",
  "hackathons in Kolkata and West Bengal for engineering students",
  "national and government-run hackathons in India open to engineering students, such as Smart India Hackathon",
];

const PROMPT = `Today's date is {today}.
Search the web for real hackathons and coding competitions starting between {today} and {end}.
Focus: {focus}.

Rules:
- The event must be open to Computer Science / CSE students. Skip events restricted to other branches or to non-students.
- Online events can be hosted anywhere in the world.
- Offline (or hybrid) events must physically take place in India.
- Only include events with a real, verifiable date. Never invent events.

Respond with ONLY a valid JSON array, no commentary, no markdown fences, no citations.
Each object must have exactly these keys:
"title", "organizer",
"mode": "Online" or "Offline",
"city": city in India, or "" for online events,
"state": Indian state, or "" for online events,
"country": country where an offline event happens, or "" for online events,
"location": venue or "Online",
"prize": prize details or "TBA",
"event_date": start date as YYYY-MM-DD,
"days_left": registration status in plain words (for example "Registration open"),
"eligibility": who can apply,
"category": one of "Undergraduate", "Independent", "Government",
"domain": one of "Software", "Hardware", "Cybersecurity", "Web", "AI/ML", "Other",
"url": official website link,
"summary": a clear 2-sentence summary of the tech focus.`;
/* Asks Geminie */
// Pulls the JSON list out of the reply, even if Gemini wrapped it in text or code fences
export function extractJson(text) {
  const cleaned = text.replace(/```(json)?/g, "").trim();
  try { return JSON.parse(cleaned); } catch {}
  const match = cleaned.match(/\[[\s\S]*\]/);
  if (match) return JSON.parse(match[0]);
  throw new Error("No JSON list found in the reply");
}

async function askGemini(focus, today, end, tries = 3) {
  const prompt = PROMPT.replaceAll("{focus}", focus).replaceAll("{today}", today).replaceAll("{end}", end);
  for (let attempt = 1; attempt <= tries; attempt++) {
    try {
      const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": process.env.GEMINI_API_KEY },
        // google_search lets Gemini look things up on the web.
        // We do not set temperature: Gemini 3.6 Flash does not accept custom values for it.
        body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], tools: [{ google_search: {} }] }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
      const data = await res.json();
      const text = (data.candidates?.[0]?.content?.parts || []).map(p => p.text || "").join("");
      return extractJson(text);
    } catch (err) {
      console.log(`  attempt ${attempt}/${tries} failed: ${err.message}`);
      await new Promise(r => setTimeout(r, 5000 * attempt));   // wait a bit longer after each failure
    }
  }
  return [];   // give up on this search, the others still run
}

/* Result */
// Turns Gemini's free-form topic into one of the six fixed topics used by the website filters
function normalizeDomain(v = "") {
  v = v.toLowerCase();
  if (/\b(ai|ml)\b|machine|data/.test(v)) return "AI/ML";
  if (/cyber|security|ctf/.test(v)) return "Cybersecurity";
  if (/hardware|iot|robot|embedded/.test(v)) return "Hardware";
  if (v.includes("web")) return "Web";
  if (v.includes("software")) return "Software";
  return "Other";
}

// Checks one event. Returns a clean event, or null if it breaks a rule.
export function clean(item, today, end) {
  const title = String(item.title || "").trim();
  const date = String(item.event_date || "");
  if (!title || !/^\d{4}-\d{2}-\d{2}$/.test(date) || date < today || date > end) return null;   // needs a real date inside the window

  const mode = String(item.mode || "").toLowerCase();
  const country = String(item.country || "").trim().toLowerCase();
  let city = "", state = "", location = "Online", finalMode = "Online";

  if (mode !== "online") {
    if (!["offline", "hybrid"].includes(mode)) return null;               // unknown mode
    if (!["india", "in", "bharat"].includes(country)) return null;        // offline events must be in India
    finalMode = "Offline";
    city = String(item.city || "").trim();
    state = String(item.state || "").trim();
    location = String(item.location || "").trim() || [city, state].filter(Boolean).join(", ") || "India";
  }

  const category = ["Undergraduate", "Independent", "Government"].includes(item.category) ? item.category : "Independent";
  const url = /^https?:\/\//i.test(item.url || "") ? String(item.url).trim() : "";   // only real web links

  return {
    title, organizer: String(item.organizer || "").trim(), mode: finalMode, city, state, location,
    prize: String(item.prize || "TBA").trim(), event_date: date, days_left: String(item.days_left || "").trim(),
    eligibility: String(item.eligibility || "CSE students").trim(), category,
    domain: normalizeDomain(item.domain), url, summary: String(item.summary || "").trim(),
  };
}

// Same title + same date = same event, so duplicates collapse into one
const eventId = e => e.title.toLowerCase().replace(/[^a-z0-9]+/g, "") + e.event_date;

async function main() {
  if (!process.env.GEMINI_API_KEY) throw new Error("GEMINI_API_KEY is not set. Add it as a repository secret.");

  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  const end = new Date(now.getTime() + WINDOW_DAYS * 864e5).toISOString().slice(0, 10);

  // Start from what is already saved, so events do not vanish just because one search missed them
  const merged = new Map();
  try {
    const old = JSON.parse(await readFile(FILE, "utf8"));
    for (const e of old.hackathons || []) if (e.event_date >= today) merged.set(eventId(e), e);   // keep only upcoming ones
  } catch {}

  let found = 0;
  for (const focus of SEARCHES) {
    console.log("Searching:", focus);
    for (const raw of await askGemini(focus, today, end)) {
      const event = raw && typeof raw === "object" ? clean(raw, today, end) : null;
      if (event) { merged.set(eventId(event), event); found++; }   // new info replaces old info
    }
    console.log(`  valid events so far this run: ${found}`);
  }

  // Safety: if nothing valid came back, leave the file alone and mark the run as failed
  if (found === 0) throw new Error("No valid events found. hackathons.json was not changed.");

  const list = [...merged.values()].sort((a, b) => a.event_date.localeCompare(b.event_date));
  await writeFile(FILE, JSON.stringify({ updated: now.toISOString(), hackathons: list }, null, 2) + "\n");
  console.log(`Saved ${list.length} hackathons to ${FILE}.`);
}

// Only run main() when this file is started directly (so the checks above can be tested on their own)
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(err => { console.error(err.message); process.exit(1); });
}
