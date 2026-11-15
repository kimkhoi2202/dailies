// The avatar catalog: every item a Dailie can wear or hold. The app draws each one from the same ids
// (Sources/Avatar/AvatarCatalog.swift), and the server decides prices and ownership from this list.

export type Slot = "body" | "face" | "hair" | "hat" | "outfit" | "gadget";
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

  { id: "outfit.tee", slot: "outfit", name: "Signature Tee", price: 0, rarity: "common" },
  { id: "outfit.overalls", slot: "outfit", name: "Overalls", price: 70, rarity: "common" },
  { id: "outfit.sweater", slot: "outfit", name: "Cozy Sweater", price: 80, rarity: "common" },
  { id: "outfit.hoodie", slot: "outfit", name: "Gold Hoodie", price: 90, rarity: "common" },
  { id: "outfit.tracksuit", slot: "outfit", name: "Tracksuit", price: 140, rarity: "rare" },
  { id: "outfit.varsity", slot: "outfit", name: "Varsity Jacket", price: 160, rarity: "rare" },
  { id: "outfit.cape", slot: "outfit", name: "Hero Cape", price: 200, rarity: "rare" },
  { id: "outfit.tux", slot: "outfit", name: "Tux", price: 320, rarity: "epic" },
  { id: "outfit.astronaut", slot: "outfit", name: "Astronaut Suit", price: 900, rarity: "legendary" },

  { id: "gadget.phone", slot: "gadget", name: "Phone", price: 50, rarity: "common" },
  { id: "gadget.controller", slot: "gadget", name: "Controller", price: 60, rarity: "common" },
  { id: "gadget.joystick", slot: "gadget", name: "Joystick", price: 70, rarity: "common" },
  { id: "gadget.boba", slot: "gadget", name: "Bubble Tea", price: 80, rarity: "common" },
  { id: "gadget.mic", slot: "gadget", name: "Microphone", price: 130, rarity: "rare" },
  { id: "gadget.trophy", slot: "gadget", name: "Trophy Cup", price: 260, rarity: "epic" },
  { id: "gadget.goldpad", slot: "gadget", name: "Golden Controller", price: 700, rarity: "legendary" },
];

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
