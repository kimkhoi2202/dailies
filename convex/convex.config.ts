import auth from "@convex-dev/auth/convex.config";
import authPassword from "@convex-dev/auth/components/password/convex.config";
import authUsername from "@convex-dev/auth/components/username/convex.config";
import { defineApp } from "convex/server";
import { v } from "convex/values";

const app = defineApp({
  env: {
    WHOP_API_KEY: v.optional(v.string()),
    WHOP_WEBHOOK_SECRET: v.optional(v.string()),
    WHOP_ENVIRONMENT: v.optional(v.string()),
    WHOP_ACCOUNT_ID: v.optional(v.string()),
  },
});
app.use(auth);
app.use(authPassword);
app.use(authUsername);

export default app;
