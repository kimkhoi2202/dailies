import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { currentUser, requireUser } from "./lib";

// A studio that wants its game seen funds a creator program through Whop (convex/whop.ts). Every
// first view of a clip of that game moves a little of the program's budget to the clip's creator.

/** Cents one view is worth under a program, or 0 when its budget cannot cover another view. */
function perView(program: { rate: number; budget: number; spent: number } | null) {
  if (program === null) return 0;
  const cents = program.rate / 1000;
  return program.budget - program.spent >= cents ? cents : 0;
}

/** Counts one view of a clip. A player's first view of someone else's clip pays its creator when the game has a program. */
export const view = mutation({
  args: { clipId: v.id("clips") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const clip = await ctx.db.get("clips", args.clipId);
    if (clip === null || clip.userId === user._id) return null;
    const seen = await ctx.db
      .query("clipViews")
      .withIndex("by_clip_and_user", (q) => q.eq("clipId", clip._id).eq("userId", user._id))
      .first();
    if (seen !== null) return null;
    await ctx.db.insert("clipViews", { clipId: clip._id, userId: user._id });

    const program = await ctx.db
      .query("programs")
      .withIndex("by_gameSlug", (q) => q.eq("gameSlug", clip.gameSlug))
      .unique();
    const cents = perView(program);
    await ctx.db.patch("clips", clip._id, { views: (clip.views ?? 0) + 1, cents: (clip.cents ?? 0) + cents });
    if (program === null || cents === 0) return null;
    await ctx.db.patch("programs", program._id, { spent: program.spent + cents, views: program.views + 1 });
    const creator = await ctx.db.get("users", clip.userId);
    if (creator)
      await ctx.db.patch("users", creator._id, {
        cents: (creator.cents ?? 0) + cents,
        centsAllTime: (creator.centsAllTime ?? 0) + cents,
      });
    return null;
  },
});

/** The signed-in creator: what their clips brought in, the clips, and what they sent to Whop. */
export const mine = query({
  args: {},
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return null;
    const clips = await ctx.db
      .query("clips")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(30);
    const transfers = await ctx.db
      .query("transfers")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(20);
    return {
      cents: user.cents ?? 0,
      centsAllTime: user.centsAllTime ?? 0,
      whopUsername: user.whopUsername ?? null,
      clips: clips.map((clip) => ({
        _id: clip._id,
        gameSlug: clip.gameSlug,
        caption: clip.caption,
        views: clip.views ?? 0,
        cents: clip.cents ?? 0,
        at: clip._creationTime,
      })),
      transfers: transfers.map((row) => ({
        _id: row._id,
        cents: row.cents,
        whopUsername: row.whopUsername,
        status: row.status,
        at: row._creationTime,
      })),
    };
  },
});

/** Every creator program, for the studio screen and for creators picking what to post. */
export const programs = query({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("programs").take(60);
    return rows.map((row) => ({
      gameSlug: row.gameSlug,
      studio: row.studio,
      rate: row.rate,
      left: row.budget - row.spent,
      spent: row.spent,
      views: row.views,
    }));
  },
});
