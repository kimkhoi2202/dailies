import { ConvexError, v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { currentUser, dayNumber, earningsFor, requireUser } from "./lib";

const FIRST = ["quick", "sunny", "mellow", "brave", "swift", "cosmic", "jolly", "nimble", "tidy", "witty", "zesty", "calm"];
const SECOND = ["otter", "falcon", "panda", "comet", "pixel", "mango", "badger", "robin", "lynx", "koala", "gecko", "heron"];
export const COLORS = ["#7C5CFF", "#FF6B57", "#19B8A6", "#F5B301", "#FF7AB6", "#4C9AFF", "#8BC34A", "#FF9F43"];

export const createForDevice = internalMutation({
  args: { method: v.object({ name: v.literal("usernamePassword"), profile: v.object({}) }) },
  returns: v.id("users"),
  handler: async (ctx) => {
    const pick = (list: string[]) => list[Math.floor(Math.random() * list.length)];
    let handle = "";
    for (let attempt = 0; attempt < 8; attempt++) {
      handle = pick(FIRST) + pick(SECOND) + Math.floor(10 + Math.random() * 990);
      const taken = await ctx.db
        .query("users")
        .withIndex("by_handle", (q) => q.eq("handle", handle))
        .unique();
      if (taken === null) break;
    }
    return await ctx.db.insert("users", {
      name: handle,
      handle,
      color: pick(COLORS),
      gold: 0,
      goldAllTime: 0,
      rounds: 0,
      streak: 0,
      fastGold: true,
      seeded: false,
    });
  },
});

export const me = query({
  args: { day: v.string() },
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    if (user === null) return null;
    const earnings = await earningsFor(ctx, user._id, args.day);
    const today = dayNumber(args.day);
    const purchases = await ctx.db
      .query("purchases")
      .withIndex("by_user_and_item", (q) => q.eq("userId", user._id))
      .take(100);
    const streakAlive = user.lastGoldDay !== undefined && today - dayNumber(user.lastGoldDay) <= 1;
    return {
      _id: user._id,
      name: user.name,
      handle: user.handle,
      color: user.color,
      gold: user.gold,
      goldAllTime: user.goldAllTime,
      rounds: user.rounds,
      streak: streakAlive ? user.streak : 0,
      playedToday: user.lastGoldDay === args.day,
      fastGold: user.fastGold,
      changes: user.changes ?? 0,
      today: earnings.reduce((sum, row) => sum + row.gold, 0),
      earnings: earnings.map((row) => ({
        gameSlug: row.gameSlug,
        studio: row.studio,
        gold: row.gold,
        playMs: row.playMs,
        carry: row.carry ?? 0,
      })),
      owned: purchases.map((row) => row.item),
    };
  },
});

export const update = mutation({
  args: { name: v.optional(v.string()), fastGold: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (args.fastGold !== undefined) await ctx.db.patch("users", user._id, { fastGold: args.fastGold });
    if (args.name === undefined) return null;
    const name = args.name.trim().replace(/\s+/g, " ");
    if (name.length < 2 || name.length > 20) throw new ConvexError("Names are 2 to 20 characters");
    const base = name.toLowerCase().replace(/[^a-z0-9.]+/g, "") || "player";
    let handle = base;
    for (let attempt = 0; attempt < 8; attempt++) {
      const taken = await ctx.db
        .query("users")
        .withIndex("by_handle", (q) => q.eq("handle", handle))
        .unique();
      if (taken === null || taken._id === user._id) break;
      handle = base + Math.floor(10 + Math.random() * 990);
    }
    await ctx.db.patch("users", user._id, { name, handle });
    return null;
  },
});
