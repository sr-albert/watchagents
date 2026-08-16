# Farm reference material

Nothing here is built or shipped. It is the working material behind
`docs/farm-design-spec.md`, vendored out of a throwaway scratch directory so the spec's
citations keep resolving after the session that wrote them ended.

| file | what it is | status |
|---|---|---|
| `mock7.py` | The Python reference implementation. `render()` **is** the layout algorithm the Swift renderer ports — pens, lattice, scenery placement, tinting. The spec cites this as source of truth for anything ambiguous in prose. | authoritative |
| `states.py` | Renders the four-state key (idle / active / overloaded / frozen). | authoritative |
| `FARM-ART-SPEC.md` | The long-form art brief: tile inventory, measured tints, why each cue was chosen. | rationale |
| `FARM-HANDOVER.md` | The design handover that preceded the spec. Contains the two blockers that shaped the project — cutting `AnimalSpecies` from 7 to 4, and the CC-BY attribution obligation. | rationale, historical |
| `UNADOPTED-spec-rewrite.md` | A 62KB proposed rewrite of the whole design spec. **Not adopted, not reviewed.** It predates the renderer-flip fix (`0801ade`), so it still carries the "the canopy art reads upside down" misdiagnosis that §6.2 now retracts. Adopting it as-is would re-import that error. | undecided |
| `dooropen.png` | Three-panel render proving tile `0074` has transparent corners — it is an arch meant to composite onto a wall, so the open barn door repaints `0073` underneath it first. | evidence |
| `trees-fixed.png` | Post-flip-fix render of the woodland, showing a correct forest frame. The evidence behind the §6.2 retraction. | evidence |

Everything else from that scratch directory — roughly eighty exploratory PNGs, a dozen
mock iterations, probe binaries — was deliberately not kept.
