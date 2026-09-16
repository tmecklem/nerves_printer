---
name: dothework
description: End-to-end card workflow for nerves_printer. Takes a Launchbox card short code (e.g. mec-303), checks out a fresh branch from main, moves the card to Development, drives the work TDD-style, verifies on the Pi when the change touches the device, opens a PR, and finally moves the card to Automated Review. Invoke when the user runs `/dothework <short-code>`.
---

# Do The Work

Ported from equipment_tracker's `dothework` for this repo: the Nerves firmware at the root, the `printer_relay` package in `printer_relay/`, and the Pi Zero 2 W + Zebra printer it runs on.

This skill takes a Launchbox card from "ready to start" to "in automated review" with no shortcuts. You are responsible for delivering tested, review-ready code on a branch with an open PR.

The skill takes one argument: a Launchbox card short code (e.g. `mec-303`). If the user invokes `/dothework` without an argument, ask which card they want to work.

All Launchbox operations use the Launch Box MCP `execute` tool with Lua scripts that call `launchbox.call_tool(name, args)`. Cards for this repo live in the **Mecklem** organization (short code `mec`) on the **Equipment Tracker** board. Before the first call, make sure Mecklem is the active organization (`get_current_organization`, then `set_active_organization` if needed).

## Workflow — execute these steps in order

### 1. Sync local main and stash any in-progress work

```
git checkout main && git pull
```

If `git status` shows uncommitted changes after the checkout, run `git stash push -u -m "dothework auto-stash"` to keep the workspace clean. Tell the user you stashed their changes so they can restore them later with `git stash pop`. Do not delete or discard work without permission.

### 2. Look up the card and check out its branch

```lua
local results = launchbox.call_tool("search_cards", { query = "<short-code>" })
return results
```

Capture:
- card id
- title
- notes (the card description) and implementation_plan
- `suggested_branch_name`
- the board_placement (board id + current column id)

Then create the branch from the just-pulled main:

```
git checkout -b <suggested_branch_name>
```

If the branch already exists locally, check it out and `git pull --ff-only` if there's a remote. If the branch already has unrelated commits, stop and ask the user how to proceed.

Cards here often span repos (`custom_rpi3`, `equipment_tracker`). Use the same branch name in every repo the card touches, and follow that repo's own conventions (equipment_tracker has its own `CLAUDE.md` and `mix precommit`).

### 3. Move the card to Development and assign yourself

```lua
local board = launchbox.call_tool("get_board_overview", { id = "<board_id>" })
return board
```

```lua
launchbox.call_tool("move_card_to_column", {
  board_id = "<board_id>",
  card_id = "<card_id>",
  column_id = "<development_column_id>"
})
```

Skip if it's already in Development.

Then assign the developer:

1. Read the developer's email from git: `git config user.email`.
2. Look up users: `launchbox.call_tool("get_users", {})`
3. Assign: `launchbox.call_tool("assign_user", { card_id = "<card_id>", user_id = "<user_id>" })`

If the user is already assigned, treat that as success. If no org member matches the git email, match the Claude session's user email instead; if neither matches, warn and skip.

### 4. Read the card description and project documentation

- Re-read the card notes and implementation plan you captured in step 2
- Read `PLAN.md` (hardware, system, and dev-loop decisions), `README.md`, and `printer_relay/README.md` (package API and protocol)
- Read any memory files for this project

The goal is to load enough context that you can make good design decisions without guessing.

### 5. Web research for technical unknowns

If the card touches a library, API, or pattern you're not certain about (Nerves systems, VintageNet, Slipstream, Phoenix.Tracker, GitHub Actions), look it up. Prefer official docs and the dependency source in `deps/`.

### 6. Interview the user for design and product gaps

After research, ask the user any questions you still have about scope, behavior, or design. Skip this step only if the card and docs already give you everything you need.

### 7. Work the card with a TDD red-green-refactor loop

1. Write a failing test that captures one slice of behavior
2. Run the test, confirm it fails for the right reason
3. Implement the minimum code to make it pass
4. Run the test, confirm it passes
5. Refactor if needed, keeping tests green
6. **Run `mix precommit`** before moving to the next red test. At the root it checks formatting, compiles with warnings as errors, runs the firmware tests, then does the same in `printer_relay/`
7. Repeat until the slice is done

If `mix precommit` fails, fix it before proceeding. Never accumulate broken state.

When a change touches firmware code or config, also confirm the target build: `MIX_TARGET=custom_rpi3 mix compile --warnings-as-errors`, and `mix firmware` when config or dependencies change.

### 8. Verify on hardware when the change reaches the device

If the Pi is reachable (`ssh nerves.local`), deploy with `MIX_TARGET=custom_rpi3 mix firmware && mix upload nerves.local` and check the behavior on the device. Build with the same `PRINTER_RELAY_*` settings the Pi already uses, or it will stop connecting to the relay.

- WiFi is persisted on the device, so firmware builds don't need `NERVES_WIFI_*`. Never upload firmware that could leave the Pi without network access.
- Don't claim hardware verification you didn't do. If the Pi or printer isn't available, say so and list the manual checks in the PR.

### 9. Self-review before committing

Before staging anything, re-read `PLAN.md` and check your memory files for prior feedback. Then scan the diff for common issues:

- [ ] No discarded return values on failable calls
- [ ] No `Mix.*` calls at runtime in `lib/` (Mix isn't in the release; capture `Mix.target()` in a module attribute)
- [ ] Device-only modules (VintageNet, sysfs paths) stay off the host path or are injectable for tests
- [ ] `printer_relay` modules that need Phoenix or Slipstream stay behind `Code.ensure_loaded?` guards, and the firmware target compiles without warnings
- [ ] No secrets in commits, config, workflow files, or anything built into CI firmware (this repo is public)

Fix any violations before committing.

### 10. Commit in semantic chunks

Group changes into commits that each tell a coherent story. Prefer multiple small commits over one giant one. Always include the card short code in commit messages (e.g. `mec-303: ...`) so the PR links back to the card.

### 11. Push and open a PR after the first commit

After the **first** commit lands locally:

```
git push -u origin <branch>
```

Then open a PR with `gh pr create`. Title should include the card short code. Body should have a Summary and Test plan section. Link the PR to the card with `link_card_to_pr` (this repo isn't connected to the Launchbox GitHub webhook).

Subsequent commits just need `git push` — the PR updates automatically.

### 12. Move the card to Automated Review after the final commit

When the work is done and the final commit is pushed, find the column tagged `automatic_code_review` on the card's board:

```lua
local board = launchbox.call_tool("get_board_overview", { id = "<board_id>" })
return board
```

Pick the column whose `tags` array includes `"automatic_code_review"`. **Don't match on column name** — use the tag. If no column has that tag, stop and warn the user.

```lua
launchbox.call_tool("move_card_to_column", {
  board_id = "<board_id>",
  card_id = "<card_id>",
  column_id = "<automated_review_column_id>"
})
```

### 13. Print a fun success emoji

End with a one-line celebration. Pick one: 🎉, 🚀, 🦄, 🍰, ✨, 🥳

## Hard rules

- **Never skip precommit between green tests.** That's the whole point of running it small and often.
- **Never force-push or use `--no-verify`** unless the user explicitly tells you to.
- **Never move the card to Done.** Automated Review is the terminal step for this skill.
- **Never put secrets in the repo or in CI-built firmware.** The repo and its workflow artifacts are public.
- **If anything fails along the way**, stop and tell the user — don't paper over failures to keep moving.
