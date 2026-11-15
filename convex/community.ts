import { ConvexError, v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { ratingBand, reactionKind } from "./communitySchema";
import { currentUser, gameBySlug, requireUser } from "./lib";

// COMMUNITY: friends' posts, reactions, ratings, challenges, who is live and notifications.
// Posts for new bests and streaks are written by the server when a round finishes (see recordRound),
// so a phone cannot make them up.

const LIVE_WINDOW_MS = 60_000;
const REACTIONS = ["gg", "fire", "crown", "clap"] as const;

export const feed = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentUser(ctx);
    const posts = await ctx.db.query("posts").withIndex("by_at").order("desc").take(40);
    return await Promise.all(
      posts.map(async (post) => {
        const author = await ctx.db.get("users", post.userId);
        const rows = await ctx.db
          .query("reactions")
          .withIndex("by_postId", (q) => q.eq("postId", post._id))
          .take(500);
        const reactions: Record<string, number> = { gg: 0, fire: 0, crown: 0, clap: 0 };
        for (const row of rows) reactions[row.kind] = (reactions[row.kind] ?? 0) + 1;
        const comments = await ctx.db
          .query("postComments")
          .withIndex("by_postId", (q) => q.eq("postId", post._id))
          .take(100);
        return {
          _id: post._id,
          name: author?.name ?? "someone",
          own: me !== null && post.userId === me._id,
          kind: post.kind,
          gameSlug: post.gameSlug,
          score: post.score ?? null,
          scoreText: post.scoreText ?? null,
          unit: post.unit ?? null,
          rating: post.rating ?? null,
          at: post.at,
          reactions,
          mine: me === null ? [] : rows.filter((row) => row.userId === me._id).map((row) => row.kind),
          comments: comments.length,
        };
      }),
    );
  },
});

/** Everything above the feed: who is live, open challenges, notifications and what friends rate each game. */
export const home = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentUser(ctx);
    const now = Date.now();

    const present = await ctx.db
      .query("presence")
      .withIndex("by_lastSeen", (q) => q.gt("lastSeen", now - LIVE_WINDOW_MS))
      .take(100);
    const byGame = new Map<string, string[]>();
    for (const row of present) {
      if (me !== null && row.userId === me._id) continue;
      const user = await ctx.db.get("users", row.userId);
      if (user === null) continue;
      byGame.set(row.gameSlug, [...(byGame.get(row.gameSlug) ?? []), user.name]);
    }
    const live = [...byGame.entries()]
      .map(([gameSlug, names]) => ({ gameSlug, names }))
      .sort((a, b) => b.names.length - a.names.length)
      .slice(0, 3);

    const open = await ctx.db
      .query("challenges")
      .withIndex("by_status_and_expiresAt", (q) => q.eq("status", "open").gt("expiresAt", now))
      .take(20);
    const challenges = [];
    for (const row of open) {
      if (me !== null && (row.fromId === me._id || (row.toId !== undefined && row.toId !== me._id))) continue;
      if (me === null && row.toId !== undefined) continue;
      const from = await ctx.db.get("users", row.fromId);
      challenges.push({
        _id: row._id,
        from: from?.name ?? "A friend",
        gameSlug: row.gameSlug,
        targetText: row.targetText,
        unit: row.unit,
        expiresAt: row.expiresAt,
      });
    }

    const notes =
      me === null
        ? []
        : await ctx.db
            .query("notifications")
            .withIndex("by_userId_and_at", (q) => q.eq("userId", me._id))
            .order("desc")
            .take(20);

    const games = await ctx.db.query("games").take(50);
    const friendRatings = [];
    for (const game of games) {
      const rows = await ctx.db
        .query("ratings")
        .withIndex("by_gameSlug", (q) => q.eq("gameSlug", game.slug))
        .take(200);
      if (rows.length === 0) continue;
      const average = rows.reduce((sum, row) => sum + row.score, 0) / rows.length;
      friendRatings.push({ gameSlug: game.slug, score: Math.round(average * 10) / 10, count: rows.length });
    }

    return {
      live,
      challenges: challenges.slice(0, 3),
      notifications: notes.map((row) => ({
        _id: row._id,
        name: row.actorName,
        kind: row.kind,
        text: row.text,
        at: row.at,
        read: row.read,
        gameSlug: row.gameSlug ?? null,
      })),
      friendRatings,
    };
  },
});

export const unreadCount = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentUser(ctx);
    if (me === null) return 0;
    const rows = await ctx.db
      .query("notifications")
      .withIndex("by_userId_and_read", (q) => q.eq("userId", me._id).eq("read", false))
      .take(100);
    return rows.length;
  },
});

/** Adds a reaction, or takes it back when it is already there. */
export const react = mutation({
  args: { postId: v.id("posts"), kind: reactionKind },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const post = await ctx.db.get("posts", args.postId);
    if (post === null) throw new ConvexError("No such post");
    const existing = await ctx.db
      .query("reactions")
      .withIndex("by_postId_and_userId_and_kind", (q) =>
        q.eq("postId", args.postId).eq("userId", user._id).eq("kind", args.kind),
      )
      .unique();
    if (existing) {
      await ctx.db.delete("reactions", existing._id);
      return false;
    }
    await ctx.db.insert("reactions", { postId: args.postId, userId: user._id, kind: args.kind });
    if (post.userId !== user._id) {
      await notify(ctx, post.userId, user.name, "reaction", reactionText(user.name, args.kind), post.gameSlug);
    }
    return true;
  },
});

export const comment = mutation({
  args: { postId: v.id("posts"), body: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const post = await ctx.db.get("posts", args.postId);
    if (post === null) throw new ConvexError("No such post");
    const body = args.body.trim().slice(0, 280);
    if (body.length === 0) throw new ConvexError("Empty comment");
    await ctx.db.insert("postComments", { postId: args.postId, userId: user._id, body });
    if (post.userId !== user._id) {
      await notify(ctx, post.userId, user.name, "comment", user.name + " commented: " + body.slice(0, 60), post.gameSlug);
    }
    return null;
  },
});

/** Saves the player's rating of a game and posts it to friends. */
export const rate = mutation({
  args: { slug: v.string(), band: ratingBand, rank: v.number(), score: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.slug);
    const score = Math.round(Math.max(0, Math.min(10, args.score)) * 10) / 10;
    const rank = Math.max(0, Math.round(args.rank));
    const existing = await ctx.db
      .query("ratings")
      .withIndex("by_userId_and_gameSlug", (q) => q.eq("userId", user._id).eq("gameSlug", game.slug))
      .unique();
    if (existing) await ctx.db.patch("ratings", existing._id, { band: args.band, rank, score });
    else await ctx.db.insert("ratings", { userId: user._id, gameSlug: game.slug, band: args.band, rank, score });
    await ctx.db.insert("posts", { userId: user._id, kind: "rated", gameSlug: game.slug, rating: score, at: Date.now() });
    return score;
  },
});

/** Challenges a friend, or everyone when no friend is named, to beat a score within a day. */
export const challenge = mutation({
  args: { slug: v.string(), target: v.number(), targetText: v.string(), unit: v.string(), to: v.optional(v.id("users")) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.slug);
    const id = await ctx.db.insert("challenges", {
      fromId: user._id,
      toId: args.to,
      gameSlug: game.slug,
      target: args.target,
      targetText: args.targetText.slice(0, 20),
      unit: args.unit.slice(0, 20),
      expiresAt: Date.now() + 24 * 3600 * 1000,
      status: "open",
    });
    if (args.to !== undefined) {
      await notify(ctx, args.to, user.name, "challenge",
        user.name + " challenged you to beat " + args.targetText + " " + args.unit + " in " + game.title, game.slug);
    }
    return id;
  },
});

export const accept = mutation({
  args: { challengeId: v.id("challenges") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const row = await ctx.db.get("challenges", args.challengeId);
    if (row === null || row.status !== "open") throw new ConvexError("No such challenge");
    if (row.toId !== undefined && row.toId !== user._id) throw new ConvexError("Not your challenge");
    if (row.toId !== undefined) await ctx.db.patch("challenges", row._id, { status: "accepted" });
    return row.gameSlug;
  },
});

/** Called every few seconds while a game is open, so friends see who is playing what. */
export const heartbeat = mutation({
  args: { slug: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.slug);
    const existing = await ctx.db
      .query("presence")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .unique();
    if (existing) await ctx.db.patch("presence", existing._id, { gameSlug: game.slug, lastSeen: Date.now() });
    else await ctx.db.insert("presence", { userId: user._id, gameSlug: game.slug, lastSeen: Date.now() });
    return null;
  },
});

export const markRead = mutation({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    const rows = await ctx.db
      .query("notifications")
      .withIndex("by_userId_and_read", (q) => q.eq("userId", user._id).eq("read", false))
      .take(100);
    for (const row of rows) await ctx.db.patch("notifications", row._id, { read: true });
    return null;
  },
});

export const follow = mutation({
  args: { to: v.id("users") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (args.to === user._id) return null;
    const existing = await ctx.db
      .query("follows")
      .withIndex("by_fromId_and_toId", (q) => q.eq("fromId", user._id).eq("toId", args.to))
      .unique();
    if (existing) return null;
    await ctx.db.insert("follows", { fromId: user._id, toId: args.to });
    await notify(ctx, args.to, user.name, "follow", user.name + " started following you");
    return null;
  },
});

/**
 * Called by rounds:finish. Writes the post for a new best, the streak post when the streak grows,
 * and tells friends whose best this round passed. Gold is not touched here.
 */
export async function recordRound(
  ctx: MutationCtx,
  user: Doc<"users">,
  game: Doc<"games">,
  round: { score: number; scoreText?: string; unit?: string; newBest: boolean; streak: number; streakGrew: boolean },
) {
  const now = Date.now();
  if (round.newBest && round.score > 0) {
    await ctx.db.insert("posts", {
      userId: user._id,
      kind: "best",
      gameSlug: game.slug,
      score: round.score,
      scoreText: round.scoreText,
      unit: round.unit ?? game.unit,
      at: now,
    });
    const passed = await ctx.db
      .query("bests")
      .withIndex("by_gameSlug_and_score", (q) => q.eq("gameSlug", game.slug).lt("score", round.score))
      .order("desc")
      .take(3);
    for (const best of passed) {
      if (best.userId === user._id) continue;
      await notify(ctx, best.userId, user.name, "passed",
        user.name + " passed your best in " + game.title, game.slug);
    }
  }
  if (round.streakGrew && round.streak >= 2) {
    await ctx.db.insert("posts", {
      userId: user._id,
      kind: "streak",
      gameSlug: game.slug,
      score: round.streak,
      scoreText: String(round.streak),
      at: now + 1,
    });
  }
  const presence = await ctx.db
    .query("presence")
    .withIndex("by_userId", (q) => q.eq("userId", user._id))
    .unique();
  if (presence) await ctx.db.patch("presence", presence._id, { gameSlug: game.slug, lastSeen: now });
}

async function notify(
  ctx: MutationCtx,
  userId: Id<"users">,
  actorName: string,
  kind: string,
  text: string,
  gameSlug?: string,
) {
  await ctx.db.insert("notifications", { userId, actorName, kind, text, gameSlug, read: false, at: Date.now() });
}

function reactionText(name: string, kind: (typeof REACTIONS)[number]) {
  switch (kind) {
    case "gg":
      return name + " said GG on your run";
    case "fire":
      return name + " thinks your run is fire";
    case "crown":
      return name + " crowned your run";
    case "clap":
      return name + " clapped for your run";
  }
}
