import { ConvexError, v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { currentUser, gameBySlug, requireUser } from "./lib";
import { BUNDLES, itemById } from "./items";

/** What gold can be spent on. Prices are decided here, never by the phone. */
const ITEMS = [
  { title: "Extra guess", detail: "A seventh try, this round only", price: 5, gameSlug: "five-up", keep: false },
  { title: "Slow slab", detail: "Next 3 slabs slide at half speed", price: 8, gameSlug: "tippy-tower", keep: false },
  { title: "Second chance", detail: "Carry on from where you fell", price: 6, gameSlug: "spiral-drop", keep: false },
  { title: "Comet trail", detail: "Cosmetic. Yours to keep", price: 40, gameSlug: "lane-dash", keep: true },
  { title: "Gilded tower", detail: "Cosmetic. Yours to keep", price: 500, gameSlug: "tippy-tower", keep: true },
];

export const list = query({
  args: {},
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    const purchases = user
      ? await ctx.db
          .query("purchases")
          .withIndex("by_user_and_item", (q) => q.eq("userId", user._id))
          .take(100)
      : [];
    return ITEMS.map((item) => ({ ...item, owned: purchases.some((row) => row.item === item.title) }));
  },
});

export const spend = mutation({
  args: { item: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const item = ITEMS.find((entry) => entry.title === args.item);
    if (!item) throw new ConvexError("No such item");
    const owned = await ctx.db
      .query("purchases")
      .withIndex("by_user_and_item", (q) => q.eq("userId", user._id).eq("item", item.title))
      .first();
    if (item.keep && owned !== null) throw new ConvexError("You already have that");
    if (user.gold < item.price) throw new ConvexError("Not enough gold");
    const game = await gameBySlug(ctx, item.gameSlug);
    await ctx.db.patch("users", user._id, { gold: user.gold - item.price, changes: (user.changes ?? 0) + 1 });
    if (owned === null) await ctx.db.insert("purchases", { userId: user._id, item: item.title, price: item.price });
    await ctx.db.insert("ledger", {
      userId: user._id,
      kind: "spend",
      title: item.title,
      detail: `Spent in ${game.title}`,
      amount: -item.price,
      gameSlug: game.slug,
    });
    return { balance: user.gold - item.price, changes: (user.changes ?? 0) + 1 };
  },
});

/** Buys an avatar item for gold. The price comes from convex/items.ts, never from the phone. */
export const buy = mutation({
  args: { itemId: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const item = itemById(args.itemId);
    if (!item) throw new ConvexError("No such item");
    if (item.price === 0) throw new ConvexError("That one is free");
    const owned = await ctx.db
      .query("inventory")
      .withIndex("by_user_and_item", (q) => q.eq("userId", user._id).eq("itemId", item.id))
      .unique();
    if (owned !== null) throw new ConvexError("You already have that");
    if (user.gold < item.price) throw new ConvexError("Not enough gold");
    const balance = user.gold - item.price;
    const changes = (user.changes ?? 0) + 1;
    await ctx.db.patch("users", user._id, { gold: balance, changes });
    await ctx.db.insert("inventory", { userId: user._id, itemId: item.id, price: item.price });
    await ctx.db.insert("ledger", {
      userId: user._id,
      kind: "spend",
      title: item.name,
      detail: "Bought in the Shop",
      amount: -item.price,
    });
    return { balance, changes };
  },
});

/** Buys every item of a bundle that is not owned yet, for 20 percent less than buying them one by one. */
export const buyBundle = mutation({
  args: { bundleId: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const bundle = BUNDLES.find((entry) => entry.id === args.bundleId);
    if (!bundle) throw new ConvexError("No such bundle");
    const missing = [];
    for (const id of bundle.items) {
      const item = itemById(id);
      if (!item) continue;
      const owned = await ctx.db
        .query("inventory")
        .withIndex("by_user_and_item", (q) => q.eq("userId", user._id).eq("itemId", id))
        .unique();
      if (owned === null) missing.push(item);
    }
    if (missing.length === 0) throw new ConvexError("You already have all of these");
    const price = Math.floor(missing.reduce((sum, item) => sum + item.price, 0) * 0.8);
    if (user.gold < price) throw new ConvexError("Not enough gold");
    const balance = user.gold - price;
    const changes = (user.changes ?? 0) + 1;
    await ctx.db.patch("users", user._id, { gold: balance, changes });
    for (const item of missing) {
      await ctx.db.insert("inventory", { userId: user._id, itemId: item.id, price: Math.floor(item.price * 0.8) });
    }
    await ctx.db.insert("ledger", {
      userId: user._id,
      kind: "spend",
      title: bundle.name,
      detail: "Bundle bought in the Shop",
      amount: -price,
    });
    return { balance, changes };
  },
});
