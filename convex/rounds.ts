import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import {
  FAST_GOLD_MULTIPLIER,
  GAME_DAILY_LIMIT,
  STUDIO_DAILY_LIMIT,
  assertCurrentDay,
  dayNumber,
  earningsFor,
  gameBySlug,
  requireUser,
} from "./lib";
import { roomByCode } from "./rooms";

export const start = mutation({
  args: { slug: v.string(), day: v.string(), room: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    assertCurrentDay(args.day);
    const game = await gameBySlug(ctx, args.slug);
    const earnings = await earningsFor(ctx, user._id, args.day);
    const today = earnings.find((row) => row.gameSlug === game.slug)?.gold ?? 0;
    const studioToday = earnings.filter((row) => row.studio === game.studio).reduce((sum, row) => sum + row.gold, 0);
    const best = await ctx.db
      .query("bests")
      .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id).eq("gameSlug", game.slug))
      .unique();
    const room = args.room === undefined ? null : await roomByCode(ctx, args.room);
    const seed = room?.gameSlug === game.slug ? room.seed : Math.floor(Math.random() * 1_000_000) + 1;
    const roundId = await ctx.db.insert("rounds", {
      userId: user._id,
      gameSlug: game.slug,
      studio: game.studio,
      seed,
      day: args.day,
      startedAt: Date.now(),
    });
    return {
      roundId,
      seed,
      best: best?.score ?? 0,
      goldPerMinute: game.goldPerMinute * (user.fastGold ? FAST_GOLD_MULTIPLIER : 1),
      left: Math.max(0, Math.min(GAME_DAILY_LIMIT - today, STUDIO_DAILY_LIMIT - studioToday)),
    };
  },
});

export const finish = mutation({
  args: { roundId: v.id("rounds"), score: v.number(), activeMs: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const round = await ctx.db.get("rounds", args.roundId);
    if (round === null || round.userId !== user._id) throw new ConvexError("No such round");
    if (round.endedAt !== undefined) throw new ConvexError("Round already finished");
    const game = await gameBySlug(ctx, round.gameSlug);

    const now = Date.now();
    const playMs = Math.max(0, Math.min(Number.isFinite(args.activeMs) ? args.activeMs : 0, now - round.startedAt + 2000));
    const score = Number.isFinite(args.score) ? Math.max(0, Math.round(args.score * 10) / 10) : 0;

    const earnings = await earningsFor(ctx, user._id, round.day);
    const row = earnings.find((entry) => entry.gameSlug === game.slug);
    const today = row?.gold ?? 0;
    const studioToday = earnings.filter((entry) => entry.studio === game.studio).reduce((sum, entry) => sum + entry.gold, 0);
    const left = Math.max(0, Math.min(GAME_DAILY_LIMIT - today, STUDIO_DAILY_LIMIT - studioToday));
    const rate = game.goldPerMinute * (user.fastGold ? FAST_GOLD_MULTIPLIER : 1);
    const gold = Math.min(left, Math.floor((playMs / 60000) * rate));

    if (row) await ctx.db.patch("earnings", row._id, { gold: row.gold + gold, playMs: row.playMs + playMs });
    else
      await ctx.db.insert("earnings", { userId: user._id, day: round.day, gameSlug: game.slug, studio: game.studio, gold, playMs });

    let streak = user.streak;
    let lastGoldDay = user.lastGoldDay;
    if (gold > 0 && lastGoldDay !== round.day) {
      streak = lastGoldDay !== undefined && dayNumber(round.day) - dayNumber(lastGoldDay) === 1 ? streak + 1 : 1;
      lastGoldDay = round.day;
    }
    await ctx.db.patch("users", user._id, {
      gold: user.gold + gold,
      goldAllTime: user.goldAllTime + gold,
      rounds: user.rounds + 1,
      streak,
      lastGoldDay,
    });

    const best = await ctx.db
      .query("bests")
      .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id).eq("gameSlug", game.slug))
      .unique();
    const newBest = score > 0 && (best === null || score > best.score);
    if (newBest) {
      if (best) await ctx.db.patch("bests", best._id, { score, day: round.day });
      else await ctx.db.insert("bests", { userId: user._id, gameSlug: game.slug, score, day: round.day });
    }

    await ctx.db.patch("rounds", round._id, { endedAt: now, score, playMs, gold });
    await ctx.db.patch("games", game._id, { plays: game.plays + 1 });

    return {
      gold,
      balance: user.gold + gold,
      today: today + gold,
      left: left - gold,
      best: newBest ? score : (best?.score ?? 0),
      previousBest: best?.score ?? 0,
      newBest,
      streak,
    };
  },
});

export const history = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    const rounds = await ctx.db
      .query("rounds")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(40);
    return rounds
      .filter((round) => round.endedAt !== undefined)
      .map((round) => ({
        _id: round._id,
        gameSlug: round.gameSlug,
        score: round.score ?? 0,
        gold: round.gold ?? 0,
        playMs: round.playMs ?? 0,
        endedAt: round.endedAt ?? round.startedAt,
      }));
  },
});
