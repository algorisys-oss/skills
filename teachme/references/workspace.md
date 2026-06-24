# The teaching workspace — multi-session continuity

Teaching spans sessions. A small per-topic workspace lets you resume at the right level, run spaced
retrieval, and avoid re-teaching what already landed. Keep it lean — these are working notes, not a
course to polish.

## Layout

Created under `./.teachme/<topic-slug>/` in the user's working directory (override the parent dir
when scaffolding). `scripts/init-workspace.sh <topic> [dir]` creates the skeleton.

```
.teachme/<topic-slug>/
├── MISSION.md      # why they're learning this, goal, success criteria, current level
├── LOG.md          # session-by-session record: covered, struggled, misconceptions, retrieval queue
├── RESOURCES.md    # curated high-trust sources (optional)
└── examples/       # worked + faded examples worth keeping for reference/retrieval
```

## Session flow

- **Start of every session:** read `MISSION.md` (re-enter at the right level and goal) and `LOG.md`
  (what's done, what's shaky). **Open with spaced retrieval**: ask the learner to recall the 1–3
  queued items *from memory* before re-teaching anything. Retrieval that feels effortful is the
  point — it strengthens storage far more than re-reading.
- **End of every session:** append to `LOG.md` — what was covered, what landed, what didn't, the
  misconceptions surfaced, and the new retrieval queue for next time. Update `MISSION.md` if the
  goal or assessed level changed.

## `MISSION.md` template

```markdown
# Mission — <topic>

**Goal (what they want to *do*):** <e.g. "write and debug my own React hooks without copying">
**Why it matters to them:** <the real motivation — grounds difficulty and examples>
**Success looks like:** <observable: "explains the dependency array and fixes a stale-closure bug">
**Current level:** novice | developing | proficient   (re-assess each session)
**Constraints / preferences:** <pace, background, format likes/dislikes>
```

## `LOG.md` template

Append one block per session (newest at the bottom is fine):

```markdown
## Session <n> — <date>
- **Covered:** <concept(s), one idea per loop>
- **Landed:** <what they can now do / explained well>
- **Shaky / misconceptions:** <what to revisit; phrase the actual wrong belief>
- **Level move:** <e.g. "faded last step successfully → push to developing">
- **Retrieval queue (ask from memory next time):**
  - [ ] <question 1>
  - [ ] <question 2>
```

## `RESOURCES.md` (optional)

Only high-trust sources, with a one-line why. Prefer primary docs and known-good references over
random posts. Record anything you taught *from* so the learner can go deeper.

## Notes

- Markdown by design — portable, diffable, lives next to the user's code. (The skill that inspired
  this used HTML lessons; for a developer's workflow plain markdown + runnable code is lighter and
  more useful.)
- The workspace is disposable. If the user just wants a quick one-off explanation, skip it — don't
  impose ceremony on a five-minute question.
- Consider adding `.teachme/` to the project's `.gitignore` unless the user wants their learning
  log committed.
