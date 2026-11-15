import { ConvexError, v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import type { QueryCtx } from "./_generated/server";
import { currentUser, requireUser } from "./lib";
import { defaultLook, itemById } from "./items";

const SLOTS = ["body", "face", "hair", "hat", "outfit", "gadget"] as const;

export function lookOf(user: Doc<"users">) {
  return user.avatar ?? defaultLook(user.handle);
}

async function ownedIds(ctx: QueryCtx, userId: Id<"users">) {
  const rows = await ctx.db
    .query("inventory")
    .withIndex("by_user_and_item", (q) => q.eq("userId", userId))
    .take(500);
  return rows.map((row) => row.itemId);
}

/** The signed-in player's look and every item they own. Free items are always owned and not listed. */
export const locker = query({
  args: {},
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return null;
    return { look: lookOf(user), owned: await ownedIds(ctx, user._id), color: user.color };
  },
});

/** A player's profile by handle, or the signed-in player's for "me". */
export const profile = query({
  args: { handle: v.string() },
  handler: async (ctx, args) => {
    const me = await currentUser(ctx);
    const user =
      args.handle === "me"
        ? me
        : await ctx.db
            .query("users")
            .withIndex("by_handle", (q) => q.eq("handle", args.handle))
            .unique();
    if (user === null) return null;
    const bests = await ctx.db
      .query("bests")
      .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", user._id))
      .take(50);
    return {
      name: user.name,
      handle: user.handle,
      color: user.color,
      gold: user.gold,
      streak: user.streak,
      rounds: user.rounds,
      look: lookOf(user),
      you: me !== null && me._id === user._id,
      bests: bests.map((row) => ({ gameSlug: row.gameSlug, score: row.score, text: row.text ?? null, unit: row.unit ?? null })),
    };
  },
});

/** Puts an owned item on, or takes the item in a slot off. Body and face can only be swapped, never removed. */
export const equip = mutation({
  args: {
    slot: v.union(...SLOTS.map((slot) => v.literal(slot))),
    itemId: v.union(v.string(), v.null()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const look = { ...lookOf(user) };
    if (args.itemId === null) {
      if (args.slot === "body" || args.slot === "face") throw new ConvexError("That slot always has something");
      delete look[args.slot];
    } else {
      const item = itemById(args.itemId);
      if (!item || item.slot !== args.slot) throw new ConvexError("No such item");
      if (item.price > 0) {
        const owned = await ctx.db
          .query("inventory")
          .withIndex("by_user_and_item", (q) => q.eq("userId", user._id).eq("itemId", item.id))
          .unique();
        if (owned === null) throw new ConvexError("Get it in the shop first");
      }
      look[args.slot] = item.id;
    }
    await ctx.db.patch("users", user._id, { avatar: look });
    return null;
  },
});
