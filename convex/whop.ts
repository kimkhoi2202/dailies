import { WhopClient, WhopEnvironment } from "@whop/sdk";
import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { action, env, internalMutation, query } from "./_generated/server";
import { currentUser, gameBySlug, requireUser } from "./lib";

// Money moves through Whop in three places: a player buys a gold pack, a studio funds a creator
// program, and a creator sends what their clips brought in to their Whop account. Prices are
// decided here, never by the phone, and nothing is added until Whop says the payment went through.

const PACKS = [
  { id: "pouch", title: "Pouch", gold: 500, cents: 199 },
  { id: "chest", title: "Chest", gold: 1500, cents: 499 },
  { id: "vault", title: "Vault", gold: 5000, cents: 999 },
];
/** Cents a studio pays for 1,000 views. */
const RATES = [1000, 2000, 5000];
/** Cents a studio can add to a program in one payment. */
const BUDGETS = [500, 2000, 5000];
/** The least a creator can send to Whop, in cents. */
export const SEND_MINIMUM = 100;

function whop() {
  if (!env.WHOP_API_KEY) throw new ConvexError("Whop is not set up");
  return new WhopClient({
    token: env.WHOP_API_KEY,
    environment: env.WHOP_ENVIRONMENT === "production" ? WhopEnvironment.Production : WhopEnvironment.Sandbox,
  });
}

function dollars(cents: number) {
  return "$" + (cents / 100).toFixed(2);
}

export const catalog = query({
  args: {},
  handler: async () => {
    return { packs: PACKS, rates: RATES, budgets: BUDGETS, sendMinimum: SEND_MINIMUM };
  },
});

/** One of the caller's checkouts. The phone watches it to know when the payment has landed. */
export const order = query({
  args: { orderId: v.id("orders") },
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    const row = await ctx.db.get("orders", args.orderId);
    if (user === null || row === null || row.userId !== user._id) return null;
    return { status: row.status, kind: row.kind, gold: row.gold ?? 0, cents: row.cents };
  },
});

export const openOrder = internalMutation({
  args: {
    kind: v.union(v.literal("gold"), v.literal("program")),
    cents: v.number(),
    gold: v.optional(v.number()),
    gameSlug: v.optional(v.string()),
    rate: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (args.gameSlug !== undefined) await gameBySlug(ctx, args.gameSlug);
    return await ctx.db.insert("orders", { ...args, userId: user._id, status: "open" });
  },
});

export const attachCheckout = internalMutation({
  args: { orderId: v.id("orders"), checkoutId: v.string() },
  handler: async (ctx, args) => {
    await ctx.db.patch("orders", args.orderId, { checkoutId: args.checkoutId });
    return null;
  },
});

/** Marks an order paid and hands over what it bought. Safe to call twice for one payment. */
export const settle = internalMutation({
  args: { order: v.string(), paymentId: v.string() },
  handler: async (ctx, args) => {
    const orderId = ctx.db.normalizeId("orders", args.order);
    const row = orderId === null ? null : await ctx.db.get("orders", orderId);
    if (row === null || row.status === "paid") return null;
    await ctx.db.patch("orders", row._id, { status: "paid", paymentId: args.paymentId });

    if (row.kind === "gold") {
      const user = await ctx.db.get("users", row.userId);
      if (user === null) return null;
      const gold = row.gold ?? 0;
      await ctx.db.patch("users", user._id, { gold: user.gold + gold, changes: (user.changes ?? 0) + 1 });
      await ctx.db.insert("ledger", {
        userId: user._id,
        kind: "buy",
        title: "Gold pack",
        detail: `${dollars(row.cents)} through Whop`,
        amount: gold,
      });
      return null;
    }

    if (row.gameSlug === undefined) return null;
    const game = await gameBySlug(ctx, row.gameSlug);
    const program = await ctx.db
      .query("programs")
      .withIndex("by_gameSlug", (q) => q.eq("gameSlug", game.slug))
      .unique();
    const rate = row.rate ?? RATES[0];
    if (program) await ctx.db.patch("programs", program._id, { rate, budget: program.budget + row.cents, ownerId: row.userId });
    else
      await ctx.db.insert("programs", {
        gameSlug: game.slug,
        studio: game.studio,
        ownerId: row.userId,
        rate,
        budget: row.cents,
        spent: 0,
        views: 0,
      });
    return null;
  },
});

async function checkout(orderId: Id<"orders">, title: string, cents: number) {
  const made = await whop().checkoutConfigurations.create({
    variant: {
      title,
      initial_price: cents / 100,
      currency: "usd",
      billing_type: "one_time",
      visibility: "hidden",
    },
    metadata: { order: orderId },
    redirect_url: `${env.CONVEX_SITE_URL}/whop/done`,
  });
  if (!made.purchase_url) throw new ConvexError("Whop gave no page to pay on");
  return { checkoutId: made.id, url: made.purchase_url };
}

/** Starts a Whop checkout for a gold pack and returns the page to pay on. */
export const buyGold = action({
  args: { pack: v.string() },
  handler: async (ctx, args): Promise<{ orderId: Id<"orders">; url: string }> => {
    const pack = PACKS.find((entry) => entry.id === args.pack);
    if (!pack) throw new ConvexError("No such pack");
    const orderId: Id<"orders"> = await ctx.runMutation(internal.whop.openOrder, {
      kind: "gold",
      cents: pack.cents,
      gold: pack.gold,
    });
    const made = await checkout(orderId, `DEGEN ${pack.gold} gold`, pack.cents);
    await ctx.runMutation(internal.whop.attachCheckout, { orderId, checkoutId: made.checkoutId });
    return { orderId, url: made.url };
  },
});

/** Starts a Whop checkout that adds budget to a game's creator program, at the rate picked. */
export const fundProgram = action({
  args: { slug: v.string(), rate: v.number(), budget: v.number() },
  handler: async (ctx, args): Promise<{ orderId: Id<"orders">; url: string }> => {
    if (!RATES.includes(args.rate)) throw new ConvexError("No such rate");
    if (!BUDGETS.includes(args.budget)) throw new ConvexError("No such budget");
    const orderId: Id<"orders"> = await ctx.runMutation(internal.whop.openOrder, {
      kind: "program",
      cents: args.budget,
      gameSlug: args.slug,
      rate: args.rate,
    });
    const made = await checkout(orderId, `DEGEN creator program, ${args.slug}`, args.budget);
    await ctx.runMutation(internal.whop.attachCheckout, { orderId, checkoutId: made.checkoutId });
    return { orderId, url: made.url };
  },
});

/** Takes the whole cents of a creator's earnings out of their balance, ready to send. */
export const reserve = internalMutation({
  args: { username: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const cents = Math.floor(user.cents ?? 0);
    if (cents < SEND_MINIMUM) throw new ConvexError(`You can send from ${dollars(SEND_MINIMUM)}`);
    await ctx.db.patch("users", user._id, { cents: (user.cents ?? 0) - cents, whopUsername: args.username });
    const transferId = await ctx.db.insert("transfers", {
      userId: user._id,
      cents,
      whopUsername: args.username,
      status: "sending",
    });
    return { transferId, cents };
  },
});

/** Records how a send ended. A send that failed puts the money back. */
export const finishTransfer = internalMutation({
  args: { transferId: v.id("transfers"), whopTransferId: v.optional(v.string()), error: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const row = await ctx.db.get("transfers", args.transferId);
    if (row === null || row.status !== "sending") return null;
    if (args.error === undefined) {
      await ctx.db.patch("transfers", row._id, { status: "sent", whopTransferId: args.whopTransferId });
      return null;
    }
    await ctx.db.patch("transfers", row._id, { status: "failed", error: args.error.slice(0, 300) });
    const user = await ctx.db.get("users", row.userId);
    if (user) await ctx.db.patch("users", user._id, { cents: (user.cents ?? 0) + row.cents });
    return null;
  },
});

/** Sends a creator's earnings to their Whop account with a Whop transfer. */
export const sendEarnings = action({
  args: { username: v.string() },
  handler: async (ctx, args): Promise<{ sent: boolean; cents: number }> => {
    const username = args.username.trim().replace(/^@/, "");
    if (!/^[A-Za-z0-9_.-]{2,40}$/.test(username)) throw new ConvexError("That is not a Whop username");
    if (!env.WHOP_ACCOUNT_ID) throw new ConvexError("Whop is not set up");
    const client = whop();

    let whopUserId: string;
    try {
      whopUserId = (await client.users.retrieve({ id: username })).id;
    } catch {
      throw new ConvexError("No Whop account has that username");
    }

    const reserved: { transferId: Id<"transfers">; cents: number } = await ctx.runMutation(internal.whop.reserve, { username });
    try {
      const made = await client.transfers.create({
        type: "balance",
        amount: reserved.cents / 100,
        currency: "usd",
        origin_id: env.WHOP_ACCOUNT_ID,
        destination_id: whopUserId,
        idempotence_key: reserved.transferId,
        notes: "DEGEN creator earnings",
      });
      await ctx.runMutation(internal.whop.finishTransfer, { transferId: reserved.transferId, whopTransferId: made.id });
      return { sent: true, cents: reserved.cents };
    } catch (error) {
      const body = (error as { body?: { error?: { message?: string } } }).body;
      const message = body?.error?.message ?? (error instanceof Error ? error.message : "Whop refused the transfer");
      await ctx.runMutation(internal.whop.finishTransfer, { transferId: reserved.transferId, error: message });
      return { sent: false, cents: reserved.cents };
    }
  },
});
