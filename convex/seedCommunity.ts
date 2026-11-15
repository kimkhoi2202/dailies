import type { Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";

// Seeds Community so the demo looks alive on first open: six friends, a day of posts across our games,
// ratings, two games friends are playing now, and two open challenges.
// Run with: npx convex run seedCommunity:run (after seed:run, which adds the games).

const FRIENDS = [
  { name: "Khoi", color: "#4C9AFF", streak: 9 },
  { name: "Ben", color: "#FF6B57", streak: 3 },
  { name: "Dylan", color: "#19B8A6", streak: 12 },
  { name: "Nyx", color: "#7C5CFF", streak: 6 },
  { name: "Kiko", color: "#FF7AB6", streak: 2 },
  { name: "Vanessa", color: "#F5B301", streak: 5 },
];

type Kind = "best" | "passed" | "rated" | "streak" | "video" | "game";
type Seeded = { who: string; kind: Kind; game: string; score?: number; text?: string; unit?: string; rating?: number; minutesAgo: number };

const POSTS: Seeded[] = [
  { who: "Dylan", kind: "best", game: "five-up", score: 1125, text: "1,125", unit: "points", minutesAgo: 12 },
  { who: "Ben", kind: "passed", game: "spiral-drop", score: 23, text: "23", unit: "floors", minutesAgo: 34 },
  { who: "Khoi", kind: "rated", game: "gulp-city", rating: 8.7, minutesAgo: 51 },
  { who: "Vanessa", kind: "streak", game: "tippy-tower", score: 5, text: "5", minutesAgo: 75 },
  { who: "Nyx", kind: "video", game: "lane-dash", score: 2840, text: "2,840", unit: "m", minutesAgo: 96 },
  { who: "Kiko", kind: "best", game: "tippy-tower", score: 76, text: "76", unit: "floors", minutesAgo: 130 },
  { who: "Khoi", kind: "best", game: "inkland", score: 34.2, text: "34.2%", unit: "of the map", minutesAgo: 170 },
  { who: "Ben", kind: "rated", game: "five-up", rating: 9.4, minutesAgo: 215 },
  { who: "Dylan", kind: "video", game: "gulp-city", score: 87, text: "87%", unit: "of the block", minutesAgo: 260 },
  { who: "Vanessa", kind: "best", game: "spiral-drop", score: 31, text: "31", unit: "floors", minutesAgo: 330 },
  { who: "Nyx", kind: "rated", game: "tippy-tower", rating: 8.9, minutesAgo: 420 },
  { who: "Kiko", kind: "passed", game: "lane-dash", score: 3110, text: "3,110", unit: "m", minutesAgo: 510 },
  { who: "Khoi", kind: "game", game: "spiral-drop", minutesAgo: 640 },
  { who: "Ben", kind: "best", game: "gulp-city", score: 92, text: "92%", unit: "of the block", minutesAgo: 800 },
  { who: "Dylan", kind: "rated", game: "lane-dash", rating: 7.9, minutesAgo: 900 },
  { who: "Vanessa", kind: "rated", game: "inkland", rating: 7.6, minutesAgo: 1000 },
];

const RATINGS: { who: string; game: string; band: "loved" | "fine" | "not"; score: number }[] = [
  { who: "Khoi", game: "gulp-city", band: "loved", score: 8.7 },
  { who: "Khoi", game: "five-up", band: "loved", score: 9.0 },
  { who: "Ben", game: "five-up", band: "loved", score: 9.4 },
  { who: "Ben", game: "tippy-tower", band: "loved", score: 8.4 },
  { who: "Nyx", game: "tippy-tower", band: "loved", score: 8.9 },
  { who: "Nyx", game: "spiral-drop", band: "loved", score: 8.4 },
  { who: "Dylan", game: "lane-dash", band: "fine", score: 7.9 },
  { who: "Vanessa", game: "inkland", band: "fine", score: 7.6 },
  { who: "Kiko", game: "five-up", band: "loved", score: 8.9 },
];

const LIVE: { who: string; game: string }[] = [
  { who: "Dylan", game: "inkland" },
  { who: "Kiko", game: "inkland" },
  { who: "Nyx", game: "inkland" },
  { who: "Ben", game: "five-up" },
  { who: "Khoi", game: "five-up" },
];

const REACTIONS = ["gg", "fire", "crown", "clap"] as const;

export const run = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const ids = new Map<string, Id<"users">>();
    for (const friend of FRIENDS) {
      const handle = friend.name.toLowerCase();
      const existing = await ctx.db
        .query("users")
        .withIndex("by_handle", (q) => q.eq("handle", handle))
        .unique();
      const id =
        existing?._id ??
        (await ctx.db.insert("users", {
          name: friend.name,
          handle,
          color: friend.color,
          gold: 0,
          goldAllTime: 0,
          rounds: 0,
          streak: friend.streak,
          fastGold: false,
          seeded: true,
        }));
      ids.set(friend.name, id);
    }
    const friendIds = [...ids.values()];

    // Clear what an earlier run of this seed wrote, so it can be run again for a fresh demo.
    for (const userId of friendIds) {
      const posts = await ctx.db
        .query("posts")
        .withIndex("by_userId_and_at", (q) => q.eq("userId", userId))
        .take(200);
      for (const post of posts) {
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_postId", (q) => q.eq("postId", post._id))
          .take(500);
        for (const row of reactions) await ctx.db.delete("reactions", row._id);
        await ctx.db.delete("posts", post._id);
      }
      const presence = await ctx.db
        .query("presence")
        .withIndex("by_userId", (q) => q.eq("userId", userId))
        .unique();
      if (presence) await ctx.db.delete("presence", presence._id);
    }
    const oldChallenges = await ctx.db.query("challenges").withIndex("by_status_and_expiresAt", (q) => q.eq("status", "open")).take(200);
    for (const row of oldChallenges) if (friendIds.includes(row.fromId)) await ctx.db.delete("challenges", row._id);

    for (const [index, post] of POSTS.entries()) {
      const userId = ids.get(post.who)!;
      const postId = await ctx.db.insert("posts", {
        userId,
        kind: post.kind,
        gameSlug: post.game,
        score: post.score,
        scoreText: post.text,
        unit: post.unit,
        rating: post.rating,
        at: now - post.minutesAgo * 60_000,
      });
      // A few friends react to each post.
      for (const [offset, other] of friendIds.entries()) {
        if (other === userId || (index + offset) % 3 === 0) continue;
        await ctx.db.insert("reactions", { postId, userId: other, kind: REACTIONS[(index + offset) % REACTIONS.length] });
      }
    }

    for (const rating of RATINGS) {
      const userId = ids.get(rating.who)!;
      const existing = await ctx.db
        .query("ratings")
        .withIndex("by_userId_and_gameSlug", (q) => q.eq("userId", userId).eq("gameSlug", rating.game))
        .unique();
      if (existing) await ctx.db.patch("ratings", existing._id, { band: rating.band, score: rating.score });
      else await ctx.db.insert("ratings", { userId, gameSlug: rating.game, band: rating.band, rank: 0, score: rating.score });
    }

    // Demo presence lasts the day, so the live row stays full for judging. Real presence is a 60 second heartbeat.
    for (const entry of LIVE) {
      await ctx.db.insert("presence", { userId: ids.get(entry.who)!, gameSlug: entry.game, lastSeen: now + 12 * 3600_000 });
    }

    await ctx.db.insert("challenges", {
      fromId: ids.get("Khoi")!,
      gameSlug: "tippy-tower",
      target: 76,
      targetText: "76",
      unit: "floors",
      expiresAt: now + (5 * 3600 + 42 * 60) * 1000,
      status: "open",
    });
    await ctx.db.insert("challenges", {
      fromId: ids.get("Vanessa")!,
      gameSlug: "five-up",
      target: 1200,
      targetText: "1,200",
      unit: "points",
      expiresAt: now + 20 * 3600_000,
      status: "open",
    });

    return { friends: friendIds.length, posts: POSTS.length, ratings: RATINGS.length, live: LIVE.length, challenges: 2 };
  },
});
