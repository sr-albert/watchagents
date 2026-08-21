# watchagents

A menu-bar app that watches local Claude Code sessions, plus a pixel-art farm window
where each session is an animal and each project is a pen.

`docs/farm-design-spec.md` is the source of truth for the farm. Its reference
implementation lives in `docs/reference/` — see the README there.

## Rules that were learned the hard way

**Animal placement is a pure function of `(pid, time)`.** No pathfinding, no per-frame
mutable position, no simulation state. Everything an animal does — its slot, its walk
phase, its idle wander — is derived. When something looks like it needs memory, look for
an existing timestamp to evaluate the same pure function at: "rest where you stopped
walking" is `activeTraverse` evaluated at `idleSince`, not a stored coordinate.

**One rule, one function.** `FarmLayoutEngine.penColumns(animalCount:)` is the only
place that decides how many animals stand side by side. It exists because `penSize` and
`FarmAnimalPlacer.place` used to derive it separately and disagreed — the surplus column
silently ate the slack an active animal walks in, so animals in crowded pens walked on
the spot. The pens were never too small; they were being divided wrong.

**Render it and look at it before you trust a tile ID.** Two of the worst bugs in this
project were invisible to code reading and obvious in a PNG: the barn was already drawn
doors-open (so "opening" it did nothing), and tile `0074` has transparent corners that
let the shut door show through underneath. Both were found by rendering a contact sheet
with PIL and looking. Neither was found by reading.

**A test that cannot fail is not a test.** `test_anActiveAnimalStaysInsideThePen` passed
throughout the period when animals were not moving at all — standing still is trivially
inside the pen. When a test passes on the first run, check what it would take to make it
fail.

**Watch for sampling aliasing in animation tests.** A step that evenly divides the
animation period samples the same handful of phases forever. The traverse tests step by
`0.17s` specifically because a cow's period is exactly `2.5s`.

## Conventions

- Comments explain *why*, and are written for someone who will otherwise re-make the
  same mistake. Match the density already in the file.
- Commit messages: imperative, plain, one line, describing the change in the product's
  own terms — `Rest an animal where it stopped walking, not where it started`.
- Run `swift test` before committing. `./Scripts/build-app.sh` builds and signs the app.
