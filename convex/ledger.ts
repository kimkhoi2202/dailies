import { query } from "./_generated/server";
import { currentUser } from "./lib";

/** Every gold collected or spent by the signed-in player, newest first. */
export const list = query({
  args: {},
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return null;
    const rows = await ctx.db
      .query("ledger")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(60);
    return rows.map((row) => ({
      _id: row._id,
      kind: row.kind,
      title: row.title,
      detail: row.detail,
      amount: row.amount,
      gameSlug: row.gameSlug ?? null,
      at: row._creationTime,
    }));
  },
});
