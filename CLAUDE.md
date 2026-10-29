# Shrimpillion (Roblox)

A remake of Krillion's "Puffer Party", called Blowfish Blowout. Players sit on boulder armchairs in a ring on the seabed. A blowfish fills with air while someone holds it. To pass it on, the holder types an answer to the round's category ("Name a fish"). If the air fills up while you hold it, it pops and you're out. Last player left wins. Rarer answers let air out and give more control. Players are mostly 5–17, so everything stays simple and readable.

## Repo layout (Rojo project)
- `default.project.json`: the Rojo project. `src/<Service>/` maps onto that Roblox service.
- `docs/shrimpillion-design-doc.md`: the full design. Read it before any big task.
- `docs/claude-code-prompts.md`: the build plan, as prompts 1–10. Part 1 of it is this file.
- `assets/ShrimpillionAnswers.rbxmx`: the answer banks as a Studio model. Same content as `src/ServerStorage/ShrimpillionAnswers`, for inserting by hand without Rojo.
- `tools/`: the Python scripts that built the answer banks (not needed in-game).
- `src/ServerStorage/ShrimpillionAnswers/`: the answer-bank modules:
  - `AnswerMatcher`: `Matcher.check(categoryId, text, used)`, `Matcher.newRound(categoryId)` then `round:submit(text)`, and `Matcher.randomCategory(rng, minSize)`.
  - `Rarity`: the 5 tiers and every tuning number.
  - `Luck`: `Luck.submit(round, text, level, mayRescue)`, `Luck.CHANCES`, `Luck.oddsText()`.
  - `Categories`: id/name/prompt/count for all 201 categories.
  - `Blocklist`, `CommonWords`, `Banks/`.
  - `docs/answer-banks-README.md` explains the API. Don't rewrite these modules; build on them. Only change the tuning numbers in Rarity and Luck.

## Tiers (from Rarity)
| Tier | Coins | Air let out | Extra |
|---|---|---|---|
| 0 Shallows | 1 | 0 s | |
| 1 Reef | 3 | 1 s | |
| 2 Twilight | 6 | 2 s | |
| 3 Midnight | 12 | 3 s | holder picks who gets the blowfish |
| 4 Abyss | 25 | 5 s | holder picks; next holder starts with +2 s air; server-wide banner |

## Rules
- The server decides everything: timers, answers, coins, rank and rolls. The client only shows things and sends requests. Validate every RemoteEvent (type checks, rate limits, "is it your turn").
- Timers run on server time. Store end times as attributes and let clients count down with `workspace:GetServerTimeNow()`.
- Every typed answer goes through `TextService:FilterStringAsync` before anyone else sees it. If the filter changed it (hashes), treat it as wrong and pass `mayRescue = false` to Luck.
- Use ProfileStore (or DataStore with session locking and retries) for player data. Never lose coins.
- Monetisation rules: anything random bought with Robux shows exact odds that add up to 100%. Check `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted` and hide paid random items for those players. No casino-style games (no slots, cards or roulette). Paid luck shows its exact chances. No fake timers, no guilt pop-ups.
- Use metric units in any text.
- Keep the code in tidy modules (ServerScriptService/Server, ReplicatedStorage/Shared, StarterPlayerScripts/Client). Use one RemoteEvents folder in ReplicatedStorage.
- Phone first: test UI at 844×390 landscape, use big tap targets, and give every ScreenGui ResetOnSpawn = false.

## UI style
Bright simulator-store look, not dark and not generic:
- Thick near-black outlines (#14162E) on panels and buttons (UIStroke, 3 px).
- Header bars with a checkered pattern over a bright gradient.
- Bright gradient cards. Green buttons for "go/buy", red for close, gold for shop.
- White Fredoka text with a thick dark outline (UIStroke on text, 3–4 px).
- A small dark drop "shadow" under buttons. Buttons squash when pressed.
- Tier colours: Shallows light blue, Reef green, Twilight blue, Midnight purple, Abyss gold/orange.
- The underwater scene is bright turquoise, with sunbeams, kelp, fish, a turtle, a manta, jellyfish, walking starfish and crabs, all animated.
- The blowfish is glossy and yellow, with gold studs, big shiny eyes and pink cheeks. It's a 3D model, not a flat image.
- Everything animates: tier stamps slam in, panels pop in with a small overshoot, coins fly to the counter, and the blowfish puffs and bobs, then flashes red near the end.
## Working without Studio (cloud sessions)
When there is no Roblox Studio connection:
- Write all code as `.luau` files under `src/`, following Rojo naming:
  - `Name.server.luau` = Script
  - `Name.client.luau` = LocalScript
  - `Name.luau` = ModuleScript
  - A folder = Folder
  - `init.luau` makes the folder itself the script
- Keep the code where it goes: server code in `src/ServerScriptService/Server`, shared modules in `src/ReplicatedStorage/Shared`, client code in `src/StarterPlayerScripts/Client`, and UI built in code (no hand-made GUIs).
- Build parts, rings and UI from code (e.g. a MapBuilder module that creates the ring models at runtime, or a Studio command script), so everything lives in git.
- Anything that needs Studio goes in `TODO-studio.md` with exact steps for the owner. This covers generating meshes and textures, screenshots, playtests, uploading sounds and images, and creating products in the Creator Dashboard. Use placeholder parts or IDs in code until then.
- Pure logic (ranked maths, clam odds, wheel odds, luck, pity) goes in plain modules with no Roblox services, so it can be unit tested. If `lune` is available, add tests under `tests/` and run them.
- Commit after each prompt is finished, with a clear message.
