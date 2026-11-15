import { ConvexError, v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { type MutationCtx, type QueryCtx, mutation, query } from "./_generated/server";
import { currentUser, gameBySlug, requireUser } from "./lib";

const LETTERS = "BCDFGHJKLMNPQRSTVWXZ";
const ROOM_SIZE = 6;

export async function roomByCode(ctx: QueryCtx | MutationCtx, code: string) {
  return await ctx.db
    .query("rooms")
    .withIndex("by_code", (q) => q.eq("code", code.trim().toUpperCase()))
    .unique();
}

async function playersIn(ctx: QueryCtx | MutationCtx, room: Doc<"rooms">) {
  return await ctx.db
    .query("roomPlayers")
    .withIndex("by_room", (q) => q.eq("roomId", room._id))
    .take(ROOM_SIZE * 2);
}

async function leaveOtherRooms(ctx: MutationCtx, user: Doc<"users">, keep?: Doc<"rooms">) {
  const seats = await ctx.db
    .query("roomPlayers")
    .withIndex("by_user", (q) => q.eq("userId", user._id))
    .take(20);
  for (const seat of seats) {
    if (keep && seat.roomId === keep._id) continue;
    await ctx.db.delete("roomPlayers", seat._id);
    const room = await ctx.db.get("rooms", seat.roomId);
    if (room === null) continue;
    const rest = await playersIn(ctx, room);
    if (rest.length === 0) await ctx.db.delete("rooms", room._id);
    else if (room.hostId === user._id) await ctx.db.patch("rooms", room._id, { hostId: rest[0].userId });
  }
}

export const create = mutation({
  args: { slug: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const game = await gameBySlug(ctx, args.slug);
    await leaveOtherRooms(ctx, user);
    let code = "";
    for (let attempt = 0; attempt < 12; attempt++) {
      code = Array.from({ length: 4 }, () => LETTERS[Math.floor(Math.random() * LETTERS.length)]).join("");
      if ((await roomByCode(ctx, code)) === null) break;
    }
    const roomId = await ctx.db.insert("rooms", {
      code,
      gameSlug: game.slug,
      hostId: user._id,
      seed: Math.floor(Math.random() * 1_000_000) + 1,
      round: 0,
      status: "lobby",
    });
    await ctx.db.insert("roomPlayers", { roomId, userId: user._id, score: 0, done: false, round: 0 });
    return code;
  },
});

export const join = mutation({
  args: { code: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const room = await roomByCode(ctx, args.code);
    if (room === null) throw new ConvexError("No room has that code");
    const players = await playersIn(ctx, room);
    if (!players.some((player) => player.userId === user._id)) {
      if (players.length >= ROOM_SIZE) throw new ConvexError("That room is full");
      await leaveOtherRooms(ctx, user);
      await ctx.db.insert("roomPlayers", { roomId: room._id, userId: user._id, score: 0, done: false, round: 0 });
    }
    return room.code;
  },
});

export const leave = mutation({
  args: {},
  handler: async (ctx) => {
    await leaveOtherRooms(ctx, await requireUser(ctx));
    return null;
  },
});

export const start = mutation({
  args: { code: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const room = await roomByCode(ctx, args.code);
    if (room === null) throw new ConvexError("No room has that code");
    if (room.hostId !== user._id) throw new ConvexError("Only the host starts the round");
    await ctx.db.patch("rooms", room._id, {
      seed: Math.floor(Math.random() * 1_000_000) + 1,
      round: room.round + 1,
      status: "playing",
    });
    return null;
  },
});

export const score = mutation({
  args: { code: v.string(), round: v.number(), score: v.number(), done: v.boolean() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const room = await roomByCode(ctx, args.code);
    if (room === null || room.round !== args.round) return null;
    const players = await playersIn(ctx, room);
    const seat = players.find((player) => player.userId === user._id);
    if (!seat) return null;
    const value = Number.isFinite(args.score) ? Math.max(0, Math.round(args.score * 10) / 10) : 0;
    await ctx.db.patch("roomPlayers", seat._id, { score: value, done: args.done, round: args.round });
    const allDone = players.every((player) => (player._id === seat._id ? args.done : player.round === room.round && player.done));
    if (allDone && room.status === "playing") await ctx.db.patch("rooms", room._id, { status: "lobby" });
    return null;
  },
});

export const get = query({
  args: { code: v.string() },
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    const room = await roomByCode(ctx, args.code);
    if (user === null || room === null) return null;
    const seats = await playersIn(ctx, room);
    if (!seats.some((seat) => seat.userId === user._id)) return null;
    const players = [];
    for (const seat of seats) {
      const player = await ctx.db.get("users", seat.userId);
      if (player === null) continue;
      const current = room.round > 0 && seat.round === room.round;
      players.push({
        id: seat.userId,
        name: player.name,
        color: player.color,
        you: seat.userId === user._id,
        host: seat.userId === room.hostId,
        score: current ? seat.score : 0,
        done: current && seat.done,
        playing: current && !seat.done,
      });
    }
    players.sort((a, b) => b.score - a.score);
    return {
      code: room.code,
      slug: room.gameSlug,
      round: room.round,
      seed: room.seed,
      status: room.status,
      host: room.hostId === user._id,
      players,
    };
  },
});
