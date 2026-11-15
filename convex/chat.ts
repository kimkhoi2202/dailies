import { ConvexError, v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { type MutationCtx, type QueryCtx, mutation, query } from "./_generated/server";
import { currentUser, requireUser } from "./lib";
import { FRIEND_HANDLES, giveStarterChats, insertConversation, workplaceName } from "./seedChat";

const ONLINE_MS = 2 * 60 * 1000;
const TYPING_MS = 5000;
const PERSONAL_DOMAINS = ["gmail.com", "googlemail.com", "yahoo.com", "outlook.com", "hotmail.com", "icloud.com", "me.com", "proton.me", "aol.com"];

async function membership(ctx: QueryCtx | MutationCtx, conversationId: Id<"chatConversations">, userId: Id<"users">) {
  return await ctx.db
    .query("chatMembers")
    .withIndex("by_conversationId_and_userId", (q) => q.eq("conversationId", conversationId).eq("userId", userId))
    .unique();
}

async function requireMember(ctx: QueryCtx | MutationCtx, conversationId: Id<"chatConversations">) {
  const user = await requireUser(ctx);
  const member = await membership(ctx, conversationId, user._id);
  if (member === null) throw new ConvexError("You are not in this chat");
  return { user, member };
}

async function membersOf(ctx: QueryCtx | MutationCtx, conversationId: Id<"chatConversations">) {
  return await ctx.db
    .query("chatMembers")
    .withIndex("by_conversationId_and_userId", (q) => q.eq("conversationId", conversationId))
    .take(200);
}

async function isOnline(ctx: QueryCtx, userId: Id<"users">) {
  const row = await ctx.db
    .query("chatOnline")
    .withIndex("by_userId", (q) => q.eq("userId", userId))
    .unique();
  return row !== null && Date.now() - row.at < ONLINE_MS;
}

async function person(ctx: QueryCtx, user: Doc<"users">) {
  return {
    _id: user._id,
    name: user.name,
    handle: user.handle,
    color: user.color,
    online: await isOnline(ctx, user._id),
  };
}

export const ping = mutation({
  args: {},
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    const row = await ctx.db
      .query("chatOnline")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .unique();
    if (row) await ctx.db.patch("chatOnline", row._id, { at: Date.now() });
    else await ctx.db.insert("chatOnline", { userId: user._id, at: Date.now() });
    await giveStarterChats(ctx, user._id);
    return null;
  },
});

export const inbox = query({
  args: {},
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return null;
    const memberships = await ctx.db
      .query("chatMembers")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .take(100);
    const chats = [];
    const friends = new Map<Id<"users">, Doc<"users">>();
    for (const member of memberships) {
      const conversation = await ctx.db.get("chatConversations", member.conversationId);
      if (conversation === null) continue;
      const last = await ctx.db
        .query("chatMessages")
        .withIndex("by_conversationId", (q) => q.eq("conversationId", conversation._id))
        .order("desc")
        .first();
      const members = await membersOf(ctx, conversation._id);
      let other = null;
      if (conversation.kind === "direct") {
        const otherId = members.find((row) => row.userId !== user._id)?.userId;
        const otherUser = otherId ? await ctx.db.get("users", otherId) : null;
        if (otherUser) {
          friends.set(otherUser._id, otherUser);
          other = await person(ctx, otherUser);
        }
      }
      const lastAuthor = last ? await ctx.db.get("users", last.userId) : null;
      chats.push({
        _id: conversation._id,
        kind: conversation.kind,
        name: other ? other.name : conversation.name,
        icon: conversation.icon,
        domain: conversation.domain ?? null,
        other,
        memberCount: members.length,
        at: last ? (last.sentAt ?? last._creationTime) : conversation.lastMessageAt,
        preview: last ? preview(last, lastAuthor, user._id, conversation.kind !== "direct") : "Say hi",
        unread: last !== null && last.userId !== user._id && last._creationTime > member.lastReadAt,
      });
    }
    chats.sort((a, b) => b.at - a.at);
    const friendRows = await Promise.all([...friends.values()].map((friend) => person(ctx, friend)));
    friendRows.sort((a, b) => Number(b.online) - Number(a.online));
    return { chats, friends: friendRows };
  },
});

function preview(message: Doc<"chatMessages">, author: Doc<"users"> | null, me: Id<"users">, group: boolean) {
  const who = message.userId === me ? "You: " : group && author ? author.name + ": " : "";
  if (message.kind === "invite") return who + "Sent a game invite";
  if (message.kind === "score") return who + "Shared a score";
  if (message.kind === "post") return who + "Shared a post";
  return who + message.body;
}

function weekNumber() {
  return Math.floor((Date.now() / 86400000 + 3) / 7);
}

export const conversation = query({
  args: { conversationId: v.id("chatConversations") },
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    if (user === null) return null;
    const conversation = await ctx.db.get("chatConversations", args.conversationId);
    if (conversation === null || (await membership(ctx, conversation._id, user._id)) === null) return null;
    const members = await membersOf(ctx, conversation._id);
    const people = new Map<Id<"users">, Awaited<ReturnType<typeof person>>>();
    for (const row of members) {
      const doc = await ctx.db.get("users", row.userId);
      if (doc) people.set(doc._id, await person(ctx, doc));
    }
    const recent = await ctx.db
      .query("chatMessages")
      .withIndex("by_conversationId", (q) => q.eq("conversationId", conversation._id))
      .order("desc")
      .take(80);
    const messages = [];
    for (const message of recent.reverse()) {
      let author = people.get(message.userId);
      if (!author) {
        const doc = await ctx.db.get("users", message.userId);
        if (doc) author = await person(ctx, doc);
      }
      messages.push({
        _id: message._id,
        kind: message.kind,
        body: message.body,
        gameSlug: message.gameSlug ?? null,
        roomCode: message.roomCode ?? null,
        score: message.score ?? null,
        at: message.sentAt ?? message._creationTime,
        mine: message.userId === user._id,
        author: author ? { name: author.name, handle: author.handle, color: author.color } : null,
      });
    }
    const typing = [];
    for (const row of members) {
      if (row.userId === user._id) continue;
      const signal = await ctx.db
        .query("chatTyping")
        .withIndex("by_conversationId_and_userId", (q) => q.eq("conversationId", conversation._id).eq("userId", row.userId))
        .unique();
      if (signal && Date.now() - signal.at < TYPING_MS) typing.push(people.get(row.userId)?.name ?? "Someone");
    }
    const others = [...people.values()].filter((row) => row._id !== user._id);
    let board = null;
    if (conversation.kind !== "direct") {
      const games = (await ctx.db.query("games").take(60)).sort((a, b) => a.order - b.order);
      const game = games.length ? games[weekNumber() % games.length] : null;
      if (game) {
        const rows = [];
        for (const row of members) {
          const best = await ctx.db
            .query("bests")
            .withIndex("by_user_and_gameSlug", (q) => q.eq("userId", row.userId).eq("gameSlug", game.slug))
            .unique();
          const who = people.get(row.userId);
          if (best && who) rows.push({ name: who.name, color: who.color, score: best.score, you: row.userId === user._id });
        }
        rows.sort((a, b) => b.score - a.score);
        board = { slug: game.slug, title: game.title, unit: game.unit, rows: rows.slice(0, 5) };
      }
    }
    return {
      _id: conversation._id,
      kind: conversation.kind,
      name: conversation.kind === "direct" ? (others[0]?.name ?? "Chat") : conversation.name,
      icon: conversation.icon,
      domain: conversation.domain ?? null,
      other: conversation.kind === "direct" ? (others[0] ?? null) : null,
      memberCount: members.length,
      members: [...people.values()],
      messages,
      typing,
      board,
    };
  },
});

export const send = mutation({
  args: {
    conversationId: v.id("chatConversations"),
    kind: v.union(v.literal("text"), v.literal("invite"), v.literal("score"), v.literal("post")),
    body: v.string(),
    gameSlug: v.optional(v.string()),
    roomCode: v.optional(v.string()),
    score: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { user, member } = await requireMember(ctx, args.conversationId);
    const body = args.body.trim();
    if (body.length > 500) throw new ConvexError("Messages are up to 500 characters");
    if (args.kind === "text" && body.length === 0) throw new ConvexError("Write something first");
    if (args.kind !== "text" && !args.gameSlug) throw new ConvexError("Pick a game");
    const now = Date.now();
    await ctx.db.insert("chatMessages", {
      conversationId: args.conversationId,
      userId: user._id,
      kind: args.kind,
      body,
      gameSlug: args.gameSlug,
      roomCode: args.roomCode,
      score: args.score,
    });
    await ctx.db.patch("chatConversations", args.conversationId, { lastMessageAt: now });
    await ctx.db.patch("chatMembers", member._id, { lastReadAt: now });
    const signal = await ctx.db
      .query("chatTyping")
      .withIndex("by_conversationId_and_userId", (q) => q.eq("conversationId", args.conversationId).eq("userId", user._id))
      .unique();
    if (signal) await ctx.db.delete("chatTyping", signal._id);
    return null;
  },
});

export const markRead = mutation({
  args: { conversationId: v.id("chatConversations") },
  handler: async (ctx, args) => {
    const { member } = await requireMember(ctx, args.conversationId);
    await ctx.db.patch("chatMembers", member._id, { lastReadAt: Date.now() });
    return null;
  },
});

export const typing = mutation({
  args: { conversationId: v.id("chatConversations") },
  handler: async (ctx, args) => {
    const { user } = await requireMember(ctx, args.conversationId);
    const signal = await ctx.db
      .query("chatTyping")
      .withIndex("by_conversationId_and_userId", (q) => q.eq("conversationId", args.conversationId).eq("userId", user._id))
      .unique();
    if (signal) await ctx.db.patch("chatTyping", signal._id, { at: Date.now() });
    else await ctx.db.insert("chatTyping", { conversationId: args.conversationId, userId: user._id, at: Date.now() });
    return null;
  },
});

export const openDirect = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (user._id === args.userId) throw new ConvexError("That is you");
    const other = await ctx.db.get("users", args.userId);
    if (other === null) throw new ConvexError("No such player");
    const key = [user._id, other._id].sort().join(":");
    const existing = await ctx.db
      .query("chatConversations")
      .withIndex("by_key", (q) => q.eq("key", key))
      .unique();
    if (existing) {
      if ((await membership(ctx, existing._id, user._id)) === null)
        await ctx.db.insert("chatMembers", { conversationId: existing._id, userId: user._id, lastReadAt: 0 });
      return existing._id;
    }
    return await insertConversation(ctx, { kind: "direct", name: "", icon: "", key }, [user._id, other._id]);
  },
});

/** People you can start a chat or group with: the seeded friends plus everyone you already talk to. */
export const people = query({
  args: {},
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return [];
    const found = new Map<Id<"users">, Doc<"users">>();
    for (const handle of FRIEND_HANDLES) {
      const doc = await ctx.db
        .query("users")
        .withIndex("by_handle", (q) => q.eq("handle", handle))
        .unique();
      if (doc) found.set(doc._id, doc);
    }
    const memberships = await ctx.db
      .query("chatMembers")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .take(100);
    for (const member of memberships) {
      const conversation = await ctx.db.get("chatConversations", member.conversationId);
      if (conversation?.kind !== "direct") continue;
      for (const row of await membersOf(ctx, conversation._id)) {
        if (found.has(row.userId)) continue;
        const doc = await ctx.db.get("users", row.userId);
        if (doc) found.set(doc._id, doc);
      }
    }
    found.delete(user._id);
    return await Promise.all([...found.values()].map((doc) => person(ctx, doc)));
  },
});

export const createGroup = mutation({
  args: { name: v.string(), icon: v.string(), userIds: v.array(v.id("users")) },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const name = args.name.trim().replace(/\s+/g, " ");
    if (name.length < 2 || name.length > 30) throw new ConvexError("Group names are 2 to 30 characters");
    const ids = [...new Set(args.userIds)].filter((id) => id !== user._id);
    if (ids.length === 0) throw new ConvexError("Pick at least one friend");
    if (ids.length > 30) throw new ConvexError("Groups hold up to 30 friends");
    for (const id of ids) if ((await ctx.db.get("users", id)) === null) throw new ConvexError("No such player");
    const conversationId = await insertConversation(ctx, { kind: "group", name, icon: args.icon.slice(0, 40) || "gamecontroller.fill" }, [user._id, ...ids]);
    await ctx.db.insert("chatMessages", { conversationId, userId: user._id, kind: "text", body: `Made ${name}. First one to beat my score picks the next game.` });
    return conversationId;
  },
});

export const requestWorkplaceCode = mutation({
  args: { email: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const email = args.email.trim().toLowerCase();
    const match = /^[^\s@]+@([a-z0-9-]+(\.[a-z0-9-]+)+)$/.exec(email);
    if (!match) throw new ConvexError("That does not look like an email");
    const domain = match[1];
    if (PERSONAL_DOMAINS.includes(domain)) throw new ConvexError("Use a work or school email");
    const code = String(Math.floor(100000 + Math.random() * 900000));
    const existing = await ctx.db
      .query("workplaceCodes")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .unique();
    const row = { userId: user._id, domain, code, expiresAt: Date.now() + 10 * 60 * 1000 };
    if (existing) await ctx.db.replace("workplaceCodes", existing._id, row);
    else await ctx.db.insert("workplaceCodes", row);
    return { domain, name: workplaceName(domain), demoCode: code };
  },
});

export const verifyWorkplaceCode = mutation({
  args: { code: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const pending = await ctx.db
      .query("workplaceCodes")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .unique();
    if (pending === null || pending.expiresAt < Date.now()) throw new ConvexError("That code expired. Ask for a new one");
    if (pending.code !== args.code.trim()) throw new ConvexError("That code is not right");
    await ctx.db.delete("workplaceCodes", pending._id);
    const existing = await ctx.db
      .query("chatConversations")
      .withIndex("by_domain", (q) => q.eq("domain", pending.domain))
      .first();
    if (existing === null)
      return await insertConversation(ctx, { kind: "workplace", name: workplaceName(pending.domain), icon: "building.2.fill", domain: pending.domain }, [user._id]);
    if ((await membership(ctx, existing._id, user._id)) === null) {
      await ctx.db.insert("chatMembers", { conversationId: existing._id, userId: user._id, lastReadAt: 0 });
      await ctx.db.insert("chatMessages", { conversationId: existing._id, userId: user._id, kind: "text", body: "Just joined. Who is up for a round?" });
      await ctx.db.patch("chatConversations", existing._id, { lastMessageAt: Date.now() });
    }
    return existing._id;
  },
});
