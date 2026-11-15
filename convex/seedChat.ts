import type { Id } from "./_generated/dataModel";
import { type MutationCtx, internalMutation } from "./_generated/server";

export const FRIEND_HANDLES = ["devon.plays", "kaz", "noor.runs", "tofu", "juno", "wordnerd.sam"];

const KNOWN_WORKPLACES: Record<string, string> = {
  "stanford.edu": "Stanford",
  "meta.com": "Meta",
  "berkeley.edu": "Berkeley",
  "google.com": "Google",
  "mit.edu": "MIT",
};

export function workplaceName(domain: string) {
  const known = KNOWN_WORKPLACES[domain];
  if (known) return known;
  const label = domain.split(".")[0];
  return label.charAt(0).toUpperCase() + label.slice(1);
}

type Line = { from: number; kind?: "text" | "invite" | "score" | "post"; body: string; gameSlug?: string; score?: number; minutesAgo: number };

export async function insertConversation(
  ctx: MutationCtx,
  fields: { kind: "direct" | "group" | "workplace"; name: string; icon: string; key?: string; domain?: string },
  userIds: Id<"users">[],
) {
  const conversationId = await ctx.db.insert("chatConversations", { ...fields, lastMessageAt: Date.now() });
  for (const userId of userIds) await ctx.db.insert("chatMembers", { conversationId, userId, lastReadAt: 0 });
  return conversationId;
}

async function writeLines(ctx: MutationCtx, conversationId: Id<"chatConversations">, people: Id<"users">[], lines: Line[]) {
  const now = Date.now();
  for (const line of lines) {
    await ctx.db.insert("chatMessages", {
      conversationId,
      userId: people[line.from],
      kind: line.kind ?? "text",
      body: line.body,
      gameSlug: line.gameSlug,
      score: line.score,
      sentAt: now - line.minutesAgo * 60000,
    });
  }
  const last = lines[lines.length - 1];
  if (last) await ctx.db.patch("chatConversations", conversationId, { lastMessageAt: now - last.minutesAgo * 60000 });
}

async function friendIds(ctx: MutationCtx) {
  const ids: Id<"users">[] = [];
  for (const handle of FRIEND_HANDLES) {
    const user = await ctx.db
      .query("users")
      .withIndex("by_handle", (q) => q.eq("handle", handle))
      .unique();
    if (user) ids.push(user._id);
  }
  return ids;
}

/** The shared groups. Safe to run again. */
async function ensureCommunity(ctx: MutationCtx) {
  const friends = await friendIds(ctx);
  if (friends.length < 6) return null;

  let squad = await ctx.db
    .query("chatConversations")
    .withIndex("by_key", (q) => q.eq("key", "seed:squad"))
    .unique();
  if (squad === null) {
    const id = await insertConversation(ctx, { kind: "group", name: "Hackathon squad", icon: "hammer.fill", key: "seed:squad" }, friends);
    await writeLines(ctx, id, friends, [
      { from: 1, body: "demo is at six. who is still building", minutesAgo: 95 },
      { from: 3, body: "me. fueled by snacks", minutesAgo: 90 },
      { from: 0, kind: "score", body: "Beat it before the demo", gameSlug: "tippy-tower", score: 58, minutesAgo: 62 },
      { from: 4, body: "58 floors is unreal", minutesAgo: 60 },
      { from: 2, kind: "invite", body: "Quick round on the break?", gameSlug: "lane-dash", minutesAgo: 24 },
      { from: 5, body: "in. loser buys coffee", minutesAgo: 21 },
    ]);
    squad = await ctx.db.get("chatConversations", id);
  }

  const stanford = await ctx.db
    .query("chatConversations")
    .withIndex("by_domain", (q) => q.eq("domain", "stanford.edu"))
    .first();
  if (stanford === null) {
    const members = [friends[1], friends[4], friends[5]];
    const id = await insertConversation(ctx, { kind: "workplace", name: "Stanford", icon: "graduationcap.fill", domain: "stanford.edu" }, members);
    await writeLines(ctx, id, members, [
      { from: 0, body: "library quiet floor Five Up tournament tonight?", minutesAgo: 180 },
      { from: 2, kind: "score", body: "Opening bid", gameSlug: "five-up", score: 585, minutesAgo: 170 },
      { from: 1, body: "cs106 people are getting destroyed", minutesAgo: 150 },
    ]);
  }

  return squad;
}

/** Gives a new player four DMs with history and a seat in the squad group, so the inbox is alive on first open. */
export async function giveStarterChats(ctx: MutationCtx, userId: Id<"users">) {
  const already = await ctx.db
    .query("chatMembers")
    .withIndex("by_userId", (q) => q.eq("userId", userId))
    .first();
  if (already !== null) return;
  const squad = await ensureCommunity(ctx);
  if (squad === null) return;
  const friends = await friendIds(ctx);
  const starters: { friend: number; lines: Line[] }[] = [
    {
      friend: 1,
      lines: [
        { from: 1, body: "you up?", minutesAgo: 48 },
        { from: 1, kind: "invite", body: "Play Five Up with me", gameSlug: "five-up", minutesAgo: 47 },
      ],
    },
    {
      friend: 0,
      lines: [
        { from: 0, body: "saw your tower. not bad", minutesAgo: 130 },
        { from: 1, body: "not bad? that was my best ever", minutesAgo: 128 },
        { from: 0, kind: "score", body: "Beat it?", gameSlug: "tippy-tower", score: 58, minutesAgo: 120 },
      ],
    },
    {
      friend: 2,
      lines: [
        { from: 0, kind: "post", body: "the near miss at the end. I stopped breathing", gameSlug: "lane-dash", minutesAgo: 300 },
        { from: 0, body: "this clip is everything", minutesAgo: 299 },
      ],
    },
    {
      friend: 4,
      lines: [
        { from: 0, body: "inkland later? I need revenge", minutesAgo: 1500 },
        { from: 1, body: "only if you stop cutting my trail", minutesAgo: 1490 },
      ],
    },
  ];
  for (const starter of starters) {
    const friend = friends[starter.friend];
    const key = [userId, friend].sort().join(":");
    const existing = await ctx.db
      .query("chatConversations")
      .withIndex("by_key", (q) => q.eq("key", key))
      .unique();
    if (existing) continue;
    const id = await insertConversation(ctx, { kind: "direct", name: "", icon: "", key }, [userId, friend]);
    await writeLines(ctx, id, [friend, userId], starter.lines);
  }
  await ctx.db.insert("chatMembers", { conversationId: squad._id, userId, lastReadAt: 0 });
}

export const run = internalMutation({
  args: {},
  handler: async (ctx) => {
    const squad = await ensureCommunity(ctx);
    return { ready: squad !== null };
  },
});
