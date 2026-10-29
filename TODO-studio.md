# TODO in Studio

Steps that need Roblox Studio. The cloud sessions can't do these.

## 1. Install Rojo

1. Install the Rojo command-line tool (7.x) on your computer. Pick one:
   - With [Rokit](https://github.com/rojo-rbx/rokit): `rokit add rojo-rbx/rojo`
   - Or download `rojo` for your OS from https://github.com/rojo-rbx/rojo/releases and put it on your PATH.
2. Install the Rojo Studio plugin. Pick one:
   - Run `rojo plugin install` with Studio closed.
   - Or in Studio: **Toolbox → Plugins**, search "Rojo", and install the one published by the Rojo team.
3. Restart Studio. A **Rojo** button shows in the **Plugins** tab.

The plugin version should match the CLI version (both 7.x). The plugin warns you if they don't.

## 2. Connect

1. Get the repo on your computer: `git clone https://github.com/matthewchee417-byte/shrimpillion` (or `git pull`).
2. In the repo folder, run `rojo serve`. It should print `Rojo server listening` on port 34872.
3. In Studio, open a new **Baseplate** place and save it (e.g. `Shrimpillion.rbxl` inside the repo. `*.rbxl` is already in `.gitignore`).
4. **Plugins → Rojo → Connect** (address `localhost`, port `34872`).
5. Check the Explorer: `ServerStorage/ShrimpillionAnswers` should have `AnswerMatcher`, `Luck`, `Rarity`, `Categories`, `Blocklist`, `CommonWords`, and a `Banks` folder with **202** ModuleScripts.

Don't edit synced scripts in Studio. Rojo overwrites them. Edit the files in `src/` and they sync on save.

## 3. Playtest the answer banks

There are no game scripts yet, so for now this is a quick check from the command bar.

1. Press **Play** (F5).
2. Switch the command bar to **Server** (the Client/Server toggle at the top of the Home/Test tab), then paste:

```lua
local SS = game:GetService("ServerStorage")
local M = require(SS.ShrimpillionAnswers.AnswerMatcher)
local t = os.clock(); M.preloadAll(); print("preload ms", (os.clock() - t) * 1000)
for _, c in { {"animals","dog"}, {"body_parts","infraorbitals"}, {"body_parts","zygomatics"},
	{"sharks_rays","hammerhead"}, {"animals","golden"}, {"animals","killer"} } do
	local r = M.check(c[1], c[2]); print(c[1], c[2], r.reason, r.display, r.tier)
end
local round = M.newRound("animals"); round:submit("dog"); print("again:", round:submit("dog").reason)
```

3. Expected output: Dog tier 0, Infraorbital nerve, Cheekbone, Hammerhead shark, `unknown` for golden and killer, then `again: used`. Preload ran in about 0.7 s in Lune. Write down the Studio time here. If it's well over 1 s, preload in chunks across frames at server start.
4. Stop the playtest.

The same checks run outside Studio with `lune run tests/run_matcher.luau` (Lune 0.10.x).
