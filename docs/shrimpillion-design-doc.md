# Shrimpillion — design notes

Roblox take on Krillion's Puffer Party (krillion.io/party). Krill → **Shrimp**illion, Puffer Party → **Blowfish Blowout**. We keep the mechanic but use none of Krillion's names, art or answer data.

## Blowfish Blowout (core loop)
- Players stand on platforms around an underwater arena. A category appears, e.g. "Name a sea creature".
- The blowfish starts with a random player and inflates on a hidden timer.
- The holder types an answer. A valid, unused answer passes it on. A wrong or repeated answer means they keep it.
- If it pops on you, you're blasted out of the ring. Last one floating wins.
- Popped players come back as ghost shrimp who can nudge the timer, so they stay in the server.

## World and the rock rings
- Players spawn on a beach island (shell shop on the sand), then walk down a sandy slope into the sea, following glowing stones.
- The seabed has **several rock rings at once**, each its own game of up to 8. Floating signs show each ring's state: OPEN 3/8, STARTING 0:12, PLAYING. New rings open as the server fills.
- Each seat is a rounded boulder armchair: a lumpy stone with a scooped-out hollow and a flat seat pad, like a stone beanbag rather than a throne. Players sit facing the middle, so they can see each other, like the krill on rocks in Puffer Party.
- A ring starts once 2 or more are seated. The blowfish floats above whoever holds it, and that player's chair glows gold. Popped players turn see-through on their chair.
- Living background: swaying kelp, coral, rising bubbles, shimmering sunbeams, a crawling starfish, a scuttling crab, a bobbing jellyfish, fish schools and a turtle swimming past, and a far-off manta. Random sea creatures cross now and then.

## Coins: what players buy
Cosmetics, plus Luck Potions (see Luck). Cosmetics need real 3D models and particle effects that look good enough to want, not recoloured parts.
- Seats: chair skins for your rock (Coral Pebble, Clam Seat, Golden Rock that shines when you win).
- Blowfish skins: how the blowfish looks while you hold it.
- Pop effects: what happens when you pop (confetti, ink cloud, bubble burst).
- Stamps: the style of your tier stamp when you score.
- Emotes: reactions you can do from your chair.
- Shop tabs: Daily, Shop and Robux (coin packs).

## Motion (everything animates)
- Tier stamps slam in and shake. Abyss gets a sweeping server-wide banner with confetti.
- The blowfish bobs and puffs, swells faster as air runs low, flashes red near the end, then pops. Passing it flies it in an arc to the next chair.
- Buttons squash when pressed, coins fly to the counter, and the feed slides new lines in.
- Panels pop in with a small overshoot.
- Everything respects reduced motion.

## HUD details
- The commentary feed (top left) is compact.
- The "How deep?" tier guide is hidden behind a "? Tiers" button, and only opens when a player taps it.

## UI style
- Simulator-store look: thick near-black outlines (#14162E), checkered gradient header bars, bright gradient cards, green buttons, white text with a thick dark outline (Fredoka). Coins pill with a green "+".
- Tier colours: Shallows light blue, Reef green, Twilight blue, Midnight purple, Abyss gold/orange.
- The blowfish is a glossy, 3D-looking yellow puffer with gold studs, big shiny eyes and pink cheeks.
- Mockups: the "Shrimpillion UI" design canvas.

## Rarity twist
Five tiers, like Krillion's rarities. Deeper answers let air out and give more control:

| Tier | Like | Effect |
|---|---|---|
| Shallows | Common | Pass only (dog, shark, pizza) |
| Reef | Uncommon | Small deflate (octopus, flamingo) |
| Twilight | Rare | Bigger deflate (cockatoo, platypus) |
| Midnight | Epic | Deflate + you pick who gets it (narwhal, axolotl) |
| Abyss | Legendary | Big deflate, pick target, extra air for the next holder, server banner (okapi, anything obscure) |

Tiers come from fixed familiarity cut-offs tuned for 5–17 year olds, not from rank inside a category. Anything only found in the dictionary, and not in any hand-written list, can't be Shallows or Reef. All tuning numbers live in the `Rarity` module.

## Answer banks (updated 28 Oct 2026)
- 53,498 answers in 201 categories (55 original + 146 new), built from WordNet, Corpora, country data, wordfreq and hand-written lists.
- New categories are mostly hand-written lists of everyday answers (things in a bathroom, breakfast foods, pirate things), with WordNet depth added where it fits (fish, snakes, currencies). The lists are in `new_cats_a/b/c.py`.
- Easy prompts on purpose: the audience is young Roblox players, so prompts stay simple ("Name a fish"), not narrowed ("a bird that lives near water").
- No Australian slant: the obvious answers and gems were rewritten to be globally known. Australian answers are still accepted, just never favoured.
- Includes nicknames, plural and typo forgiveness, and a guard so real English words are never auto-corrected into answers. Across all 201 categories, only 18 of the 4,000 most common English words get forgiven into an answer, and almost all are plurals of real answers.
- Rarity combines hand-picked obvious answers per category with word frequency, using fixed cut-offs (see Rarity twist). Each category has 3–6 hand-picked rare answers, which are always Abyss.
- Deliverables: `ShrimpillionAnswers.rbxmx` goes in ServerStorage, and `ShrimpillionAnswers-source.zip` has the Luau sources plus the builder scripts.
- Odd answers found in playtests go in the `Blocklist` module.

## Ranked (decided 29 Oct 2026)
- Some rings on the seabed are gold Ranked rings that need 4+ players; the rest are casual.
- You gain or lose rank points by how late you pop, adjusted for how strong the ring was (stronger rings = more points for beating them).
- Ranks: Plankton → Shrimp → Crab → Octopus → Shark → Orca → Kraken. The top 100 players show as Leviathan.
- Seasons last about 6 weeks. Your peak rank earns a season chair skin and a badge.
- Your rank icon shows on your name tag and your chair.

## Gambling-style features (decided 29 Oct 2026)
All four chosen:
- **Clam Cracking:** spend coins on a clam. It wobbles and glows a colour that hints at what's inside, then pops open a random seat, blowfish skin or pop effect, sometimes Shiny or Rainbow. Odds are shown on every clam and add up to 100%. Duplicates turn into pearls for a pity shop.
- **Daily Tide Wheel:** one free spin a day for coins, clams or luck.
- **Dive Deeper:** in a round, the holder can choose to Dive Deeper: answer Twilight or rarer for double the air let out and double coins; miss and the blowfish puffs up. Skill decides it, nothing is paid.
- **Pearl drops:** deep answers have a chance to drop a pearl or a clam.

Roblox rules: anything random bought with Robux shows exact odds that sum to 100%, and is hidden where PolicyService says paid random items are restricted. No playable casino games (no slots, cards or roulette for Robux). Clams are bought with coins.

## Luck (decided 29 Oct 2026)
- Luck levels 1–5 from Luck Potions, sold for coins and Robux, and earned from the Tide Wheel and pearls. Works in every ring, ranked included (user's call, knowing players may call it pay-to-win).
- **Rescue:** a wrong answer has a chance to turn into a random unused Shallows or Reef answer, like Krillion turning "chile soup" into a random dish.
- **Upgrade:** a right answer has a chance to turn into a random unused answer one tier deeper.
- Chances per level: rescue 10/20/30/40/50%, upgrade 4/8/12/16/20%. They live in the `Luck` module, and the shop shows them straight from there (Roblox requires the exact odds for paid luck).
- Rude words caught by the text filter are never rescued.

## Autocorrect (updated 29 Oct 2026)
More forgiving even without luck: typing the first word of a longer answer counts ("infraorbitals" → Infraorbital nerve, "hammerhead" → Hammerhead shark), as long as that word is 5+ letters and not an everyday word ("golden" and "killer" don't count). Science words also map to everyday names ("zygomatics" → Cheekbone).

## Next up
Round loop (server): many rings at once, blowfish timer, passing, popping, Dive Deeper, luck. Then ranked points, the economy (coins, clams, wheel, shop), the map, and the UI from the design canvas.
