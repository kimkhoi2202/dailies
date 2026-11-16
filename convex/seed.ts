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
  {
    slug: "slip-out",
    title: "Slip Out",
    studio: "Paper Lantern",
    pitch: "Tap the arrow. Mind the way out.",
    how: "Tap an arrow and it slides off the board the way its head points. If another arrow is in the way it bumps back and costs a heart. Clear the board to move up a level before the clock runs out.",
    minPlayers: 1,
    maxPlayers: 1,
    mode: "casual" as const,
    category: "Puzzle",
    unit: "arrows",
    goldPerMinute: 1,
    likes: 275,
    dislikes: 21,
    scores: [47, 71, 39, 26, 55, 64],
  },
  {
    slug: "block-party",
    title: "Block Party",
    studio: "Paper Lantern",
    pitch: "Fill the line. Clear it.",
    how: "Drag a piece from the tray onto the board. A full row or column clears. Clear more than one at once, or several in a row, for a combo. The round ends when none of your pieces fit.",
    minPlayers: 1,
    maxPlayers: 1,
    mode: "casual" as const,
    category: "Puzzle",
    unit: "points",
    goldPerMinute: 1,
    likes: 741,
    dislikes: 42,
    scores: [2680, 1910, 1450, 980, 760, 530],
  },
  {
    slug: "wild-eights",
    title: "Wild Eights",
    studio: "Paper Lantern",
    pitch: "Match the suit. Eights go anywhere.",
    how: "Play a card that matches the top of the pile by suit or number, or draw one. An eight goes on anything and picks the next suit. Empty your hand first.",
    minPlayers: 2,
    maxPlayers: 4,
    mode: "competitive" as const,
    category: "Cards",
    unit: "points",
    goldPerMinute: 1,
    likes: 261,
    dislikes: 22,
    scores: [96, 131, 33, 41, 112, 74],
  },
  {
    slug: "brick-out",
    title: "Brick Out",
    studio: "Paper Lantern",
    pitch: "Slide every brick out.",
    how: "Drag a brick along its row or column. It leaves the board through a gate of its own colour. Clear the board before the clock runs out and before the moves are gone.",
    minPlayers: 1,
    maxPlayers: 1,
    mode: "casual" as const,
    category: "Puzzle",
    unit: "points",
    goldPerMinute: 1,
    likes: 261,
    dislikes: 22,
    scores: [1240, 980, 1510, 640, 870, 1120],
  },
  {
    slug: "daily-grid",
    title: "Daily Grid",
    studio: "Paper Lantern",
    pitch: "Six crowns. No touching.",
    how: "Put one crown in every row, column and colour, with no two crowns touching. Tap once for a cross, twice for a crown. Solve as many boards as you can in three minutes.",
    minPlayers: 1,
    maxPlayers: 4,
    mode: "casual" as const,
    category: "Puzzle",
    unit: "points",
    goldPerMinute: 1,
    likes: 286,
    dislikes: 14,
    scores: [544, 812, 160, 305, 418, 690],
  },
  {
    slug: "letter-rush",
    title: "Letter Rush",
    studio: "Paper Lantern",
    pitch: "Drag a word. Beat the clock.",
    how: "Drag through touching letters to spell a word, diagonals too, then lift to submit. Longer words score more. Same board for both players, 80 seconds.",
    minPlayers: 2,
    maxPlayers: 2,
    mode: "competitive" as const,
    category: "Word",
    unit: "points",
    goldPerMinute: 1.1,
    likes: 275,
    dislikes: 18,
    scores: [2600, 3500, 1900, 1200, 2100, 2900],
  },
  {
    slug: "pour-party",
    title: "Pour Party",
    studio: "Paper Lantern",
    pitch: "Sort the colours. Beat the clock.",
    how: "Tap a tube to lift it, tap another to pour. A colour only pours onto the same colour or into an empty tube. Sort every tube before the clock runs out, then the next level comes.",
    minPlayers: 1,
    maxPlayers: 1,
    mode: "casual" as const,
    category: "Puzzle",
    unit: "points",
    goldPerMinute: 1,
    likes: 276,
    dislikes: 21,
    scores: [700, 1500, 300, 400, 1000, 1200],
  },
  {
    slug: "deep-end",
    title: "Deep End",
    studio: "Paper Lantern",
    pitch: "Rarer answers sink deeper.",
    how: "Each prompt asks for one thing, like a bird or a cheese. Type one answer before the clock runs out. Rarer answers score more and sink the krill deeper. Seven prompts in a round.",
    minPlayers: 1,
    maxPlayers: 4,
    mode: "casual" as const,
    category: "Word",
    unit: "m",
    goldPerMinute: 1,
    likes: 114,
    dislikes: 8,
    scores: [4650, 3610, 5120, 2380, 3940, 2870],
  },
  {
    slug: "jam-slide",
    title: "Jam Slide",
    studio: "Wobble Works",
    pitch: "Every block has its gate.",
    how: "Drag a block along its row or column. It slides out through a gate of its own color. A number on a gate is how many more blocks it lets through. Clear the tray to open the chest.",
    minPlayers: 1,
    maxPlayers: 1,
    mode: "casual" as const,
    category: "Puzzle",
    unit: "points",
    goldPerMinute: 1,
    likes: 234,
    dislikes: 19,
    scores: [2310, 1840, 1420, 1060, 760, 520],
  },
  {
    slug: "bus-rush",
    title: "Bus Rush",
    studio: "Paper Lantern",
    pitch: "Clear the lot. Fill every bus.",
    how: "Tap a bus to drive it out to one of five slots. It only goes if nothing is parked in front of it. Riders board the bus of their colour in queue order, and a full bus leaves. Five slots of buses nobody can board jams the lot.",
    minPlayers: 1,
    maxPlayers: 1,
    mode: "casual" as const,
    category: "Puzzle",
    unit: "riders",
    goldPerMinute: 1,
    likes: 234,
    dislikes: 19,
    scores: [212, 168, 240, 131, 187, 95],
  },
  {
    slug: "corner-pocket",
    title: "Corner Pocket",
    studio: "Paper Lantern",
    pitch: "Sink your group. Then the 8.",
    how: "Drag on the table to aim, then pull the meter down and let go to shoot. Sink a ball to claim solids or stripes, clear your group, then sink the 8. Keep shooting while you sink your own balls.",
    minPlayers: 1,
    maxPlayers: 2,
    mode: "competitive" as const,
    category: "Sports",
    unit: "points",
    goldPerMinute: 1,
    likes: 234,
    dislikes: 19,
    scores: [90, 100, 40, 60, 80, 30],
  },
  {
    slug: "can-cannon",
    title: "Can Cannon",
    studio: "Sandcastle",
    pitch: "Aim low. Knock it all down.",
    how: "Drag back to aim and let go to fire. Knock every can off the shelf with five balls to clear the level. Fewer balls give more stars.",
    minPlayers: 1,
    maxPlayers: 4,
    mode: "casual" as const,
    category: "Arcade",
    unit: "points",
    goldPerMinute: 1,
    likes: 261,
    dislikes: 22,
    scores: [1210, 1480, 760, 540, 990, 310],
  },
  {
    slug: "short-stack",
    title: "Short Stack",
    studio: "Paper Lantern",
    pitch: "Six seats. Three minutes.",
    how: "Texas Hold'em with play chips. Fold, check, call or raise. Make the best five cards from your two and the five on the table. The chips you hold at the end are your score.",
    minPlayers: 1,
    maxPlayers: 6,
    mode: "competitive" as const,
    category: "Cards",
    unit: "chips",
    goldPerMinute: 1,
    likes: 264,
    dislikes: 21,
    scores: [1840, 2460, 920, 1310, 640, 1120],
  },
  {
    slug: "sakura-days",
    title: "Sakura Days",
    studio: "Paper Lantern",
    pitch: "Pick your words. Find your ending.",
    how: "A short anime story. Pick old Kyoto or a modern campus, read along, and choose what to say. Kind choices fill the hearts. Each story has three endings, and your hearts plus your ending make the score.",
    minPlayers: 1,
    maxPlayers: 1,
    mode: "casual" as const,
    category: "Story",
    unit: "points",
    goldPerMinute: 1,
    likes: 198,
    dislikes: 11,
    scores: [460, 580, 300, 400, 640, 520],
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
  "slip-out": ["tapped the one arrow that was blocked. three times", "level nine with two seconds left"],
  "block-party": ["three rows at once and the whole board lit up", "saved the 3x3 for the corner. no regrets"],
  "wild-eights": ["held my eight until the last card. nobody saw it coming", "drew six times in a row and still went out first"],
  "brick-out": ["cleared four boards and lost on the fifth with one move left", "the yellow one was blocking everything the whole time"],
  "daily-grid": ["five boards in three minutes and not one wrong crown", "the lilac region got me twice"],
  "letter-rush": ["found a six letter word with two seconds left", "we had the same board and still found different words"],
  "pour-party": ["level four with two seconds left. my hands were shaking", "used all three undos on one tube"],
  "deep-end": ["typed kakapo and sank straight past the titanic", "blanked on a cheese for twenty seconds and said cheddar"],
  "jam-slide": ["the blue gate said 1 and I used it on the wrong block", "watched the chest open six times in one round"],
  "bus-rush": ["five slots, five wrong colours. never again", "sent the blue bus out first and the whole queue just flowed"],
  "corner-pocket": ["called the 8 off two rails and it dropped", "scratched on the break and still ran the table after"],
  "can-cannon": ["one ball, whole pyramid. still not over it", "the giraffe level took me four tries"],
  "short-stack": ["all in on the last hand with a pair of sevens. it held", "folded four hands, then took the whole table on the fifth"],
  "sakura-days": ["went to get noodles and missed the whole fireworks show", "ren naming his wooden sword after me is the best thing in this app"],
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
