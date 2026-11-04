# Drawing with Graphite: a guide for AI agents (and people)

Graphite turns a 3D model into a pencil drawing. It doesn't know what anything looks like: you write the subject as
Swift code (a signed-distance shape, its regions and materials), and Graphite draws it. This file is for whoever writes
that code. If you're an AI agent asked to "draw a book" or "draw a heron" with Graphite, read this first.

## Who does what

- **The engine owns the look:** the lines, hatching, stipple, paper and colour. It is deterministic: the same model,
  view and seed always give the same drawing. You don't tune the look per subject. Pick a `Style` and leave it.
- **You own the likeness:** the proportions, the parts, and the few features that make it *this* thing rather than a
  generic one. This is where drawings succeed or fail, and nothing in the engine can fix a wrong model.

## The loop

Don't write the model in one pass and hand it over. Work in rounds, and look at every render.

1. **Brief.** Before writing code, write down:
   - what the subject is;
   - its real size and proportions, from a source if you have one;
   - the 3–5 features that make it recognisable (a heron: the S-neck, dagger bill, long legs, the black head plume);
   - which views you'll draw, and how large they'll be shown.
2. **Model the silhouette first,** in true proportions, from a few primitives. Get the overall shape right from every
   side before adding any detail.
3. **Render a turnaround:** `turnaround(subject, options)` draws the front, side, three-quarter and from-above views on
   one labelled sheet. Write it to a PNG and **open it and look at it.** If you can read images, do. If you can't, ask
   a person to look.
4. **Critique against the brief**, in writing, before you fix anything:
   - Does it read as the subject at a glance, at the size it will be shown?
   - Are the proportions right? Compare them to the brief's numbers, not your memory.
   - Is anything floating, missing, doubled or cut off?
   - Is there a line everywhere one belongs, and none where it doesn't?
   - Is the shading clean? Blotches or holes mean the distance field overshoots.
5. **Fix, then render again.** Two to four rounds is normal. Keep the seed fixed between rounds so you see only your
   own changes.
6. **Details last.** Add regions (seams, bands, windows), finer parts, and close-up studies (`drawDetail`).
7. **Final:** choose the views and seeds, and write the PNGs.

An example: `Examples/Book.swift` took three rounds.
1. Round one read as a book, but as a box with paper in it.
2. Round two added the hinge groove by the spine, which is what makes a hardcover read as one. The groove didn't draw,
   because it was too shallow to make a line from its depth.
3. Round three made the groove its own region, and it drew.

## Rules of thumb

**Lines**
- **Every line is a region boundary.** A line is drawn where neighbouring pixels show different regions, along the
  silhouette, where one surface passes in front of another, and at creases if you turn them on. A seam, band, window
  or label is a region (`SurfaceID.make(part, kind, index)`). If a line is missing, make the feature its own region.
- **Faceted things want creases:** set `rules.creaseAngle` to 30–45°, so that one region can show sharp edges.
- **Light lines between similar regions** (stacked pages, planks): give the kind a weight floor in
  `rules.floor[kind]` of about 0.2.

**Shape**
- **True proportions, any unit.** The drawing scales itself to the view.
- **Nothing thinner than about two drawn pixels as a distance field.** Needles, twigs, veins, wires and railings
  belong as `Stroke3D` / `Curve3D` / `Mark3D` (see `Strokes3D.swift`), as thin triangle cards, or as 2D marks in a
  detail (`Canvas2D.swift`).
- **Keep the distance field honest.** Use the exact primitives in `SDF.swift`. A shape that is only a bound (blended
  ellipsoids, added noise) wants `options.march.stepScale = 0.7`. Blotchy shading or speckled holes mean the field
  overshoots.
- **Bound every part.** Give `ShapeSubject` parts tight `lo`/`hi` boxes, or test a box first in your own class.
  `sceneSDF` runs millions of times.

**Tone and colour**
- **Darkness is a material, not a style.** A dark surface is `Material(value:)`, an opening is `.opening`, and an
  underside gets a `minTone`. Leave `Style` alone unless you are deliberately changing the look of everything.
- **Colour:**
  - use `Style.colouredPencil` and a palette that gives each region kind a real pencil colour (`Pigment(hex:)`);
  - greys and very pale colours come out pale, so pick colours a shade deeper than you think;
  - a region the palette leaves out gets the style's fallback pencil.

**Checking and output**
- **A close-up is a closer study, not a crop.** Magnifying a view only enlarges flat tone. Model the feature finer
  for its `drawDetail`: the feathers, grain, scales or joints.
- **Check at display size.** A view is often shown at a quarter to half of its pixels. Contours that read at
  1200 px can vanish at 300.
- **When nothing is drawn**, read `drawing.error`: the bounds don't hold the subject, the distance never reaches the
  surface, or the view looks away.
- **Everything is made by code.** No photos, traced images or outside artwork.

## Working in this repository

- Build and run the examples with `swift run -c release graphite [example…] [--out dir]`. The examples are mug, book,
  tree, leaf, crystal, gallery, styles and colour.
- New subjects go in `Examples/` (one file per subject, plus a line in `Examples/main.swift`), or in your own package
  that depends on Graphite.
- **Don't change the default look.** If you touch `Sources/Engine`, render the examples before and after, and make
  sure the PNGs match byte for byte (`cmp`). A new look is a new style or an option that is off by default.
- No dependencies beyond Apple's frameworks.

## A brief to start from

```
Draw <subject> with Graphite, as Examples/<Subject>.swift (registered in Examples/main.swift).
- Size and proportions: <real dimensions, and where they come from>.
- Recognisable by: <3–5 features>.
- Regions (each boundary becomes a line): <…>.
- Views: <front / side / three-quarter / from above / a close-up of …>, shown about <N> px wide.
- Style: <Style.standard | Style.colouredPencil with a palette: region → colour>.
Work in the loop from AGENTS.md: render turnaround(subject) after every change, look at it, write what does not read
as <subject>, fix it. Stop after four rounds or when it reads at a glance; report what you guessed.
```
