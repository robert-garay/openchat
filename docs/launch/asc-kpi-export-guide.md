# App Store Connect — Weekly KPI Export for Campaign Agent

Robert exports numbers the cloud agent **cannot** read from App Store Connect. Paste into the campaign thread, Agent Store `internal/campaign-weekly.md`, or a weekly message. Align with OKR dashboard in Project store `docs/marketing-okrs.md`.

**App:** OpenChat Connect · **Bundle ID:** `com.genion.openchat`  
**Campaign:** `launch2026` · report **calendar week** (Mon–Sun) and **week number** (W1, W2, …).

---

## Where to click in App Store Connect

1. Sign in: [App Store Connect](https://appstoreconnect.apple.com/)
2. **Apps** → **OpenChat Connect**
3. Left sidebar → **Analytics** (or **App Analytics**)

If Analytics is empty, wait 24–48 h after first download or confirm the app version is live in all territories you care about.

---

## Metrics to copy each week

### 1. Downloads (units)

**Path:** Analytics → **Metrics** → **Units** (or **App Units**)

- Set date range: **last 7 days** (or match your reporting week).
- Note **Total** (or sum daily bars).
- Optional: screenshot the chart with date range visible.

**Paste format:**

```
Week W[N] ([YYYY-MM-DD] – [YYYY-MM-DD])
Downloads (units, 7d total): [number]
```

### 2. Product page views & conversion

**Path:** Analytics → **Metrics** → **Impressions** / **Product Page Views** (label varies by ASC UI version)

Also check **Conversion Rate** if shown on the product page funnel, or compute:

`conversion % = (units in period / product page views in period) × 100`

**Paste format:**

```
Product page views (7d): [number]
Conversion % (views → downloads, 7d): [number]%
```

### 3. Ratings & reviews (trust KR)

**Path:** **Ratings and Reviews** (under App Store tab or Analytics, depending on UI)

- **Average rating** (all versions or current version — note which).
- **Total rating count** (or review count).
- List any **new reviews this week** with 1-line summary (no PII).

**Paste format:**

```
Avg rating: [x.x] ([N] ratings total)
New reviews this week: [count]
Unanswered reviews >48h: [count] (target 0)
```

### 4. Attribution spikes (campaign log)

**Path:** Analytics → **Metrics** → **Units** → switch to **Daily** granularity

- Note dates that align with HN, Reddit, X, PH posts.
- One line per spike: `YYYY-MM-DD: ~[units] units — [channel]`

**Paste format:**

```
Daily spikes (optional):
- 2026-09-26: 42 units — Product Hunt
```

### 5. GitHub stars (not in ASC)

From https://github.com/robert-garay/openchat — paste **star count** same day as ASC export.

---

## Screenshot checklist (if pasting images instead of numbers)

Capture these with the **date range** visible in the UI:

| Screenshot | Must show |
|------------|-----------|
| Units chart | 7-day range, total or daily bars |
| Product page views | Same date range |
| Ratings summary | Average + count |

Save as PNG; attach to weekly message or drop in Agent Store `media/` if your workflow uses it.

---

## Full weekly paste template (copy for Robert)

```
OpenChat campaign weekly — W[N] ([start] – [end])

ASC:
- Downloads (7d units): 
- Product page views (7d): 
- Conversion %: 
- Avg rating / count: 
- New reviews: 
- Unanswered >48h: 

GitHub stars: 

Touchpoints shipped this week:
- [e.g. Show HN 2026-09-28]

Blockers:

Agent: please update marketing-okrs KPI table and campaign log.
```

---

## Privacy

Do not export reviewer names, emails, or App Store Connect sales/financial **Proceeds** unless needed for a separate finance report. Units and page metrics are sufficient for marketing OKRs.
