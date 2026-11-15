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
  }).index("by_user_and_day", ["userId", "day"]),

  bests: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    score: v.number(),
    day: v.string(),
  })
    .index("by_gameSlug_and_score", ["gameSlug", "score"])
    .index("by_user_and_gameSlug", ["userId", "gameSlug"]),

  votes: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    value: v.union(v.literal(1), v.literal(-1)),
  }).index("by_user_and_gameSlug", ["userId", "gameSlug"]),

  comments: defineTable({
    gameSlug: v.string(),
    userId: v.id("users"),
    body: v.string(),
  }).index("by_gameSlug", ["gameSlug"]),
});
