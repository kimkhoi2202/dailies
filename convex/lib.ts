import { getAuthUserId } from "@convex-dev/auth/server";
import { ConvexError } from "convex/values";
import type { Id } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";

export const GAME_DAILY_LIMIT = 100;
export const STUDIO_DAILY_LIMIT = 300;
/** What one round may collect: this much, plus one gold for every two seconds since it opened. */
export const ROUND_HEAD_START = 30;
/** Gold for time with the app open, each mark once a day. The same list as AppTime.marks in the app. */
export const TIME_MARKS = [
  { minutes: 15, gold: 5 },
  { minutes: 30, gold: 5 },
  { minutes: 60, gold: 10 },
  { minutes: 120, gold: 20 },
  { minutes: 180, gold: 20 },
  { minutes: 240, gold: 25 },
  { minutes: 300, gold: 25 },
  { minutes: 360, gold: 40 },
];

export async function currentUser(ctx: QueryCtx | MutationCtx) {
  const userId = await getAuthUserId(ctx);
  if (userId === null) return null;
  return await ctx.db.get("users", userId);
}

export async function requireUser(ctx: QueryCtx | MutationCtx) {
  const user = await currentUser(ctx);
  if (user === null) throw new ConvexError("Not signed in");
  return user;
}

export function dayNumber(day: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new ConvexError("Bad day");
  const ms = Date.parse(day + "T00:00:00Z");
  if (Number.isNaN(ms)) throw new ConvexError("Bad day");
  return Math.round(ms / 86400000);
}

export function assertCurrentDay(day: string) {
  if (Math.abs(dayNumber(day) - Date.now() / 86400000) > 1.6) throw new ConvexError("Bad day");
}

export function playedText(playMs: number) {
  const total = Math.max(0, Math.round(playMs / 1000));
  if (total >= 3600) return `${Math.floor(total / 3600)}h ${Math.floor((total % 3600) / 60)}m`;
  if (total >= 60) return `${Math.floor(total / 60)}m ${String(total % 60).padStart(2, "0")}s`;
  return `${total}s`;
}

export async function earningsFor(ctx: QueryCtx | MutationCtx, userId: Id<"users">, day: string) {
  return await ctx.db
    .query("earnings")
    .withIndex("by_user_and_day", (q) => q.eq("userId", userId).eq("day", day))
    .take(200);
}

export async function gameBySlug(ctx: QueryCtx | MutationCtx, slug: string) {
  const game = await ctx.db
    .query("games")
    .withIndex("by_slug", (q) => q.eq("slug", slug))
    .unique();
  if (game === null) throw new ConvexError("No such game");
  return game;
}
