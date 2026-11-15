import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

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
  }).index("by_slug", ["slug"]),

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

  purchases: defineTable({
    userId: v.id("users"),
    item: v.string(),
    price: v.number(),
  }).index("by_user_and_item", ["userId", "item"]),

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
