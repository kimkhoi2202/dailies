import { ConvexError, v } from "convex/values";
import { components } from "./_generated/api";
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
      // Builds from before gold came from the game still read this.
      fastGold: user.fastGold,
      changes: user.changes ?? 0,
      today: earnings.reduce((sum, row) => sum + row.gold, 0),
      earnings: earnings.map((row) => ({
        gameSlug: row.gameSlug,
        studio: row.studio,
        gold: row.gold,
        playMs: row.playMs,
      })),
      owned: purchases.map((row) => row.item),
    };
  },
});

// Gives the silent account a phone made for itself the person's own username and password. The account,
// its gold and its scores stay as they are. Answers null, or the reason it could not be done.
export const claim = mutation({
  args: { username: v.string(), password: v.string() },
  returns: v.union(v.null(), v.string()),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (!/^[A-Za-z0-9._]{3,20}$/.test(args.username)) return "USERNAME_INVALID";
    const owner = await ctx.runQuery(components.authUsername.public.getUserIdByUsername, { username: args.username });
    if (owner !== null && owner !== user._id) return "USERNAME_TAKEN";
    const handle = args.username.toLowerCase();
    const taken = await ctx.db
      .query("users")
      .withIndex("by_handle", (q) => q.eq("handle", handle))
      .unique();
    if (taken !== null && taken._id !== user._id) return "USERNAME_TAKEN";
    const password = await ctx.runMutation(components.authPassword.public._internal_dangerous_setPassword, {
      userId: user._id,
      password: args.password,
      minimumLength: 10,
    });
    if (!password.success) return password.userError.error;
    const username = await ctx.runMutation(components.authUsername.public.setUsername, {
      userId: user._id,
      username: args.username,
    });
    // Throwing takes the new password back out with everything else.
    if (!username.success) throw new ConvexError(username.userError.error);
    await ctx.db.patch("users", user._id, { name: args.username, handle });
    return null;
  },
});

export const update = mutation({
  args: { name: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
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
