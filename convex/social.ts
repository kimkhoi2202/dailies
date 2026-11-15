import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { currentUser, gameBySlug, requireUser } from "./lib";

export const vote = mutation({
  args: { slug: v.string(), value: v.union(v.literal(1), v.literal(-1), v.literal(0)) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.slug);
    const existing = await ctx.db
      .query("votes")
      .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id).eq("gameSlug", game.slug))
      .unique();
    const before = existing?.value ?? 0;
    if (before === args.value) return null;
    if (existing && args.value === 0) await ctx.db.delete("votes", existing._id);
    else if (existing && args.value !== 0) await ctx.db.patch("votes", existing._id, { value: args.value });
    else if (args.value !== 0) await ctx.db.insert("votes", { userId: user._id, gameSlug: game.slug, value: args.value });
    await ctx.db.patch("games", game._id, {
      likes: game.likes + (args.value === 1 ? 1 : 0) - (before === 1 ? 1 : 0),
      dislikes: game.dislikes + (args.value === -1 ? 1 : 0) - (before === -1 ? 1 : 0),
    });
    return null;
  },
});

export const comments = query({
  args: { slug: v.string() },
  handler: async (ctx, args) => {
    const me = await currentUser(ctx);
    const rows = await ctx.db
      .query("comments")
      .withIndex("by_gameSlug", (q) => q.eq("gameSlug", args.slug))
      .order("desc")
      .take(50);
    return await Promise.all(
      rows.map(async (row) => {
        const author = await ctx.db.get("users", row.userId);
        return {
          _id: row._id,
          body: row.body,
          at: row._creationTime,
          handle: author?.handle ?? "someone",
          color: author?.color ?? "#7C5CFF",
          mine: me !== null && row.userId === me._id,
        };
      }),
    );
  },
});

export const addComment = mutation({
  args: { slug: v.string(), body: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.slug);
    const body = args.body.trim();
    if (body.length === 0 || body.length > 280) throw new ConvexError("Comments are 1 to 280 characters");
    await ctx.db.insert("comments", { gameSlug: game.slug, userId: user._id, body });
    await ctx.db.patch("games", game._id, { comments: game.comments + 1 });
    return null;
  },
});

export const leaderboard = query({
  args: { slug: v.string() },
  handler: async (ctx, args) => {
    const me = await currentUser(ctx);
    const rows = await ctx.db
      .query("bests")
      .withIndex("by_gameSlug_and_score", (q) => q.eq("gameSlug", args.slug))
      .order("desc")
      .take(25);
    return await Promise.all(
      rows.map(async (row, index) => {
        const player = await ctx.db.get("users", row.userId);
        return {
          rank: index + 1,
          score: row.score,
          handle: player?.handle ?? "someone",
          color: player?.color ?? "#7C5CFF",
          you: me !== null && row.userId === me._id,
        };
      }),
    );
  },
});
