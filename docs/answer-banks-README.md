# Shrimpillion answer banks

53,000+ answers across 201 categories, each tagged with a rarity tier, plus a matcher that forgives typos and plurals without letting players cheat.

## Install

**Studio:** drag `ShrimpillionAnswers.rbxmx` into **ServerStorage**. Keep it on the server so exploiters can't read the answer lists.

**Repo / Rojo:** put this folder at `src/ServerStorage/ShrimpillionAnswers/` (the `.luau` files become ModuleScripts, `Banks/` becomes a Folder).

Copy `Rarity` into ReplicatedStorage as well if the client UI needs the tier names and colours.

## Use it

```lua
local ServerStorage = game:GetService("ServerStorage")
local Answers = ServerStorage.ShrimpillionAnswers
local Matcher = require(Answers.AnswerMatcher)
local Rarity = require(Answers.Rarity)
local Categories = require(Answers.Categories)

Matcher.preloadAll() -- once at server start, so the first round has no hitch

local categoryId = Matcher.randomCategory(nil, 30) -- every category has 30+ answers; raise this to skip smaller ones
local prompt = Categories.byId[categoryId].prompt   -- "Name a sea creature"
local round = Matcher.newRound(categoryId)

-- when the blowfish holder submits text:
local result = round:submit(text)
if result.ok then
	local tier = Rarity.get(result.tier)
	-- pass the blowfish, deflate by tier.deflate, let them pick a target if tier.chooseTarget,
	-- give tier.coins, show result.display in tier.color, banner if tier.announce
elseif result.reason == "used" then
	-- "Someone already said Octopus!" (result.display) — they keep the blowfish
else
	-- "unknown" or "empty" — they keep the blowfish
end
```

Show `result.display` in the feed, not the raw text. If you ever show raw typed text to other players, it has to go through `TextService:FilterStringAsync` first.

## Rarity tiers

Five tiers, like Krillion's rarities. The deeper the answer, the more air it lets out of the blowfish.

| Tier | Name | Like | Effect (edit in `Rarity`) |
|---|---|---|---|
| 0 | Shallows | Common | Pass only. Dog, shark, pizza. |
| 1 | Reef | Uncommon | Small deflate. Octopus, flamingo, hedgehog. |
| 2 | Twilight | Rare | Bigger deflate. Cockatoo, platypus, seahorse. |
| 3 | Midnight | Epic | Deflate, and the answerer picks the next holder. Narwhal, axolotl, meerkat. |
| 4 | Abyss | Legendary | Big deflate, pick a target, extra air for the next holder, and a server banner. Okapi, coelacanth, anything obscure. |

How rarity was decided:
- Tiers are set by how well-known the answer is to a 5–17 year old, using everyday word frequency with fixed cut-offs. The same answer gets the same tier in every category, except where it's an obvious answer for that category.
- Each category has hand-picked obvious answers, which are always Shallows.
- Each category also has a few hand-picked rare-but-gettable answers, which are always Abyss.
- Anything only found in the dictionary, and not in any hand-written list, can't be Shallows or Reef. Places and people (countries, cities, authors) count as less familiar, because kids know fewer of them than adults.

## What the matcher accepts

- Ignores case, spaces, punctuation, accents and a leading "the/a/an". `the Puffer-Fish` matches Pufferfish.
- Plurals and singulars, including irregular ones: wolves, geese, octopi, berries, boxes.
- Typos on longer words: 1 typo from 6 letters, 2 from 10. The first letter must be right, and if two different answers are equally close it doesn't guess.
- Real English words are never auto-corrected into answers. `taking` won't become Takin, `castle` won't become Cattle. This uses the `CommonWords` module.
- Nicknames work, such as orca for Killer whale or Einstein for Albert Einstein. A spelling can't be cashed in twice, so typing "anteater" three times won't score aardvark, pangolin and echidna.

## Fixing weird answers

The banks are auto-built from big word lists, so playtests will turn up odd ones. Add them to `Blocklist`; no rebuild is needed:

```lua
return {
	all = {},
	sports = { "Some Weird One" },
}
```

## Categories

- **Animals & nature** (37): Animals, Sea creatures, Birds, Mammals, Bugs & insects, Reptiles & amphibians, Dog breeds, Cat breeds, Dinosaurs, Flowers, Trees & plants, Weather, Shrimp, crabs & lobsters, Fish, Sharks & rays, Snakes, Spiders & scorpions, Butterflies & moths, Monkeys & apes, Wild cats, Rodents, Horse breeds, Farm animals, Pets, Baby animals, Animal sounds, Animal homes, Animal group names, Extinct animals, Birds of prey, Mushrooms & fungi, Crops, Things at the beach, Things in a forest, Things in a garden, Landforms, Natural disasters
- **Food & drink** (35): Fruits, Vegetables, Foods & dishes, Desserts & sweets, Drinks (non-alcoholic), Cheeses, Breads & baked goods, Herbs & spices, Sauces & condiments, Pasta & noodles, Nuts, seeds & beans, Breakfast foods, Fast food, Sandwiches, Soups & stews, Pizza toppings, Ice cream flavours, Cakes, Cookies & biscuits, Pastries, Candy & chocolate, Meats, Seafood dishes, Grains & cereals, Coffee & tea drinks, Cuisines, Cooking methods, Italian foods, Mexican foods, Chinese foods, Japanese foods, Indian foods, Things in a fridge, Berries, Snacks
- **Places** (28): Buildings & places, Countries, Capital cities, Cities of the world, Rivers, lakes & seas, Countries in Europe, Countries in Africa, Countries in Asia, Countries in the Americas, US states, Islands, Mountains, Famous landmarks, Deserts, Rooms in a house, Shops & stores, Things in a classroom, Things in a bathroom, Things in a bedroom, Things in an office, Things in a hospital, Things at an airport, Things at a theme park, Things on a farm, Things at a circus, Languages, Nationalities, Currencies
- **People & life** (27): Jobs, Feelings & emotions, Family members, Hobbies, Chores, School subjects, School supplies, Holidays & festivals, Christmas things, Halloween things, Halloween costumes, Birthday party things, Things you pack for a trip, Jewellery, Bags & accessories, Hairstyles, Makeup & beauty, Toiletries, Cleaning supplies, Ways to say hello, Ways to move, Superpowers, Famous scientists, Famous painters, Classical composers, Famous authors, Famous explorers
- **Sports & games** (15): Sports, Toys & games, Sports equipment, Board games, Card games, Video game genres, Playground things, Dances, Martial arts, Gym exercises, Olympic events, Ball sports, Water sports, Winter sports, Camping gear
- **Music, art & fun** (13): Musical instruments, Music genres, Art supplies, Art styles, Book genres, Movie genres, Fairy tales, Pirate things, Wizard things, Knight & castle things, Patterns, Apps & websites, Car brands
- **Science & body** (21): Gems, rocks & minerals, Chemical elements, Body parts, Space, Bones, Organs, Illnesses, Branches of science, Units of measurement, Computer parts, Inventions, Energy sources, Constellations, Planets & moons, Things that fly, Things with wheels, Car parts, Things in a car, Aircraft, Trains & rail, Science tools
- **Myths & stories** (6): Medieval & fantasy weapons, Gods & goddesses, Myths & legends, Greek mythology, Norse mythology, Egyptian mythology
- **Vehicles** (2): Vehicles, Boats & ships
- **Stuff** (17): Clothing, Hats & shoes, Furniture, Tools, Things in a kitchen, Containers, Colours, Fabrics & materials, Shapes, Knots, Gadgets & appliances, Things made of wood, Things that are round, Things that are red, Gardening tools, Sewing & craft things, Lights & lamps

Answer counts and per-tier counts for each category are in `Categories`.

## Credits (keep these somewhere in the game's credits or description)

- WordNet 3.0, © Princeton University (WordNet licence)
- Corpora by Darius Kazemi and contributors (CC0)
- Country data: mledoze/countries (ODbL)
- Word frequencies: wordfreq by Robyn Speer (CC BY-SA 4.0)
