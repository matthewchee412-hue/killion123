# Shrimpillion — prompts for Claude Code

How to use this:
1. Make a folder for the game (e.g. `Shrimpillion`) and put these in it:
   - `ShrimpillionAnswers.rbxmx`
   - `ShrimpillionAnswers-source.zip`, unzipped
   - `shrimpillion-design-doc.md`
2. Save **Part 1** below as `CLAUDE.md` in that folder. Claude Code reads it automatically every session, so every prompt gets the background.
3. Open Roblox Studio with a new place called **Shrimpillion**, with the Studio MCP server connected to Claude Code.
4. Open Claude Code in the folder and paste the prompts in **Part 2** one at a time. Wait for each to finish, playtest, and fix anything before moving on. Running `/clear` between prompts keeps it focused.

---

## Part 1 — CLAUDE.md

```markdown
# Shrimpillion (Roblox)

A remake of Krillion's "Puffer Party", called Blowfish Blowout. Players sit on boulder armchairs in a ring on the seabed. A blowfish fills with air while someone holds it. To pass it on, the holder types an answer to the round's category ("Name a fish"). If the air fills up while you hold it, it pops and you're out. Last player left wins. Rarer answers let air out and give more control. Players are mostly 5–17, so everything stays simple and readable.

## Files in this folder
- `shrimpillion-design-doc.md`: the full design. Read it before any big task.
- `ShrimpillionAnswers.rbxmx`: the answer-bank folder. Goes in ServerStorage.
- `ShrimpillionAnswers/`: the same modules as source:
  - `AnswerMatcher`: `Matcher.check(categoryId, text, used)`, `Matcher.newRound(categoryId)` then `round:submit(text)`, and `Matcher.randomCategory(rng, minSize)`.
  - `Rarity`: the 5 tiers and every tuning number.
  - `Luck`: `Luck.submit(round, text, level, mayRescue)`, `Luck.CHANCES`, `Luck.oddsText()`.
  - `Categories`: id/name/prompt/count for all 201 categories.
  - `Blocklist`, `CommonWords`, `Banks/`.
  - The README explains the API. Don't rewrite these modules; build on them. Only change the tuning numbers in Rarity and Luck.

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
```

---

## Part 2 — prompts, in order

### 1. Load the answer banks and test them
```
Read CLAUDE.md and shrimpillion-design-doc.md. Then in Roblox Studio:
1. Insert ShrimpillionAnswers.rbxmx into ServerStorage. If you can't insert the file, recreate the folder from the ShrimpillionAnswers/ source modules.
2. In a test Script, require AnswerMatcher and check these in the right categories:
   - "dog" (animals) is Shallows.
   - "infraorbitals" (body parts) becomes Infraorbital nerve.
   - "zygomatics" becomes Cheekbone.
   - "hammerhead" becomes Hammerhead shark.
   - "golden" and "killer" are unknown.
   - A used answer comes back "used".
3. Time Matcher.preloadAll() and a single check, and tell me the numbers.
4. Test Luck.submit at level 5 a few hundred times on wrong and right answers. Report the rescue and upgrade rates, which should be about 50% and 20%.
Fix anything that errors, but don't change the matching rules. Delete the test script when done.
```

### 2. The round system (several rings at once)
```
Build the server round system for Blowfish Blowout. Use the design doc and the Rarity, Luck and AnswerMatcher modules.

Rings:
- Each ring is a Model in workspace.Rings with 8 Seat parts and a centre point. Make a RingService that handles any number of rings at the same time, each with its own state.
- A ring has a "Ranked" attribute (true/false). Casual rings start with 2+ players. Ranked rings need 4+.
- Once enough players are seated, count down 15 s, or 8 s if all 8 seats are full. Standing up during the countdown leaves. Standing up mid-round counts as popping.

A round:
- Pick a category with Matcher.randomCategory(rng, 30) and show its prompt.
- Make a Matcher.newRound for the round. Give the blowfish to a random player.
- Air fills by 1 per second while held. It pops at a random max between 18 and 30 s, which is hidden from players. Clients only see how puffed it looks.
- The holder types an answer. Filter it, then run it through Luck.submit with the player's luck level.
  - Wrong or used: show a shake and let them keep trying. No penalty except time.
  - Right: let out air equal to the tier's deflate value (never below 0) and award its coins.
  - Midnight or Abyss: the holder picks the next player (10 s to pick, else random).
  - Abyss: the next holder starts with +2 s of air, and every player in the server gets a banner.
  - Otherwise the blowfish goes to the next seated player clockwise.
- When it pops, the holder is out. They stay in their seat as a "ghost" and watch.
- New category every round. The last player left wins. Then reset after a 6 s results screen.

Dive Deeper:
- Before answering, the holder can press Dive Deeper once per turn.
- If their next right answer is Twilight or rarer: double air let out and double coins.
- If it's a right answer below Twilight, or they let 5 s pass: +3 s of air, and the turn carries on.

Luck results:
- Show what they typed and what luck turned it into ("chile soup → Paella ✨ LUCKY!").

Feed:
- Send every event to that ring's clients for the commentary feed: who answered what, tier, coins, luck, pops and Dive Deeper.

Remotes:
- SubmitAnswer, PickTarget, DiveDeeper, and one RingUpdate event the server sends with the ring state.
- Add rate limits.

Test it in Studio with a local 3-player test server. Print a log of a full round and fix bugs.
```

### 3. The map
```
Build the map (keep it lightweight so it runs well on phones):
- Spawn on a sunny beach at the top. A sandy slope and rocky path lead down into the water and onto a bright seabed.
- Use bright, light underwater lighting, not dark: Atmosphere plus a soft blue-green ColorCorrection when the camera is underwater. Use god-ray beams from above.
- Place 6 rings spread over the seabed: 4 casual and 2 Ranked. Ranked rings have gold trim and a gold glowing sign.
- Each ring has 8 seats facing the centre. Each seat is a rounded boulder ARMCHAIR with a hollowed-out seat, a high back and arm rests, like a carved stone lounge chair (NOT a throne).
  - Build them from generated meshes (use the generate_mesh / generate_procedural_model tools) so they look carved and natural, then add the Seat part.
  - Every seat has a SeatSkin attribute so cosmetics can swap the model later.
- Each ring gets a sign above it showing its status: "Open 3/8", "Starting 0:08", "In game".
- Seabed life:
  - Swaying kelp (animated bones or a TweenService sway).
  - Coral, rocks, shells and sand ripples.
  - Starfish and crabs that slowly walk around.
  - Schools of fish, a turtle, a manta ray and jellyfish that swim across on loops.
  - Bubbles rising.
  Run all the animation on the client so the server stays light.
- Players walk and swim normally between rings.
- Take screenshots from a few angles, show me, and improve anything that looks plain.
```

### 4. The round UI and HUD
```
Build the in-game UI in the style from CLAUDE.md. Use TweenService for all the motion.
- Top right: a coin pill with a coin icon and a green "+" that opens the shop.
- Top left: a small commentary feed (last 4 lines, slides in, fades out).
- Top centre: the category prompt in a bold header bar, and whose turn it is.
- When it's your turn:
  - A big answer box with a green "Send" button. The keyboard opens automatically on mobile.
  - A Dive Deeper button.
  - The blowfish shown big over the scene, puffing up and flashing red near the end.
- When it's someone else's turn: their name and avatar headshot, plus "is thinking…".
- Tier stamp: when someone scores, a stamp with the tier name and colour slams in and shakes. Abyss gets a gold banner sweeping across the screen with confetti for everyone in the server.
- Midnight/Abyss pick screen: tap a player's portrait to choose who gets the blowfish, with a 10 s ring timer.
- "? Tiers" button: opens a small panel listing the five tiers with an example answer each and what they do. Hidden by default.
- Ring lobby: "Ring full · 8/8 · starts in 0:08", plus Shop and Stand up buttons.
- Results: placement, coins earned, best answer of the round, rank points (if ranked), and a "Play again" button.
- The 3D blowfish (a glossy yellow puffer with gold studs) floats above the holder's chair and flies in an arc to the next holder when passed. It pops with a burst of particles.
Test at 844×390 and 1920×1080. Screenshot each screen and fix anything cramped, overlapping or unreadable.
```

### 5. Player data and coins
```
Add player data with ProfileStore (install it from the official source), or DataStore with session locking and retries.

Save:
- coins, pearls
- owned and equipped cosmetics
- clams
- luck potions (with expiry times)
- rank points, peak rank this season
- wins, rounds played
- best answer ever (text + tier)
- daily wheel last-spin time
- pity counter

Rules:
- Coins come from answers (Rarity coins), with +20 for winning and +5 for 2nd place.
- Save on leave and every 2 minutes. Handle BindToClose.
- Make a leaderstats folder showing Coins and Rank.
- Write a test that joins, earns coins, leaves, rejoins and checks nothing was lost.
```

### 6. Ranked
```
Add ranked play (design doc, "Ranked" section). Only rings with Ranked = true count.

Points:
- When a ranked round ends, change each player's points Elo-style. For each pair of players in the ring, the one who popped later "won" against the other. Expected score = 1 / (1 + 10^((theirPoints − yourPoints) / 400)). Change = round(32 × (actual − expected) / (playerCount − 1)), summed over every opponent.
- Minimum change is +3 for the winner, and points can't go below 0.

Ranks:
- Plankton 0, Shrimp 300, Crab 700, Octopus 1100, Shark 1500, Orca 1900, Kraken 2300.
- The top 100 by points (and Kraken or higher) show as Leviathan. Use an OrderedDataStore leaderboard that refreshes every 5 minutes.

Display:
- The rank icon and name show on the player's name tag (BillboardGui) and on a small plate on their chair.
- A leaderboard board stands near the ranked rings.

Seasons:
- Each season lasts 6 weeks. Keep the season number and end date in one config module.
- At season end, points soft-reset to (points × 0.5). Each player gets a badge and a season chair skin for their peak rank. Give the reward when they next join.
```

### 7. Cosmetics that look good enough to buy
```
Make the cosmetics. They have to look genuinely good, or nobody will buy them. Use generate_mesh, generate_texture and generate_material for models, and ParticleEmitters/Beams/Trails for effects. Show me screenshots of each before moving on.
- Seats (replace the boulder armchair model):
  - Coral Pebble (pink coral armchair)
  - Clam Seat (an open clam shell you sit in)
  - Kelp Lounger (woven kelp)
  - Golden Rock (shines and sparkles when you win)
  - Shipwreck Chair (old wood and brass)
  - Crystal Geode (glowing purple crystals)
  - Lava Vent (warm glow, rising bubbles)
- Blowfish skins (how the blowfish looks when you hold it):
  - Classic
  - Spotted
  - Galaxy (dark with stars)
  - Gold
  - Ice
  - Neon
- Pop effects (when you pop):
  - Confetti
  - Ink cloud
  - Bubble burst
  - Firework
  - Glitter shark
- Answer stamps (style of your tier stamp):
  - Classic
  - Graffiti
  - Pixel
  - Bubble letters
- Emotes from your chair: Wave, Laugh, Clap, Facepalm, Dance (use standard Roblox animations).
- Each item has a rarity (Common, Rare, Epic, Legendary) and a coin price: Common 400, Rare 1,200, Epic 3,500, Legendary 9,000.
- Every cosmetic also has Shiny and Rainbow variants, which can only come from clams. Shiny is brighter with sparkles. Rainbow cycles colours.
- Build a Cosmetics catalogue module (id, name, type, rarity, price, model/effect reference). Make equipping work: the seat model swaps on your chair, the blowfish swaps when you hold it, and the effects play.
```

### 8. Shop, Clam Cracking, Tide Wheel and pearls
```
Build the shop and the luck-based rewards (design doc, "Gambling-style features"). Follow the Roblox rules in CLAUDE.md exactly.

Shop:
- Tabs: Daily, Shop and Robux.
- Shop sub-tabs: Seats, Blowfish, Pop FX, Stamps, Emotes, Luck.
- Item cards have a 3D ViewportFrame preview that slowly spins.

Clam Cracking:
- A clam costs 500 coins. Only coins can buy clams; you can't buy them directly with Robux.
- Odds: Common 60%, Rare 28%, Epic 10%, Legendary 2%. Then 5% chance the item is Shiny and 0.5% chance it's Rainbow.
- Show these odds on the clam button and in an "Odds" panel before buying.
- Opening animation: the clam wobbles. Its glow colour hints at the rarity (blue, purple, gold). Glow hints can be wrong to tease for Common/Rare only, never for Epic/Legendary. Then it bursts open, and the item spins in a ViewportFrame.
- Pity: if 20 clams in a row give nothing Epic or better, the next is guaranteed Epic or better. Show an "Epic in X clams" counter.
- Duplicates become pearls: Common 5, Rare 15, Epic 50, Legendary 200.

Pearl shop:
- Buy any non-variant cosmetic with pearls, at price ÷ 10 (rounded).

Tide Wheel (free, once a day, resets at 00:00 UTC):
- 50 coins 30%
- 150 coins 20%
- 400 coins 8%
- 1 clam 12%
- Luck I potion 15%
- Luck III potion 5%
- 10 pearls 10%
- The wheel spins with easing, and the result is decided on the server before the animation.

Pearl drops:
- A Midnight answer has a 5% chance of 1–3 pearls.
- An Abyss answer has a 15% chance of 2–5 pearls and a 3% chance of a clam. Show it as a little pop-up.

Robux tab:
- Coin packs as Developer Products: 1,000 / 3,000 / 7,500 / 20,000.
- A "2× coins" Game Pass.
- A "VIP chair plate" Game Pass.
- Handle ProcessReceipt correctly (idempotent, saved before returning PurchaseGranted).
Write the Developer Product IDs into one config module with placeholder IDs. Tell me what products to create in the Creator Dashboard.
```

### 9. Luck Potions
```
Add Luck Potions using the existing Luck module (design doc, "Luck" section). Works in all rings, ranked included.
- Levels 1–5.
- Each potion lasts 10 minutes of real time. Drinking a higher level replaces a lower one, and the same level adds time.
- Prices:
  - Luck I: 300 coins
  - Luck II: 800 coins
  - Luck III: 2,000 coins or 49 Robux
  - Luck IV: 99 Robux
  - Luck V: 199 Robux
- Store the active level and expiry on the server. Pass the level into Luck.submit.
- The shop's Luck tab lists every level with its exact chances, read from Luck.oddsText() (Roblox requires showing the odds for paid luck).
- While luck is active, show a clover badge with a countdown near the coins.
- When luck changes an answer, show "chile soup → Paella ✨ LUCKY!" in the feed and a green sparkle on the stamp.
```

### 10. Polish and test pass
```
Do a full test and polish pass:
1. Run a local server with 4 test players. Play a full casual round and a full ranked round.
2. Check:
   - Answers, tiers, Dive Deeper, Midnight pick, Abyss banner, luck rescue/upgrade.
   - Pops, results, coins saved, rank points.
   - Clams, the wheel and pearls.
   - Leaving mid-round.
   - Two rings running at once.
3. Try to break it: spam remotes, send answers when it's not your turn, send huge strings, buy with not enough coins. Make sure the server rejects each one.
4. Check performance on the phone emulator: frame rate, number of parts, and memory. Cut anything heavy.
5. Screenshot every screen at phone size and fix ugly or cramped spots.
6. Add sounds for:
   - Pass, each tier (deeper tiers = deeper/bigger sounds)
   - Pop, win
   - Clam open, wheel tick
   - Button presses
   - Gentle underwater music
7. Give me a list of what's done, what's still rough, and what I need to do in the Creator Dashboard (products, passes, badges, game icon, thumbnails).
```
