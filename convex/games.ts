import { v } from "convex/values";
import { query } from "./_generated/server";
import { GAME_DAILY_LIMIT, STUDIO_DAILY_LIMIT, currentUser, earningsFor } from "./lib";

export const list = query({
  args: { day: v.string() },
  handler: async (ctx, args) => {
    const games = (await ctx.db.query("games").take(200))
      .filter((game) => game.creatorId === undefined)
      .sort((a, b) => a.order - b.order);
    const user = await currentUser(ctx);
    const earnings = user ? await earningsFor(ctx, user._id, args.day) : [];
    const bests = user
      ? await ctx.db
          .query("bests")
          .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id))
          .take(100)
      : [];
    const votes = user
      ? await ctx.db
          .query("votes")
          .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id))
          .take(100)
      : [];
    const byStudio: Record<string, number> = {};
    for (const row of earnings) byStudio[row.studio] = (byStudio[row.studio] ?? 0) + row.gold;

    return games.map((game) => {
      const best = bests.find((row) => row.gameSlug === game.slug);
      const today = earnings.find((row) => row.gameSlug === game.slug)?.gold ?? 0;
      const studioToday = byStudio[game.studio] ?? 0;
      return {
        slug: game.slug,
        title: game.title,
        studio: game.studio,
        pitch: game.pitch,
        how: game.how,
        minPlayers: game.minPlayers,
        maxPlayers: game.maxPlayers,
        mode: game.mode,
        category: game.category,
        unit: game.unit,
        goldPerMinute: game.goldPerMinute,
        likes: game.likes,
        dislikes: game.dislikes,
        plays: game.plays,
        comments: game.comments,
        today,
        studioToday,
        left: Math.max(0, Math.min(GAME_DAILY_LIMIT - today, STUDIO_DAILY_LIMIT - studioToday)),
        best: best?.score ?? null,
        bestUnit: best?.unit ?? null,
        bestText: best?.text ?? null,
        vote: votes.find((row) => row.gameSlug === game.slug)?.value ?? 0,
      };
    });
  },
});
