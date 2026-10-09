# Known bugs and obsolete tests

The suite (`tests/run.gd`) is meant to be green. A test that fails because the GAME is wrong is left failing and listed here (name, what is wrong, how to see it, a suggested fix); a test whose
feature no longer exists for players is listed under "obsolete". Everything else that fails is a stale test or a flaky one, and is fixed in the test, not listed.

Last checked 2026-10-09 (the TESTS round, branch `feature/ph4-tests`, on main 43fc3f2): 4303 tests, nothing listed below.

## Real bugs (the test is right, the game is wrong)

None. Two that looked like it and were not:

- `test_round18_integration: test_take_the_gate_post_and_fire_from_it` ("she fired from the post: 20 rounds left of 20"). The game is right: `scripts/main.gd` `HIDDEN_GAP_S` lets go of everything held (trigger,
  aim, keys) when a frame comes more than 1.5 s of real time after the last, which is what a browser tab that was hidden needs. The test drives `main._process` by hand and awaits two engine frames
  (`_draw_once`) before it holds the trigger; on a busy machine (the lab and an export running beside the suite) those two frames can take that long, and the trigger is let go. Shown by sleeping 1.7 s in
  the test at that point (the shot is not fired), and fixed in the test: `_frames` and `_until` start the game's clock again (`main._last_tick_us = 0`) before they step. It passes alone, and in the
  suite when the machine is quiet, which is why it looked like an order problem.
- `test_oh_view` (the roof fades in the house the avatar is in, the veils, a pawn drawn by where it stands). The roofs, the veils and the drawing are right; the tests stood the avatar in the start house
  and a run has begun at the town's entry since the arrival (`scripts/town/arrival.gd`). `Helpers.town_game(seed, {"home": true})` puts her in the start room, as the tests need.

## Obsolete (the feature is gone for players; the test is kept)

None. The school-yard tests that failed (the pause menu's "How to play", the settings' three switches, the 150 to 250 houses) were stale expectations of things that exist in another form, and were updated.

## Seen while fixing the tests (no test fails on these)

- `scripts/ui/tutor_cues.gd` `_beside` (line 437): `inside` is `Rect2(Vector2(PAD, 70), vp - Vector2(PAD * 2, 70 + 90))`, a rectangle of negative size when the viewport is smaller than `PAD * 2` by 160 pixels;
  `encloses` then logs "Rect2 size is negative" on every frame the walk cue is drawn. Not reachable in the game (the smallest window is 700 x 560, `Main.MIN_LOGICAL`); it showed in
  `test_oh_town: test_main_boots_a_town_run...` run alone in a headless window nobody had sized (the test now sizes it). If it ever matters: `.abs()`, or skip the cue when `inside.size` is not positive.
- `scripts/town/town_gen.gd` `_people_arrival` (line 1098) pushes the warning "town: no start lot, house 3 stands in" while the 64 x 64 mini town of the tests (`blocks` 2) is made for a real
  `Main` (`test_oh_town: test_main_boots...`): the mini town has no start lot. A warning only; the tests' stand-in entry is used.
- The static callbacks `PawnMotion.step_cb` and `PawnMotion.thump_cb` stay pointing at a freed game's effects when that game is freed (the next game sets them again). In the game this is harmless; in the
  suite it made `test_place_flow: test_a_whole_trip...` and `test_pawn_mesh: test_a_zombie_out_of_sight_makes_no_draw` log errors whenever a town run came before them. The runner now clears every
  `static var x := Callable()` after each case (`tests/run.gd`), so no production code was touched. If the game ever starts a second scene in one process, `CombatFx` could clear them in its own teardown.
