# Experiment branches (2026-10-12)

Three experiments were built in separate git worktrees under `.worktrees/`. None is merged into main. None is pushed to GitHub or itch.

## Decision (2026-10-12)

The owner chose to **focus on the prison extraction experiment and keep its graphics**. The other two stay as reference only. Main (the One House demo) is unchanged.

## Branches

### experiment/prison-extraction (ACTIVE, worktree `.worktrees/exp-prison`, latest commit 0cfe6b7)

A hand-built 96x72 prison compound with 10 working NPCs and 72 dead at the gate. The player raids a generated 64x64 town from the gate, extracts through a cutscene, and banks the loot. Dying loses the pack. It has tower guards with an alarm, day and night, ambient life (chatting pairs, canteen meals, kids, a dog, campfires), sound, a custom minimap, and four Blender-rendered trees.

Run:

    /Applications/Godot.app/Contents/MacOS/Godot --path /Users/jaf_lab/last-bell/.worktrees/exp-prison -- --prison

Its own notes are `docs/experiments/prison-extraction.md` inside that worktree. The agent's estimate was 6 to 8 weeks for a small shippable version. Known gaps: no backpack grid, no base attacks, no saving, no NPC damage.

### experiment/iso-25d (reference, worktree `.worktrees/exp-iso`, latest commit db9aca9)

Isometric 2.5D sprite mode of the main game, behind `--iso`. Blender-rendered 8-direction character sheets, props, walls. Not verified: tests were never confirmed, no web size check, commits are tangled across agents. Notes: `docs/experiments/iso-25d.md` in that worktree.

### experiment/iso-3d (reference, worktree `.worktrees/exp-3d`, latest commit ce85b8c, based on iso-25d)

Real-time 3D on a fixed isometric camera, behind `--3d`. Performance was fine on an M1 (84 fps desktop, 60 fps web at 70 awake dead). The owner did not like the look, so it is parked. Notes: `docs/experiments/iso-3d.md` in that worktree.

## Next: improve prison extraction

To be planned with the owner. Open gaps from the experiment: backpack grid, base attacks, saving, NPC damage, a human hand-playtest.
