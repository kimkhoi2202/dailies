import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, internalQuery, mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import { requireUser } from "./lib";
import { designValidator } from "./schema";

// A game designed in the studio. The maker talks to the studio (an OpenAI model, see ai.ts), and
// with every reply the studio fills in a little more of the design sheet: the idea, how it plays,
// how it scores, how it looks. The sheet is the plan for a game. Nothing is built from it here.

const ideaValidator = v.object({ title: v.string(), pitch: v.string() });

function publicCreation(row: Doc<"creations">) {
  return {
    _id: row._id,
    status: row.status,
    wish: row.wish,
    thinking: row.thinking,
    design: row.design ?? null,
    progress: row.progress ?? 0,
    error: row.error ?? null,
    at: row._creationTime,
  };
}

async function ownCreation(ctx: QueryCtx | MutationCtx, creationId: Id<"creations">) {
  const user = await requireUser(ctx);
  const creation = await ctx.db.get("creations", creationId);
  if (creation === null || creation.userId !== user._id) throw new ConvexError("No such design");
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

async function askStudio(ctx: MutationCtx, creation: Doc<"creations">, text: string, finish: boolean) {
  if (creation.thinking) throw new ConvexError("The studio is still answering");
  await ctx.db.insert("creationMessages", { creationId: creation._id, role: "maker", text });
  await ctx.db.patch("creations", creation._id, { thinking: true, status: "talking", error: undefined });
  await ctx.scheduler.runAfter(0, internal.ai.replyToCreation, { creationId: creation._id, finish });
}

/// This player's designs, newest first.
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

/// One design with its whole conversation.
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

/// Opens a design with the maker's first line and asks the studio to answer.
export const start = mutation({
  args: { text: v.string() },
  returns: v.id("creations"),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const text = cleanText(args.text);
    const creationId = await ctx.db.insert("creations", { userId: user._id, status: "talking", wish: text, thinking: true });
    await ctx.db.insert("creationMessages", { creationId, role: "maker", text });
    await ctx.scheduler.runAfter(0, internal.ai.replyToCreation, { creationId, finish: false });
    return creationId;
  },
});

/// Adds the maker's next line. A finished design can be reopened by talking to it again.
export const send = mutation({
  args: { creationId: v.id("creations"), text: v.string() },
  handler: async (ctx, args) => {
    const { creation } = await ownCreation(ctx, args.creationId);
    await askStudio(ctx, creation, cleanText(args.text), false);
    return null;
  },
});

/// The maker is happy: the studio writes the sheet out in full and the design is done.
export const finish = mutation({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const { creation } = await ownCreation(ctx, args.creationId);
    if (creation.status === "ready") return null;
    await askStudio(ctx, creation, "That is the game. Write the full sheet.", true);
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
    await ctx.scheduler.runAfter(0, internal.ai.replyToCreation, { creationId: creation._id, finish: false });
    return null;
  },
});

/// Throws a design away with its conversation.
export const remove = mutation({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const { creation } = await ownCreation(ctx, args.creationId);
    const messages = await ctx.db
      .query("creationMessages")
      .withIndex("by_creation", (q) => q.eq("creationId", creation._id))
      .take(200);
    for (const message of messages) await ctx.db.delete("creationMessages", message._id);
    await ctx.db.delete("creations", creation._id);
    return null;
  },
});

// MARK: For the studio's action

/// Everything the model needs: the maker's name, the sheet so far and the conversation.
export const context = internalQuery({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const creation = await ctx.db.get("creations", args.creationId);
    if (creation === null) return null;
    const user = await ctx.db.get("users", creation.userId);
    return {
      creation: publicCreation(creation),
      handle: user?.handle ?? "maker",
      messages: await messagesFor(ctx, creation._id),
    };
  },
});

/// The studio's answer: a line, choices or ideas to pick from, and the sheet with what it settled.
export const reply = internalMutation({
  args: {
    creationId: v.id("creations"),
    text: v.string(),
    options: v.optional(v.array(v.string())),
    ideas: v.optional(v.array(ideaValidator)),
    design: designValidator,
    progress: v.number(),
    done: v.boolean(),
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
    // The sheet only ever gains: a part the studio left out this time keeps its last value.
    const merged = { ...(creation.design ?? {}) };
    for (const [key, value] of Object.entries(args.design)) {
      if (value !== undefined && (typeof value !== "string" || value.trim().length > 0)) (merged as Record<string, unknown>)[key] = value;
    }
    await ctx.db.patch("creations", creation._id, {
      thinking: false,
      status: args.done ? "ready" : "talking",
      design: merged,
      progress: Math.max(creation.progress ?? 0, Math.min(1, Math.max(0, args.progress))),
    });
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
