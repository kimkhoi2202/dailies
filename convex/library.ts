import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { currentUser, gameBySlug, requireUser } from "./lib";

export const mySaved = query({
  args: {},
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return [];
    const rows = await ctx.db
      .query("saved")
      .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id))
      .take(100);
    return rows.map((row) => row.gameSlug);
  },
});

export const toggleSave = mutation({
  args: { slug: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.slug);
    const existing = await ctx.db
      .query("saved")
      .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id).eq("gameSlug", game.slug))
      .unique();
    if (existing !== null) {
      await ctx.db.delete("saved", existing._id);
      return false;
    }
    await ctx.db.insert("saved", { userId: user._id, gameSlug: game.slug });
    return true;
  },
});
