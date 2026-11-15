// The avatar catalog: every item a Dailie can wear or hold. The app draws each one from the same ids
// (Sources/Avatar/AvatarCatalog.swift), and the server decides prices and ownership from this list.

export type Slot = "body" | "face" | "hair" | "hat" | "outfit" | "gadget" | "decor";
export type Rarity = "common" | "rare" | "epic" | "legendary";
export type Item = { id: string; slot: Slot; name: string; price: number; rarity: Rarity };

export const ITEMS: Item[] = [
  { id: "body.porcelain", slot: "body", name: "Porcelain", price: 0, rarity: "common" },
  { id: "body.peach", slot: "body", name: "Peach", price: 0, rarity: "common" },
  { id: "body.honey", slot: "body", name: "Honey", price: 0, rarity: "common" },
  { id: "body.umber", slot: "body", name: "Umber", price: 0, rarity: "common" },
  { id: "body.cocoa", slot: "body", name: "Cocoa", price: 0, rarity: "common" },
  { id: "body.mint", slot: "body", name: "Mint", price: 0, rarity: "common" },
  { id: "body.sky", slot: "body", name: "Sky", price: 0, rarity: "common" },
  { id: "body.lilac", slot: "body", name: "Lilac", price: 0, rarity: "common" },
  { id: "body.coral", slot: "body", name: "Coral", price: 0, rarity: "common" },
  { id: "body.gold", slot: "body", name: "Gold", price: 0, rarity: "common" },

  { id: "face.happy", slot: "face", name: "Happy", price: 0, rarity: "common" },
  { id: "face.smirk", slot: "face", name: "Smirk", price: 0, rarity: "common" },
  { id: "face.wink", slot: "face", name: "Wink", price: 0, rarity: "common" },
  { id: "face.determined", slot: "face", name: "Determined", price: 0, rarity: "common" },
  { id: "face.sleepy", slot: "face", name: "Sleepy", price: 50, rarity: "common" },
  { id: "face.shades", slot: "face", name: "Cool Shades", price: 150, rarity: "rare" },
  { id: "face.stars", slot: "face", name: "Star Eyes", price: 280, rarity: "epic" },

  { id: "hair.short", slot: "hair", name: "Short Crop", price: 0, rarity: "common" },
  { id: "hair.bob", slot: "hair", name: "Bob", price: 0, rarity: "common" },
  { id: "hair.spiky", slot: "hair", name: "Spiky", price: 0, rarity: "common" },
  { id: "hair.bun", slot: "hair", name: "Top Bun", price: 0, rarity: "common" },
  { id: "hair.buzz", slot: "hair", name: "Buzz", price: 0, rarity: "common" },
  { id: "hair.curly", slot: "hair", name: "Curly", price: 60, rarity: "common" },
  { id: "hair.long", slot: "hair", name: "Long Lilac", price: 90, rarity: "common" },
  { id: "hair.mohawk", slot: "hair", name: "Pink Mohawk", price: 140, rarity: "rare" },

  { id: "hat.party", slot: "hat", name: "Party Hat", price: 60, rarity: "common" },
  { id: "hat.beanie", slot: "hat", name: "Beanie", price: 70, rarity: "common" },
  { id: "hat.cap", slot: "hat", name: "Cap", price: 80, rarity: "common" },
  { id: "hat.catears", slot: "hat", name: "Cat Ears", price: 150, rarity: "rare" },
  { id: "hat.headset", slot: "hat", name: "Gamer Headset", price: 180, rarity: "rare" },
  { id: "hat.halo", slot: "hat", name: "Halo", price: 300, rarity: "epic" },
  { id: "hat.wizard", slot: "hat", name: "Wizard Hat", price: 350, rarity: "epic" },
  { id: "hat.crown", slot: "hat", name: "Crown", price: 800, rarity: "legendary" },
  { id: "hat.bucket", slot: "hat", name: "Bucket Hat", price: 70, rarity: "common" },
  { id: "hat.chef", slot: "hat", name: "Chef Hat", price: 90, rarity: "common" },
  { id: "hat.bunny", slot: "hat", name: "Bunny Ears", price: 120, rarity: "rare" },
  { id: "hat.flowers", slot: "hat", name: "Flower Crown", price: 140, rarity: "rare" },
  { id: "hat.pirate", slot: "hat", name: "Pirate Hat", price: 260, rarity: "epic" },
  { id: "hat.viking", slot: "hat", name: "Viking Helmet", price: 380, rarity: "epic" },

  { id: "outfit.tee", slot: "outfit", name: "Signature Tee", price: 0, rarity: "common" },
  { id: "outfit.overalls", slot: "outfit", name: "Overalls", price: 70, rarity: "common" },
  { id: "outfit.sweater", slot: "outfit", name: "Cozy Sweater", price: 80, rarity: "common" },
  { id: "outfit.hoodie", slot: "outfit", name: "Gold Hoodie", price: 90, rarity: "common" },
  { id: "outfit.tracksuit", slot: "outfit", name: "Tracksuit", price: 140, rarity: "rare" },
  { id: "outfit.varsity", slot: "outfit", name: "Varsity Jacket", price: 160, rarity: "rare" },
  { id: "outfit.cape", slot: "outfit", name: "Hero Cape", price: 200, rarity: "rare" },
  { id: "outfit.tux", slot: "outfit", name: "Tux", price: 320, rarity: "epic" },
  { id: "outfit.astronaut", slot: "outfit", name: "Astronaut Suit", price: 900, rarity: "legendary" },
  { id: "outfit.pajamas", slot: "outfit", name: "Star Pajamas", price: 80, rarity: "common" },
  { id: "outfit.denim", slot: "outfit", name: "Denim Jacket", price: 90, rarity: "common" },
  { id: "outfit.jersey", slot: "outfit", name: "Gold Jersey", price: 120, rarity: "rare" },
  { id: "outfit.puffer", slot: "outfit", name: "Puffer Jacket", price: 150, rarity: "rare" },
  { id: "outfit.dino", slot: "outfit", name: "Dino Onesie", price: 340, rarity: "epic" },

  { id: "gadget.phone", slot: "gadget", name: "Phone", price: 50, rarity: "common" },
  { id: "gadget.controller", slot: "gadget", name: "Controller", price: 60, rarity: "common" },
  { id: "gadget.joystick", slot: "gadget", name: "Joystick", price: 70, rarity: "common" },
  { id: "gadget.boba", slot: "gadget", name: "Bubble Tea", price: 80, rarity: "common" },
  { id: "gadget.mic", slot: "gadget", name: "Microphone", price: 130, rarity: "rare" },
  { id: "gadget.trophy", slot: "gadget", name: "Trophy Cup", price: 260, rarity: "epic" },
  { id: "gadget.goldpad", slot: "gadget", name: "Golden Controller", price: 700, rarity: "legendary" },
  { id: "gadget.icecream", slot: "gadget", name: "Ice Cream", price: 50, rarity: "common" },
  { id: "gadget.balloon", slot: "gadget", name: "Gold Balloon", price: 60, rarity: "common" },
  { id: "gadget.plush", slot: "gadget", name: "Plush Bear", price: 90, rarity: "common" },
  { id: "gadget.camera", slot: "gadget", name: "Camera", price: 120, rarity: "rare" },
  { id: "gadget.wand", slot: "gadget", name: "Star Wand", price: 300, rarity: "epic" },

  { id: "decor.plant", slot: "decor", name: "Potted Plant", price: 40, rarity: "common" },
  { id: "decor.lamp", slot: "decor", name: "Floor Lamp", price: 50, rarity: "common" },
  { id: "decor.rug", slot: "decor", name: "Round Rug", price: 60, rarity: "common" },
  { id: "decor.beanbag", slot: "decor", name: "Bean Bag", price: 70, rarity: "common" },
  { id: "decor.poster", slot: "decor", name: "Game Poster", price: 80, rarity: "common" },
  { id: "decor.fridge", slot: "decor", name: "Mini Fridge", price: 90, rarity: "common" },
  { id: "decor.lavalamp", slot: "decor", name: "Lava Lamp", price: 120, rarity: "rare" },
  { id: "decor.bookshelf", slot: "decor", name: "Bookshelf", price: 140, rarity: "rare" },
  { id: "decor.neon", slot: "decor", name: "GG Neon Sign", price: 180, rarity: "rare" },
  { id: "decor.arcade", slot: "decor", name: "Arcade Cabinet", price: 300, rarity: "epic" },
  { id: "decor.cat", slot: "decor", name: "Pet Cat", price: 360, rarity: "epic" },
  { id: "decor.robot", slot: "decor", name: "Pet Robot", price: 420, rarity: "epic" },
  { id: "decor.goldtrophy", slot: "decor", name: "Gold Trophy Stand", price: 800, rarity: "legendary" },
];

/** Items sold together. Items already owned are left out, and the rest cost 20 percent less. */
export const BUNDLES = [
  { id: "bundle.arcade", name: "Arcade Kid", items: ["hat.headset", "outfit.hoodie", "gadget.controller", "decor.arcade"] },
  { id: "bundle.cozy", name: "Cozy Day", items: ["hat.beanie", "outfit.sweater", "gadget.boba", "decor.beanbag"] },
  { id: "bundle.royal", name: "Royal Court", items: ["hat.crown", "outfit.tux", "gadget.trophy", "decor.goldtrophy"] },
];

/** A room holds this many decor items at once. */
export const ROOM_SPOTS = 4;

export function itemById(id: string) {
  return ITEMS.find((item) => item.id === id);
}

export type Look = { body: string; face: string; hair?: string; hat?: string; outfit?: string; gadget?: string };

const FREE_BODIES = ["body.porcelain", "body.peach", "body.honey", "body.umber", "body.cocoa"];
const FREE_HAIR = ["hair.short", "hair.bob", "hair.spiky", "hair.bun"];

/** Everyone starts with a look picked from their handle, so a new player is never blank. */
export function defaultLook(handle: string): Look {
  let sum = 0;
  for (const char of handle) sum = (sum * 31 + char.charCodeAt(0)) % 100003;
  return {
    body: FREE_BODIES[sum % FREE_BODIES.length],
    face: "face.happy",
    hair: FREE_HAIR[Math.floor(sum / 7) % FREE_HAIR.length],
    outfit: "outfit.tee",
  };
}
