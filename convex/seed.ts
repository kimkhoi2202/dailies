import type { Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";

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
];

const PLAYERS = [
  { handle: "devon.plays", color: "#19B8A6" },
  { handle: "kaz", color: "#7C5CFF" },
  { handle: "noor.runs", color: "#FF6B57" },
  { handle: "tofu", color: "#FF9F43" },
  { handle: "juno", color: "#8BC34A" },
  { handle: "wordnerd.sam", color: "#FF7AB6" },
];

const COMMENTS: Record<string, string[]> = {
  "tippy-tower": ["the slab at floor 30 had no business landing like that", "held my breath for the whole last ten floors", "tried it straight after. 14 floors"],
  "five-up": ["got it in three and my group chat is furious", "two minutes left and I blanked on a word I use daily"],
  "spiral-drop": ["eleven floors without touching red", "the combo smash is the best feeling in this app"],
  "gulp-city": ["swallowed the whole block with two seconds left", "started with a flower, ended with a bus"],
  inkland: ["took a fifth of the map in one loop", "got cut one step from home. again"],
  "lane-dash": ["the near miss at the end. I stopped breathing", "ramp into three gems into a barrier. classic"],
  "block-party": ["three rows at once and the whole board lit up", "saved the 3x3 for the corner. no regrets"],
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
