/* Deep End. Seven prompts, one answer each. Rarer answers sink the krill deeper. */
(function () {
  var D = window.Dailies;

  var ROUND = 7;
  var TIME = 25;
  var INTRO = 0.9;
  var REVEAL = 1.8;
  var MAXLEN = 30;
  var PPM = 1;
  var BAND = 6;

  var TIERS = ['SURFACE', 'SUNLIT', 'TWILIGHT', 'MIDNIGHT', 'ABYSS', 'TRENCH'];
  var POINTS = [10, 25, 45, 65, 85, 100];
  var TIER_COLORS = ['#BFE9FF', '#7FD4F5', '#41D6F2', '#9C8CFF', '#FF5C8A', '#FFC531'];
  var BOT_WEIGHTS = [0.1, 0.2, 0.25, 0.2, 0.15, 0.1];

  var CYAN = '#41D6F2';
  var PINK = '#FF5C8A';
  var WHITE = '#F2F7FB';
  var DIM = '#7891AD';
  var KEY = '#1B2C47';
  var KEY_EDGE = '#0A1424';
  var KEY_TEXT = '#CFE6F5';

  var GLYPHS = {
    A: '.###. #...# #...# ##### #...# #...# #...#',
    B: '####. #...# #...# ####. #...# #...# ####.',
    C: '.###. #...# #.... #.... #.... #...# .###.',
    D: '####. #...# #...# #...# #...# #...# ####.',
    E: '##### #.... #.... ####. #.... #.... #####',
    F: '##### #.... #.... ####. #.... #.... #....',
    G: '.###. #...# #.... #.### #...# #...# .####',
    H: '#...# #...# #...# ##### #...# #...# #...#',
    I: '.###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.',
    J: '..### ...#. ...#. ...#. ...#. #..#. .##..',
    K: '#...# #..#. #.#.. ##... #.#.. #..#. #...#',
    L: '#.... #.... #.... #.... #.... #.... #####',
    M: '#...# ##.## #.#.# #.#.# #...# #...# #...#',
    N: '#...# #...# ##..# #.#.# #..## #...# #...#',
    O: '.###. #...# #...# #...# #...# #...# .###.',
    P: '####. #...# #...# ####. #.... #.... #....',
    Q: '.###. #...# #...# #...# #.#.# #..#. .##.#',
    R: '####. #...# #...# ####. #.#.. #..#. #...#',
    S: '.#### #.... #.... .###. ....# ....# ####.',
    T: '##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..',
    U: '#...# #...# #...# #...# #...# #...# .###.',
    V: '#...# #...# #...# #...# #...# .#.#. ..#..',
    W: '#...# #...# #...# #.#.# #.#.# #.#.# .#.#.',
    X: '#...# #...# .#.#. ..#.. .#.#. #...# #...#',
    Y: '#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..',
    Z: '##### ....# ...#. ..#.. .#... #.... #####',
    0: '.###. #...# #..## #.#.# ##..# #...# .###.',
    1: '..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.',
    2: '.###. #...# ....# ...#. ..#.. .#... #####',
    3: '####. ....# ....# .###. ....# ....# ####.',
    4: '...#. ..##. .#.#. #..#. ##### ...#. ...#.',
    5: '##### #.... ####. ....# ....# #...# .###.',
    6: '.###. #.... #.... ####. #...# #...# .###.',
    7: '##### ....# ...#. ..#.. .#... .#... .#...',
    8: '.###. #...# #...# .###. #...# #...# .###.',
    9: '.###. #...# #...# .#### ....# ....# .###.',
    '.': '..... ..... ..... ..... ..... ..... ..#..',
    ',': '..... ..... ..... ..... ..... ..#.. .#...',
    '-': '..... ..... ..... .###. ..... ..... .....',
    '+': '..... ..#.. ..#.. ##### ..#.. ..#.. .....',
    ':': '..... ..#.. ..... ..... ..... ..#.. .....',
    '?': '.###. #...# ....# ...#. ..#.. ..... ..#..',
    '<': '..... ..#.. .#... ##### .#... ..#.. .....',
    'v': '##### ##### .###. .###. ..#.. ..#.. .....'
  };
  var GLYPH = {};
  for (var gk in GLYPHS) GLYPH[gk] = GLYPHS[gk].replace(/ /g, '');

  var PROMPTS = [
    { q: 'NAME A NOODLE DISH', t: [
      'ramen, spaghetti, pad thai, lo mein, mac and cheese/macaroni and cheese/macaroni, lasagna/lasagne',
      'pho, udon, chow mein, fettuccine alfredo/alfredo/fettuccine, carbonara, soba, spaghetti and meatballs',
      'pad see ew, dan dan noodles/dan dan, japchae, laksa, yakisoba, pancit, singapore noodles, bolognese/spaghetti bolognese, cacio e pepe',
      'drunken noodles/pad kee mao, bun bo hue, jajangmyeon/zhajiangmian/zha jiang mian, naengmyeon, khao soi, mee goreng, char kway teow, biang biang noodles/biangbiang, hiyashi chuka',
      'bun cha, mohinga, kuy teav, cao lau, mi quang, champon, tsukemen, hokkien mee, wonton noodles/wonton mee',
      'lagman, kesme, kalguksu, khao poon, ash reshteh/reshteh, mee siam, misua, boat noodles, okinawa soba, cold noodles'
    ] },
    { q: 'NAME A BIRD', t: [
      'eagle, pigeon, robin, crow, chicken, duck, parrot, owl, penguin, sparrow, seagull/gull',
      'flamingo, hawk, blue jay/jay, cardinal, peacock, swan, ostrich, hummingbird, woodpecker, turkey, goose, falcon, pelican, toucan, dove',
      'heron, stork, crane, vulture, kingfisher, magpie, raven, finch, canary, emu, condor, puffin, albatross, osprey, cockatoo, starling, wren',
      'kiwi, roadrunner, cassowary, egret, ibis, lyrebird, kookaburra, nightingale, oriole, warbler, tern, cormorant, macaw, sandpiper, quail, pheasant, grouse',
      'shoebill, hoatzin, kakapo, potoo, bowerbird, hornbill, oystercatcher, frigatebird, booby/blue footed booby, avocet, spoonbill, nuthatch, waxwing, kestrel',
      'secretary bird/secretarybird, takahe, kea, bee eater, hoopoe, quetzal, motmot, jacana, oilbird, limpkin, sungrebe, lammergeier/bearded vulture, dunnock, tui'
    ] },
    { q: 'NAME A CHEESE', t: [
      'cheddar, mozzarella, swiss, parmesan, american',
      'brie, gouda, feta, provolone, ricotta, blue cheese/blue, cream cheese, pepper jack, colby, monterey jack',
      'camembert, gruyere, manchego, havarti, goat cheese/chevre, mascarpone, halloumi, gorgonzola, muenster, emmental/emmentaler, edam, burrata, cottage cheese, paneer',
      'roquefort, stilton, pecorino/pecorino romano, asiago, fontina, taleggio, comte, jarlsberg, queso fresco, raclette, boursin, cotija, oaxaca',
      'epoisses, reblochon, limburger, wensleydale, brunost/gjetost, red leicester, double gloucester, manouri, scamorza, caciocavallo, leerdammer, mimolette, tomme',
      'casu marzu, vacherin, morbier, beaufort, abondance, saint nectaire, livarot, pont l eveque, stinking bishop, cabrales, idiazabal, torta del casar, tete de moine, bryndza'
    ] },
    { q: 'NAME A COUNTRY IN AFRICA', t: [
      'egypt, south africa, nigeria, kenya, morocco',
      'ethiopia, ghana, madagascar, algeria, tanzania, uganda, somalia, sudan, libya, tunisia, zimbabwe',
      'senegal, rwanda, cameroon, angola, congo/democratic republic of the congo/drc/republic of the congo, mali, zambia, mozambique, namibia, botswana, ivory coast/cote d ivoire, niger, chad, liberia, sierra leone',
      'malawi, burkina faso, guinea, benin, togo, gabon, mauritania, eritrea, south sudan, lesotho, eswatini/swaziland, gambia/the gambia, mauritius, burundi, central african republic',
      'djibouti, equatorial guinea, guinea bissau, cape verde/cabo verde, seychelles, comoros',
      'sao tome and principe/sao tome'
    ] },
    { q: 'NAME A DOG BREED', t: [
      'labrador/labrador retriever/lab, golden retriever, poodle, bulldog, german shepherd, chihuahua, beagle, husky/siberian husky, pug',
      'dachshund, rottweiler, boxer, corgi, pit bull/pitbull, shih tzu, yorkie/yorkshire terrier, great dane, dalmatian, border collie, doberman, maltese, pomeranian, french bulldog/frenchie',
      'shiba inu/shiba, akita, bernese mountain dog/bernese, saint bernard/st bernard, greyhound, cocker spaniel, collie, samoyed, malamute/alaskan malamute, australian shepherd/aussie, mastiff, newfoundland, bichon frise/bichon, schnauzer, weimaraner, havanese, cavalier king charles spaniel/cavalier, jack russell/jack russell terrier',
      'basenji, vizsla, whippet, bloodhound, chow chow/chow, shar pei, papillon, basset hound, bull terrier, airedale, rhodesian ridgeback, pekingese, lhasa apso, irish setter, afghan hound, borzoi, cane corso',
      'xoloitzcuintli/xolo, komondor, puli, saluki, leonberger, kooikerhondje, lagotto romagnolo/lagotto, keeshond, schipperke, dogue de bordeaux, anatolian shepherd, tibetan mastiff',
      'azawakh, mudi, otterhound, bergamasco, norwegian lundehund/lundehund, catalburun, thai ridgeback, peruvian inca orchid, kai ken, sloughi, stabyhoun, pumi'
    ] },
    { q: 'NAME A FRUIT', t: [
      'apple, banana, orange, strawberry, grape, watermelon, mango, pineapple',
      'peach, pear, cherry, blueberry, lemon, kiwi, raspberry, lime, coconut, plum, avocado, cantaloupe, papaya, grapefruit, pomegranate',
      'apricot, fig, nectarine, blackberry, cranberry, dragon fruit/pitaya, passion fruit, guava, honeydew, tangerine, clementine, lychee/litchi, date, persimmon, tomato',
      'kumquat, starfruit/carambola, jackfruit, durian, quince, gooseberry, mulberry, elderberry, rambutan, plantain, pomelo, longan, loquat, yuzu',
      'mangosteen, salak/snake fruit, cherimoya, soursop/guanabana, feijoa, tamarillo, jabuticaba, sapodilla, ackee, physalis/ground cherry, medlar, kiwano/horned melon, cloudberry, lingonberry, jujube',
      'rollinia, mamey/mamey sapote, cupuacu, langsat, santol, marula, pawpaw, miracle fruit/miracle berry, bael, safou, lucuma, ugni'
    ] },
    { q: 'NAME A MUSICAL INSTRUMENT', t: [
      'guitar, piano, drums/drum, violin, flute, trumpet',
      'saxophone/sax, cello, clarinet, harp, bass guitar/bass, ukulele, keyboard, trombone, harmonica, tuba, xylophone, accordion, banjo, triangle, tambourine',
      'oboe, bassoon, viola, french horn/horn, piccolo, mandolin, bagpipes/bagpipe, organ, recorder, cymbals/cymbal, synthesizer/synth, double bass/upright bass, glockenspiel, marimba, bongos/bongo',
      'sitar, didgeridoo, theremin, harpsichord, lute, kazoo, cowbell, djembe, steel drum/steel pan, castanets, bugle, timpani, vibraphone, ocarina, zither, euphonium',
      'erhu, koto, shamisen, oud, tabla, bouzouki, balalaika, hurdy gurdy, dulcimer, kalimba/mbira, bodhran, sousaphone, celesta, cajon, melodica, shakuhachi',
      'guzheng, pipa, kora, duduk, nyckelharpa, sarangi, santoor, theorbo, ondes martenot, serpent, crumhorn, handpan/hang, glass harmonica, morin khuur, bandoneon'
    ] },
    { q: 'NAME A VEGETABLE', t: [
      'carrot, broccoli, potato, lettuce, corn, onion, cucumber, tomato',
      'spinach, celery, cabbage, peas/pea, bell pepper/pepper, cauliflower, green beans/green bean, mushroom, zucchini, asparagus, garlic, sweet potato, pumpkin, eggplant/aubergine',
      'kale, beet/beetroot, radish, brussels sprouts/brussels sprout, artichoke, squash, leek, turnip, okra, yam, arugula/rocket, bok choy/pak choi, edamame',
      'parsnip, rutabaga/swede, fennel, chard/swiss chard, endive, kohlrabi, watercress, shallot, jicama, collard greens/collards, daikon, butternut squash, scallion/green onion/spring onion, radicchio',
      'celeriac, salsify, sunchoke/jerusalem artichoke, cardoon, romanesco, taro, cassava/yuca, chayote, lotus root, bitter melon, gai lan/chinese broccoli, mizuna, sorrel, samphire',
      'oca, ulluco, skirret, mashua, scorzonera, crosne, yacon, celtuce, fiddleheads/fiddlehead, nettle, purslane, malanga, ramps/ramp'
    ] },
    { q: 'NAME A SPORT', t: [
      'soccer/football, basketball, baseball, tennis, golf, hockey/ice hockey, swimming, volleyball',
      'boxing, cricket, rugby, running, cycling, skiing, wrestling, bowling, surfing, skateboarding, badminton, softball, lacrosse, gymnastics',
      'table tennis/ping pong, snowboarding, karate, judo, archery, fencing, rowing, sailing, rock climbing/climbing, handball, polo, water polo, track and field/athletics, figure skating, darts',
      'curling, squash, bobsled/bobsleigh, triathlon, taekwondo, luge, biathlon, field hockey, kickboxing, pickleball, racquetball, equestrian, canoeing/kayaking, diving, pole vault',
      'hurling, sepak takraw, kabaddi, korfball, skeleton, netball, jai alai, bandy, petanque/boules, bocce, croquet, orienteering, sumo, mixed martial arts/mma, roller derby',
      'buzkashi, pesapallo, shinty, hornussen, chess boxing, underwater hockey/octopush, kin ball, footvolley, teqball, tchoukball, bossaball, fistball, camogie, sambo, pelota'
    ] },
    { q: 'NAME AN OCEAN ANIMAL', t: [
      'shark, whale, dolphin, fish, octopus, jellyfish/jelly, crab, starfish/sea star',
      'seal, sea turtle/turtle, squid, lobster, shrimp, stingray/ray, clownfish, sea lion, orca/killer whale, seahorse, eel, walrus, manatee',
      'manta ray/manta, swordfish, tuna, barracuda, sea urchin/urchin, coral, sea otter/otter, narwhal, beluga, pufferfish/puffer, anglerfish, hammerhead, krill, plankton, oyster, clam',
      'humpback, blue whale, sperm whale, sea cucumber, sea anemone/anemone, moray eel/moray, lionfish, cuttlefish, nautilus, dugong, marlin, mackerel, sardine, halibut, mussel, scallop',
      'blobfish, sunfish/mola/mola mola, giant squid, colossal squid, oarfish, vampire squid, gulper eel, siphonophore, nudibranch/sea slug, mantis shrimp, hagfish, coelacanth, leafy sea dragon/sea dragon, frilled shark, goblin shark',
      'dumbo octopus, barreleye, fangtooth, sea pig, viperfish, lanternfish, cookiecutter shark, pyrosome, sea butterfly, salp, hatchetfish, giant isopod/isopod, yeti crab, comb jelly/ctenophore, bristlemouth'
    ] },
    { q: 'NAME A COLOR', t: [
      'red, blue, green, yellow, purple, orange, pink, black, white',
      'brown, gray/grey, gold, silver, turquoise, navy, teal, maroon, beige, violet, lavender',
      'magenta, cyan, indigo, crimson, burgundy, scarlet, olive, coral, peach, tan, ivory, lime, mint, salmon, aqua',
      'chartreuse, vermilion, fuchsia, mauve, ochre, taupe, periwinkle, cerulean, amber, khaki, lilac, mustard, emerald, sapphire, charcoal',
      'puce, celadon, cobalt, viridian, sepia, umber, sienna, carmine, cinnabar, aubergine, heliotrope, marigold, ultramarine, saffron, gamboge',
      'zaffre, smaragdine, fulvous, glaucous, wenge, falu red, xanadu, coquelicot, gingerline, eburnean, mikado, razzmatazz, isabelline, caput mortuum, verdigris'
    ] },
    { q: 'NAME A BONE IN THE HUMAN BODY', t: [
      'skull, femur, rib, spine',
      'tibia, humerus, pelvis, jawbone/jaw, collarbone, kneecap, sternum, radius, ulna, fibula',
      'clavicle, patella, scapula/shoulder blade, mandible, vertebra/vertebrae, coccyx/tailbone, cranium, phalanges/phalanx, metatarsal',
      'sacrum, ilium, ischium, maxilla, carpal/carpals, tarsal/tarsals, metacarpal, hyoid, stapes/stirrup, malleus/hammer, incus/anvil, calcaneus/heel bone, zygomatic/cheekbone',
      'atlas, axis, sphenoid, ethmoid, temporal, occipital, parietal, frontal, scaphoid, talus, pubis, vomer, nasal bone',
      'lunate, trapezium, trapezoid, capitate, hamate, pisiform, triquetrum, cuboid, navicular, cuneiform, lacrimal, palatine, sesamoid'
    ] },
    { q: 'NAME A HERB OR SPICE', t: [
      'black pepper/pepper, cinnamon, basil, garlic, oregano',
      'paprika, cumin, ginger, parsley, mint, rosemary, thyme, nutmeg, chili powder/chili, vanilla, dill, cilantro/coriander',
      'turmeric, cloves/clove, cardamom, sage, bay leaf/bay, saffron, cayenne, curry powder/curry, chives, tarragon, mustard seed/mustard, allspice, fennel seed',
      'star anise/anise, sumac, zaatar/za atar, marjoram, lemongrass, fenugreek, caraway, garam masala, mace, five spice, juniper/juniper berries, sesame, poppy seed',
      'asafoetida/hing, galangal, nigella/kalonji, ajwain, grains of paradise, sichuan pepper/szechuan pepper, makrut lime/kaffir lime, epazote, lovage, berbere, ras el hanout, annatto/achiote, mahlab',
      'long pepper, cubeb, amchur/amchoor, kokum, anardana, wattleseed, sansho, grains of selim, black lime/loomi, mastic, savory/summer savory, hyssop, shiso/perilla, sassafras/file'
    ] },
    { q: 'NAME A CITY IN EUROPE', t: [
      'paris, london, rome, berlin, madrid, barcelona, amsterdam',
      'vienna, prague, lisbon, dublin, athens, venice, milan, munich, moscow, brussels, budapest, florence, stockholm, copenhagen',
      'edinburgh, manchester, liverpool, warsaw, oslo, helsinki, zurich, geneva, krakow, naples, seville, lyon, marseille, hamburg, istanbul, porto, frankfurt',
      'bruges, salzburg, valencia, bologna, turin, nice, bordeaux, dubrovnik, tallinn, riga, vilnius, bratislava, ljubljana, belgrade, bucharest, sofia, reykjavik, granada',
      'ghent, antwerp, rotterdam, utrecht, gothenburg, bergen, tromso, split, sarajevo, skopje, tirana, chisinau, plovdiv, lviv, gdansk, wroclaw, cluj napoca/cluj, thessaloniki, valletta',
      'tartu, kaunas, brno, olomouc, ohrid, kotor, mostar, sibiu, aarhus, odense, umea, oulu, gyor, debrecen, timisoara, novi sad, maribor, torshavn'
    ] },
    { q: 'NAME A BOARD GAME', t: [
      'monopoly, chess, scrabble, checkers/draughts, clue/cluedo',
      'sorry, risk, connect four, battleship, candy land, the game of life/game of life/life, trivial pursuit, operation, backgammon, mouse trap',
      'catan/settlers of catan, ticket to ride, pandemic, guess who, stratego, othello/reversi, go, mahjong, pictionary, chutes and ladders/snakes and ladders, ludo/parcheesi, cranium, codenames',
      'carcassonne, azul, splendor, wingspan, mancala, chinese checkers, diplomacy, axis and allies, small world, king of tokyo, sequence, trouble, hungry hungry hippos',
      'agricola, puerto rico, terraforming mars, power grid, twilight struggle, gloomhaven, brass, scythe, root, tigris and euphrates, el grande, hive, blokus, dixit, mysterium',
      'shogi, xiangqi, hnefatafl/tafl, senet, nine mens morris, fanorona, oware, pachisi, tak, arimaa, hex, crokinole, through the ages, mage knight, spirit island'
    ] },
    { q: 'NAME A FLOWER', t: [
      'rose, tulip, sunflower, daisy, lily',
      'orchid, daffodil, lavender, carnation, lilac, poppy, dandelion, violet, iris, hibiscus, marigold, peony',
      'chrysanthemum/mum, magnolia, jasmine, lotus, hydrangea, gardenia, azalea, begonia, pansy, petunia, zinnia, dahlia, lily of the valley, cherry blossom',
      'camellia, gerbera, freesia, ranunculus, anemone, foxglove, snapdragon, gladiolus, bluebell, crocus, hyacinth, aster, cosmos, lupin/lupine, wisteria, bougainvillea, morning glory, honeysuckle',
      'protea, plumeria/frangipani, edelweiss, amaryllis, delphinium/larkspur, hellebore, verbena, calla lily/calla, bird of paradise, heather, primrose, geranium, columbine, cornflower, forget me not',
      'titan arum/corpse flower, rafflesia, gazania, scabiosa, love in a mist/nigella, astilbe, bletilla, lisianthus, statice, celosia, alstroemeria, red hot poker/kniphofia, gaillardia, trillium, bloodroot'
    ] },
    { q: 'NAME A MYTHICAL CREATURE', t: [
      'dragon, unicorn, mermaid, vampire, werewolf, ghost, fairy',
      'phoenix, centaur, minotaur, pegasus, troll, goblin, zombie, elf, giant, bigfoot/yeti/sasquatch, griffin/gryphon, cyclops',
      'kraken, hydra, medusa/gorgon, sphinx, banshee, leprechaun, gnome, ogre, siren, chimera, loch ness monster/nessie, genie/djinn/jinn, basilisk, dwarf',
      'wendigo, kitsune, kelpie, golem, harpy, selkie, manticore, chupacabra, satyr/faun, pixie, nymph, cerberus, valkyrie, wyvern, thunderbird',
      'kappa, tengu, baku, naga, garuda, roc, qilin/kirin, bunyip, cockatrice, hippogriff, jormungandr, fenrir, sleipnir, krampus, dryad',
      'tarasque, bakeneko, nuckelavee, encantado, aswang, tikbalang, adze, ammit, simurgh, makara, nue, kushtaka, hodag, jackalope, wolpertinger, camazotz'
    ] },
    { q: 'NAME A KITCHEN TOOL', t: [
      'spoon, fork, knife, spatula, whisk, ladle',
      'tongs, peeler, grater, rolling pin, colander, can opener, cutting board, measuring cup, strainer, frying pan/pan, pot',
      'zester, garlic press, mortar and pestle/mortar/pestle, sieve, wok, skillet, saucepan, cleaver, corkscrew, kitchen scale/scale, thermometer, mandoline, blender, pizza cutter, timer',
      'baster, skimmer, dutch oven, ricer, pastry brush, piping bag, melon baller, egg slicer, nutcracker, salad spinner, spider, ramekin, sifter, honing steel, steamer',
      'microplane, tamis, chinois, offset spatula, bench scraper/dough scraper, mezzaluna, fish slice, spurtle, tagine, moka pot, molcajete, chitarra, pasta machine, kitchen torch/blowtorch',
      'aebleskiver pan, tortilla press, apple corer, cherry pitter, egg topper, lemon reamer/reamer, butter curler, banneton, couche, gnocchi board, pastry blender, suribachi'
    ] },
    { q: 'NAME A CAR BRAND', t: [
      'toyota, ford, honda, bmw, tesla, mercedes/mercedes benz, chevrolet/chevy',
      'audi, nissan, volkswagen/vw, hyundai, ferrari, lamborghini, porsche, jeep, kia, subaru, mazda, dodge, lexus',
      'volvo, jaguar, land rover/range rover, cadillac, buick, chrysler, mini, fiat, bentley, rolls royce, maserati, mitsubishi, gmc, acura, infiniti',
      'aston martin, bugatti, mclaren, alfa romeo, lincoln, peugeot, renault, citroen, skoda, seat, lotus, genesis, rivian, lucid, polestar, isuzu',
      'koenigsegg, pagani, saab, opel, vauxhall, dacia, lada, tata, mahindra, byd, geely, alpine, cupra, maybach, smart',
      'rimac, spyker, morgan, caterham, de tomaso, lancia, hispano suiza, zenvo, noble, ariel, trabant, proton, perodua, holden, scion'
    ] },
    { q: 'NAME A GREEK OR ROMAN GOD', t: [
      'zeus, poseidon, hades, athena, apollo, aphrodite',
      'ares, hermes, artemis, hera, jupiter, mars, venus, neptune, mercury, cupid/eros, dionysus, pluto',
      'hephaestus, demeter, persephone, minerva, juno, bacchus, diana, vulcan, saturn, cronus/kronos, gaia, nike, janus, hestia',
      'hecate, nemesis, morpheus, pan, helios, selene, eos, uranus, rhea, iris, hypnos, thanatos, vesta, ceres, aurora, fortuna',
      'tyche, nyx, erebus, hebe, asclepius, priapus, aeolus, boreas, zephyrus, triton, proteus, nereus, themis, mnemosyne, hyperion, oceanus',
      'hymenaeus, harpocrates, terminus, quirinus, pomona, faunus, bellona, robigo, eileithyia, phanes, chaos, aether, hemera, pontus, tartarus, ourea'
    ] },
    { q: 'NAME SOMETHING AT THE BEACH', t: [
      'sand, seashell/shell/shells, water, waves/wave, sun, towel, umbrella',
      'crab, seaweed, sunscreen, rocks/rock, bucket, shovel/spade, surfboard, seagull, lifeguard, sandcastle, starfish, boat, flip flops',
      'jellyfish, driftwood, pier, dunes/dune, tide pool, beach ball, cooler, sunglasses, kite, volleyball net, lighthouse, kelp, pebbles',
      'sea glass, sandpiper, sand dollar, hermit crab, boardwalk, jetty, buoy, snorkel, lifebuoy, bodyboard/boogie board, wetsuit, windbreak, deck chair',
      'barnacle, mermaids purse/egg case, cuttlebone, sea foam, groyne, breakwater, wrack line/tidemark, sand flea, ghost crab, beach hut, metal detector',
      'sea bean, fulgurite, nurdle, sea potato, razor clam, whelk egg case, lugworm, sea pottery, ambergris, mermaid tears, velella/by the wind sailor, sea pen'
    ] }
  ];

  var ZONES = [
    [120, 'LIGHT STARTS TO FADE', 0],
    [200, 'THE TWILIGHT ZONE', 1],
    [332, 'DEEPEST SCUBA DIVE, 332M', 0],
    [500, 'EMPEROR PENGUINS DIVE THIS DEEP', 0],
    [1000, 'THE MIDNIGHT ZONE', 1],
    [1500, 'ANGLERFISH TERRITORY', 0],
    [2000, 'THE WATER IS NEAR FREEZING', 0],
    [2250, 'SPERM WHALES HUNT THIS DEEP', 0],
    [3800, 'THE TITANIC RESTS HERE', 0],
    [4000, 'THE ABYSSAL ZONE', 1],
    [5000, 'THE ABYSSAL PLAIN', 0],
    [6000, 'THE HADAL ZONE', 1],
    [6990, 'THE TRENCH FLOOR', 0]
  ];

  var WATER_STOPS = [
    [0, 58, 127, 181], [150, 37, 96, 143], [500, 23, 63, 102], [1200, 14, 38, 67],
    [3000, 8, 22, 41], [6000, 5, 11, 22], [8000, 3, 6, 13]
  ];
  var LUTN = 801;
  var WATER = [];
  (function () {
    for (var i = 0; i < LUTN; i++) {
      var d = i * 10, s = 0;
      while (s < WATER_STOPS.length - 2 && d > WATER_STOPS[s + 1][0]) s++;
      var a = WATER_STOPS[s], b = WATER_STOPS[s + 1];
      var k = Math.max(0, Math.min(1, (d - a[0]) / (b[0] - a[0])));
      WATER.push('rgb(' + Math.round(a[1] + (b[1] - a[1]) * k) + ',' + Math.round(a[2] + (b[2] - a[2]) * k) + ',' + Math.round(a[3] + (b[3] - a[3]) * k) + ')');
    }
  })();
  var SKY = [];
  (function () {
    var top = [126, 200, 234], bottom = [214, 240, 248];
    for (var i = 0; i < 14; i++) {
      var k = i / 13;
      SKY.push('rgb(' + Math.round(top[0] + (bottom[0] - top[0]) * k) + ',' + Math.round(top[1] + (bottom[1] - top[1]) * k) + ',' + Math.round(top[2] + (bottom[2] - top[2]) * k) + ')');
    }
  })();

  function norm(s) {
    s = String(s).toLowerCase();
    if (s.normalize) s = s.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    s = s.replace(/&/g, ' and ').replace(/^\s*the\s+/, '');
    return s.replace(/[^a-z0-9]/g, '');
  }

  var bankCache = [];
  function bankFor(i) {
    if (bankCache[i]) return bankCache[i];
    var p = PROMPTS[i], map = Object.create(null), list = [];
    for (var t = 0; t < p.t.length; t++) {
      var entries = p.t[t].split(',');
      for (var e = 0; e < entries.length; e++) {
        var names = entries[e].split('/');
        var display = names[0].trim().toUpperCase();
        if (!display) continue;
        var item = { tier: t + 1, name: display };
        list.push(item);
        for (var n = 0; n < names.length; n++) {
          var key = norm(names[n]);
          if (key && !map[key]) map[key] = item;
        }
      }
    }
    bankCache[i] = { map: map, list: list, keys: Object.keys(map) };
    return bankCache[i];
  }

  function distance(a, b, max) {
    var prev = [], cur = [], i, j;
    for (j = 0; j <= b.length; j++) prev[j] = j;
    for (i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = i;
      for (j = 1; j <= b.length; j++) {
        cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1));
        if (cur[j] < rowMin) rowMin = cur[j];
      }
      if (rowMin > max) return max + 1;
      var swap = prev; prev = cur; cur = swap;
    }
    return prev[b.length];
  }

  function lookup(bank, raw) {
    var k = norm(raw);
    if (!k) return null;
    if (bank.map[k]) return bank.map[k];
    if (k.length > 3 && k.charAt(k.length - 1) === 's' && bank.map[k.slice(0, -1)]) return bank.map[k.slice(0, -1)];
    if (k.length > 2 && bank.map[k + 's']) return bank.map[k + 's'];
    if (k.length < 5) return null;
    var max = k.length >= 9 ? 2 : 1, best = null, bestD = max + 1, tie = false;
    for (var i = 0; i < bank.keys.length; i++) {
      var key = bank.keys[i];
      if (key.length < 5 || key.charAt(0) !== k.charAt(0) || Math.abs(key.length - k.length) > max) continue;
      var d = distance(k, key, max);
      if (d < bestD) { bestD = d; best = key; tie = false; }
      else if (d === bestD && bank.map[key] !== bank.map[best]) tie = true;
    }
    return best && !tie ? bank.map[best] : null;
  }

  var textCache = {}, textCacheSize = 0;
  function textSprite(str, color) {
    var key = color + '|' + str;
    var c = textCache[key];
    if (c) return c;
    if (textCacheSize > 500) { textCache = {}; textCacheSize = 0; }
    c = document.createElement('canvas');
    c.width = Math.max(1, str.length * 6 - 1);
    c.height = 7;
    var g = c.getContext('2d');
    g.fillStyle = color;
    for (var i = 0; i < str.length; i++) {
      var gl = GLYPH[str.charAt(i)];
      if (!gl) continue;
      for (var p = 0; p < 35; p++) if (gl.charCodeAt(p) === 35) g.fillRect(i * 6 + (p % 5), (p / 5) | 0, 1, 1);
    }
    textCache[key] = c;
    textCacheSize++;
    return c;
  }
  function textWidth(str, s, track) {
    return str.length ? (str.length * 6 - 1) * s + (str.length - 1) * (track || 0) : 0;
  }
  function drawText(ctx, str, x, y, s, color, align, track) {
    if (!str) return;
    var w = textWidth(str, s, track);
    var x0 = Math.round(align === 'center' ? x - w / 2 : align === 'right' ? x - w : x);
    var y0 = Math.round(y);
    if (!track) {
      var spr = textSprite(str, color);
      ctx.drawImage(spr, x0, y0, spr.width * s, 7 * s);
      return;
    }
    for (var i = 0; i < str.length; i++) {
      var ch = str.charAt(i);
      if (ch !== ' ') ctx.drawImage(textSprite(ch, color), x0, y0, 5 * s, 7 * s);
      x0 += 6 * s + track;
    }
  }
  function drawChroma(ctx, str, x, y, s, align, track) {
    var o = Math.max(1, Math.round(s / 2));
    drawText(ctx, str, x - o, y + o, s, PINK, align, track);
    drawText(ctx, str, x + o, y - o, s, CYAN, align, track);
    drawText(ctx, str, x, y, s, WHITE, align, track);
  }
  function wrap(str, s, maxW) {
    var words = str.split(' '), lines = [], line = '';
    for (var i = 0; i < words.length; i++) {
      var next = line ? line + ' ' + words[i] : words[i];
      if (line && textWidth(next, s) > maxW) { lines.push(line); line = words[i]; }
      else line = next;
    }
    if (line) lines.push(line);
    return lines;
  }
  function fmt(n) {
    return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  function makeSprite(rows, palette, s) {
    var c = document.createElement('canvas');
    c.width = rows[0].length * s;
    c.height = rows.length * s;
    var g = c.getContext('2d');
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        var col = palette[rows[y].charAt(x)];
        if (!col) continue;
        g.fillStyle = col;
        g.fillRect(x * s, y * s, s, s);
      }
    }
    return c;
  }
  function makeGlow(size, inner, outer) {
    var c = document.createElement('canvas');
    c.width = c.height = size;
    var g = c.getContext('2d');
    var grad = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
    grad.addColorStop(0, inner);
    grad.addColorStop(1, outer);
    g.fillStyle = grad;
    g.fillRect(0, 0, size, size);
    return c;
  }

  var SPR = null;
  function sprites() {
    if (SPR) return SPR;
    var krillPal = { a: '#FF9AAA', r: '#FF4D67', R: '#FF8E9C', w: '#FFFFFF', k: '#1A0F14', l: '#D12C47' };
    var body = ['..a...........', '.a.a..........', 'a...a.rrrr....', '....rrRRRRrr..', '...rwkrRRRRrr.', '..rrrrrrrrrrrr', '...rrrrrrrr.rr'];
    var fishRows = ['..###...', '.#####.#', '########', '.#####.#', '..###...'];
    var fishRowsL = fishRows.map(function (r) { return r.split('').reverse().join(''); });
    var sun = [];
    for (var y = 0; y < 20; y++) {
      var row = '';
      for (var x = 0; x < 20; x++) {
        var d = Math.sqrt((x - 9.5) * (x - 9.5) + (y - 9.5) * (y - 9.5));
        row += d < 8 ? 'c' : d < 9.6 ? 'r' : '.';
      }
      sun.push(row);
    }
    var scanCanvas = document.createElement('canvas');
    scanCanvas.width = 4; scanCanvas.height = 3;
    var sg = scanCanvas.getContext('2d');
    sg.fillStyle = 'rgba(255,255,255,0.035)'; sg.fillRect(0, 0, 4, 1);
    sg.fillStyle = 'rgba(0,0,0,0.09)'; sg.fillRect(0, 2, 4, 1);
    SPR = {
      krill: [
        makeSprite(body.concat(['....l.l.l.l.r.', '...l.l.l.l..rr']), krillPal, 3),
        makeSprite(body.concat(['...l.l.l.l..r.', '....l.l.l.l.rr']), krillPal, 3)
      ],
      krillGlow: makeGlow(120, 'rgba(255,77,103,0.32)', 'rgba(255,77,103,0)'),
      fishR: makeSprite(fishRowsL, { '#': 'rgba(6,16,30,0.8)' }, 3),
      fishL: makeSprite(fishRows, { '#': 'rgba(6,16,30,0.8)' }, 3),
      sun: makeSprite(sun, { c: '#FFF1B8', r: '#FFE08A' }, 3),
      sunGlow: makeGlow(170, 'rgba(255,236,170,0.55)', 'rgba(255,236,170,0)'),
      cloud: makeSprite(['......####........', '....########..##..', '..##############..', '.################.', '##################', '.gggggggggggggggg.'], { '#': '#FFFFFF', g: '#DCEEF6' }, 4),
      boat: makeSprite(['....f.....', '....fpp...', '....f.....', '..dddd....', 'dddddddddd', '.dddddddd.'], { d: '#1E2B3A', f: '#1E2B3A', p: PINK }, 3),
      scan: D.ctx.createPattern(scanCanvas, 'repeat')
    };
    return SPR;
  }

  var L = { W: -1, H: -1, top: -1, bottom: -1 };
  var keys = [];
  var dive = { k: 'GO', x: 0, y: 0, w: 0, h: 0 };

  function layout() {
    var W = D.W, H = D.H, top = D.safe.top;
    L.W = W; L.H = H; L.top = top; L.bottom = D.safe.bottom;
    L.compact = H - top - D.safe.bottom < 700;
    L.cardX = 16; L.cardY = top + (L.compact ? 84 : 116); L.cardW = W - 32; L.cardH = L.compact ? 100 : 136;
    L.kbBottom = H - D.safe.bottom - 16;
    var kh = L.compact ? 34 : 42, gy = L.compact ? 5 : 8, gx = 4, side = 6;
    var kw = (W - side * 2 - gx * 9) / 10;
    L.kbTop = L.kbBottom - (kh * 4 + gy * 3);
    keys.length = 0;
    var rows = ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'];
    var starts = [side, side + (kw + gx) / 2, side + (kw + gx) * 1.5];
    for (var r = 0; r < 3; r++) {
      for (var i = 0; i < rows[r].length; i++) {
        keys.push({ k: rows[r].charAt(i), label: rows[r].charAt(i), x: starts[r] + i * (kw + gx), y: L.kbTop + r * (kh + gy), w: kw, h: kh });
      }
    }
    var bkX = starts[2] + 7 * (kw + gx);
    keys.push({ k: 'BK', label: '<', x: bkX, y: L.kbTop + 2 * (kh + gy), w: W - side - bkX, h: kh });
    keys.push({ k: 'SP', label: 'SPACE', x: side + (kw + gx) * 2, y: L.kbTop + 3 * (kh + gy), w: (kw + gx) * 6 - gx, h: kh });
    L.inH = L.compact ? 42 : 50;
    L.inY = L.kbTop - (L.compact ? 10 : 16) - L.inH;
    L.timerX = 16 + L.inH / 2;
    L.inX = 16 + L.inH + 10;
    dive.w = 80; dive.h = L.inH; dive.x = W - 16 - dive.w; dive.y = L.inY;
    L.inW = dive.x - 8 - L.inX;
    L.msgY = L.inY - 22;
    L.baseY = L.cardY + L.cardH + 34;
    L.anchorY = Math.round((L.cardY + L.cardH + L.msgY) / 2);
  }
  function ensureLayout() {
    if (L.W !== D.W || L.H !== D.H || L.top !== D.safe.top || L.bottom !== D.safe.bottom) layout();
  }

  var prompts, banks, idx, phase, phaseT, timeLeft, input, results, points, shown, krill, cam, lastCam, clock;
  var msg = { text: '', color: PINK, t: 0 };
  var shakeT, pressK, pressT, kbShow, titleA, reveal, ended, bubbleT;
  var botS = { wait: 0, plan: null, pos: 0 };
  var fish = [], snow = [], bubbles = [], clouds = [];

  function screenY(depth) { return L.baseY + (depth - cam) * PPM; }

  function seedScene() {
    var span = Math.max(300, (D.H - L.baseY) / PPM + 200);
    fish.length = 0;
    for (var i = 0; i < 9; i++) {
      var dir = Math.random() < 0.5 ? -1 : 1;
      fish.push({ x: Math.random() * D.W, d: cam + 25 + Math.random() * span, vx: dir * (14 + Math.random() * 26) });
    }
    snow.length = 0;
    for (var j = 0; j < 36; j++) snow.push({ x: Math.random() * D.W, y: Math.random() * D.H, s: Math.random() < 0.3 ? 2 : 1 });
    clouds.length = 0;
    clouds.push({ x: D.W * 0.04, y: 52, s: 0.9 }, { x: D.W * 0.6, y: 40, s: 0.7 }, { x: D.W * 0.3, y: 30, s: 0.6 });
  }

  function setMsg(text, color) { msg.text = text; msg.color = color; msg.t = 1.4; }

  function finishAnswer(item) {
    var pts = item ? POINTS[item.tier - 1] : 0;
    points += pts;
    results.push({ tier: item ? item.tier : 0, pts: pts });
    reveal = item ? { name: item.name, tier: item.tier, pts: pts } : { name: 'TIME', tier: 0, pts: 0 };
    phase = 'reveal';
    phaseT = 0;
    msg.t = 0;
    D.score(points * 10);
    if (!item) { D.haptic('warning'); D.tone({ freq: 300, slide: 140, dur: 0.3, type: 'square', vol: 0.06 }); return; }
    D.haptic(item.tier >= 5 ? 'success' : item.tier >= 3 ? 'medium' : 'light');
    D.tone({ freq: 380 + item.tier * 60, slide: 180, dur: 0.35, type: 'triangle', vol: 0.12 });
  }

  function submit() {
    if (phase !== 'answer' && phase !== 'intro') return;
    var item = lookup(banks[idx], input);
    if (item) { finishAnswer(item); return; }
    setMsg(input.trim() ? 'NOT ON THE LIST' : 'TYPE ONE ANSWER', PINK);
    shakeT = 0.35;
    D.haptic('warning');
    D.tone({ freq: 160, dur: 0.12, type: 'square', vol: 0.06 });
  }

  function nextPrompt() {
    idx++;
    reveal = null;
    if (idx >= ROUND) {
      phase = 'done';
      if (!ended) {
        ended = true;
        var m = points * 10;
        D.haptic('success');
        D.end({ score: m, unit: 'm', headline: headlineFor(m) });
      }
      return;
    }
    phase = 'intro';
    phaseT = 0;
    timeLeft = TIME;
    input = '';
    botS.plan = null;
    botS.wait = 0.5 + Math.random() * 0.6;
  }

  function headlineFor(m) {
    if (m >= 7000) return 'Touched the trench floor';
    if (m >= 6000) return 'Reached the hadal zone';
    if (m >= 4000) return 'Reached the abyss';
    if (m >= 1000) return 'Reached the midnight zone';
    if (m >= 200) return 'Reached the twilight zone';
    return 'Stayed in the sunlit zone';
  }

  function press(k) {
    pressK = k;
    pressT = 0.12;
    if (k === 'GO') { submit(); return; }
    D.haptic('light');
    D.tone({ freq: 520 + Math.random() * 80, dur: 0.03, type: 'square', vol: 0.03 });
    if (phase !== 'answer' && phase !== 'intro') return;
    if (k === 'BK') input = input.slice(0, -1);
    else if (k === 'SP') { if (input && input.charAt(input.length - 1) !== ' ' && input.length < MAXLEN) input += ' '; }
    else if (input.length < MAXLEN) input += k;
  }

  function hit(x, y) {
    if (x >= dive.x - 4 && x <= dive.x + dive.w + 4 && y >= dive.y - 4 && y <= dive.y + dive.h + 4) return 'GO';
    for (var i = 0; i < keys.length; i++) {
      var b = keys[i];
      if (x >= b.x - 2 && x <= b.x + b.w + 2 && y >= b.y - 4 && y <= b.y + b.h + 4) return b.k;
    }
    return null;
  }

  function botAnswer(bank) {
    var r = Math.random(), tier = 1, acc = 0;
    for (var i = 0; i < BOT_WEIGHTS.length; i++) { acc += BOT_WEIGHTS[i]; if (r <= acc) { tier = i + 1; break; } }
    var pool = [];
    for (var j = 0; j < bank.list.length; j++) if (bank.list[j].tier === tier) pool.push(bank.list[j]);
    if (!pool.length) pool = bank.list;
    return pool[Math.floor(Math.random() * pool.length)].name.replace(/[^A-Z ]/g, '').replace(/\s+/g, ' ').trim();
  }

  function drawScene(ctx, W, H, state) {
    var S = sprites();
    var sy = Math.round(screenY(0));
    if (sy > 0) {
      var bh = Math.ceil(sy / SKY.length);
      for (var b = 0; b < SKY.length; b++) { ctx.fillStyle = SKY[b]; ctx.fillRect(0, b * bh, W, bh + 1); }
      var sunX = Math.round(W * 0.84), sunY = Math.round(sy - 56);
      ctx.drawImage(S.sunGlow, sunX - 85, sunY - 85);
      ctx.drawImage(S.sun, sunX - 30, sunY - 30);
      for (var c = 0; c < clouds.length; c++) {
        var cl = clouds[c];
        ctx.drawImage(S.cloud, Math.round(cl.x), Math.round(sy - cl.y), Math.round(S.cloud.width * cl.s), Math.round(S.cloud.height * cl.s));
      }
      ctx.fillStyle = 'rgba(255,255,255,0.35)';
      ctx.fillRect(0, sy - 18, W, 18);
    }
    var y0 = Math.max(0, sy);
    for (var y = y0; y < H; y += BAND) {
      var d = cam + (y + BAND / 2 - L.baseY) / PPM;
      ctx.fillStyle = WATER[d <= 0 ? 0 : Math.min(LUTN - 1, (d / 10) | 0)];
      ctx.fillRect(0, y, W, BAND);
    }
    if (sy > -12 && sy < H) {
      ctx.fillStyle = '#BFE6F7';
      for (var wx = 0; wx < W; wx += 4) ctx.fillRect(wx, sy - 2 + Math.round(Math.sin(wx * 0.035 + clock * 1.6) * 1.5), 4, 3);
      ctx.drawImage(S.boat, Math.round(W * 0.26), sy - S.boat.height + 4 + Math.round(Math.sin(clock * 1.4) * 1.5));
    }

    var labelTop = state === 'ready' ? -20 : L.cardY + L.cardH + 8;
    for (var z = 0; z < ZONES.length; z++) {
      var zy = screenY(ZONES[z][0]);
      if (zy < labelTop || zy > H + 20) continue;
      if (ZONES[z][2]) {
        drawText(ctx, ZONES[z][1], W / 2 - 12, zy - 7, 2, 'rgba(65,214,242,0.55)', 'center', 2);
      } else if (z % 2) {
        ctx.fillStyle = 'rgba(160,190,220,0.35)';
        ctx.fillRect(16, Math.round(zy), 18, 1);
        drawText(ctx, ZONES[z][1], 40, zy - 3, 1, 'rgba(170,200,230,0.6)', 'left', 1);
      } else {
        ctx.fillStyle = 'rgba(160,190,220,0.35)';
        ctx.fillRect(W - 70, Math.round(zy), 18, 1);
        drawText(ctx, ZONES[z][1], W - 76, zy - 3, 1, 'rgba(170,200,230,0.6)', 'right', 1);
      }
    }

    var kelpBase = screenY(330);
    if (kelpBase > -10 && kelpBase - 240 < H) {
      ctx.fillStyle = 'rgba(5,18,34,0.55)';
      var strands = [8, 30, 54, W - 66, W - 40];
      for (var s = 0; s < strands.length; s++) {
        for (var seg = 0; seg < 26; seg++) {
          var kx = Math.round(strands[s] + Math.sin(clock * 1.1 + seg * 0.45 + s * 1.7) * seg * 0.5);
          var ky = Math.round(kelpBase - seg * 8);
          ctx.fillRect(kx, ky - 8, 6, 8);
          if (seg % 3 === 1) ctx.fillRect(seg % 2 ? kx + 6 : kx - 6, ky - 6, 6, 4);
        }
      }
    }

    for (var f = 0; f < fish.length; f++) {
      var fy = screenY(fish[f].d);
      if (fy < -20 || fy > H + 20) continue;
      ctx.drawImage(fish[f].vx > 0 ? S.fishR : S.fishL, Math.round(fish[f].x), Math.round(fy));
    }

    var floorY = screenY(7000);
    if (floorY < H) {
      ctx.fillStyle = '#02040A';
      ctx.fillRect(0, Math.round(floorY), W, H - floorY + 1);
      for (var fx = 0; fx < W; fx += 8) ctx.fillRect(fx, Math.round(floorY - ((fx * 37) % 5) * 3), 8, 16);
    }

    var rx = W - 22;
    var dTop = Math.max(0, cam + (0 - L.baseY) / PPM), dBot = cam + (H - L.baseY) / PPM;
    ctx.fillStyle = 'rgba(150,180,210,0.3)';
    var lineTop = Math.max(0, sy);
    if (lineTop < H) ctx.fillRect(rx, lineTop, 1, H - lineTop);
    for (var m = Math.floor(dTop / 50) * 50; m <= dBot; m += 50) {
      if (m < 0) continue;
      var my = Math.round(screenY(m));
      var major = m % 100 === 0;
      ctx.fillStyle = 'rgba(150,180,210,' + (major ? 0.55 : 0.3) + ')';
      ctx.fillRect(rx - (major ? 10 : 5), my, major ? 10 : 5, 1);
      if (major && my > labelTop) drawText(ctx, (m ? '-' : '') + m + 'M', rx - 14, my - 3, 1, 'rgba(170,200,230,0.6)', 'right');
    }

    for (var n = 0; n < snow.length; n++) {
      if (snow[n].y < sy + 4) continue;
      ctx.fillStyle = 'rgba(200,225,245,0.25)';
      ctx.fillRect(Math.round(snow[n].x), Math.round(snow[n].y), snow[n].s, snow[n].s);
    }

    var kx2 = W / 2 + Math.sin(clock * 1.3) * 14;
    var ky2 = screenY(krill) + Math.sin(clock * 2.1) * 3;
    ctx.drawImage(S.krillGlow, Math.round(kx2 - 60), Math.round(ky2 - 60));
    var spr = S.krill[(clock * (state === 'playing' ? 6 : 3)) % 2 | 0];
    ctx.drawImage(spr, Math.round(kx2 - spr.width / 2), Math.round(ky2 - spr.height / 2));

    ctx.strokeStyle = 'rgba(200,235,255,0.55)';
    ctx.lineWidth = 1.5;
    for (var q = 0; q < bubbles.length; q++) {
      var bb = bubbles[q];
      if (bb.y < sy) continue;
      ctx.globalAlpha = Math.min(1, bb.life);
      ctx.beginPath();
      ctx.arc(bb.x, bb.y, bb.r, 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  function panel(ctx, x, y, w, h, fill) {
    ctx.fillStyle = fill;
    ctx.fillRect(x + 6, y, w - 12, h);
    ctx.fillRect(x, y + 6, w, h - 12);
    ctx.fillRect(x + 2, y + 2, w - 4, h - 4);
  }

  function drawTitle(ctx, W, alpha) {
    var ty = D.safe.top + (L.compact ? 34 : 108);
    ctx.globalAlpha = alpha;
    drawChroma(ctx, 'DEEP END', W / 2, ty, Math.min(6, Math.floor((W - 40) / 47)), 'center');
    drawText(ctx, 'THE DAILY DIVE', W / 2, ty + 60, 2, '#1D6E8C', 'center', 6);
    drawText(ctx, '7 PROMPTS. 25 SECONDS EACH.', W / 2, ty + 92, 1, '#3D6F8A', 'center', 3);
    drawText(ctx, 'RARER ANSWERS SINK DEEPER.', W / 2, ty + 108, 1, '#3D6F8A', 'center', 3);
    if (D.best > 0) drawText(ctx, 'BEST ' + fmt(D.best) + 'M', W / 2, ty + 132, 1, '#1D6E8C', 'center', 3);
    ctx.globalAlpha = 1;
  }

  function drawHud(ctx, W) {
    var top = D.safe.top;
    var pw = ROUND * 12 + (ROUND - 1) * 5;
    var px = Math.round(Math.max(72, Math.min(W - 120 - pw, W / 2 - pw / 2)));
    for (var i = 0; i < ROUND; i++) {
      var x = px + i * 17, y = top + 18;
      if (i < results.length) {
        ctx.fillStyle = results[i].tier ? TIER_COLORS[results[i].tier - 1] : '#3A4A5E';
        ctx.fillRect(x, y, 12, 12);
      } else if (i === idx && phase !== 'done') {
        ctx.fillStyle = WHITE; ctx.fillRect(x - 2, y - 2, 16, 16);
        ctx.fillStyle = PINK; ctx.fillRect(x, y, 12, 12);
      } else {
        ctx.fillStyle = 'rgba(10,20,36,0.8)'; ctx.fillRect(x, y, 12, 12);
      }
    }
    if (L.compact) {
      drawChroma(ctx, fmt(shown) + 'M', W / 2, top + 58, 3, 'center', 1);
      return;
    }
    drawText(ctx, 'DEPTH', W / 2, top + 60, 1, DIM, 'center', 3);
    drawChroma(ctx, fmt(shown) + 'M', W / 2, top + 74, 4, 'center', 1);
    drawText(ctx, points + ' PTS', W / 2, top + 108, 1, DIM, 'center', 2);
  }

  function drawCard(ctx, W) {
    var x = L.cardX, y = L.cardY, w = L.cardW, h = L.cardH;
    panel(ctx, x, y, w, h, 'rgba(10,19,34,0.9)');
    drawText(ctx, 'PROMPT ' + (idx + 1) + ' OF ' + ROUND, x + 18, y + 16, 2, PINK, 'left', 3);
    var q = prompts[idx].q;
    var s = L.compact ? 2 : 3, lines = wrap(q, s, w - 36);
    if (lines.length > 2) { s = 2; lines = wrap(q, s, w - 36); }
    var shownChars = phase === 'intro' ? Math.floor(phaseT * 70) : 999;
    var lh = 7 * s + 8, ty = y + (L.compact ? 40 : s === 3 ? 46 : 52);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].slice(0, Math.max(0, shownChars));
      shownChars -= lines[i].length + 1;
      drawText(ctx, line, x + 18, ty + i * lh, s, WHITE, 'left');
    }
    drawText(ctx, 'v RARER ANSWERS SINK DEEPER v', x + 18, y + h - (L.compact ? 14 : 19), 1, DIM, 'left', 2);
  }

  function drawReveal(ctx, W) {
    var a = Math.min(1, phaseT / 0.15);
    var y = L.cardY + L.cardH + (L.compact ? 10 : 18) - (1 - a) * 8;
    ctx.globalAlpha = a;
    var s = L.compact || textWidth(reveal.name, 3) > W - 40 ? 2 : 3;
    if (reveal.tier) {
      var lines = wrap(reveal.name, s, W - 32);
      for (var i = 0; i < lines.length; i++) drawChroma(ctx, lines[i], W / 2, y + i * (7 * s + 6), s, 'center');
      drawText(ctx, '+' + reveal.pts + '  ' + TIERS[reveal.tier - 1], W / 2, y + lines.length * (7 * s + 6) + 4, 2, TIER_COLORS[reveal.tier - 1], 'center', 3);
    } else {
      drawText(ctx, 'TIME', W / 2, y, s, PINK, 'center', 3);
      drawText(ctx, '+0', W / 2, y + 7 * s + 10, 2, DIM, 'center', 3);
    }
    ctx.globalAlpha = 1;
  }

  function drawInput(ctx, W, H) {
    var e = 1 - Math.pow(1 - kbShow, 3);
    var off = Math.round((1 - e) * (H - L.inY + 30));
    ctx.fillStyle = 'rgba(4,9,18,0.84)';
    ctx.fillRect(0, L.inY - 30 + off, W, H - L.inY + 30);

    if (msg.t > 0 && msg.text) {
      ctx.globalAlpha = Math.min(1, msg.t / 0.3);
      drawText(ctx, msg.text, W / 2, L.msgY - 7 + off - 26, 2, msg.color, 'center', 3);
      ctx.globalAlpha = 1;
    }

    var cx = L.timerX, cy = L.inY + L.inH / 2 + off, frac = Math.max(0, timeLeft / TIME);
    var low = phase === 'answer' && timeLeft <= 6;
    ctx.fillStyle = '#081222';
    var rr = L.inH / 2 - 4;
    ctx.beginPath(); ctx.arc(cx, cy, rr + 4, 0, Math.PI * 2); ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(65,214,242,0.18)';
    ctx.beginPath(); ctx.arc(cx, cy, rr, 0, Math.PI * 2); ctx.stroke();
    ctx.strokeStyle = low ? PINK : CYAN;
    ctx.beginPath(); ctx.arc(cx, cy, rr, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); ctx.stroke();
    drawText(ctx, String(Math.ceil(timeLeft)), cx, cy - 7, 2, low ? PINK : CYAN, 'center');

    var sx = shakeT > 0 ? Math.round(Math.sin(shakeT * 70) * 5 * (shakeT / 0.35)) : 0;
    var ix = L.inX + sx, iy = L.inY + off;
    ctx.fillStyle = shakeT > 0 ? PINK : CYAN;
    ctx.fillRect(ix, iy, L.inW, L.inH);
    ctx.fillStyle = '#081222';
    ctx.fillRect(ix + 2, iy + 2, L.inW - 4, L.inH - 4);
    var room = Math.max(1, Math.floor((L.inW - 24) / 12));
    if (input) {
      var vis = input.length > room ? input.slice(input.length - room) : input;
      drawText(ctx, vis, ix + 12, iy + L.inH / 2 - 7, 2, WHITE, 'left');
      if ((clock * 2) % 2 < 1.2) { ctx.fillStyle = PINK; ctx.fillRect(ix + 12 + textWidth(vis, 2) + 3, iy + 12, 2, L.inH - 24); }
    } else {
      drawText(ctx, room >= 15 ? 'TYPE ONE ANSWER' : 'ANSWER', ix + 12, iy + L.inH / 2 - 7, 2, '#3E5670', 'left');
      if ((clock * 2) % 2 < 1.2) { ctx.fillStyle = PINK; ctx.fillRect(ix + 10, iy + 12, 2, L.inH - 24); }
    }
    ctx.fillStyle = 'rgba(65,214,242,0.15)';
    ctx.fillRect(L.inX, iy + L.inH + 4, L.inW, 3);
    ctx.fillStyle = low ? PINK : CYAN;
    ctx.fillRect(L.inX, iy + L.inH + 4, Math.round(L.inW * frac), 3);

    var dp = pressK === 'GO' && pressT > 0;
    ctx.fillStyle = '#8E2944';
    ctx.fillRect(dive.x, dive.y + off + 4, dive.w, dive.h - 4);
    ctx.fillStyle = '#E0587C';
    ctx.fillRect(dive.x, dive.y + off + (dp ? 4 : 0), dive.w, dive.h - 4);
    drawText(ctx, 'DIVE', dive.x + dive.w / 2, dive.y + off + (dp ? 4 : 0) + (dive.h - 4) / 2 - 7, 2, '#2A0B16', 'center', 2);

    for (var i = 0; i < keys.length; i++) {
      var k = keys[i], pressed = pressK === k.k && pressT > 0;
      var ky = Math.round(k.y + off), kx = Math.round(k.x), kw = Math.round(k.x + k.w) - kx;
      ctx.fillStyle = KEY_EDGE;
      ctx.fillRect(kx, ky + 3, kw, k.h - 3);
      ctx.fillStyle = pressed ? '#2A4266' : KEY;
      ctx.fillRect(kx, ky + (pressed ? 3 : 0), kw, k.h - 3);
      var s = k.k === 'SP' ? 1 : 2;
      drawText(ctx, k.label, kx + kw / 2, ky + (pressed ? 3 : 0) + (k.h - 3) / 2 - 3.5 * s, s, KEY_TEXT, 'center', k.k === 'SP' ? 3 : 0);
    }
  }

  function drawHint(ctx, W, H) {
    var y = H - D.safe.bottom - 80;
    var text = 'TAP TO DIVE', w = textWidth(text, 2, 3) + 40;
    var pulse = 0.75 + Math.sin(clock * 3) * 0.25;
    panel(ctx, Math.round(W / 2 - w / 2), y, Math.round(w), 40, 'rgba(8,16,30,0.86)');
    ctx.globalAlpha = pulse;
    drawText(ctx, text, W / 2, y + 13, 2, CYAN, 'center', 3);
    ctx.globalAlpha = 1;
  }

  D.game({
    reset: function () {
      ensureLayout();
      var order = [];
      for (var i = 0; i < PROMPTS.length; i++) order.push(i);
      for (var j = order.length - 1; j > 0; j--) {
        var r = Math.floor(D.rand() * (j + 1));
        var tmp = order[j]; order[j] = order[r]; order[r] = tmp;
      }
      prompts = []; banks = [];
      for (var p = 0; p < ROUND; p++) { prompts.push(PROMPTS[order[p]]); banks.push(bankFor(order[p])); }
      idx = 0; phase = 'ready'; phaseT = 0; timeLeft = TIME; input = ''; results = []; points = 0; shown = 0;
      krill = 14; cam = 0; lastCam = 0; clock = 0; msg.t = 0; shakeT = 0; pressK = ''; pressT = 0;
      kbShow = 0; titleA = 1; reveal = null; ended = false; bubbleT = 0;
      botS.wait = 0.9; botS.plan = null; botS.pos = 0;
      bubbles.length = 0;
      seedScene();
    },

    start: function () {
      phase = 'intro';
      phaseT = 0;
      D.haptic('medium');
      D.tone({ freq: 620, slide: 220, dur: 0.4, type: 'triangle', vol: 0.1 });
    },

    update: function (dt, state) {
      ensureLayout();
      clock += dt;
      if (pressT > 0) pressT -= dt;
      if (msg.t > 0) msg.t -= dt;
      if (shakeT > 0) shakeT = Math.max(0, shakeT - dt);

      if (state === 'playing') {
        titleA = Math.max(0, titleA - dt * 3);
        kbShow = Math.min(1, kbShow + dt * 3.5);
        phaseT += dt;
        if (phase === 'intro' && phaseT >= INTRO) { phase = 'answer'; phaseT = 0; }
        else if (phase === 'answer') {
          var before = Math.ceil(timeLeft);
          timeLeft -= dt;
          if (timeLeft > 0 && timeLeft <= 5 && Math.ceil(timeLeft) !== before) {
            D.haptic('select');
            D.tone({ freq: 880, dur: 0.05, type: 'square', vol: 0.05 });
          }
          if (timeLeft <= 0) { timeLeft = 0; finishAnswer(null); }
        } else if (phase === 'reveal' && phaseT >= REVEAL) nextPrompt();
      } else if (state === 'over') {
        kbShow = Math.max(0, kbShow - dt * 2.5);
      }

      var target = points * 10;
      shown += (target - shown) * Math.min(1, dt * 2.2);
      if (Math.abs(target - shown) < 1) shown = target;
      var goal = state === 'ready' ? 14 : Math.max(40, target);
      var prevKrill = krill;
      krill += (goal - krill) * Math.min(1, dt * 2.2);
      cam = Math.max(0, krill - (L.anchorY - L.baseY) / PPM);
      var dc = (cam - lastCam) * PPM;
      lastCam = cam;

      var W = D.W, H = D.H;
      for (var f = 0; f < fish.length; f++) {
        var fi = fish[f];
        fi.x += fi.vx * dt;
        if (fi.vx > 0 && fi.x > W + 30) fi.x = -30;
        if (fi.vx < 0 && fi.x < -30) fi.x = W + 30;
        if (screenY(fi.d) < -40) { fi.d = cam + (H - L.baseY) / PPM + 20 + Math.random() * 300; fi.x = Math.random() * W; }
      }
      for (var n = 0; n < snow.length; n++) {
        var sn = snow[n];
        sn.y += 5 * dt - dc * 0.5;
        if (sn.y < 0) { sn.y += H; sn.x = Math.random() * W; }
        if (sn.y > H) sn.y -= H;
      }
      for (var c = 0; c < clouds.length; c++) {
        clouds[c].x += 4 * clouds[c].s * dt;
        if (clouds[c].x > W + 20) clouds[c].x = -80;
      }
      bubbleT -= dt;
      var sinking = krill - prevKrill > dt * 30;
      if (bubbleT <= 0 && bubbles.length < 40 && state !== 'ready') {
        bubbleT = sinking ? 0.05 : 0.5;
        bubbles.push({ x: W / 2 + Math.sin(clock * 1.3) * 14 - 16 + Math.random() * 10, y: screenY(krill) - 6, r: 1.5 + Math.random() * 2.5, life: 1.6 });
      }
      for (var b = bubbles.length - 1; b >= 0; b--) {
        var bb = bubbles[b];
        bb.y -= 40 * dt + dc;
        bb.x += Math.sin(clock * 4 + b) * 0.3;
        bb.life -= dt;
        if (bb.life <= 0 || bb.y < -10) bubbles.splice(b, 1);
      }
    },

    draw: function (ctx, W, H, state) {
      ensureLayout();
      ctx.imageSmoothingEnabled = false;
      drawScene(ctx, W, H, state);
      if (titleA > 0) drawTitle(ctx, W, titleA);
      if (state !== 'ready') drawHud(ctx, W);
      if (state === 'playing' && phase !== 'done') drawCard(ctx, W);
      if (reveal && phase === 'reveal') drawReveal(ctx, W);
      if (kbShow > 0) drawInput(ctx, W, H);
      if (state === 'ready' && !D.clip) drawHint(ctx, W, H);
      ctx.fillStyle = sprites().scan;
      ctx.fillRect(0, 0, W, H);
    },

    pointerDown: function (x, y, id, first) {
      if (first || kbShow < 0.9) return;
      var k = hit(x, y);
      if (k) press(k);
    },

    key: function (k) {
      if (k === 'Enter') press('GO');
      else if (k === 'Backspace') press('BK');
      else if (k === ' ') press('SP');
      else if (/^[a-zA-Z]$/.test(k)) press(k.toUpperCase());
    },

    bot: function (dt) {
      if (phase !== 'intro' && phase !== 'answer') return;
      botS.wait -= dt;
      if (botS.wait > 0) return;
      if (!botS.plan) { botS.plan = botAnswer(banks[idx]); botS.pos = 0; }
      if (botS.pos < botS.plan.length) {
        var ch = botS.plan.charAt(botS.pos++);
        press(ch === ' ' ? 'SP' : ch);
        botS.wait = 0.06 + Math.random() * 0.06;
      } else {
        press('GO');
        botS.wait = 99;
      }
    },

    resize: function () {
      layout();
      if (prompts) seedScene();
    }
  });
})();
