import { paginationOptsValidator } from "convex/server";
import { ConvexError, v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";

// For scripts/clean-clips.mjs, which takes the recording controls out of clips filmed before the recorder
// left them out. All internal, so only the deploy key can call them.

/** Clips that hold a video file, a page at a time. */
export const videos = internalQuery({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db.query("clips").paginate(args.paginationOpts);
    const page: { clipId: string; storageId: string; url: string }[] = [];
    for (const clip of result.page) {
      if (clip.kind !== "video" || clip.storageId === undefined) continue;
      const url = await ctx.storage.getUrl(clip.storageId);
      if (url !== null) page.push({ clipId: clip._id, storageId: clip.storageId, url });
    }
    return { page, isDone: result.isDone, continueCursor: result.continueCursor };
  },
});

export const uploadUrl = internalMutation({
  args: {},
  handler: async (ctx) => await ctx.storage.generateUploadUrl(),
});

/** Points a clip at its cleaned file and deletes the old one. false if the clip changed since it was read. */
export const swap = internalMutation({
  args: { clipId: v.id("clips"), from: v.id("_storage"), to: v.id("_storage") },
  handler: async (ctx, args) => {
    if ((await ctx.db.system.get("_storage", args.to)) === null) throw new ConvexError("Upload not found");
    const clip = await ctx.db.get("clips", args.clipId);
    if (clip === null || clip.storageId !== args.from) {
      await ctx.storage.delete(args.to);
      return false;
    }
    await ctx.db.patch("clips", args.clipId, { storageId: args.to });
    await ctx.storage.delete(args.from);
    return true;
  },
});
