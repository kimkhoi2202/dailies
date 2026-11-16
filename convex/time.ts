import { v } from "convex/values";
import { mutation } from "./_generated/server";
import { TIME_MARKS, assertCurrentDay, requireUser } from "./lib";

/** Beats further apart than this are two visits, and the time between them is not counted. */
const LONGEST_GAP_MS = 90_000;

/**
 * The app calls this when it opens and every half minute while it stays open. The server adds the
 * time since the last beat to the day, and gives the gold of every mark the day has now passed.
 */
export const beat = mutation({
  args: { day: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    assertCurrentDay(args.day);
    const now = Date.now();
    const row = await ctx.db
      .query("appTime")
      .withIndex("by_user_and_day", (q) => q.eq("userId", user._id).eq("day", args.day))
      .unique();
    const gap = row === null ? 0 : now - row.lastBeatAt;
    const ms = (row?.ms ?? 0) + (gap > 0 && gap <= LONGEST_GAP_MS ? gap : 0);

    let marks = row?.marks ?? 0;
    let gold = 0;
    while (marks < TIME_MARKS.length && ms >= TIME_MARKS[marks].minutes * 60000) {
      const mark = TIME_MARKS[marks];
      gold += mark.gold;
      await ctx.db.insert("ledger", {
        userId: user._id,
        kind: "time",
        title: "Time in DEGEN",
        detail: mark.minutes < 60 ? `${mark.minutes} minutes today` : mark.minutes === 60 ? "1 hour today" : `${mark.minutes / 60} hours today`,
        amount: mark.gold,
      });
      marks += 1;
    }

    if (row === null) await ctx.db.insert("appTime", { userId: user._id, day: args.day, ms, lastBeatAt: now, marks });
    else await ctx.db.patch("appTime", row._id, { ms, lastBeatAt: now, marks });
    const changes = (user.changes ?? 0) + (gold > 0 ? 1 : 0);
    if (gold > 0)
      await ctx.db.patch("users", user._id, { gold: user.gold + gold, goldAllTime: user.goldAllTime + gold, changes });

    return { ms, marks, gold, changes };
  },
});
