import auth from "@convex-dev/auth/convex.config";
import authGoogle from "@convex-dev/auth/components/google/convex.config";
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
    AUTH_GOOGLE_CLIENT_ID: v.string(),
    AUTH_GOOGLE_CLIENT_SECRET: v.string(),
  },
});
app.use(auth);
app.use(authPassword);
app.use(authUsername);
// Google sends people back to <site>/oauth/google/callback, so the prefix is part of the client's setup in Google Cloud.
app.use(authGoogle, {
  httpPrefix: "/oauth/google",
  env: { CLIENT_ID: app.env.AUTH_GOOGLE_CLIENT_ID, CLIENT_SECRET: app.env.AUTH_GOOGLE_CLIENT_SECRET },
});

export default app;
