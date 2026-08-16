# Sakura Night Garden retained-asset record

## Production method

- Generator: built-in image-generation tool.
- Reference: the user-approved Sakura Night Garden visual direction retained
  in the runtime theme implementation.
- Botanical source background: flat `#00ff00` chroma key.
- Delivery: locally keyed RGBA PNGs with transparent corners, then retained by
  Flutter at fixed logical sizes through `RetainedAssetImage`.
- Material source: opaque authored texture tiles layered over deterministic
  gradients and paint-only bevels.
- No screenshot, mockup panel, application text, or functional icon is present
  in any runtime art asset.

## Runtime assets

| Asset | Source pixels | Flutter size |
| --- | ---: | ---: |
| `assets/sakura/botanicals/sidebar-branch.png` | `792 x 1160` | `198 x 290` maximum |
| `assets/sakura/botanicals/title-sprig.png` | `840 x 160` | `168 x 32` |
| `assets/sakura/botanicals/section-bloom.png` | `320 x 72` | `80 x 18` |
| `assets/sakura/botanicals/queue-rising-bloom.png` | `432 x 240` | `54 x 30` |
| `assets/sakura/botanicals/queue-low-buds.png` | `432 x 240` | `54 x 30` |
| `assets/sakura/botanicals/queue-split-bloom.png` | `432 x 240` | `54 x 30` |
| `assets/sakura/materials/blackened-cedar.png` | `1254 x 1254` | surface-local cover |
| `assets/sakura/materials/charcoal-plum-lacquer.png` | `1254 x 1254` | surface-local cover |

## Final prompt set

### Sidebar branch

Create an isolated, production-quality cherry-blossom branch using the approved
sidebar as the binding composition and material reference. Preserve the
bottom-left to upper-right sweep, generous negative space, two or three
intertwined tapered base stems, irregular fine secondary twigs, and a strong
hierarchy of a few focal blossoms, smaller half-blooms, buds, muted leaves, and
individually shaped falling petals. Render dark umber bark with grooves, knots,
shadow and a restrained copper ridge. Render dusty rose petals with overlapping
layers, darker folds, pale edges, warm centers and visible fine stamens. Keep it
quiet, natural and handcrafted: no generic radial marks, repeated flowers,
plastic gloss, neon pink, flat vector treatment, UI, frame, text, icons or
watermark. Place it on a perfectly flat uniform `#00ff00` background with no
shadow, gradient, floor or reflection.

### Title sprig

Create a very slender horizontal title-bar cherry branch for a 40-pixel dark
title strip. Use a long shallow twig, one very small open bloom, two side-facing
half-blooms, several varied buds, tiny muted leaves and two detached petals,
with most detail in the right third. Keep bark and petals dimensional at
`168 x 32` logical pixels, but avoid a bouquet or oversized focal flower. Use
the same flat chroma-key and exclusions as the sidebar branch.

### Section bloom

Create a restrained horizontal heading-rule cluster designed for an
`80 x 18` fixed bloom host. Include one readable small open blossom, one
side-facing bloom and varied buds on a dark umber/copper twig. Preserve layered
petals and a visible warm center at final size. Keep the asset extremely shallow
and transparent-ready, with no UI, text, symbols or oversized bouquet.

### Queue variants

Create three distinct, compact bottom-right queue-card flourishes designed for
`54 x 30` logical pixels:

1. one readable open blossom, one half-open bloom and two buds;
2. one side-facing half bloom, three varied buds and one falling petal;
3. two overlapping blossoms at different angles, one tight bud and two leaves.

Each branch enters from the right or lower-right, stays safely inset, uses
dimensional bark and petals, and retains a clear silhouette after downscaling.
Avoid generic flower symbols, repeated layouts, flat vectors, neon color, UI,
text and frames.

### Blackened cedar

Create a dark, edge-to-edge blackened cedar material tile with natural vertical
grain: broad stained bands, irregular split-and-merge mid-grain, sparse pores,
subtle knot arcs and restrained rosewood/copper undertones. Use flat material
scan lighting and a satin hand-finished surface. No pinstripes, grid, paper,
fabric, scratches, flowers, objects, text or watermark.

### Charcoal-plum lacquer

Create a dark charcoal-plum hand-lacquer material tile with faint cloudy depth,
fine mineral/fiber variation, sparse pores and subtle horizontal polishing
traces. It must feel dense and tactile without plastic gloss. Use flat material
scan lighting. No bevel, vignette, leather, paper, marble, obvious noise,
objects, text or watermark.

