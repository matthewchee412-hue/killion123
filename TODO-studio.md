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

The same checks run outside Studio with `lune run tests/run_matcher.luau` (Lune 0.10.x). The round system has its own: `lune run tests/run_rounds.luau`.

## 4. Playtest a round with 3 players (round system, prompt 2)

The round rules are tested outside Studio with `lune run tests/run_rounds.luau`. That covers 99 checks plus 50 bot games, and prints a full 3-player game log. What only Studio can check is the Roblox side: seats, remotes, the text filter and timing over the network.

1. Sync with Rojo (section 2). There's no map yet, so on Play the server builds two placeholder rings at z = 40: **Ring1** (casual, sand floor) and **RankedRing1** (ranked, gold floor). Each has 8 grey seat pads. If you already have a `workspace.Rings` folder with models in it, those get used instead.
2. **Test tab → Clients and Servers → Local Server**, set **3** players, then **Start**. A server window and 3 client windows open.
3. In each client, walk onto a different seat in **Ring1**. The top of the screen should say `Starting in 15`. Standing up (Space) during the countdown with only 2 seated should cancel it. Sit back down.
4. When it starts, the holder sees an answer box, **Send** and **Dive Deeper**. The others see "… is thinking…". Try these:
   - Something wrong (`blorp`): the box shakes and you keep the blowfish.
   - A right answer: it passes clockwise, and the feed (top left) shows tier and coins.
   - **Dive Deeper**, then a common answer: +3 s of air and you keep it. Dive, then wait 5 s: same.
   - A rare answer (Midnight/Abyss): purple name buttons appear to pick the next holder, with a 10 s limit. Abyss also shows a gold banner in every window.
   - Hold it until it pops: you become see-through (ghost) and stay seated. A new category starts after 3 s.
   - Stand up mid-round with one of the others: that counts as popping.
5. When one player is left, the results show for 6 s, then the ring resets and counts down again.
6. In the **server** output window, every feed line prints as `[Ring Ring1 …] …`. Copy the log of one full game into a GitHub issue (or paste it to Claude) along with anything that looked wrong. Also note the `answer banks loaded in … ms` line.
7. Optional: seat 4 players in **RankedRing1**. It shouldn't start with 3.

To test luck, run `game.Players.<Name>:SetAttribute("Luck", 5)` from the server command bar, then type junk like `chile soup` a few times. The feed should show `chile soup → Something ✨ LUCKY!`.

`DebugRoundUI.client.luau` is a throwaway screen for this test. Prompt 4 replaces it with the real HUD.
