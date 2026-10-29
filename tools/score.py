"""Turn raw banks into tiered banks.

Rarity = how unlikely a player is to say it. Signals:
  1. hand-picked OBVIOUS answers per category -> always Shallows (the "everyone says it" tier)
  2. word frequency (wordfreq zipf), with a penalty for multi-word names whose
     per-word frequency overstates how often the whole phrase is used
  3. hand-curated entries get a small familiarity boost
Tiers are then cut by rank inside each category, so "Triceratops" counts as an
obvious dinosaur even though it is a rare English word.

Shrimpillion (the gem) = a few rare-but-gettable answers per category.
"""
import json, re, sys, unicodedata
from pathlib import Path
from wordfreq import zipf_frequency

OUT = Path("/home/claude/shrimpillion/out")

def norm_key(s):
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower().replace("&", "and").replace("ø", "o").replace("æ", "ae").replace("ß", "ss")
    return re.sub(r"[^a-z0-9]", "", s)

TIERS = ["Shallows", "Reef", "Twilight", "Midnight", "Abyss"]   # + "Shrimpillion" (gems)
# cumulative share of each category (by rank) that falls in each tier
CUTS = [0.06, 0.18, 0.40, 0.68, 1.0]
MIN_SHALLOWS = 6

def L(s):
    return [x.strip() for x in s.split(",") if x.strip()]

OBVIOUS = {
"animals": L("Dog, Cat, Lion, Tiger, Elephant, Giraffe, Monkey, Horse, Cow, Pig, Sheep, Goat, Chicken, Duck, Rabbit, Mouse, Rat, Bear, Wolf, Fox, Zebra, Kangaroo, Koala, Panda, Penguin, Shark, Whale, Dolphin, Snake, Frog, Fish, Bird, Eagle, Owl, Parrot, Crocodile, Turtle, Spider, Bee, Ant, Butterfly, Deer, Camel, Hippo, Rhino, Gorilla, Cheetah, Leopard, Squirrel, Hamster, Octopus, Crab, Shrimp"),
"sea_creatures": L("Shark, Whale, Dolphin, Octopus, Squid, Jellyfish, Starfish, Crab, Lobster, Shrimp, Prawn, Seahorse, Clownfish, Turtle, Sea turtle, Seal, Sea lion, Stingray, Orca, Killer whale, Eel, Tuna, Salmon, Fish, Coral, Oyster, Clam, Penguin, Walrus, Blue whale, Great white shark, Pufferfish"),
"birds": L("Eagle, Owl, Parrot, Penguin, Pigeon, Crow, Duck, Chicken, Swan, Flamingo, Peacock, Ostrich, Emu, Seagull, Robin, Sparrow, Hawk, Falcon, Magpie, Hummingbird, Toucan, Turkey, Goose, Raven, Dove, Pelican, Woodpecker, Kiwi, Vulture, Bald eagle, Blue jay, Cardinal"),
"mammals": L("Dog, Cat, Lion, Tiger, Elephant, Giraffe, Monkey, Horse, Cow, Pig, Sheep, Goat, Rabbit, Mouse, Rat, Bear, Wolf, Fox, Zebra, Kangaroo, Koala, Panda, Whale, Dolphin, Bat, Human, Deer, Camel, Hippo, Rhino, Gorilla, Cheetah, Squirrel, Platypus, Seal"),
"insects": L("Ant, Bee, Fly, Spider, Butterfly, Beetle, Mosquito, Cockroach, Ladybug, Ladybird, Grasshopper, Cricket, Dragonfly, Moth, Wasp, Caterpillar, Worm, Scorpion, Termite, Flea"),
"reptiles": L("Snake, Lizard, Crocodile, Alligator, Turtle, Tortoise, Frog, Toad, Gecko, Chameleon, Iguana, Python, Cobra, Komodo dragon, Salamander, Axolotl"),
"dog_breeds": L("Labrador, Golden retriever, German shepherd, Poodle, Pug, Beagle, Bulldog, Chihuahua, Husky, Dachshund, Corgi, Rottweiler, Dalmatian, Border collie, Pomeranian, Shih tzu, Greyhound, Boxer, Great Dane, Doberman"),
"cat_breeds": L("Persian, Siamese, Maine Coon, Ragdoll, Bengal, Sphynx, British Shorthair, Scottish Fold, Russian Blue, Burmese"),
"dinosaurs": L("Tyrannosaurus rex, Triceratops, Stegosaurus, Velociraptor, Brachiosaurus, Pterodactyl, Diplodocus, Spinosaurus, Ankylosaurus, Brontosaurus"),
"fruits": L("Apple, Banana, Orange, Grape, Strawberry, Watermelon, Mango, Pineapple, Pear, Peach, Cherry, Lemon, Lime, Kiwi, Blueberry, Raspberry, Coconut, Plum, Apricot, Avocado, Pomegranate, Mandarin"),
"vegetables": L("Carrot, Potato, Broccoli, Tomato, Onion, Lettuce, Cucumber, Corn, Pea, Peas, Pumpkin, Cabbage, Spinach, Capsicum, Celery, Cauliflower, Zucchini, Eggplant, Mushroom, Garlic, Bean, Sweet potato, Beetroot"),
"food_dishes": L("Pizza, Burger, Hamburger, Pasta, Spaghetti, Sushi, Fried rice, Hot dog, Sandwich, Taco, Tacos, Fish and chips, Fries, Chips, Noodles, Ramen, Curry, Steak, Salad, Soup, Lasagne, Lasagna, Dumplings, Burrito, Nachos, Meat pie, Sausage roll, Fried chicken, Chicken nuggets, Toast, Eggs"),
"desserts": L("Ice cream, Cake, Chocolate, Cookie, Brownie, Cupcake, Donut, Doughnut, Pie, Cheesecake, Jelly, Pudding, Muffin, Lollipop, Candy, Pancake, Waffle, Apple pie, Chocolate cake, Cotton candy, Popsicle"),
"drinks": L("Water, Milk, Juice, Orange juice, Apple juice, Coffee, Tea, Hot chocolate, Lemonade, Coke, Cola, Soda, Soft drink, Milkshake, Smoothie, Iced tea, Bubble tea, Energy drink, Sprite, Fanta"),
"cheeses": L("Cheddar, Mozzarella, Parmesan, Brie, Feta, Swiss, Blue cheese, Cream cheese, Gouda, Camembert, Halloumi, Ricotta, Cottage cheese"),
"breads": L("White bread, Brown bread, Toast, Bagel, Croissant, Baguette, Sourdough, Bun, Roll, Garlic bread, Pita, Naan, Tortilla, Wholemeal, Muffin, Banana bread"),
"herbs_spices": L("Salt, Pepper, Basil, Oregano, Parsley, Mint, Cinnamon, Garlic, Ginger, Chilli, Paprika, Cumin, Turmeric, Rosemary, Thyme, Coriander, Nutmeg, Curry powder"),
"sauces": L("Tomato sauce, Ketchup, Barbecue sauce, BBQ sauce, Mayonnaise, Mayo, Mustard, Soy sauce, Gravy, Hot sauce, Sweet chilli sauce, Ranch, Aioli, Salsa, Pesto, Honey, Jam, Peanut butter, Nutella"),
"pasta": L("Spaghetti, Penne, Macaroni, Fettuccine, Lasagne, Lasagna, Ravioli, Tortellini, Linguine, Fusilli, Ramen, Udon, Rice noodles, Egg noodles, Instant noodles, Gnocchi"),
"nuts_seeds": L("Peanut, Almond, Cashew, Walnut, Macadamia, Pistachio, Hazelnut, Coconut, Pecan, Brazil nut, Sunflower seed, Pumpkin seed, Sesame seed, Chia seed, Baked beans, Green bean, Kidney bean, Chickpea, Lentil, Jelly bean, Coffee bean"),
"flowers": L("Rose, Tulip, Daisy, Sunflower, Lily, Orchid, Lavender, Daffodil, Poppy, Carnation, Lotus, Hibiscus, Dandelion, Cherry blossom, Violet, Marigold, Jasmine, Peony"),
"trees_plants": L("Oak, Pine, Palm, Maple, Eucalyptus, Willow, Birch, Christmas tree, Cactus, Bamboo, Fern, Grass, Moss, Ivy, Aloe vera, Rose bush, Apple tree, Bonsai, Seaweed"),
"instruments": L("Guitar, Piano, Drums, Violin, Flute, Trumpet, Saxophone, Cello, Clarinet, Harp, Ukulele, Keyboard, Bass guitar, Electric guitar, Recorder, Trombone, Tuba, Triangle, Tambourine, Harmonica, Xylophone, Didgeridoo, Bagpipes, Accordion"),
"music_genres": L("Pop, Rock, Rap, Hip hop, Jazz, Country, Classical, R&B, EDM, Metal, Heavy metal, Blues, Reggae, Punk, K-pop, Techno, House, Dubstep, Opera, Indie, Folk, Soul, Disco"),
"sports": L("Football, Soccer, Basketball, Tennis, Cricket, Golf, Swimming, Rugby, Netball, Baseball, Volleyball, Hockey, Ice hockey, Boxing, Running, Cycling, Surfing, Skateboarding, Gymnastics, Badminton, Table tennis, Skiing, Snowboarding, Athletics, Karate, Wrestling, American football"),
"jobs": L("Teacher, Doctor, Nurse, Police officer, Firefighter, Chef, Cook, Pilot, Farmer, Lawyer, Dentist, Vet, Engineer, Scientist, Builder, Plumber, Electrician, Carpenter, Mechanic, Artist, Singer, Actor, YouTuber, Programmer, Astronaut, Judge, Waiter, Cashier, Driver, Soldier"),
"clothing": L("Shirt, T-shirt, Pants, Jeans, Shorts, Dress, Skirt, Jacket, Coat, Hoodie, Jumper, Sweater, Socks, Shoes, Hat, Cap, Scarf, Gloves, Tie, Suit, Pyjamas, Belt, Boots, Singlet"),
"hats_shoes": L("Cap, Baseball cap, Beanie, Top hat, Cowboy hat, Sun hat, Bucket hat, Helmet, Crown, Sneakers, Trainers, Flip-flops, Sandals, Boots, Slippers, High heels, Heels, Crocs"),
"furniture": L("Chair, Table, Bed, Couch, Sofa, Desk, Bookshelf, Wardrobe, Cupboard, Drawers, Stool, Bench, Armchair, Coffee table, Lamp, Cabinet, Dresser, Bunk bed"),
"tools": L("Hammer, Screwdriver, Saw, Drill, Wrench, Spanner, Pliers, Axe, Shovel, Spade, Rake, Tape measure, Ruler, Level, Chisel, Ladder, Nail, Screw, Toolbox"),
"kitchen": L("Fridge, Oven, Microwave, Stove, Toaster, Kettle, Sink, Dishwasher, Blender, Knife, Fork, Spoon, Plate, Bowl, Cup, Mug, Glass, Pan, Frying pan, Pot, Spatula, Chopping board, Bin, Tap"),
"vehicles": L("Car, Bus, Truck, Train, Plane, Bike, Bicycle, Motorbike, Motorcycle, Boat, Ship, Helicopter, Scooter, Taxi, Tram, Van, Tractor, Ambulance, Fire truck, Police car, Rocket, Submarine, Skateboard, Jet"),
"boats": L("Canoe, Kayak, Yacht, Sailboat, Ship, Ferry, Cruise ship, Speedboat, Raft, Submarine, Pirate ship, Rowboat, Fishing boat, Tugboat, Jet ski, Dinghy, Catamaran, Cargo ship"),
"buildings": L("House, School, Hospital, Church, Library, Supermarket, Shop, Mall, Bank, Hotel, Restaurant, Cafe, Office, Apartment, Castle, Skyscraper, Museum, Stadium, Cinema, Police station, Fire station, Airport, Gym, Factory, Farm, Zoo"),
"containers": L("Box, Bag, Bottle, Jar, Can, Tin, Bucket, Bin, Basket, Cup, Bowl, Backpack, Suitcase, Lunchbox, Cooler, Tupperware, Crate, Barrel, Envelope, Wallet, Purse, Vase, Chest"),
"weapons": L("Sword, Bow, Arrow, Spear, Axe, Shield, Dagger, Knife, Crossbow, Mace, Club, Catapult, Katana, Hammer, Whip, Slingshot, Lance, Trident"),
"gems_rocks": L("Diamond, Ruby, Emerald, Sapphire, Gold, Silver, Opal, Pearl, Amethyst, Crystal, Quartz, Granite, Marble, Coal, Jade, Topaz, Obsidian, Limestone, Sandstone, Rock, Pebble"),
"metals_elements": L("Hydrogen, Oxygen, Carbon, Gold, Silver, Iron, Copper, Helium, Nitrogen, Lead, Sodium, Aluminium, Aluminum, Calcium, Zinc, Uranium, Neon, Tin, Mercury, Lithium"),
"colours": L("Red, Orange, Yellow, Green, Blue, Purple, Pink, Brown, Black, White, Grey, Gray, Gold, Silver, Navy, Light blue, Dark blue, Teal, Turquoise, Violet, Indigo, Maroon, Beige, Cyan, Magenta, Lime"),
"fabrics": L("Cotton, Wool, Silk, Leather, Denim, Polyester, Nylon, Linen, Velvet, Fleece, Satin, Lace, Lycra, Spandex, Felt, Canvas"),
"body_parts": L("Head, Arm, Leg, Hand, Foot, Eye, Ear, Nose, Mouth, Finger, Toe, Knee, Elbow, Shoulder, Neck, Hair, Teeth, Tooth, Tongue, Heart, Brain, Stomach, Back, Chest, Face, Lips, Thumb, Skin"),
"emotions": L("Happy, Sad, Angry, Scared, Excited, Nervous, Bored, Love, Joy, Fear, Anger, Sadness, Jealous, Surprised, Tired, Calm, Proud, Embarrassed, Confused, Lonely, Hate, Worried"),
"toys_games": L("Lego, Teddy bear, Doll, Ball, Yo-yo, Kite, Puzzle, Rubik's cube, Chess, Checkers, Monopoly, Uno, Jenga, Hide and seek, Tag, Cards, Board game, Video game, Toy car, Barbie, Action figure, Slime, Frisbee, Nerf gun"),
"shapes": L("Circle, Square, Triangle, Rectangle, Oval, Star, Heart, Diamond, Pentagon, Hexagon, Octagon, Cube, Sphere, Cone, Cylinder, Pyramid, Rhombus"),
"weather": L("Sunny, Rain, Rainy, Cloudy, Snow, Windy, Storm, Thunderstorm, Lightning, Thunder, Hail, Fog, Tornado, Hurricane, Cyclone, Hot, Cold, Rainbow, Wind, Sun, Clouds, Drizzle"),
"countries": L("Australia, America, USA, United States, China, Japan, India, Canada, England, UK, France, Germany, Italy, Spain, Mexico, Brazil, Russia, New Zealand, Egypt, South Africa, South Korea, Korea, Indonesia, Thailand, Vietnam, Philippines, Greece, Ireland, Argentina, Fiji"),
"capitals": L("Canberra, London, Paris, Tokyo, Washington D.C., Beijing, Rome, Berlin, Madrid, Moscow, Ottawa, Wellington, Seoul, Bangkok, Cairo, New Delhi, Dublin, Athens"),
"cities": L("London, Paris, New York, Tokyo, Los Angeles, Rome, Dubai, Singapore, Beijing, Hong Kong, Sydney, Melbourne, Berlin, Moscow, Bangkok, Seoul, Chicago, Las Vegas, Toronto, Barcelona, Madrid, Istanbul, Mumbai, Shanghai, Rio de Janeiro, San Francisco, Miami"),
"rivers_lakes": L("Pacific Ocean, Atlantic Ocean, Indian Ocean, Arctic Ocean, Southern Ocean, Nile, Amazon, Mississippi, Thames, Dead Sea, Red Sea, Mediterranean, Caribbean, Great Lakes, Yangtze, Danube, Lake Michigan"),
"space": L("Sun, Moon, Earth, Mars, Jupiter, Saturn, Venus, Mercury, Uranus, Neptune, Pluto, Star, Planet, Comet, Asteroid, Meteor, Black hole, Galaxy, Milky Way, Satellite, Rocket, Alien, UFO, Nebula, Space station"),
"gods": L("Zeus, Poseidon, Hades, Athena, Apollo, Ares, Aphrodite, Hermes, Thor, Odin, Loki, Ra, Anubis, Jupiter, Mars, Venus, Neptune, Hera, Artemis"),
"myth_creatures": L("Dragon, Unicorn, Mermaid, Vampire, Werewolf, Zombie, Ghost, Phoenix, Griffin, Fairy, Elf, Goblin, Troll, Giant, Witch, Wizard, Bigfoot, Yeti, Minotaur, Medusa, Centaur, Pegasus, Kraken, Loch Ness Monster, Cyclops, Genie, Demon, Angel"),
"knots": L("Reef knot, Square knot, Granny knot, Bow, Shoelace knot, Slip knot, Overhand knot, Figure eight, Bowline, Clove hitch, Windsor knot"),
"appliances": L("Phone, TV, Television, Laptop, Computer, Tablet, iPad, iPhone, Fridge, Microwave, Toaster, Kettle, Washing machine, Dryer, Fan, Heater, Air conditioner, Vacuum cleaner, Hair dryer, Headphones, Speaker, Camera, Console, PlayStation, Xbox, Nintendo Switch"),
"shrimp_things": L("Shrimp, Prawn, Crab, Lobster, King prawn, Tiger prawn, Crayfish, Crawfish, Krill, Hermit crab, King crab, Mantis shrimp"),
}

# rare-but-gettable gems, hand-picked where it matters most; others are auto-picked
GEMS = {
"sea_creatures": L("Blobfish, Mantis shrimp, Leafy sea dragon, Dumbo octopus, Sea pig, Vampire squid, Barreleye, Goblin shark"),
"shrimp_things": L("Pistol shrimp, Peacock mantis shrimp, Coconut crab, Japanese spider crab, Yeti crab, Harlequin shrimp"),
"animals": L("Okapi, Pangolin, Aye-aye, Tardigrade, Fossa, Saiga"),
"birds": L("Shoebill, Kakapo, Hoatzin, Secretary bird, Potoo, Cassowary"),
"mammals": L("Okapi, Pangolin, Aye-aye, Narwhal, Fossa, Saiga"),
"dinosaurs": L("Therizinosaurus, Parasaurolophus, Pachycephalosaurus, Microraptor, Amargasaurus"),
"fruits": L("Mangosteen, Rambutan, Jabuticaba, Durian, Salak, Cherimoya"),
"countries": L("Kiribati, Tuvalu, Liechtenstein, Bhutan, Djibouti, Eswatini, Vanuatu"),
"capitals": L("Ouagadougou, Ulaanbaatar, Reykjavik, Thimphu, Tegucigalpa, Ashgabat"),
"metals_elements": L("Oganesson, Tennessine, Moscovium, Praseodymium, Ytterbium"),
"pasta": L("Strozzapreti, Orecchiette, Malloreddus, Bucatini, Biang biang noodles"),
"instruments": L("Theremin, Otamatone, Hurdy-gurdy, Handpan, Didgeridoo, Kalimba"),
"myth_creatures": L("Wendigo, Kitsune, Chupacabra, Qilin, Jormungandr, Baku"),
"gods": L("Quetzalcoatl, Huitzilopochtli, Amaterasu, Sun Wukong, Viracocha"),
"space": L("Betelgeuse, Proxima Centauri, Enceladus, Oort cloud, Kuiper belt, Magnetar"),
"cheeses": L("Burrata, Taleggio, Epoisses, Casu marzu, Raclette"),
"weather": L("Haboob, Graupel, Virga, Derecho, Sundog, Mammatus clouds"),
"knots": L("Monkey's fist, Prusik, Constrictor knot, Trucker's hitch, Alpine butterfly knot"),
}
GEMS.update({
"insects": L("Bombardier beetle, Hercules beetle, Orchid mantis, Assassin bug, Atlas moth, Goliath beetle"),
"reptiles": L("Tuatara, Gharial, Hellbender, Olm, Thorny devil, Basilisk lizard"),
"dog_breeds": L("Xoloitzcuintli, Basenji, Komondor, Puli, Bergamasco, Lagotto Romagnolo"),
"cat_breeds": L("Peterbald, Tonkinese, Ocicat, Lykoi, Singapura"),
"vegetables": L("Kohlrabi, Romanesco, Jerusalem artichoke, Celeriac, Salsify, Fiddlehead"),
"food_dishes": L("Bibimbap, Okonomiyaki, Takoyaki, Poutine, Haggis, Shakshuka"),
"desserts": L("Kouign-amann, Croquembouche, Baklava, Mochi, Pastel de nata, Knafeh"),
"drinks": L("Kombucha, Horchata, Teh tarik, Lassi, Ayran, Agua fresca"),
"breads": L("Challah, Lavash, Pumpernickel, Melon pan, Injera"),
"herbs_spices": L("Asafoetida, Sumac, Saffron, Grains of paradise, Fenugreek, Galangal"),
"sauces": L("Gochujang, Chimichurri, Harissa, Romesco, XO sauce"),
"nuts_seeds": L("Adzuki bean, Lupin, Tiger nut, Candlenut, Pili nut"),
"flowers": L("Edelweiss, Protea, Corpse flower, Bird of paradise, Rafflesia"),
"trees_plants": L("Welwitschia, Dragon's blood tree, Baobab, Sequoia, Ginkgo, Venus flytrap"),
"music_genres": L("Phonk, Vaporwave, Shoegaze, Amapiano, Sea shanty, Hyperpop"),
"sports": L("Padel, Sepak takraw, Kabaddi, Hurling, Chess boxing, Underwater hockey"),
"jobs": L("Sommelier, Taxidermist, Lexicographer, Ventriloquist, Farrier, Shrimp farmer"),
"clothing": L("Kimono, Hanbok, Kilt, Poncho, Sari, Lederhosen"),
"hats_shoes": L("Deerstalker, Ushanka, Espadrilles, Fez, Clogs, Tricorn"),
"furniture": L("Chaise longue, Credenza, Chiffonier, Davenport, Ottoman"),
"tools": L("Awl, Adze, Spokeshave, Stud finder, Theodolite"),
"kitchen": L("Mandoline, Spurtle, Mezzaluna, Tagine, Pestle and mortar"),
"vehicles": L("Jeepney, Tuk-tuk, Hovercraft, Zeppelin, Penny-farthing, Segway"),
"boats": L("Trireme, Dhow, Gondola, Coracle, Junk"),
"buildings": L("Ziggurat, Pagoda, Igloo, Yurt, Lighthouse"),
"containers": L("Amphora, Bento box, Canteen, Pinata, Thermos"),
"weapons": L("Khopesh, Chakram, Boomerang, Nunchucks, Morning star"),
"gems_rocks": L("Opal, Tanzanite, Alexandrite, Painite, Moldavite"),
"colours": L("Periwinkle, Chartreuse, Vermilion, Cerulean, Aubergine"),
"fabrics": L("Seersucker, Gore-Tex, Kevlar, Burlap, Tweed"),
"body_parts": L("Uvula, Philtrum, Patella, Coccyx, Hyoid"),
"emotions": L("Schadenfreude, Hangry, Ennui, Saudade, Hiraeth"),
"toys_games": L("Tamagotchi, Beyblade, Etch A Sketch, Slinky, Hacky sack"),
"shapes": L("Dodecahedron, Icosahedron, Annulus, Lemniscate, Rhombicosidodecahedron"),
"cities": L("Timbuktu, Reykjavik, Kathmandu, Marrakesh, Ushuaia"),
"rivers_lakes": L("Brahmaputra, Lake Baikal, Lake Titicaca, Zambezi, Mekong"),
"appliances": L("Thermomix, Dehumidifier, Air purifier, Robot vacuum, 3D printer"),
})
MAX_GEMS = 6

def phrase_score(name):
    words = re.split(r"[\s\-]+", name.strip())
    z = zipf_frequency(name, "en")
    if len(words) > 1:
        # word frequencies over-rate made-up-looking phrases ("Flame fish"), so every
        # extra word costs a full point; the famous ones are in the obvious lists anyway
        z -= 1.3 * (len(words) - 1)
    return z

LISTED = set()   # names that appear in a hand-written or curated list in ANY category

def score(e):
    """Familiarity of the answer's own name, the same in every category. Nicknames don't
    count, so 'Black bear' can't lift 'Asiatic black bear' into the Shallows."""
    return phrase_score(e["d"]) + (0.3 if norm_key(e["d"]) in LISTED else -0.5)

# Fixed familiarity cut-offs (not ranks), tuned for 5-17 year olds:
#   Shallows  >= 3.6  dog, shark, penguin
#   Reef      >= 3.0  octopus, parrot, flamingo, hedgehog
#   Twilight  >= 2.4  cockatoo, seahorse, platypus, stingray
#   Midnight  >= 1.7  toucan, narwhal, axolotl, capybara
#   Abyss      < 1.7  pigfish, scombroid, okapi-level and deeper
CUTOFFS = [3.6, 3.0, 2.4, 1.7]

# Names of places and people show up a lot in adult text (news, books) but kids know far
# fewer of them, so these categories count every answer as one point less familiar.
NAME_CATS = {"countries", "capitals", "cities", "rivers_lakes", "countries_europe", "countries_africa",
             "countries_asia", "countries_americas", "us_states", "islands", "mountains", "landmarks",
             "deserts", "languages", "nationalities", "currencies", "scientists", "painters",
             "composers", "authors", "explorers", "car_brands", "gods", "greek_myth", "norse_myth",
             "egyptian_myth", "constellations", "planets_moons"}

def tier_for(s):
    for t, c in enumerate(CUTOFFS):
        if s >= c:
            return t
    return 4

def main():
    raw = json.loads((OUT / "banks_raw.json").read_text())
    for cat in raw.values():
        for e in cat["entries"]:
            if e.get("c"):
                LISTED.add(norm_key(e["d"]))
        for n in cat.get("obvious", []) + cat.get("gems", []):
            LISTED.add(norm_key(n))
    for lst in list(OBVIOUS.values()) + list(GEMS.values()):
        LISTED.update(norm_key(n) for n in lst)
    out = {}
    report = []
    for cid, cat in raw.items():
        entries = cat["entries"]
        index = {}
        for i, e in enumerate(entries):          # an answer's own name first...
            index.setdefault(norm_key(e["d"]), i)
        for i, e in enumerate(entries):          # ...then nicknames
            for n in e["a"]:
                index.setdefault(norm_key(n), i)

        def find_or_add(name):
            k = norm_key(name)
            if k in index:
                return index[k]
            entries.append({"d": name, "a": [], "z": zipf_frequency(name, "en"), "c": True})
            index[k] = len(entries) - 1
            return index[k]

        def gem_entry(name):
            """A gem must be scored as itself: if it is only a nickname of a common
            answer (Ennui -> Boredom), split it out into its own answer."""
            k = norm_key(name)
            i = find_or_add(name)
            e = entries[i]
            if norm_key(e["d"]) == k:
                return i
            e["a"] = [a for a in e["a"] if norm_key(a) != k]
            entries.append({"d": name, "a": [], "z": zipf_frequency(name, "en"), "c": True})
            index[k] = len(entries) - 1
            return index[k]

        obvious = {find_or_add(n) for n in OBVIOUS.get(cid, []) + cat.get("obvious", [])}
        gems_hand = [gem_entry(n) for n in GEMS.get(cid, []) + cat.get("gems", [])]

        for e in entries:
            e["s"] = score(e)
        tier_of = {}
        for i, e in enumerate(entries):
            t = tier_for(e["s"] - (1.0 if cid in NAME_CATS else 0.0))
            if norm_key(e["d"]) not in LISTED:
                t = max(t, 2)   # dictionary-only words ("Bot", "Orphan") are never easy answers
            tier_of[i] = t
        for i in obvious:
            tier_of[i] = 0
        gems = [i for i in dict.fromkeys(gems_hand) if i not in obvious]
        for i in gems:
            tier_of[i] = 4   # hand-picked rare answers are always Abyss
        order = sorted(range(len(entries)), key=lambda i: (tier_of[i], -entries[i]["s"]))

        rows = []
        for i in order:
            e = entries[i]
            rows.append({"d": e["d"], "a": e["a"], "t": tier_of[i]})
        out[cid] = {"name": cat["name"], "prompt": cat["prompt"], "entries": rows}
        counts = [sum(1 for r in rows if r["t"] == t) for t in range(5)]
        report.append((cid, cat["name"], len(rows), counts, [entries[i]["d"] for i in gems]))

    (OUT / "banks.json").write_text(json.dumps(out, ensure_ascii=False))
    total = sum(r[2] for r in report)
    for cid, name, n, counts, gems in report:
        print(f"{cid:16} {n:5}  {counts}  gems: {', '.join(gems)}")
    print("TOTAL", total, "answers in", len(report), "categories")

if __name__ == "__main__":
    main()
