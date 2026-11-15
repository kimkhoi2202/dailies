import { defineTable } from "convex/server";
import { v } from "convex/values";

// Community's tables: friends' posts and the reactions on them, ratings, challenges, who is playing
// now, and notifications. Spread into schema.ts.

export const postKind = v.union(
  v.literal("best"),
  v.literal("passed"),
  v.literal("rated"),
  v.literal("streak"),
  v.literal("video"),
  v.literal("game"),
);

export const reactionKind = v.union(v.literal("gg"), v.literal("fire"), v.literal("crown"), v.literal("clap"));

export const ratingBand = v.union(v.literal("loved"), v.literal("fine"), v.literal("not"));

export const communityTables = {
  follows: defineTable({
    fromId: v.id("users"),
    toId: v.id("users"),
  })
    .index("by_fromId_and_toId", ["fromId", "toId"])
    .index("by_toId", ["toId"]),

  posts: defineTable({
    userId: v.id("users"),
    kind: postKind,
    gameSlug: v.string(),
    score: v.optional(v.number()),
    scoreText: v.optional(v.string()),
    unit: v.optional(v.string()),
    rating: v.optional(v.number()),
    text: v.optional(v.string()),
    at: v.number(),
  })
    .index("by_at", ["at"])
    .index("by_userId_and_at", ["userId", "at"]),

  reactions: defineTable({
    postId: v.id("posts"),
    userId: v.id("users"),
    kind: reactionKind,
  })
    .index("by_postId", ["postId"])
    .index("by_postId_and_userId_and_kind", ["postId", "userId", "kind"]),

  postComments: defineTable({
    postId: v.id("posts"),
    userId: v.id("users"),
    body: v.string(),
  }).index("by_postId", ["postId"]),

  ratings: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    band: ratingBand,
    rank: v.number(),
    score: v.number(),
  })
    .index("by_userId_and_gameSlug", ["userId", "gameSlug"])
    .index("by_gameSlug", ["gameSlug"]),

  challenges: defineTable({
    fromId: v.id("users"),
    // No one named: open to every player.
    toId: v.optional(v.id("users")),
    gameSlug: v.string(),
    target: v.number(),
    targetText: v.string(),
    unit: v.string(),
    expiresAt: v.number(),
    status: v.union(v.literal("open"), v.literal("accepted"), v.literal("done")),
  }).index("by_status_and_expiresAt", ["status", "expiresAt"]),

  presence: defineTable({
    userId: v.id("users"),
    gameSlug: v.string(),
    lastSeen: v.number(),
  })
    .index("by_userId", ["userId"])
    .index("by_lastSeen", ["lastSeen"]),

  notifications: defineTable({
    userId: v.id("users"),
    actorName: v.string(),
    kind: v.string(),
    text: v.string(),
    gameSlug: v.optional(v.string()),
    read: v.boolean(),
    at: v.number(),
  })
    .index("by_userId_and_at", ["userId", "at"])
    .index("by_userId_and_read", ["userId", "read"]),
};
