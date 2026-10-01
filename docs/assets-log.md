# Log of the AI-made pictures

Every picture in the game that an image model made, for the rights audit (Steam asks for
a disclosure of AI-generated content). Made with Meshy's text-to-image (the account's
credits; the model is `nano-banana-pro`, 9 credits a picture, unless the row says
otherwise). Nothing here was made from another person's work as a reference, and no
franchise or person is named in a prompt. The pictures are not used as they came: they
are cropped, graded and (the materials) flattened, made seamless and drawn into frames
by Python (tools/make_ui_theme.py); the code, the layout and the frames themselves are
ours.

The originals are kept where the table says. A Meshy link to a picture expires after a
day, so the files in the repository are the record; the task id finds the prompt again in
the account's history.

## Round 3: the noticeboard look (2026-10-01)

The material pictures: flat, front-on, evenly lit surfaces with no text, the raw material
of the frames in assets/ui/theme/ (tools/make_ui_theme.py reads them from tools/ui_src/).

| File | What | Prompt | Model | Date | Meshy task id | Credits |
|---|---|---|---|---|---|---|
| tools/ui_src/mat_slate_a.png | a dark chalkboard surface: the face of the panels, the clock, the banner, the badges | Flat texture swatch of a dark green-black school chalkboard surface, perfectly flat front view, orthographic, evenly lit with no vignette and no gradient, matte slate with very fine grain, faint ghosted chalk dust haze and a few faint wide eraser swipes, deep forest-green black colour, filling the whole image edge to edge, no frame, no writing, no text, no objects. | nano-banana-pro, 1:1 | 2026-10-01 | 01a0f78d-3485-731a-9228-59938b47e95c | 9 |
| tools/ui_src/mat_oak_a.png | varnished oak with the grain along one side: the trim of the boards | Flat texture swatch of varnished oak wood, perfectly flat front view, orthographic, evenly lit with no shadows and no vignette, warm medium-brown oak with clearly visible straight horizontal grain lines and fine pores, hand-sanded surface with slight wear, filling the whole image edge to edge, no knots, no board edges, no frame, no text, no objects. | nano-banana-pro, 1:1 | 2026-10-01 | 01a0f78d-37a9-7425-931a-542b40610a4d | 9 |
| tools/ui_src/mat_paper_a.png | ruled school notebook paper (the rules are taken out in Python and drawn again, to the spacing the frame needs): the modal page and the slips | Flat texture swatch of a sheet of ruled school notebook paper, perfectly flat front view, orthographic, evenly lit with no shadows and no vignette, warm cream off-white paper with fine fibres, thin pale blue horizontal ruled lines evenly spaced, one thin red vertical margin line near the left, filling the whole image edge to edge, no holes, no text, no handwriting, no objects. | nano-banana-pro, 1:1 | 2026-10-01 | 01a0f78d-3c45-7723-86a3-986115d3a0de | 9 |
| tools/ui_src/mat_brass_a.png | brushed antique brass: the rim of the clock | Flat texture swatch of brushed antique brass sheet metal, perfectly flat front view, orthographic, evenly lit with no vignette and no gradient, warm golden yellow with fine horizontal brushed scratches and subtle tarnish, filling the whole image edge to edge, no screws, no edges, no reflections of objects, no text. | nano-banana-pro, 1:1 | 2026-10-01 | 01a0f78d-4085-71f7-9ea8-a33d53e5432c | 9 |
| tools/ui_src/mat_card_a.png | pale card stock with a fibre grain and a few specks: the hall-pass badges | Flat texture swatch of pale laminated card stock like a school hall pass badge, perfectly flat front view, orthographic, evenly lit with no vignette, light warm grey-beige cardboard with fine paper fibre grain, slight scuffs and tiny stains, filling the whole image edge to edge, no card edges, no text, no objects. | nano-banana-pro, 1:1 | 2026-10-01 | 01a0f78d-44f1-706e-ba49-1738a63e7088 | 9 |
| tools/ui_src/mat_chalk_a.png | a board wiped with an eraser: the dust and smudges of chalk laid over the slate | Flat texture of a black school chalkboard wiped with an eraser, perfectly flat front view, evenly lit, dark green-black surface covered in wide soft white-grey chalk dust swipes and smudges in overlapping arcs, high contrast, filling the whole image edge to edge, no writing, no text, no frame, no objects. | nano-banana-pro, 1:1 | 2026-10-01 | 01a0f78d-488f-7553-9846-f1c4e6301817 | 9 |

The fourth site picture, for the scavenging dialog (cropped to 16:9, resized to 720x405,
a touch lighter and more colourful so it sits with its neighbours; tools/make_ui_theme.py
makes it from the original):

| File | What | Prompt | Model | Date | Meshy task id | Credits |
|---|---|---|---|---|---|---|
| assets/ui/sites/scrapyard.png (original: tools/ui_src/ref_scrapyard_a.png) | the scrapyard: stacked wrecks, heaps of sheet metal and tyres, a crane with a magnet, a corrugated shed | Isolated isometric diorama of a wrecker's scrapyard on a plain flat dark charcoal background, no vignette, no gradient. Hand-painted flat illustration with thick dark outlines and soft cel shading, muted earthy palette of olive, rust, dusty teal and sand. Stacked crushed cars, heaps of twisted sheet metal and tyres, a tall crane with a hanging magnet, a corrugated shed, dusk light, weeds through cracked dirt. Post-apocalyptic mood, no people, no text, no letters. | nano-banana-pro, 16:9 | 2026-10-01 | 01a0f78d-616d-760a-b4a7-df48fe35984d | 9 |

Spent in round 3 by this task: 7 pictures, 63 credits.

## Earlier pictures (found in the account's task history; the repository's commit messages say only "made with Meshy")

The model is not recorded in the history; the price (9 credits) and the shapes (16:9) are those of
`nano-banana-pro`. The dates are those of the tasks (UTC).

| File | What | Prompt | Date | Meshy task id | Credits |
|---|---|---|---|---|---|
| assets/ui/sites/pharmacy.png | the pharmacy, for the scavenging dialog (cropped and resized to 720x405) | Isolated isometric diorama of a small abandoned pharmacy storefront on a plain flat dark charcoal background, no vignette, no gradient. Hand-painted flat illustration with thick dark outlines and soft cel shading, muted earthy palette of olive, rust, dusty teal and sand. Faded green cross sign, boarded windows, scattered papers on cracked pavement. Post-apocalyptic mood, no people, no text, no letters. | 2026-09-30 | 01a0f446-a899-70a2-a0de-d76a6ef06b0a | 9 |
| assets/ui/sites/hardware.png | the hardware store | Isolated isometric diorama of an abandoned hardware store on a plain flat dark charcoal background, no vignette, no gradient. Hand-painted flat illustration with thick dark outlines and soft cel shading, muted earthy palette of olive, rust, dusty teal and sand. Dented corrugated metal shutter, stacked paint cans and a ladder outside, a broken window showing a pegboard of tools, weeds through cracked pavement. Post-apocalyptic mood, no people, no text, no letters. | 2026-09-30 | 01a0f446-aa5c-71f3-bcb8-c2d11fd73be0 | 9 |
| assets/ui/sites/houses.png | the houses | Isolated isometric diorama of a short row of small suburban houses with overgrown front yards, a dusty parked car and drawn curtains, on a plain flat dark charcoal background, no vignette, no gradient. Hand-painted flat illustration with thick dark outlines and soft cel shading, muted earthy palette of olive, rust, dusty teal and sand. Post-apocalyptic mood, quiet and empty, no people, no text, no letters. | 2026-09-30 | 01a0f446-aea0-7571-a73f-2d82cb1fa623 | 9 |
| tools/art_src/ref_walkway_face.png (the deck faces in assets/objects/deck_*.png are made from it by tools/make_deck_art.py) | the front of a plank walkway on posts | Straight-on front elevation, orthographic with no perspective, of the support structure under a rustic wooden fighting platform: a long horizontal strip with thick weathered timber posts every two metres, X cross braces made of planks, a horizontal ledger beam, a plank fascia board along the top edge with nail heads, concrete footings at the base, rope lashings at the joints, the space behind the frame in deep dark shadow. Hand-painted flat game asset with thick dark outlines and soft cel shading, muted earthy browns. Plain solid magenta background, no text. | 2026-10-01 | 01a0f5ea-ad9c-7055-b6d9-3800a74c573a | 9 |
| tools/art_src/ref_tower_face.png | the base of a corner watchtower | Straight-on front view, orthographic with no perspective, of the base of a rustic wooden corner watchtower: four splayed timber legs, two tiers of X cross bracing, horizontal ledger beams, a plank fascia along the top, concrete footings, rope lashings and bolts, deep dark shadow between the legs. Hand-painted flat game asset with thick dark outlines and soft cel shading, muted earthy browns. Plain solid magenta background, no text. | 2026-10-01 | 01a0f5ea-b0c9-73fa-9e80-1d10c2a7338e | 9 |
| tools/art_src/ref_ladder.png | a steel pipe ladder | Straight-on front view, orthographic, of a tall galvanized steel pipe ladder: two parallel round rails with evenly spaced round rungs, the top ends bent over into hooks, small flat foot plates at the bottom, rivets and light rust spots. Hand-painted flat game asset with thick dark outlines and soft cel shading, muted blue-grey steel. Plain solid magenta background, no text, the ladder centred and complete. | 2026-10-01 | 01a0f5ee-6d90-76b5-9bd8-ceb42ea574cd | 9 |

Reference boards in docs/audit/img/ (concepts for the audit; not used in the game):

| File | What | Date | Meshy task id | Credits |
|---|---|---|---|---|
| docs/audit/img/concept_keyart.jpg | key art concept: the school compound at dusk | 2026-10-01 | 01a0f62b-f331-7534-965b-1a6b7cb9dc8e | 9 |
| docs/audit/img/concept_ui_chalkboard.jpg | the noticeboard HUD concept this round's frames are after (a reference, not copied) | 2026-10-01 | 01a0f62b-f6de-74ed-b51c-dbf6a803b550 | 9 |
| docs/audit/img/concept_city_map.jpg | the town map concept | 2026-10-01 | 01a0f62b-fb75-70c5-9bcb-2828ebadfe53 | 9 |

The account's history also holds Meshy tasks that are not part of this repository (character and
prop references for the 3D spike that was dropped, and some experiments with another game's
style): their pictures are not in the game and are not logged here.
