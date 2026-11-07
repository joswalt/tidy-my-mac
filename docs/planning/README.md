# Wayfinder tracker (local markdown)

- `map.md` is the map (label `wayfinder:map`).
- `tickets/NNN-slug.md` are child tickets. Frontmatter: `status` (open|closed), `type` (wayfinder:research|prototype|grilling|task), `assignee` (empty = unclaimed), `blocked_by` (ticket ids).
- Frontier = open tickets with empty assignee whose `blocked_by` are all closed.
- Resolution: append a `## Resolution` section, set `status: closed`, add one line to the map's Decisions so far.
- Research findings live in `research/<name>.md`, linked from the ticket.
