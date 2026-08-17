# Feed & Harvest — an unfinished brainstorm

**This is not an adopted design.** It is the recovered state of a `/superpowers:brainstorming`
session that stopped mid-design, vendored out of a session-scoped scratchpad so the work
survives. Nothing here has been reviewed, specced, planned or built.

Session `974b517e-2b2b-4afb-9025-81d9e5b0f227`, 2026-08-17 02:23–02:54 UTC, 260 entries.
It ended inside "Design — section 2 of 3", on an unanswered question.

## The idea

> - animal feed (StrawStack) = resource (CPU and RAM)
> - render Food based on resource consume
> - Maybe you can add the straw bale to represent the token available (if subscription plan),
>   and milk tank/egg tray to represent token burnt

Turn the farm's existing feed props into a reading of the token budget.

## What was settled

| question | answer | why |
|---|---|---|
| Scope | **Whole-farm** | One feed store, one harvest pile. No per-project attribution, no new data path. |
| What feed measures | **Tokens, not CPU/RAM** | CPU and RAM already drive the animals' own behaviour (spec §5). Tokens have no presence in the scene at all. |
| The bale's denominator | **A ceiling you configure** | `ccusage` has no plan quota to read, so the ceiling has to be entered in the farmhouse. |
| What the harvest measures | **Money, not tokens** | Bale = tokens left in the block; milk vat = dollars spent. A different unit cannot be redundant with the bale, and `costUSD` / `projection.totalCost` are already fetched — zero new calls. |

The harvest question mattered because with a configured ceiling, *remaining* is just
*ceiling minus burnt* — so a harvest prop measuring tokens would be the same fact drawn
twice. Three alternatives were considered and rejected: a longer clock (bale = 5h block,
milk = today, needing a second daily `ccusage` call); work produced (eggs = `outputTokens`
only, but output is a small lumpy slice so the tray sits near-empty); and no harvest at all.

## Where it stopped, and why

Section 2 asked **what actually fills the vat**, and hit a real blocker:

`costUSD / projection.totalCost` has **both terms moving**. `projection` recomputes from
burn rate every poll, so a hot spell inflates the denominator and the vat *drops* while you
are spending faster — it can run backwards.

The obvious fix collapses. Deriving a dollar ceiling from the token ceiling gives
`ceiling$ = ceilingTokens × (costUSD / totalTokens)`, so the fill becomes:

```
costUSD / (ceilingTokens × costUSD / totalTokens)  =  totalTokens / ceilingTokens
```

The dollars cancel. That gauge is the bale's exact complement wearing a vat — precisely the
redundancy the previous question was spent avoiding.

**Three honest routes remain, and this is the open question:**

- **(A) A second setting: dollars per block.** Vat = `costUSD / thatBudget`. Strictly rising
  within a block, genuinely independent of the bale, means what it looks like. Costs one more
  field in the farmhouse and one more number you have to know.
- **(B) Keep the projection, accept the wobble.** No configuration. The vat means "share of
  where this block is heading" and will occasionally slip backwards when burn rate jumps. At
  four discrete levels the wobble is mostly invisible — but it is real, and would go in the
  spec as a stated property rather than a bug someone rediscovers.
- **(C) Money moves to the text; the vat carries a rate.** Vat fill = current
  `burnRate.tokensPerMinute` against the rate that would exactly exhaust the ceiling over the
  block's five hours. A full vat means "you are drinking faster than this block can afford".
  No denominator that moves.

## The art it had chosen

`candidates.png` is the shortlisted tile inventory, rendered with IDs. The relevant ones:

| tile | what it is |
|---|---|
| `0093` | straw bale — the budget-remaining prop |
| `0094` | haystack |
| `0106` | sack |
| `0107` | bucket / trough (already used by every pen, spec §3.3) |
| `0130` | barrel / vat, empty |
| `0131` | barrel / vat, filled blue — the harvest prop |

All are existing Kenney tiles, so §7's "nothing needs new art except the font" still holds.

## Evidence renders

| file | what it shows |
|---|---|
| `feed-and-harvest.html` | The visual companion as it stood: settled decisions, the four harvest options with trade-offs, and the facts that shaped them. Open it in a browser. |
| `gauge-mockup.png` | First iteration — one segmented vertical bale gauge plus a vat, both standing on the ground beside the barn. Four states from 100% budget to empty. |
| `gauge-mockup2.png` | Second iteration — three discrete bales on the ground depleting 3→2→1→0, with the vat mounted on the barn wall filling blue. This is the layout the design was heading toward. |

Looking at `gauge-mockup2.png` is also the fastest way to *see* the redundancy problem: the
bales empty exactly as the vat fills, because in that mockup they are complements.

Three further PNGs from the same scratchpad — `barn-grid.png`, `barn-dense.png`,
`barn-tiles.png` — were barn roof/wall tile studies rather than feed decisions, and were
deliberately not kept.

## Facts worth not rediscovering

- **`ccusage` has no plan quota.** `blocks -t max` adds no field to the JSON; "max" just means
  your own heaviest recorded block. Any real ceiling has to be configured by hand.
- **CPU is mostly near zero**, because Claude's work happens server-side (spec §0a), and
  `SessionState.swift` already spends cpu/mem on the thresholds that make animals stand, walk
  and bounce. That is why feed measures tokens instead.
- **Per-project attribution was available but set aside.** `ccusage session --json` keys on
  session UUID, and the UUID resolves to a project through `~/.claude/projects/`. Dropped with
  the whole-farm scope, not because it was impossible.
