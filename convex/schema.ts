import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import { communityTables } from "./communitySchema";

export default defineSchema({
  users: defineTable({
    name: v.string(),
    handle: v.string(),
    color: v.string(),
    gold: v.number(),
    goldAllTime: v.number(),
    rounds: v.number(),
    streak: v.number(),
    lastGoldDay: v.optional(v.string()),
    fastGold: v.boolean(),
    seeded: v.boolean(),
    // Counts every change to this player's gold, so a phone can tell when its own change has landed.
    changes: v.optional(v.number()),
    // The Dailie this player wears: an item id per slot (convex/items.ts).
    avatar: v.optional(
      v.object({
        body: v.string(),
        face: v.string(),
        hair: v.optional(v.string()),
        hat: v.optional(v.string()),
        outfit: v.optional(v.string()),
        gadget: v.optional(v.string()),
      }),
    ),
  }).index("by_handle", ["handle"]),

  games: defineTable({
    slug: v.string(),
    title: v.string(),
    studio: v.string(),
    pitch: v.string(),
    how: v.string(),
    minPlayers: v.number(),
    maxPlayers: v.number(),
    mode: v.union(v.literal("casual"), v.literal("competitive")),
    category: v.string(),
    unit: v.string(),
    goldPerMinute: v.number(),
    likes: v.number(),
    dislikes: v.number(),
    plays: v.number(),
    comments: v.number(),
    order: v.number(),
    // Set on a game a player made in the studio. It plays on one of the built-in engines, named in kind.
    creatorId: v.optional(v.id("users")),
    kind: v.optional(v.string()),
    tint: v.optional(v.string()),
  }).index("by_slug", ["slug"]),

  // A game being made in the studio: the conversation that shapes it, then the game it became.
  creations: defineTable({
    userId: v.id("users"),
    status: v.union(v.literal("talking"), v.literal("building"), v.literal("ready"), v.literal("failed")),
    wish: v.string(),
    // true while the studio is working on its next reply.
    thinking: v.boolean(),
    title: v.optional(v.string()),
    pitch: v.optional(v.string()),
    how: v.optional(v.string()),
    category: v.optional(v.string()),
    kind: v.optional(v.string()),
    tint: v.optional(v.string()),
    unit: v.optional(v.string()),
    gameSlug: v.optional(v.string()),
    error: v.optional(v.string()),
  }).index("by_user", ["userId"]),

  creationMessages: defineTable({
    creationId: v.id("creations"),
    role: v.union(v.literal("maker"), v.literal("studio")),
    text: v.string(),
    options: v.optional(v.array(v.string())),
    ideas: v.optional(v.array(v.object({ title: v.string(), pitch: v.string() }))),
  }).index("by_creation", ["creationId"]),

  rounds: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    studio: v.string(),
    seed: v.number(),
    day: v.string(),
    startedAt: v.number(),
    endedAt: v.optional(v.number()),
    score: v.optional(v.number()),
    playMs: v.optional(v.number()),
    gold: v.optional(v.number()),
  }).index("by_user", ["userId"]),

  earnings: defineTable({
    userId: v.id("users"),
    day: v.string(),
    gameSlug: v.string(),
    studio: v.string(),
    gold: v.number(),
    playMs: v.number(),
    carry: v.optional(v.number()),
  }).index("by_user_and_day", ["userId", "day"]),

  bests: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    score: v.number(),
    day: v.string(),
    unit: v.optional(v.string()),
    text: v.optional(v.string()),
  })
    .index("by_gameSlug_and_score", ["gameSlug", "score"])
    .index("by_user_and_gameSlug", ["userId", "gameSlug"]),

  votes: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    value: v.union(v.literal(1), v.literal(-1)),
  }).index("by_user_and_gameSlug", ["userId", "gameSlug"]),

  rooms: defineTable({
    code: v.string(),
    gameSlug: v.string(),
    hostId: v.id("users"),
    seed: v.number(),
    round: v.number(),
    status: v.union(v.literal("lobby"), v.literal("playing")),
  }).index("by_code", ["code"]),

  roomPlayers: defineTable({
    roomId: v.id("rooms"),
    userId: v.id("users"),
    score: v.number(),
    done: v.boolean(),
    round: v.number(),
  })
    .index("by_room", ["roomId"])
    .index("by_user", ["userId"]),

  comments: defineTable({
    gameSlug: v.string(),
    userId: v.id("users"),
    body: v.string(),
    likes: v.optional(v.number()),
  })
    .index("by_gameSlug", ["gameSlug"])
    .index("by_user", ["userId"]),

  commentLikes: defineTable({
    userId: v.id("users"),
    key: v.string(),
  }).index("by_user_and_key", ["userId", "key"]),

  ledger: defineTable({
    userId: v.id("users"),
    kind: v.union(v.literal("round"), v.literal("spend")),
    title: v.string(),
    detail: v.string(),
    amount: v.number(),
    gameSlug: v.optional(v.string()),
  }).index("by_user", ["userId"]),

  clips: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    kind: v.union(v.literal("video"), v.literal("photo")),
    // Missing when the phone could not record (a simulator with no screen recording): the clip replays the game.
    storageId: v.optional(v.id("_storage")),
    roundId: v.optional(v.id("rounds")),
    // Copied from the round on the server, never taken from the phone.
    score: v.optional(v.number()),
    seed: v.optional(v.number()),
    caption: v.string(),
    layout: v.union(v.literal("cutout"), v.literal("bubble")),
    durationMs: v.number(),
    visibility: v.union(v.literal("friends"), v.literal("everyone")),
    likes: v.number(),
    comments: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_visibility", ["visibility"])
    .index("by_roundId", ["roundId"]),

  purchases: defineTable({
    userId: v.id("users"),
    item: v.string(),
    price: v.number(),
  }).index("by_user_and_item", ["userId", "item"]),

  // Avatar items a player bought. Free items are owned by everyone and have no row.
  inventory: defineTable({
    userId: v.id("users"),
    itemId: v.string(),
    price: v.number(),
  }).index("by_user_and_item", ["userId", "itemId"]),

  saved: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
  }).index("by_user_and_gameSlug", ["userId", "gameSlug"]),

  ...communityTables,

  chatConversations: defineTable({
    kind: v.union(v.literal("direct"), v.literal("group"), v.literal("workplace")),
    name: v.string(),
    icon: v.string(),
    key: v.optional(v.string()),
    domain: v.optional(v.string()),
    lastMessageAt: v.number(),
  })
    .index("by_key", ["key"])
    .index("by_domain", ["domain"]),

  chatMembers: defineTable({
    conversationId: v.id("chatConversations"),
    userId: v.id("users"),
    lastReadAt: v.number(),
  })
    .index("by_userId", ["userId"])
    .index("by_conversationId_and_userId", ["conversationId", "userId"]),

  chatMessages: defineTable({
    conversationId: v.id("chatConversations"),
    userId: v.id("users"),
    kind: v.union(v.literal("text"), v.literal("invite"), v.literal("score"), v.literal("post")),
    body: v.string(),
    gameSlug: v.optional(v.string()),
    roomCode: v.optional(v.string()),
    score: v.optional(v.number()),
    sentAt: v.optional(v.number()),
  }).index("by_conversationId", ["conversationId"]),

  chatTyping: defineTable({
    conversationId: v.id("chatConversations"),
    userId: v.id("users"),
    at: v.number(),
  }).index("by_conversationId_and_userId", ["conversationId", "userId"]),

  chatOnline: defineTable({
    userId: v.id("users"),
    at: v.number(),
  }).index("by_userId", ["userId"]),

  workplaceCodes: defineTable({
    userId: v.id("users"),
    domain: v.string(),
    code: v.string(),
    expiresAt: v.number(),
  }).index("by_userId", ["userId"]),
});
