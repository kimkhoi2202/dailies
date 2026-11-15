import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Deep End, playable.
//
// DeepEndPrompts  the 21 prompts and their answers, rarest last.
// DeepEndBank     one prompt's answers, and the forgiving lookup for what the player typed.
// DeepEndModel    the rules of a round in plain Swift: step(dt:) and press(_:).
// DeepEndPilot    the scripted player. It only runs while GameDemo.autopilot is on.
// DeepEndRunner   keeps the clock, turns touches into keys, fires haptics, reports the result.
// DeepEndGame     the view the app shows.

// MARK: - Prompts

struct DeepEndPrompt {
    let question: String
    /// Six comma separated lists, the most common answers first. "a/b" are two ways to write one answer.
    let tiers: [String]
}

enum DeepEndPrompts {
    static let all: [DeepEndPrompt] = [
        DeepEndPrompt(question: "NAME A NOODLE DISH", tiers: [
            "ramen, spaghetti, pad thai, lo mein, mac and cheese/macaroni and cheese/macaroni, lasagna/lasagne",
            "pho, udon, chow mein, fettuccine alfredo/alfredo/fettuccine, carbonara, soba, spaghetti and meatballs",
            "pad see ew, dan dan noodles/dan dan, japchae, laksa, yakisoba, pancit, singapore noodles, bolognese/spaghetti bolognese, cacio e pepe",
            "drunken noodles/pad kee mao, bun bo hue, jajangmyeon/zhajiangmian/zha jiang mian, naengmyeon, khao soi, mee goreng, char kway teow, biang biang noodles/biangbiang, hiyashi chuka",
            "bun cha, mohinga, kuy teav, cao lau, mi quang, champon, tsukemen, hokkien mee, wonton noodles/wonton mee",
            "lagman, kesme, kalguksu, khao poon, ash reshteh/reshteh, mee siam, misua, boat noodles, okinawa soba, cold noodles",
        ]),
        DeepEndPrompt(question: "NAME A BIRD", tiers: [
            "eagle, pigeon, robin, crow, chicken, duck, parrot, owl, penguin, sparrow, seagull/gull",
            "flamingo, hawk, blue jay/jay, cardinal, peacock, swan, ostrich, hummingbird, woodpecker, turkey, goose, falcon, pelican, toucan, dove",
            "heron, stork, crane, vulture, kingfisher, magpie, raven, finch, canary, emu, condor, puffin, albatross, osprey, cockatoo, starling, wren",
            "kiwi, roadrunner, cassowary, egret, ibis, lyrebird, kookaburra, nightingale, oriole, warbler, tern, cormorant, macaw, sandpiper, quail, pheasant, grouse",
            "shoebill, hoatzin, kakapo, potoo, bowerbird, hornbill, oystercatcher, frigatebird, booby/blue footed booby, avocet, spoonbill, nuthatch, waxwing, kestrel",
            "secretary bird/secretarybird, takahe, kea, bee eater, hoopoe, quetzal, motmot, jacana, oilbird, limpkin, sungrebe, lammergeier/bearded vulture, dunnock, tui",
        ]),
        DeepEndPrompt(question: "NAME A CHEESE", tiers: [
            "cheddar, mozzarella, swiss, parmesan, american",
            "brie, gouda, feta, provolone, ricotta, blue cheese/blue, cream cheese, pepper jack, colby, monterey jack",
            "camembert, gruyere, manchego, havarti, goat cheese/chevre, mascarpone, halloumi, gorgonzola, muenster, emmental/emmentaler, edam, burrata, cottage cheese, paneer",
            "roquefort, stilton, pecorino/pecorino romano, asiago, fontina, taleggio, comte, jarlsberg, queso fresco, raclette, boursin, cotija, oaxaca",
            "epoisses, reblochon, limburger, wensleydale, brunost/gjetost, red leicester, double gloucester, manouri, scamorza, caciocavallo, leerdammer, mimolette, tomme",
            "casu marzu, vacherin, morbier, beaufort, abondance, saint nectaire, livarot, pont l eveque, stinking bishop, cabrales, idiazabal, torta del casar, tete de moine, bryndza",
        ]),
        DeepEndPrompt(question: "NAME A COUNTRY IN AFRICA", tiers: [
            "egypt, south africa, nigeria, kenya, morocco",
            "ethiopia, ghana, madagascar, algeria, tanzania, uganda, somalia, sudan, libya, tunisia, zimbabwe",
            "senegal, rwanda, cameroon, angola, congo/democratic republic of the congo/drc/republic of the congo, mali, zambia, mozambique, namibia, botswana, ivory coast/cote d ivoire, niger, chad, liberia, sierra leone",
            "malawi, burkina faso, guinea, benin, togo, gabon, mauritania, eritrea, south sudan, lesotho, eswatini/swaziland, gambia/the gambia, mauritius, burundi, central african republic",
            "djibouti, equatorial guinea, guinea bissau, cape verde/cabo verde, seychelles, comoros",
            "sao tome and principe/sao tome",
        ]),
        DeepEndPrompt(question: "NAME A DOG BREED", tiers: [
            "labrador/labrador retriever/lab, golden retriever, poodle, bulldog, german shepherd, chihuahua, beagle, husky/siberian husky, pug",
            "dachshund, rottweiler, boxer, corgi, pit bull/pitbull, shih tzu, yorkie/yorkshire terrier, great dane, dalmatian, border collie, doberman, maltese, pomeranian, french bulldog/frenchie",
            "shiba inu/shiba, akita, bernese mountain dog/bernese, saint bernard/st bernard, greyhound, cocker spaniel, collie, samoyed, malamute/alaskan malamute, australian shepherd/aussie, mastiff, newfoundland, bichon frise/bichon, schnauzer, weimaraner, havanese, cavalier king charles spaniel/cavalier, jack russell/jack russell terrier",
            "basenji, vizsla, whippet, bloodhound, chow chow/chow, shar pei, papillon, basset hound, bull terrier, airedale, rhodesian ridgeback, pekingese, lhasa apso, irish setter, afghan hound, borzoi, cane corso",
            "xoloitzcuintli/xolo, komondor, puli, saluki, leonberger, kooikerhondje, lagotto romagnolo/lagotto, keeshond, schipperke, dogue de bordeaux, anatolian shepherd, tibetan mastiff",
            "azawakh, mudi, otterhound, bergamasco, norwegian lundehund/lundehund, catalburun, thai ridgeback, peruvian inca orchid, kai ken, sloughi, stabyhoun, pumi",
        ]),
        DeepEndPrompt(question: "NAME A FRUIT", tiers: [
            "apple, banana, orange, strawberry, grape, watermelon, mango, pineapple",
            "peach, pear, cherry, blueberry, lemon, kiwi, raspberry, lime, coconut, plum, avocado, cantaloupe, papaya, grapefruit, pomegranate",
            "apricot, fig, nectarine, blackberry, cranberry, dragon fruit/pitaya, passion fruit, guava, honeydew, tangerine, clementine, lychee/litchi, date, persimmon, tomato",
            "kumquat, starfruit/carambola, jackfruit, durian, quince, gooseberry, mulberry, elderberry, rambutan, plantain, pomelo, longan, loquat, yuzu",
            "mangosteen, salak/snake fruit, cherimoya, soursop/guanabana, feijoa, tamarillo, jabuticaba, sapodilla, ackee, physalis/ground cherry, medlar, kiwano/horned melon, cloudberry, lingonberry, jujube",
            "rollinia, mamey/mamey sapote, cupuacu, langsat, santol, marula, pawpaw, miracle fruit/miracle berry, bael, safou, lucuma, ugni",
        ]),
        DeepEndPrompt(question: "NAME A MUSICAL INSTRUMENT", tiers: [
            "guitar, piano, drums/drum, violin, flute, trumpet",
            "saxophone/sax, cello, clarinet, harp, bass guitar/bass, ukulele, keyboard, trombone, harmonica, tuba, xylophone, accordion, banjo, triangle, tambourine",
            "oboe, bassoon, viola, french horn/horn, piccolo, mandolin, bagpipes/bagpipe, organ, recorder, cymbals/cymbal, synthesizer/synth, double bass/upright bass, glockenspiel, marimba, bongos/bongo",
            "sitar, didgeridoo, theremin, harpsichord, lute, kazoo, cowbell, djembe, steel drum/steel pan, castanets, bugle, timpani, vibraphone, ocarina, zither, euphonium",
            "erhu, koto, shamisen, oud, tabla, bouzouki, balalaika, hurdy gurdy, dulcimer, kalimba/mbira, bodhran, sousaphone, celesta, cajon, melodica, shakuhachi",
            "guzheng, pipa, kora, duduk, nyckelharpa, sarangi, santoor, theorbo, ondes martenot, serpent, crumhorn, handpan/hang, glass harmonica, morin khuur, bandoneon",
        ]),
        DeepEndPrompt(question: "NAME A VEGETABLE", tiers: [
            "carrot, broccoli, potato, lettuce, corn, onion, cucumber, tomato",
            "spinach, celery, cabbage, peas/pea, bell pepper/pepper, cauliflower, green beans/green bean, mushroom, zucchini, asparagus, garlic, sweet potato, pumpkin, eggplant/aubergine",
            "kale, beet/beetroot, radish, brussels sprouts/brussels sprout, artichoke, squash, leek, turnip, okra, yam, arugula/rocket, bok choy/pak choi, edamame",
            "parsnip, rutabaga/swede, fennel, chard/swiss chard, endive, kohlrabi, watercress, shallot, jicama, collard greens/collards, daikon, butternut squash, scallion/green onion/spring onion, radicchio",
            "celeriac, salsify, sunchoke/jerusalem artichoke, cardoon, romanesco, taro, cassava/yuca, chayote, lotus root, bitter melon, gai lan/chinese broccoli, mizuna, sorrel, samphire",
            "oca, ulluco, skirret, mashua, scorzonera, crosne, yacon, celtuce, fiddleheads/fiddlehead, nettle, purslane, malanga, ramps/ramp",
        ]),
        DeepEndPrompt(question: "NAME A SPORT", tiers: [
            "soccer/football, basketball, baseball, tennis, golf, hockey/ice hockey, swimming, volleyball",
            "boxing, cricket, rugby, running, cycling, skiing, wrestling, bowling, surfing, skateboarding, badminton, softball, lacrosse, gymnastics",
            "table tennis/ping pong, snowboarding, karate, judo, archery, fencing, rowing, sailing, rock climbing/climbing, handball, polo, water polo, track and field/athletics, figure skating, darts",
            "curling, squash, bobsled/bobsleigh, triathlon, taekwondo, luge, biathlon, field hockey, kickboxing, pickleball, racquetball, equestrian, canoeing/kayaking, diving, pole vault",
            "hurling, sepak takraw, kabaddi, korfball, skeleton, netball, jai alai, bandy, petanque/boules, bocce, croquet, orienteering, sumo, mixed martial arts/mma, roller derby",
            "buzkashi, pesapallo, shinty, hornussen, chess boxing, underwater hockey/octopush, kin ball, footvolley, teqball, tchoukball, bossaball, fistball, camogie, sambo, pelota",
        ]),
        DeepEndPrompt(question: "NAME AN OCEAN ANIMAL", tiers: [
            "shark, whale, dolphin, fish, octopus, jellyfish/jelly, crab, starfish/sea star",
            "seal, sea turtle/turtle, squid, lobster, shrimp, stingray/ray, clownfish, sea lion, orca/killer whale, seahorse, eel, walrus, manatee",
            "manta ray/manta, swordfish, tuna, barracuda, sea urchin/urchin, coral, sea otter/otter, narwhal, beluga, pufferfish/puffer, anglerfish, hammerhead, krill, plankton, oyster, clam",
            "humpback, blue whale, sperm whale, sea cucumber, sea anemone/anemone, moray eel/moray, lionfish, cuttlefish, nautilus, dugong, marlin, mackerel, sardine, halibut, mussel, scallop",
            "blobfish, sunfish/mola/mola mola, giant squid, colossal squid, oarfish, vampire squid, gulper eel, siphonophore, nudibranch/sea slug, mantis shrimp, hagfish, coelacanth, leafy sea dragon/sea dragon, frilled shark, goblin shark",
            "dumbo octopus, barreleye, fangtooth, sea pig, viperfish, lanternfish, cookiecutter shark, pyrosome, sea butterfly, salp, hatchetfish, giant isopod/isopod, yeti crab, comb jelly/ctenophore, bristlemouth",
        ]),
        DeepEndPrompt(question: "NAME A COLOR", tiers: [
            "red, blue, green, yellow, purple, orange, pink, black, white",
            "brown, gray/grey, gold, silver, turquoise, navy, teal, maroon, beige, violet, lavender",
            "magenta, cyan, indigo, crimson, burgundy, scarlet, olive, coral, peach, tan, ivory, lime, mint, salmon, aqua",
            "chartreuse, vermilion, fuchsia, mauve, ochre, taupe, periwinkle, cerulean, amber, khaki, lilac, mustard, emerald, sapphire, charcoal",
            "puce, celadon, cobalt, viridian, sepia, umber, sienna, carmine, cinnabar, aubergine, heliotrope, marigold, ultramarine, saffron, gamboge",
            "zaffre, smaragdine, fulvous, glaucous, wenge, falu red, xanadu, coquelicot, gingerline, eburnean, mikado, razzmatazz, isabelline, caput mortuum, verdigris",
        ]),
        DeepEndPrompt(question: "NAME A BONE IN THE HUMAN BODY", tiers: [
            "skull, femur, rib, spine",
            "tibia, humerus, pelvis, jawbone/jaw, collarbone, kneecap, sternum, radius, ulna, fibula",
            "clavicle, patella, scapula/shoulder blade, mandible, vertebra/vertebrae, coccyx/tailbone, cranium, phalanges/phalanx, metatarsal",
            "sacrum, ilium, ischium, maxilla, carpal/carpals, tarsal/tarsals, metacarpal, hyoid, stapes/stirrup, malleus/hammer, incus/anvil, calcaneus/heel bone, zygomatic/cheekbone",
            "atlas, axis, sphenoid, ethmoid, temporal, occipital, parietal, frontal, scaphoid, talus, pubis, vomer, nasal bone",
            "lunate, trapezium, trapezoid, capitate, hamate, pisiform, triquetrum, cuboid, navicular, cuneiform, lacrimal, palatine, sesamoid",
        ]),
        DeepEndPrompt(question: "NAME A HERB OR SPICE", tiers: [
            "black pepper/pepper, cinnamon, basil, garlic, oregano",
            "paprika, cumin, ginger, parsley, mint, rosemary, thyme, nutmeg, chili powder/chili, vanilla, dill, cilantro/coriander",
            "turmeric, cloves/clove, cardamom, sage, bay leaf/bay, saffron, cayenne, curry powder/curry, chives, tarragon, mustard seed/mustard, allspice, fennel seed",
            "star anise/anise, sumac, zaatar/za atar, marjoram, lemongrass, fenugreek, caraway, garam masala, mace, five spice, juniper/juniper berries, sesame, poppy seed",
            "asafoetida/hing, galangal, nigella/kalonji, ajwain, grains of paradise, sichuan pepper/szechuan pepper, makrut lime/kaffir lime, epazote, lovage, berbere, ras el hanout, annatto/achiote, mahlab",
            "long pepper, cubeb, amchur/amchoor, kokum, anardana, wattleseed, sansho, grains of selim, black lime/loomi, mastic, savory/summer savory, hyssop, shiso/perilla, sassafras/file",
        ]),
        DeepEndPrompt(question: "NAME A CITY IN EUROPE", tiers: [
            "paris, london, rome, berlin, madrid, barcelona, amsterdam",
            "vienna, prague, lisbon, dublin, athens, venice, milan, munich, moscow, brussels, budapest, florence, stockholm, copenhagen",
            "edinburgh, manchester, liverpool, warsaw, oslo, helsinki, zurich, geneva, krakow, naples, seville, lyon, marseille, hamburg, istanbul, porto, frankfurt",
            "bruges, salzburg, valencia, bologna, turin, nice, bordeaux, dubrovnik, tallinn, riga, vilnius, bratislava, ljubljana, belgrade, bucharest, sofia, reykjavik, granada",
            "ghent, antwerp, rotterdam, utrecht, gothenburg, bergen, tromso, split, sarajevo, skopje, tirana, chisinau, plovdiv, lviv, gdansk, wroclaw, cluj napoca/cluj, thessaloniki, valletta",
            "tartu, kaunas, brno, olomouc, ohrid, kotor, mostar, sibiu, aarhus, odense, umea, oulu, gyor, debrecen, timisoara, novi sad, maribor, torshavn",
        ]),
        DeepEndPrompt(question: "NAME A BOARD GAME", tiers: [
            "monopoly, chess, scrabble, checkers/draughts, clue/cluedo",
            "sorry, risk, connect four, battleship, candy land, the game of life/game of life/life, trivial pursuit, operation, backgammon, mouse trap",
            "catan/settlers of catan, ticket to ride, pandemic, guess who, stratego, othello/reversi, go, mahjong, pictionary, chutes and ladders/snakes and ladders, ludo/parcheesi, cranium, codenames",
            "carcassonne, azul, splendor, wingspan, mancala, chinese checkers, diplomacy, axis and allies, small world, king of tokyo, sequence, trouble, hungry hungry hippos",
            "agricola, puerto rico, terraforming mars, power grid, twilight struggle, gloomhaven, brass, scythe, root, tigris and euphrates, el grande, hive, blokus, dixit, mysterium",
            "shogi, xiangqi, hnefatafl/tafl, senet, nine mens morris, fanorona, oware, pachisi, tak, arimaa, hex, crokinole, through the ages, mage knight, spirit island",
        ]),
        DeepEndPrompt(question: "NAME A FLOWER", tiers: [
            "rose, tulip, sunflower, daisy, lily",
            "orchid, daffodil, lavender, carnation, lilac, poppy, dandelion, violet, iris, hibiscus, marigold, peony",
            "chrysanthemum/mum, magnolia, jasmine, lotus, hydrangea, gardenia, azalea, begonia, pansy, petunia, zinnia, dahlia, lily of the valley, cherry blossom",
            "camellia, gerbera, freesia, ranunculus, anemone, foxglove, snapdragon, gladiolus, bluebell, crocus, hyacinth, aster, cosmos, lupin/lupine, wisteria, bougainvillea, morning glory, honeysuckle",
            "protea, plumeria/frangipani, edelweiss, amaryllis, delphinium/larkspur, hellebore, verbena, calla lily/calla, bird of paradise, heather, primrose, geranium, columbine, cornflower, forget me not",
            "titan arum/corpse flower, rafflesia, gazania, scabiosa, love in a mist/nigella, astilbe, bletilla, lisianthus, statice, celosia, alstroemeria, red hot poker/kniphofia, gaillardia, trillium, bloodroot",
        ]),
        DeepEndPrompt(question: "NAME A MYTHICAL CREATURE", tiers: [
            "dragon, unicorn, mermaid, vampire, werewolf, ghost, fairy",
            "phoenix, centaur, minotaur, pegasus, troll, goblin, zombie, elf, giant, bigfoot/yeti/sasquatch, griffin/gryphon, cyclops",
            "kraken, hydra, medusa/gorgon, sphinx, banshee, leprechaun, gnome, ogre, siren, chimera, loch ness monster/nessie, genie/djinn/jinn, basilisk, dwarf",
            "wendigo, kitsune, kelpie, golem, harpy, selkie, manticore, chupacabra, satyr/faun, pixie, nymph, cerberus, valkyrie, wyvern, thunderbird",
            "kappa, tengu, baku, naga, garuda, roc, qilin/kirin, bunyip, cockatrice, hippogriff, jormungandr, fenrir, sleipnir, krampus, dryad",
            "tarasque, bakeneko, nuckelavee, encantado, aswang, tikbalang, adze, ammit, simurgh, makara, nue, kushtaka, hodag, jackalope, wolpertinger, camazotz",
        ]),
        DeepEndPrompt(question: "NAME A KITCHEN TOOL", tiers: [
            "spoon, fork, knife, spatula, whisk, ladle",
            "tongs, peeler, grater, rolling pin, colander, can opener, cutting board, measuring cup, strainer, frying pan/pan, pot",
            "zester, garlic press, mortar and pestle/mortar/pestle, sieve, wok, skillet, saucepan, cleaver, corkscrew, kitchen scale/scale, thermometer, mandoline, blender, pizza cutter, timer",
            "baster, skimmer, dutch oven, ricer, pastry brush, piping bag, melon baller, egg slicer, nutcracker, salad spinner, spider, ramekin, sifter, honing steel, steamer",
            "microplane, tamis, chinois, offset spatula, bench scraper/dough scraper, mezzaluna, fish slice, spurtle, tagine, moka pot, molcajete, chitarra, pasta machine, kitchen torch/blowtorch",
            "aebleskiver pan, tortilla press, apple corer, cherry pitter, egg topper, lemon reamer/reamer, butter curler, banneton, couche, gnocchi board, pastry blender, suribachi",
        ]),
        DeepEndPrompt(question: "NAME A CAR BRAND", tiers: [
            "toyota, ford, honda, bmw, tesla, mercedes/mercedes benz, chevrolet/chevy",
            "audi, nissan, volkswagen/vw, hyundai, ferrari, lamborghini, porsche, jeep, kia, subaru, mazda, dodge, lexus",
            "volvo, jaguar, land rover/range rover, cadillac, buick, chrysler, mini, fiat, bentley, rolls royce, maserati, mitsubishi, gmc, acura, infiniti",
            "aston martin, bugatti, mclaren, alfa romeo, lincoln, peugeot, renault, citroen, skoda, seat, lotus, genesis, rivian, lucid, polestar, isuzu",
            "koenigsegg, pagani, saab, opel, vauxhall, dacia, lada, tata, mahindra, byd, geely, alpine, cupra, maybach, smart",
            "rimac, spyker, morgan, caterham, de tomaso, lancia, hispano suiza, zenvo, noble, ariel, trabant, proton, perodua, holden, scion",
        ]),
        DeepEndPrompt(question: "NAME A GREEK OR ROMAN GOD", tiers: [
            "zeus, poseidon, hades, athena, apollo, aphrodite",
            "ares, hermes, artemis, hera, jupiter, mars, venus, neptune, mercury, cupid/eros, dionysus, pluto",
            "hephaestus, demeter, persephone, minerva, juno, bacchus, diana, vulcan, saturn, cronus/kronos, gaia, nike, janus, hestia",
            "hecate, nemesis, morpheus, pan, helios, selene, eos, uranus, rhea, iris, hypnos, thanatos, vesta, ceres, aurora, fortuna",
            "tyche, nyx, erebus, hebe, asclepius, priapus, aeolus, boreas, zephyrus, triton, proteus, nereus, themis, mnemosyne, hyperion, oceanus",
            "hymenaeus, harpocrates, terminus, quirinus, pomona, faunus, bellona, robigo, eileithyia, phanes, chaos, aether, hemera, pontus, tartarus, ourea",
        ]),
        DeepEndPrompt(question: "NAME SOMETHING AT THE BEACH", tiers: [
            "sand, seashell/shell/shells, water, waves/wave, sun, towel, umbrella",
            "crab, seaweed, sunscreen, rocks/rock, bucket, shovel/spade, surfboard, seagull, lifeguard, sandcastle, starfish, boat, flip flops",
            "jellyfish, driftwood, pier, dunes/dune, tide pool, beach ball, cooler, sunglasses, kite, volleyball net, lighthouse, kelp, pebbles",
            "sea glass, sandpiper, sand dollar, hermit crab, boardwalk, jetty, buoy, snorkel, lifebuoy, bodyboard/boogie board, wetsuit, windbreak, deck chair",
            "barnacle, mermaids purse/egg case, cuttlebone, sea foam, groyne, breakwater, wrack line/tidemark, sand flea, ghost crab, beach hut, metal detector",
            "sea bean, fulgurite, nurdle, sea potato, razor clam, whelk egg case, lugworm, sea pottery, ambergris, mermaid tears, velella/by the wind sailor, sea pen",
        ]),
    ]
}

// MARK: - Answers

struct DeepEndAnswer {
    let tier: Int
    let name: String
}

final class DeepEndBank {
    let list: [DeepEndAnswer]
    private let map: [String: Int]
    private let keys: [[UInt8]]

    private static var kept: [Int: DeepEndBank] = [:]

    /// Each prompt's bank is built the first time it is asked for, then kept.
    static func bank(_ index: Int) -> DeepEndBank {
        if let bank = kept[index] { return bank }
        let bank = DeepEndBank(DeepEndPrompts.all[index])
        kept[index] = bank
        return bank
    }

    init(_ prompt: DeepEndPrompt) {
        var list: [DeepEndAnswer] = []
        var map: [String: Int] = [:]
        var order: [String] = []
        for (t, line) in prompt.tiers.enumerated() {
            for entry in line.split(separator: ",") {
                let names = entry.split(separator: "/", omittingEmptySubsequences: false)
                guard let first = names.first else { continue }
                let display = first.trimmingCharacters(in: .whitespaces).uppercased()
                if display.isEmpty { continue }
                list.append(DeepEndAnswer(tier: t + 1, name: display))
                for name in names {
                    let key = Self.norm(String(name))
                    if !key.isEmpty, map[key] == nil {
                        map[key] = list.count - 1
                        order.append(key)
                    }
                }
            }
        }
        self.list = list
        self.map = map
        keys = order.map { Array($0.utf8) }
    }

    /// Lower case, no accents, "&" as "and", no leading "the", letters and digits only.
    static func norm(_ raw: String) -> String {
        var s = raw.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        s = s.replacingOccurrences(of: "&", with: " and ")
        var rest = Substring(s).drop(while: { $0.isWhitespace })
        if rest.hasPrefix("the") {
            let after = rest.dropFirst(3)
            if let next = after.first, next.isWhitespace { rest = after.drop(while: { $0.isWhitespace }) }
        }
        var out = ""
        for scalar in rest.unicodeScalars where (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
            out.unicodeScalars.append(scalar)
        }
        return out
    }

    /// The answer the player meant: an exact match, a plural either way, or one or two letters off
    /// for a longer word, as long as only one answer is that close.
    func lookup(_ raw: String) -> DeepEndAnswer? {
        let k = Self.norm(raw)
        if k.isEmpty { return nil }
        if let i = map[k] { return list[i] }
        if k.count > 3, k.hasSuffix("s"), let i = map[String(k.dropLast())] { return list[i] }
        if k.count > 2, let i = map[k + "s"] { return list[i] }
        let typed = Array(k.utf8)
        if typed.count < 5 { return nil }
        let most = typed.count >= 9 ? 2 : 1
        var best: [UInt8]?
        var bestDistance = most + 1
        var tie = false
        for key in keys {
            if key.count < 5 || key[0] != typed[0] || abs(key.count - typed.count) > most { continue }
            let d = Self.distance(typed, key, most)
            if d < bestDistance {
                bestDistance = d
                best = key
                tie = false
            } else if d == bestDistance, let best, map[String(decoding: key, as: UTF8.self)] != map[String(decoding: best, as: UTF8.self)] {
                tie = true
            }
        }
        guard let best, !tie, let i = map[String(decoding: best, as: UTF8.self)] else { return nil }
        return list[i]
    }

    /// Edit distance, giving up once every path is past most.
    private static func distance(_ a: [UInt8], _ b: [UInt8], _ most: Int) -> Int {
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = i
            for j in 1...b.count {
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                rowMin = Swift.min(rowMin, cur[j])
            }
            if rowMin > most { return most + 1 }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}

// MARK: - Model

final class DeepEndModel {
    enum Stage { case ready, playing, ending, finished }

    /// Moments the runner answers with a haptic.
    enum Feedback {
        case key, rejected, answered(Int), timeout, tick, start, done
    }

    /// How a friend does on each prompt, by tier. Their day is worked out from the seed.
    static let friendWeights = [0.1, 0.2, 0.25, 0.2, 0.15, 0.1]

    let prompts: [Int]
    let markers: [DeepEndMarker]
    private(set) var pic = DeepEndPicture()
    private(set) var stage = Stage.ready
    /// Seconds since the round started.
    private(set) var time = 0.0
    private(set) var feedback: [Feedback] = []

    private var layout = DeepEndLayout(size: CGSize(width: 402, height: 874))
    private var scenery: DeepEndRandom
    private var lastCam = 0.0
    private var bubbleClock = 0.0
    private var rarest: DeepEndAnswer?

    init(options: GameOptions) {
        var rng = DeepEndRandom(seed: options.seed, salt: 0x2545F4914F6CDD1D)
        var order = Array(DeepEndPrompts.all.indices)
        var last = order.count - 1
        while last > 0 {
            order.swapAt(last, rng.int(last + 1))
            last -= 1
        }
        prompts = Array(order.prefix(DeepEndRules.round))

        var markers: [DeepEndMarker] = []
        if !options.solo {
            for name in options.friendNames.filter({ !$0.isEmpty }).prefix(3) {
                var points = 0
                for _ in 0..<DeepEndRules.round {
                    if rng.next() < 0.06 { continue }
                    var roll = rng.next(), tier = 0
                    while tier < Self.friendWeights.count - 1, roll > Self.friendWeights[tier] {
                        roll -= Self.friendWeights[tier]
                        tier += 1
                    }
                    points += DeepEndRules.points[tier]
                }
                let depth = points * 10
                let label = String(name.uppercased().prefix(12)) + " " + DeepEndRules.grouped(depth) + "M"
                markers.append(DeepEndMarker(name: label, depth: Double(depth)))
            }
        }
        self.markers = markers

        scenery = DeepEndRandom(seed: options.seed, salt: 0xD1B54A32D192ED03)
        feedback.reserveCapacity(8)
        pic.best = Swift.max(0, options.bestScore)
        pic.friends = markers
        pic.question = DeepEndPrompts.all[prompts[0]].question
        pic.showHint = !GameDemo.autopilot
        pic.results.reserveCapacity(DeepEndRules.round)
        pic.bubbles.reserveCapacity(40)
        seedScene()
    }

    var bank: DeepEndBank { DeepEndBank.bank(prompts[Swift.min(pic.promptIndex, prompts.count - 1)]) }

    var accepting: Bool { stage == .playing && (pic.step == .intro || pic.step == .answer) }

    var keyboardUp: Bool { pic.keyboard >= 0.9 }

    func key(at point: CGPoint) -> Int? { layout.key(at: point) }

    var result: GameResult {
        let metres = pic.points * 10
        var line = DeepEndRules.headline(metres)
        if let rarest { line += ". Rarest answer: " + rarest.name.lowercased() }
        guard !markers.isEmpty else { return GameResult(score: metres, unit: "m", detail: line) }
        let deeper = markers.filter { $0.depth > Double(metres) }.count
        return GameResult(score: metres, unit: "m", detail: line, placement: 1 + deeper, playerCount: markers.count + 1)
    }

    func clearFeedback() { feedback.removeAll(keepingCapacity: true) }

    /// The screen changed size: lay it out again and scatter the scenery over it.
    func resize(to size: CGSize) {
        guard size.width > 8, size.height > 8, size.width != layout.w || size.height != layout.h else { return }
        layout = DeepEndLayout(size: size)
        seedScene()
    }

    private func seedScene() {
        let W = Double(layout.w), H = Double(layout.h)
        let span = Swift.max(300, H - Double(layout.baseY) + 200)
        pic.fish.removeAll(keepingCapacity: true)
        for _ in 0..<9 {
            let dir = scenery.next() < 0.5 ? -1.0 : 1.0
            pic.fish.append(DeepEndFish(x: scenery.next() * W, depth: pic.cam + 25 + scenery.next() * span,
                                        vx: dir * scenery.range(14, 40)))
        }
        pic.motes.removeAll(keepingCapacity: true)
        for _ in 0..<36 {
            pic.motes.append(DeepEndMote(x: scenery.next() * W, y: scenery.next() * H, size: scenery.next() < 0.3 ? 2 : 1))
        }
        pic.clouds = [DeepEndCloud(x: W * 0.04, y: 52, s: 0.9), DeepEndCloud(x: W * 0.6, y: 40, s: 0.7),
                      DeepEndCloud(x: W * 0.3, y: 30, s: 0.6)]
    }

    // MARK: Round

    func start() {
        guard stage == .ready else { return }
        stage = .playing
        pic.started = true
        pic.showHint = false
        pic.step = .intro
        pic.stepTime = 0
        feedback.append(.start)
    }

    /// A key from the keyboard. Returns false when it did nothing.
    @discardableResult
    func press(_ code: Int) -> Bool {
        guard stage == .playing else { return false }
        pic.pressKey = code
        pic.pressTime = 0.12
        if code == DeepEndRules.dive { return submit() }
        feedback.append(.key)
        guard accepting else { return false }
        var input = pic.input
        if code == DeepEndRules.back {
            if input.isEmpty { return false }
            input.removeLast()
        } else if code == DeepEndRules.space {
            guard let lastChar = input.last, lastChar != " ", input.count < DeepEndRules.maxLength else { return false }
            input.append(" ")
        } else if code >= 0, code < DeepEndRules.keyLetters.count, input.count < DeepEndRules.maxLength {
            input.append(DeepEndRules.keyLetters[code])
        } else {
            return false
        }
        pic.input = input
        return true
    }

    private func submit() -> Bool {
        guard accepting else { return false }
        if let answer = bank.lookup(pic.input) {
            finishAnswer(answer)
            return true
        }
        pic.message = pic.input.trimmingCharacters(in: .whitespaces).isEmpty ? "TYPE ONE ANSWER" : "NOT ON THE LIST"
        pic.messageColor = DeepEndInk.pink
        pic.messageTime = 1.4
        pic.shake = 0.35
        feedback.append(.rejected)
        return false
    }

    private func finishAnswer(_ answer: DeepEndAnswer?) {
        let points = answer.map { DeepEndRules.points[$0.tier - 1] } ?? 0
        pic.points += points
        pic.results.append(answer?.tier ?? 0)
        pic.reveal = answer.map { DeepEndReveal(name: $0.name, tier: $0.tier, points: points) }
            ?? DeepEndReveal(name: "TIME", tier: 0, points: 0)
        pic.step = .reveal
        pic.stepTime = 0
        pic.messageTime = 0
        if let answer {
            if answer.tier > (rarest?.tier ?? 0) { rarest = answer }
            feedback.append(.answered(answer.tier))
        } else {
            feedback.append(.timeout)
        }
    }

    private func nextPrompt() {
        pic.promptIndex += 1
        pic.reveal = nil
        if pic.promptIndex >= DeepEndRules.round {
            stage = .ending
            pic.ending = true
            pic.step = .done
            pic.endTime = 0
            pic.headline = DeepEndRules.headline(pic.points * 10).uppercased()
            feedback.append(.done)
            return
        }
        pic.question = DeepEndPrompts.all[prompts[pic.promptIndex]].question
        pic.step = .intro
        pic.stepTime = 0
        pic.timeLeft = DeepEndRules.answerTime
        pic.input = ""
    }

    func step(dt: Double) {
        pic.clock += dt
        if pic.pressTime > 0 { pic.pressTime -= dt }
        if pic.messageTime > 0 { pic.messageTime -= dt }
        if pic.shake > 0 { pic.shake = Swift.max(0, pic.shake - dt) }

        switch stage {
        case .playing:
            time += dt
            pic.titleAlpha = Swift.max(0, pic.titleAlpha - dt * 3)
            pic.keyboard = Swift.min(1, pic.keyboard + dt * 3.5)
            pic.stepTime += dt
            switch pic.step {
            case .intro:
                if pic.stepTime >= DeepEndRules.introTime {
                    pic.step = .answer
                    pic.stepTime = 0
                }
            case .answer:
                let before = pic.timeLeft.rounded(.up)
                pic.timeLeft -= dt
                if pic.timeLeft > 0, pic.timeLeft <= 5, pic.timeLeft.rounded(.up) != before { feedback.append(.tick) }
                if pic.timeLeft <= 0 {
                    pic.timeLeft = 0
                    finishAnswer(nil)
                }
            case .reveal:
                if pic.stepTime >= DeepEndRules.revealTime { nextPrompt() }
            case .done:
                break
            }
        case .ending:
            pic.keyboard = Swift.max(0, pic.keyboard - dt * 2.5)
            pic.endTime += dt
            if pic.endTime >= DeepEndRules.endTime { stage = .finished }
        case .ready, .finished:
            break
        }
        moveScenery(dt)
    }

    private func moveScenery(_ dt: Double) {
        let target = Double(pic.points * 10)
        pic.shown += (target - pic.shown) * Swift.min(1, dt * 2.2)
        if abs(target - pic.shown) < 1 { pic.shown = target }
        let goal = stage == .ready ? 14 : Swift.max(40, target)
        let before = pic.krill
        pic.krill += (goal - pic.krill) * Swift.min(1, dt * 2.2)
        pic.cam = Swift.max(0, pic.krill - Double(layout.anchorY - layout.baseY))
        let moved = pic.cam - lastCam
        lastCam = pic.cam

        let W = Double(layout.w), H = Double(layout.h), baseY = Double(layout.baseY)
        for i in pic.fish.indices {
            pic.fish[i].x += pic.fish[i].vx * dt
            if pic.fish[i].vx > 0, pic.fish[i].x > W + 30 { pic.fish[i].x = -30 }
            if pic.fish[i].vx < 0, pic.fish[i].x < -30 { pic.fish[i].x = W + 30 }
            if baseY + pic.fish[i].depth - pic.cam < -40 {
                pic.fish[i].depth = pic.cam + H - baseY + 20 + scenery.next() * 300
                pic.fish[i].x = scenery.next() * W
            }
        }
        for i in pic.motes.indices {
            pic.motes[i].y += 5 * dt - moved * 0.5
            if pic.motes[i].y < 0 {
                pic.motes[i].y += H
                pic.motes[i].x = scenery.next() * W
            }
            if pic.motes[i].y > H { pic.motes[i].y -= H }
        }
        for i in pic.clouds.indices {
            pic.clouds[i].x += 4 * pic.clouds[i].s * dt
            if pic.clouds[i].x > W + 20 { pic.clouds[i].x = -80 }
        }

        // Bubbles trail the krill, a stream of them while it sinks.
        bubbleClock -= dt
        let sinking = pic.krill - before > dt * 30
        if bubbleClock <= 0, pic.bubbles.count < 40, stage != .ready {
            bubbleClock = sinking ? 0.05 : 0.5
            let x = W / 2 + sin(pic.clock * 1.3) * 14 - 16 + scenery.next() * 10
            pic.bubbles.append(DeepEndBubble(x: x, y: baseY + pic.krill - pic.cam - 6, r: scenery.range(1.5, 4), life: 1.6))
        }
        var i = pic.bubbles.count - 1
        while i >= 0 {
            pic.bubbles[i].y -= 40 * dt + moved
            pic.bubbles[i].x += sin(pic.clock * 4 + Double(i)) * 0.3
            pic.bubbles[i].life -= dt
            if pic.bubbles[i].life <= 0 || pic.bubbles[i].y < -10 { pic.bubbles.remove(at: i) }
            i -= 1
        }
    }
}

// MARK: - Scripted player

/// Plays a round for recordings while GameDemo.autopilot is on. It reads each prompt for a moment,
/// picks a real answer from the list, mostly a good one, and types it on the game's own keys at a
/// person's pace, now and then hitting the key next door and taking it back. Once
/// GameDemo.loseAfter has passed it stops trying: one answer that is not on the list, then the
/// most common answers, so the krill stays shallow and the round ends soon.
final class DeepEndPilot {
    static let readyHold = 0.9
    private static let weights = [0.04, 0.12, 0.24, 0.27, 0.19, 0.14]
    private static let offList = ["PIZZA", "CASTLE", "BLANKET", "PENCIL", "TRUMPET", "RAINBOW"]
    /// Real answers that are words the app keeps off its screens, so a recording never shows them.
    private static let unsaid: Set<String> = ["MINT"]

    private var rng: DeepEndRandom
    private var planFor = -1
    private var plan: [Character] = []
    private var fallback: [Character] = []
    private var nextAt = 0.0
    private var slipAt = -1
    private var losing = false
    private var missed = false

    init(seed: UInt64) {
        rng = DeepEndRandom(seed: seed, salt: 0x50494C4F54)
    }

    /// Call once per step, after the model has moved. Presses one key at most.
    func play(_ runner: DeepEndRunner, link: GameLink) {
        let model = runner.model
        let now = model.pic.clock
        if model.stage == .ready {
            if now >= Self.readyHold { runner.start(link: link) }
            return
        }
        guard model.accepting else { return }
        if !losing, let limit = GameDemo.loseAfter, model.time >= limit { losing = true }

        let index = model.pic.promptIndex
        if planFor != index {
            planFor = index
            choose(model.bank)
            nextAt = now + (losing ? rng.range(0.5, 0.8) : rng.range(1.0, 1.7))
            return
        }
        if now < nextAt { return }

        let typed = Array(model.pic.input)
        if typed.count > plan.count || typed != Array(plan.prefix(typed.count)) {
            runner.press(DeepEndRules.back, link: link)
            nextAt = now + rng.range(0.10, 0.16)
            return
        }
        if typed.count == plan.count {
            runner.press(DeepEndRules.dive, link: link)
            if model.accepting, model.pic.promptIndex == index {
                plan = fallback
                nextAt = now + rng.range(0.7, 1.0)
            }
            return
        }
        let next = plan[typed.count]
        if typed.count == slipAt, let wrong = neighbour(of: next), let code = DeepEndRules.code(for: wrong) {
            slipAt = -1
            runner.press(code, link: link)
            nextAt = now + rng.range(0.35, 0.5)
            return
        }
        guard let code = DeepEndRules.code(for: next) else { return }
        runner.press(code, link: link)
        nextAt = now + (next == " " ? rng.range(0.14, 0.22) : rng.range(0.07, 0.14))
    }

    private func choose(_ bank: DeepEndBank) {
        slipAt = -1
        let common = pick(bank, tier: 1)
        if losing {
            if !missed, let wrong = Self.offList.first(where: { bank.lookup($0) == nil }) {
                missed = true
                plan = Array(wrong)
                fallback = common
            } else {
                plan = common
                fallback = common
            }
            return
        }
        var roll = rng.next(), tier = 1
        while tier < Self.weights.count, roll > Self.weights[tier - 1] {
            roll -= Self.weights[tier - 1]
            tier += 1
        }
        plan = pick(bank, tier: tier)
        fallback = common
        if plan.count >= 5, rng.next() < 0.35 {
            let at = 1 + rng.int(plan.count - 2)
            if plan[at] != " " { slipAt = at }
        }
    }

    /// A random answer of the tier, as the keys can type it.
    private func pick(_ bank: DeepEndBank, tier: Int) -> [Character] {
        let sayable = bank.list.filter { !Self.unsaid.contains($0.name) }
        let pool = sayable.filter { $0.tier == tier }
        let from = pool.isEmpty ? sayable : pool
        guard !from.isEmpty else { return [] }
        var out: [Character] = []
        for ch in from[rng.int(from.count)].name {
            if ch == " " {
                if let lastChar = out.last, lastChar != " " { out.append(" ") }
            } else if DeepEndRules.code(for: ch) != nil {
                out.append(ch)
            }
        }
        while out.last == " " { out.removeLast() }
        return Array(out.prefix(DeepEndRules.maxLength))
    }

    private func neighbour(of letter: Character) -> Character? {
        for row in DeepEndRules.keyRows {
            let keys = Array(row)
            guard let k = keys.firstIndex(of: letter) else { continue }
            var beside: [Character] = []
            if k > 0 { beside.append(keys[k - 1]) }
            if k + 1 < keys.count { beside.append(keys[k + 1]) }
            return beside.isEmpty ? nil : beside[rng.int(beside.count)]
        }
        return nil
    }
}

// MARK: - Runner

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class DeepEndRunner: ObservableObject {
    let model: DeepEndModel
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false
    /// Made the first time it is needed, which is only when GameDemo.autopilot is on.
    private var pilot: DeepEndPilot?

    init(options: GameOptions) {
        model = DeepEndModel(options: options)
        seed = options.seed
    }

    /// Brings the model up to the given date. Returns a number that changes when there is a new frame to paint.
    func advance(to date: Date, size: CGSize, link: GameLink) -> Int {
        model.resize(to: size)
        if link.paused {
            lastDate = nil
            return frame
        }
        defer { lastDate = date }
        guard let before = lastDate else { return frame }
        var owed = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if owed <= 0 { return frame }
        while owed > 1e-6 {
            let dt = Swift.min(owed, 1.0 / 60)
            owed -= dt
            model.step(dt: dt)
            settle(link)
            if GameDemo.autopilot {
                if pilot == nil { pilot = DeepEndPilot(seed: seed) }
                pilot?.play(self, link: link)
            }
        }
        frame &+= 1
        return frame
    }

    func start(link: GameLink) {
        if link.paused || link.isFinished { return }
        model.start()
        settle(link)
    }

    func press(_ code: Int, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.press(code)
        settle(link)
    }

    /// A finger landed. The first one starts the round; after that only keys count.
    func touch(at point: CGPoint, size: CGSize, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.resize(to: size)
        if model.stage == .ready {
            start(link: link)
            return
        }
        guard model.keyboardUp, let code = model.key(at: point) else { return }
        press(code, link: link)
    }

    /// Plays the haptics the model owes and reports the round once it is over.
    private func settle(_ link: GameLink) {
        for event in model.feedback {
            switch event {
            case .key, .tick: GameHaptics.tap()
            case .rejected, .start: GameHaptics.thud()
            case .answered(let tier):
                if tier >= 5 { GameHaptics.success() } else if tier >= 3 { GameHaptics.thud() } else { GameHaptics.tap() }
            case .timeout: GameHaptics.heavy()
            case .done: GameHaptics.success()
            }
        }
        model.clearFeedback()
        if model.stage == .finished, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

// MARK: - Views

/// Paints the model as it is right now.
struct DeepEndCanvas: View {
    let model: DeepEndModel
    /// Changes every frame. The model is a class, so without it SwiftUI would skip the repaint.
    let frame: Int

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            guard size.width > 8, size.height > 8, frame >= 0 else { return }
            DeepEndPainter(size: size, picture: model.pic, showHUD: true).draw(&context)
        }
    }
}

#if canImport(UIKit) && !os(macOS)
/// Reports every finger the moment it lands, so two thumbs can type as fast as they like.
private struct DeepEndTouchPad: UIViewRepresentable {
    var onTouch: (CGPoint, CGSize) -> Void

    func makeUIView(context: Context) -> DeepEndTouchView {
        let view = DeepEndTouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.onTouch = onTouch
        return view
    }

    func updateUIView(_ view: DeepEndTouchView, context: Context) {
        view.onTouch = onTouch
    }
}

final class DeepEndTouchView: UIView {
    var onTouch: ((CGPoint, CGSize) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { onTouch?(touch.location(in: self), bounds.size) }
    }
}
#else
private struct DeepEndTouchPad: View {
    var onTouch: (CGPoint, CGSize) -> Void
    @State private var isDown = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isDown { return }
                        isDown = true
                        onTouch(value.startLocation, geo.size)
                    }
                    .onEnded { _ in isDown = false })
        }
    }
}
#endif

public struct DeepEndGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        DeepEndRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct DeepEndRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: DeepEndRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: DeepEndRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                    DeepEndCanvas(model: runner.model, frame: runner.advance(to: timeline.date, size: geo.size, link: link))
                }
                DeepEndTouchPad { point, size in
                    runner.touch(at: point, size: size, link: link)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("Deep End. Type one answer to each prompt. Rarer answers sink deeper.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
