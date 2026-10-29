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

1. Get the repo on your computer: `git clone https://github.com/matthewchee412-hue/killion123` (or `git pull`).
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

1. Sync with Rojo (section 2). On Play the server builds the map (section 5). Swim down from the beach to **Ring2** or **Ring3**, the two casual rings nearest the bottom of the path. If you already have a `workspace.Rings` folder with models in it, those get used instead.
2. **Test tab → Clients and Servers → Local Server**, set **3** players, then **Start**. A server window and 3 client windows open.
3. In each client, swim onto a different chair in **Ring2**. The top of the screen should say `Starting in 15`. Standing up (Space) during the countdown with only 2 seated should cancel it. Sit back down.
4. When it starts, the holder sees an answer box, **Send** and **Dive Deeper**. The others see "… is thinking…". Try these:
   - Something wrong (`blorp`): the box shakes and you keep the blowfish.
   - A right answer: it passes clockwise, and the feed (top left) shows tier and coins.
   - **Dive Deeper**, then a common answer: +3 s of air and you keep it. Dive, then wait 5 s: same.
   - A rare answer (Midnight/Abyss): purple name buttons appear to pick the next holder, with a 10 s limit. Abyss also shows a gold banner in every window.
   - Hold it until it pops: you become see-through (ghost) and stay seated. A new category starts after 3 s.
   - Stand up mid-round with one of the others: that counts as popping.
5. When one player is left, the results show for 6 s, then the ring resets and counts down again.
6. In the **server** output window, every feed line prints as `[Ring Ring1 …] …`. Copy the log of one full game into a GitHub issue (or paste it to Claude) along with anything that looked wrong. Also note the `answer banks loaded in … ms` line.
7. Optional: seat 4 players in **RankedRing1** (the gold ring further out). It shouldn't start with 3.

To test luck, run `game.Players.<Name>:SetAttribute("Luck", 5)` from the server command bar, then type junk like `chile soup` a few times. The feed should show `chile soup → Something ✨ LUCKY!`.

`DebugRoundUI.client.luau` is a throwaway screen for this test. Prompt 4 replaces it with the real HUD.

## 5. Check the map (prompt 3)

The server builds the map when it starts (`Server/Map/MapBuilder.luau`): terrain for the beach, slope, sea and cliffs, then the lighting, the beach props, and 6 rings with chairs and signs. Each client builds and animates the seabed life itself (`Client/SeabedLife.client.luau` and the `Client/Seabed` folder). Nothing has been looked at in Studio yet, so this is the first real look.

**Heads-up:** the map builder clears all terrain on start (`Terrain:Clear()`), and it deletes a `Baseplate` and `SpawnLocation` in Workspace if there are any. Use a fresh place, not one with terrain you want to keep.

### 5a. Play and look around

1. Sync with Rojo, then **Play** (F5).
2. In **Output**, check for these two lines and note the numbers:
   - `[MapBuilder] map built in … ms` (server)
   - `[SeabedLife] built … parts in … ms` (client)
3. Walk through it:
   - You spawn on a sunny beach with palms, an umbrella and a "BLOWFISH BLOWOUT" sign.
   - A rocky path runs down the sandy slope into the water.
   - Under water, the screen gets a soft blue-green tint, which goes away again when you surface. Sunbeams slant down from the surface.
   - There are 6 rings: 4 casual near the slope, and 2 gold Ranked rings further out with gold trim and a gold glowing sign.
   - The sign above each ring says `Open 0/8`. Sit down and it should say `Open 1/8`. With 2 seated it shows `Starting 0:15` and counts down, then `In game`.
   - On the seabed: kelp sways, crabs walk sideways, starfish creep, and you see fish schools, a turtle, a manta and jellyfish. Bubbles rise.
4. Sit in a chair: you should sit in the seat, facing the middle of the ring.

### 5b. Screenshots

I can't take screenshots from the cloud, so please take these. Press **F12**, or use the Screenshot button in the top bar. Hide the UI first with `Ctrl+Shift+G`.

1. **Beach:** from the spawn, looking down the path at the sea.
2. **Entering the water:** halfway down the path, just under the surface.
3. **Casual ring:** close up, from about 20 studs above **Ring2**, so the chairs and the sign show.
4. **Ranked ring:** the same for **RankedRing1**.
5. **Wide shot:** high over the middle of the seabed, looking towards the back cliff so most rings are in view. (Switch the command bar to **Client** and run `workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable; workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(0, 45, 0), Vector3.new(0, 0, 150))`.)
6. **A chair, close up:** looking straight at one from the front.
7. **Phone check:** **Test → Device**, pick a phone in landscape (e.g. iPhone 14, 844×390), then repeat shot 3.

Send them to Claude with anything that looks plain, too dark or too busy, and the FPS from **View → Stats** (or `Shift+F5`) on the phone emulator.

### 5c. Generated chair mesh (optional, later)

The chairs are built from rounded parts for now (`Shared/ChairSkins.luau`). To swap in a carved-looking mesh:

1. In Studio, open the Assistant and use the mesh generator with a prompt like: *"a rounded boulder armchair carved from smooth sandy-grey stone, hollowed-out seat, high rounded back leaning back slightly, thick rounded arm rests, lounge chair not a throne, low poly, game asset"*.
2. Scale it so the seat is about 2.4 studs off the ground and the chair is about 6.5 studs wide, 7 studs deep and 8 studs tall.
3. Put it in a Model named `Default`. Set the model's pivot to the centre of its base, on the ground, with the front (where you sit) facing **-Z**. Check by inserting a Part and setting its **Front** face direction the same way.
4. Right-click the model, then **Save to File…**, and save it as `src/ReplicatedStorage/ChairMeshes/Default.rbxm` in the repo. Commit and push. Rojo syncs it to `ReplicatedStorage.ChairMeshes.Default`.
5. Play. Every chair now uses the mesh. The Seat and the invisible colliders stay the same, so sitting still works. If the mesh looks off from the seat, adjust its pivot.

### 5d. Phones

- In **Workspace** properties, turn on **StreamingEnabled** (Streaming Target Radius about 384). The map is small, but this helps low-end phones.
- If FPS on a phone is low, tell Claude the part count from the `[SeabedLife]` line. Kelp, coral and fish counts are easy to lower in `Client/Seabed`.

