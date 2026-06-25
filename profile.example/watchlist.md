# Watchlist

> _The companies you want CoApply to keep an eye on. `/coapply:discover` checks each
> one's public job board and shows you the roles that match your targets — you still
> pick what to actually apply to. This is a **watchlist monitor**: it surfaces openings
> at companies **you already chose to watch**, not the whole market. Add companies with
> `/coapply:discover add <company careers URL or ATS board URL>`, or edit this table by
> hand._
>
> _No list yet, or want to cast wider? **`/coapply:discover --auto`** needs no watchlist —
> it searches public ATS boards straight from your target roles and runs the finds through
> the same pick-list, and can save any company it surfaces back here._

| Company | ATS | Board id | Filters (optional) |
|---|---|---|---|
| <Company name> | greenhouse | <board-id> | location: <city or "remote">; keywords: <a word in the title> |
| <Company name> | lever | <board-id> | |

_How to read this table:_

- **ATS** — which job-board system the company uses: `greenhouse`, `lever`, or `ashby`
  (best-effort). `/coapply:discover add` detects this for you from a careers URL.
- **Board id** — the company's identifier in that ATS. It's the last part of the board
  URL: `boards.greenhouse.io/`**`acme`** or `jobs.lever.co/`**`acme`**.
- **Filters (optional)** — narrow what gets surfaced for this company. Free-text
  `key: value; key: value`:
  - `location: <text>` — only show postings whose location contains this text
    (e.g. `remote`, or a city). Leave it off to see every location.
  - `keywords: <word>, <word>` — only show postings whose **title** contains one of
    these words. Leave it off and CoApply ranks by your target roles alone.
  - Leave the whole cell blank to take everything from that company (ranking still
    orders it by how well each title matches your target roles).

_(The two rows above are a format example — replace them with real companies. The
engine ships no companies of its own; this list is entirely yours.)_
