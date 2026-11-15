import type { Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import { itemById } from "./items";

const GAMES = [
  {
    slug: "tippy-tower",
    title: "Tippy Tower",
    studio: "Wobble Works",
    pitch: "Stack it straight.",
    how: "Tap to drop the sliding slab. Whatever hangs over the edge is cut off, so the next slab is smaller. Line it up almost exactly for a perfect.",
    minPlayers: 1,
    maxPlayers: 4,
    mode: "casual" as const,
    category: "Arcade",
    unit: "floors",
    goldPerMinute: 1,
    likes: 1480,
    dislikes: 96,
    scores: [58, 49, 37, 33, 29, 22],
  },
  {
    slug: "five-up",
    title: "Five Up",
    studio: "Paper Lantern",
    pitch: "One word, six tries, three minutes.",
    how: "Guess the five-letter word. Teal means right spot, coral means wrong spot, dark means not in the word. Fewer tries score more.",
    minPlayers: 2,
    maxPlayers: 2,
    mode: "competitive" as const,
    category: "Word",
    unit: "points",
    goldPerMinute: 1.1,
    likes: 674,
    dislikes: 35,
    scores: [1210, 1385, 80, 725, 960, 1640],
  },
  {
    slug: "spiral-drop",
    title: "Spiral Drop",
    studio: "Wobble Works",
    pitch: "Fall with style.",
    how: "Drag to spin the tower so the ball falls through the gaps. Fall two floors or more without bouncing for a combo. Do not land on red.",
    minPlayers: 1,
    maxPlayers: 2,
    mode: "casual" as const,
    category: "Arcade",
    unit: "points",
    goldPerMinute: 0.9,
    likes: 974,
    dislikes: 81,
    scores: [651, 742, 434, 371, 196, 518],
  },
  {
    slug: "gulp-city",
    title: "Gulp City",
    studio: "Nine Lives",
    pitch: "Start with flowers. End with the skyline.",
    how: "Drag to move the hole. Small things fall in first. The hole grows as it eats, until it can swallow cars, buses and buildings.",
    minPlayers: 2,
    maxPlayers: 4,
    mode: "casual" as const,
    category: "Casual",
    unit: "%",
    goldPerMinute: 1,
    likes: 402,
    dislikes: 39,
    scores: [52, 38, 61, 87, 74, 24],
  },
  {
    slug: "inkland",
    title: "Inkland",
    studio: "Nine Lives",
    pitch: "Draw a loop. Keep what is inside.",
    how: "Drag to steer. Leave your land to draw a loop, then come home to claim everything inside it. Cross an open trail to cut it.",
    minPlayers: 4,
    maxPlayers: 6,
    mode: "competitive" as const,
    category: "Multiplayer",
    unit: "%",
    goldPerMinute: 1.2,
    likes: 338,
    dislikes: 76,
    // Share of the land in tenths of a percent, the way the game reports it.
    scores: [236, 281, 152, 174, 342, 96],
  },
  {
    slug: "lane-dash",
    title: "Lane Dash",
    studio: "Second Wind",
    pitch: "Three lanes. No brakes.",
    how: "Swipe to change lane. Dodge the barriers, pick up gems and take ramps for a boost. A late dodge is a near miss and adds distance.",
    minPlayers: 2,
    maxPlayers: 6,
    mode: "competitive" as const,
    category: "Runner",
    unit: "m",
    goldPerMinute: 1,
    likes: 729,
    dislikes: 94,
    scores: [1980, 1650, 2410, 760, 1180, 420],
  },
];

const PLAYERS = [
  { handle: "devon.plays", color: "#19B8A6" },
  { handle: "kaz", color: "#7C5CFF" },
  { handle: "noor.runs", color: "#FF6B57" },
  { handle: "tofu", color: "#FF9F43" },
  { handle: "juno", color: "#8BC34A" },
  { handle: "wordnerd.sam", color: "#FF7AB6" },
];

/** Fun looks for the seeded players, so visiting a friend's profile looks good in the demo. */
const LOOKS: Record<string, { body: string; face: string; hair?: string; hat?: string; outfit?: string; gadget?: string }> = {
  "devon.plays": { body: "body.honey", face: "face.wink", hair: "hair.spiky", hat: "hat.headset", outfit: "outfit.hoodie", gadget: "gadget.controller" },
  kaz: { body: "body.lilac", face: "face.shades", hair: "hair.mohawk", outfit: "outfit.varsity", gadget: "gadget.mic" },
  "noor.runs": { body: "body.cocoa", face: "face.determined", hair: "hair.bun", hat: "hat.cap", outfit: "outfit.tracksuit", gadget: "gadget.phone" },
  tofu: { body: "body.peach", face: "face.happy", hair: "hair.bob", hat: "hat.catears", outfit: "outfit.sweater", gadget: "gadget.boba" },
  juno: { body: "body.mint", face: "face.stars", hair: "hair.curly", hat: "hat.crown", outfit: "outfit.cape", gadget: "gadget.trophy" },
  "wordnerd.sam": { body: "body.porcelain", face: "face.sleepy", hair: "hair.long", hat: "hat.wizard", outfit: "outfit.tux", gadget: "gadget.joystick" },
};

const ROOMS: Record<string, string[]> = {
  "devon.plays": ["decor.arcade", "decor.neon", "decor.beanbag", "decor.lamp"],
  kaz: ["decor.lavalamp", "decor.poster", "decor.robot", "decor.rug"],
  "noor.runs": ["decor.plant", "decor.bookshelf", "decor.fridge"],
  tofu: ["decor.cat", "decor.beanbag", "decor.plant", "decor.rug"],
  juno: ["decor.goldtrophy", "decor.neon", "decor.lamp", "decor.plant"],
  "wordnerd.sam": ["decor.bookshelf", "decor.lavalamp", "decor.cat"],
};

const COMMENTS: Record<string, string[]> = {
  "tippy-tower": ["the slab at floor 30 had no business landing like that", "held my breath for the whole last ten floors", "tried it straight after. 14 floors"],
  "five-up": ["got it in three and my group chat is furious", "two minutes left and I blanked on a word I use daily"],
  "spiral-drop": ["eleven floors without touching red", "the combo smash is the best feeling in this app"],
  "gulp-city": ["swallowed the whole block with two seconds left", "started with a flower, ended with a bus"],
  inkland: ["took a fifth of the map in one loop", "got cut one step from home. again"],
  "lane-dash": ["the near miss at the end. I stopped breathing", "ramp into three gems into a barrier. classic"],
};

export const run = internalMutation({
  args: {},
  handler: async (ctx) => {
    const playerIds: Id<"users">[] = [];
    for (const player of PLAYERS) {
      const existing = await ctx.db
        .query("users")
        .withIndex("by_handle", (q) => q.eq("handle", player.handle))
        .unique();
      playerIds.push(
        existing?._id ??
          (await ctx.db.insert("users", {
            name: player.handle,
            handle: player.handle,
            color: player.color,
            gold: 0,
            goldAllTime: 0,
            rounds: 0,
            streak: 0,
            fastGold: false,
            seeded: true,
          })),
      );
    }

    for (const [index, player] of PLAYERS.entries()) {
      const look = LOOKS[player.handle];
      if (!look) continue;
      const decor = ROOMS[player.handle] ?? [];
      await ctx.db.patch("users", playerIds[index], { avatar: look, room: { decor } });
      for (const itemId of [...Object.values(look), ...decor]) {
        const item = itemById(itemId);
        if (!item || item.price === 0) continue;
        const owned = await ctx.db
          .query("inventory")
          .withIndex("by_user_and_item", (q) => q.eq("userId", playerIds[index]).eq("itemId", itemId))
          .unique();
        if (owned === null) await ctx.db.insert("inventory", { userId: playerIds[index], itemId, price: item.price });
      }
    }

    let created = 0;
    for (const [order, entry] of GAMES.entries()) {
      const { scores, likes, dislikes, ...fields } = entry;
      const existing = await ctx.db
        .query("games")
        .withIndex("by_slug", (q) => q.eq("slug", entry.slug))
        .unique();
      if (existing) {
        await ctx.db.patch("games", existing._id, { ...fields, order, plays: Math.max(existing.plays, likes * 9) });
        for (const [index, score] of scores.entries()) {
          const best = await ctx.db
            .query("bests")
            .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", playerIds[index]).eq("gameSlug", entry.slug))
            .unique();
          if (best) await ctx.db.patch("bests", best._id, { score });
          else await ctx.db.insert("bests", { userId: playerIds[index], gameSlug: entry.slug, score, day: "2026-11-15" });
        }
        continue;
      }
      created += 1;
      const lines = COMMENTS[entry.slug] ?? [];
      await ctx.db.insert("games", { ...fields, order, likes, dislikes, plays: likes * 9, comments: lines.length });
      for (const [index, score] of scores.entries()) {
        await ctx.db.insert("bests", { userId: playerIds[index], gameSlug: entry.slug, score, day: "2026-11-15" });
      }
      for (const [index, body] of lines.entries()) {
        await ctx.db.insert("comments", { gameSlug: entry.slug, userId: playerIds[(index + order) % playerIds.length], body });
      }
    }
    return { games: GAMES.length, created };
  },
});
