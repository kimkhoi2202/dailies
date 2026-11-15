import { ConvexError, v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query, type QueryCtx } from "./_generated/server";
import { currentUser, gameBySlug, requireUser } from "./lib";

export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    await requireUser(ctx);
    return await ctx.storage.generateUploadUrl();
  },
});

export const create = mutation({
  args: {
    gameSlug: v.string(),
    kind: v.union(v.literal("video"), v.literal("photo")),
    storageId: v.optional(v.id("_storage")),
    roundId: v.optional(v.id("rounds")),
    caption: v.string(),
    layout: v.union(v.literal("cutout"), v.literal("bubble")),
    durationMs: v.number(),
    visibility: v.union(v.literal("friends"), v.literal("everyone")),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.gameSlug);
    if (args.storageId !== undefined && (await ctx.db.system.get("_storage", args.storageId)) === null)
      throw new ConvexError("Upload not found");

    let score: number | undefined;
    let seed: number | undefined;
    if (args.roundId !== undefined) {
      const round = await ctx.db.get("rounds", args.roundId);
      if (round === null || round.userId !== user._id) throw new ConvexError("No such round");
      if (round.endedAt === undefined) throw new ConvexError("Round not finished");
      if (round.gameSlug !== game.slug) throw new ConvexError("Round is for another game");
      const taken = await ctx.db
        .query("clips")
        .withIndex("by_roundId", (q) => q.eq("roundId", round._id))
        .first();
      if (taken !== null) throw new ConvexError("This round is already posted");
      score = round.score;
      seed = round.seed;
    }

    return await ctx.db.insert("clips", {
      userId: user._id,
      gameSlug: game.slug,
      kind: args.kind,
      storageId: args.storageId,
      roundId: args.roundId,
      score,
      seed,
      caption: args.caption.trim().slice(0, 140),
      layout: args.layout,
      durationMs: Math.max(0, Math.min(Number.isFinite(args.durationMs) ? args.durationMs : 0, 10 * 60 * 1000)),
      visibility: args.visibility,
      likes: 0,
      comments: 0,
    });
  },
});

async function present(ctx: QueryCtx, clips: Doc<"clips">[], meId: string | null) {
  return await Promise.all(
    clips.map(async (clip) => {
      const author = await ctx.db.get("users", clip.userId);
      const game = await ctx.db
        .query("games")
        .withIndex("by_slug", (q) => q.eq("slug", clip.gameSlug))
        .unique();
      return {
        _id: clip._id,
        at: clip._creationTime,
        gameSlug: clip.gameSlug,
        gameTitle: game?.title ?? clip.gameSlug,
        unit: game?.unit ?? "",
        kind: clip.kind,
        url: clip.storageId === undefined ? null : await ctx.storage.getUrl(clip.storageId),
        score: clip.score ?? null,
        seed: clip.seed ?? null,
        caption: clip.caption,
        layout: clip.layout,
        durationMs: clip.durationMs,
        visibility: clip.visibility,
        likes: clip.likes,
        comments: clip.comments,
        name: author?.name ?? "someone",
        handle: author?.handle ?? "someone",
        color: author?.color ?? "#7C5CFF",
        mine: meId !== null && clip.userId === meId,
      };
    }),
  );
}

/** Newest clips: everyone's public clips, and the player's own whoever they were shared with. */
export const feed = query({
  args: {},
  handler: async (ctx) => {
    const me = await currentUser(ctx);
    const open = await ctx.db
      .query("clips")
      .withIndex("by_visibility", (q) => q.eq("visibility", "everyone"))
      .order("desc")
      .take(40);
    const mine =
      me === null
        ? []
        : await ctx.db
            .query("clips")
            .withIndex("by_user", (q) => q.eq("userId", me._id))
            .order("desc")
            .take(40);
    const byId = new Map<string, Doc<"clips">>();
    for (const clip of [...open, ...mine]) byId.set(clip._id, clip);
    const clips = [...byId.values()].sort((a, b) => b._creationTime - a._creationTime).slice(0, 40);
    return await present(ctx, clips, me?._id ?? null);
  },
});

export const byUser = query({
  args: { handle: v.string() },
  handler: async (ctx, args) => {
    const me = await currentUser(ctx);
    const author = await ctx.db
      .query("users")
      .withIndex("by_handle", (q) => q.eq("handle", args.handle))
      .unique();
    if (author === null) return [];
    const clips = await ctx.db
      .query("clips")
      .withIndex("by_user", (q) => q.eq("userId", author._id))
      .order("desc")
      .take(40);
    const shown = me?._id === author._id ? clips : clips.filter((clip) => clip.visibility === "everyone");
    return await present(ctx, shown, me?._id ?? null);
  },
});
