import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, internalQuery, mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { requireUser } from "./lib";

// A game made in the studio. The maker talks to the studio (an OpenAI model, see ai.ts) until the
// studio has enough to build, then the game is assembled on one of the built-in engines and put in
// the games table, private to its maker.

export const ENGINES = ["fiveUp", "tippyTower", "spiralDrop", "laneDash", "gulpCity", "inkland"] as const;

const specValidator = v.object({
  title: v.string(),
  pitch: v.string(),
  how: v.string(),
  category: v.string(),
  kind: v.string(),
  tint: v.string(),
  unit: v.string(),
});

const ideaValidator = v.object({ title: v.string(), pitch: v.string() });

function publicCreation(row: Doc<"creations">) {
  return {
    _id: row._id,
    status: row.status,
    wish: row.wish,
    thinking: row.thinking,
    title: row.title ?? null,
    pitch: row.pitch ?? null,
    how: row.how ?? null,
    category: row.category ?? null,
    kind: row.kind ?? null,
    tint: row.tint ?? null,
    unit: row.unit ?? null,
    gameSlug: row.gameSlug ?? null,
    error: row.error ?? null,
    at: row._creationTime,
  };
}

async function ownCreation(ctx: QueryCtx | MutationCtx, creationId: Id<"creations">) {
  const user = await requireUser(ctx);
  const creation = await ctx.db.get("creations", creationId);
  if (creation === null || creation.userId !== user._id) throw new ConvexError("No such creation");
  return { user, creation };
}

async function messagesFor(ctx: QueryCtx | MutationCtx, creationId: Id<"creations">) {
  const rows = await ctx.db
    .query("creationMessages")
    .withIndex("by_creation", (q) => q.eq("creationId", creationId))
    .take(200);
  return rows.map((row) => ({
    _id: row._id,
    role: row.role,
    text: row.text,
    options: row.options ?? [],
    ideas: row.ideas ?? [],
    at: row._creationTime,
  }));
}

function cleanText(text: string) {
  const body = text.trim().replace(/\s+/g, " ");
  if (body.length === 0) throw new ConvexError("Say something first");
  return body.slice(0, 600);
}

/// This player's games in the making, newest first.
export const mine = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx).catch(() => null);
    if (user === null) return [];
    const rows = await ctx.db
      .query("creations")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(50);
    return rows.map(publicCreation);
  },
});

/// One creation with its whole conversation.
export const get = query({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx).catch(() => null);
    if (user === null) return null;
    const creation = await ctx.db.get("creations", args.creationId);
    if (creation === null || creation.userId !== user._id) return null;
    return { ...publicCreation(creation), messages: await messagesFor(ctx, creation._id) };
  },
});

/// Opens a creation with the maker's first wish and asks the studio to answer.
export const start = mutation({
  args: { text: v.string() },
  returns: v.id("creations"),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const text = cleanText(args.text);
    const creationId = await ctx.db.insert("creations", { userId: user._id, status: "talking", wish: text, thinking: true });
    await ctx.db.insert("creationMessages", { creationId, role: "maker", text });
    await ctx.scheduler.runAfter(0, internal.ai.replyToCreation, { creationId });
    return creationId;
  },
});

/// Adds the maker's next line and asks the studio to answer.
export const send = mutation({
  args: { creationId: v.id("creations"), text: v.string() },
  handler: async (ctx, args) => {
    const { creation } = await ownCreation(ctx, args.creationId);
    if (creation.status !== "talking" && creation.status !== "failed") throw new ConvexError("This game is already built");
    if (creation.thinking) throw new ConvexError("The studio is still answering");
    const text = cleanText(args.text);
    await ctx.db.insert("creationMessages", { creationId: creation._id, role: "maker", text });
    await ctx.db.patch("creations", creation._id, { thinking: true, status: "talking", error: undefined });
    await ctx.scheduler.runAfter(0, internal.ai.replyToCreation, { creationId: creation._id });
    return null;
  },
});

/// Asks the studio again after a failed answer, without adding a line.
export const retry = mutation({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const { creation } = await ownCreation(ctx, args.creationId);
    if (creation.status !== "failed") return null;
    await ctx.db.patch("creations", creation._id, { thinking: true, status: "talking", error: undefined });
    await ctx.scheduler.runAfter(0, internal.ai.replyToCreation, { creationId: creation._id });
    return null;
  },
});

/// Throws a creation away, with its messages and the game it became.
export const remove = mutation({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const { creation } = await ownCreation(ctx, args.creationId);
    const messages = await ctx.db
      .query("creationMessages")
      .withIndex("by_creation", (q) => q.eq("creationId", creation._id))
      .take(200);
    for (const message of messages) await ctx.db.delete("creationMessages", message._id);
    if (creation.gameSlug !== undefined) {
      const game = await ctx.db
        .query("games")
        .withIndex("by_slug", (q) => q.eq("slug", creation.gameSlug!))
        .unique();
      if (game !== null) await ctx.db.delete("games", game._id);
    }
    await ctx.db.delete("creations", creation._id);
    return null;
  },
});

// MARK: For the studio's action

/// Everything the model needs: the maker's name and the conversation so far.
export const context = internalQuery({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const creation = await ctx.db.get("creations", args.creationId);
    if (creation === null) return null;
    const user = await ctx.db.get("users", creation.userId);
    return { creation: publicCreation(creation), handle: user?.handle ?? "maker", messages: await messagesFor(ctx, creation._id) };
  },
});

/// The studio's answer: a line, with choices or ideas to pick from, or the finished design to build.
export const reply = internalMutation({
  args: {
    creationId: v.id("creations"),
    text: v.string(),
    options: v.optional(v.array(v.string())),
    ideas: v.optional(v.array(ideaValidator)),
    build: v.optional(specValidator),
  },
  handler: async (ctx, args) => {
    const creation = await ctx.db.get("creations", args.creationId);
    if (creation === null) return null;
    await ctx.db.insert("creationMessages", {
      creationId: creation._id,
      role: "studio",
      text: args.text,
      options: args.options,
      ideas: args.ideas,
    });
    if (args.build === undefined) {
      await ctx.db.patch("creations", creation._id, { thinking: false });
      return null;
    }
    const spec = args.build;
    const kind = (ENGINES as readonly string[]).includes(spec.kind) ? spec.kind : "tippyTower";
    const tint = /^[0-9a-fA-F]{6}$/.test(spec.tint.replace("#", "")) ? spec.tint.replace("#", "").toUpperCase() : "F5B301";
    await ctx.db.patch("creations", creation._id, {
      thinking: false,
      status: "building",
      title: spec.title.trim().slice(0, 24) || "New game",
      pitch: spec.pitch.trim().slice(0, 60),
      how: spec.how.trim().slice(0, 240),
      category: spec.category.trim().slice(0, 16) || "Arcade",
      kind,
      tint,
      unit: spec.unit.trim().toLowerCase().slice(0, 12) || "points",
    });
    // The game takes a moment to assemble, long enough for the maker to see it happening.
    await ctx.scheduler.runAfter(6000, internal.creations.finishBuild, { creationId: creation._id });
    return null;
  },
});

/// Something went wrong on the way to an answer. The maker can try again.
export const fail = internalMutation({
  args: { creationId: v.id("creations"), error: v.string() },
  handler: async (ctx, args) => {
    const creation = await ctx.db.get("creations", args.creationId);
    if (creation === null) return null;
    await ctx.db.patch("creations", creation._id, { thinking: false, status: "failed", error: args.error.slice(0, 200) });
    return null;
  },
});

/// Puts the finished game in the games table, private to its maker, and marks the creation ready.
export const finishBuild = internalMutation({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const creation = await ctx.db.get("creations", args.creationId);
    if (creation === null || creation.status !== "building") return null;
    const user = await ctx.db.get("users", creation.userId);
    const slug = "made-" + creation._id.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 20);
    const existing = await ctx.db
      .query("games")
      .withIndex("by_slug", (q) => q.eq("slug", slug))
      .unique();
    if (existing === null) {
      await ctx.db.insert("games", {
        slug,
        title: creation.title ?? "New game",
        studio: user?.handle ?? "maker",
        pitch: creation.pitch ?? "",
        how: creation.how ?? "",
        minPlayers: 1,
        maxPlayers: 1,
        mode: "casual",
        category: creation.category ?? "Arcade",
        unit: creation.unit ?? "points",
        goldPerMinute: 1,
        likes: 0,
        dislikes: 0,
        plays: 0,
        comments: 0,
        order: 1000 + Math.floor(Date.now() / 1000),
        creatorId: creation.userId,
        kind: creation.kind ?? "tippyTower",
        tint: creation.tint ?? "F5B301",
      });
    }
    await ctx.db.patch("creations", creation._id, { status: "ready", gameSlug: slug });
    return null;
  },
});
