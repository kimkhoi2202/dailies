import { ConvexError, v } from "convex/values";
import { internalQuery, mutation } from "./_generated/server";
import { gameBySlug, requireUser } from "./lib";

// A game's own icon on the Home Screen. iOS only lets Safari add one, so the app draws the icon,
// saves it here, and opens the page at /shortcut (http.ts) for Safari to add.

export const save = mutation({
  args: { gameSlug: v.string(), icon: v.id("_storage") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const file = await ctx.db.system.get("_storage", args.icon);
    if (file === null) throw new ConvexError("No such file");
    if (file.contentType !== "image/png" || file.size > 1_000_000) {
      await ctx.storage.delete(args.icon);
      throw new ConvexError("Bad icon");
    }
    await gameBySlug(ctx, args.gameSlug);
    const before = await ctx.db
      .query("shortcuts")
      .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id).eq("gameSlug", args.gameSlug))
      .unique();
    if (before === null) {
      return await ctx.db.insert("shortcuts", { userId: user._id, gameSlug: args.gameSlug, icon: args.icon });
    }
    // The page's address stays the same, so an icon already on the Home Screen keeps working.
    await ctx.storage.delete(before.icon);
    await ctx.db.patch("shortcuts", before._id, { icon: args.icon });
    return before._id;
  },
});

export const page = internalQuery({
  args: { id: v.string() },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("shortcuts", args.id);
    const shortcut = id === null ? null : await ctx.db.get("shortcuts", id);
    if (shortcut === null) return null;
    const icon = await ctx.storage.getUrl(shortcut.icon);
    if (icon === null) return null;
    const game = await gameBySlug(ctx, shortcut.gameSlug);
    return { slug: game.slug, title: game.title, icon };
  },
});
