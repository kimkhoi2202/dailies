import { setupGoogle } from "@convex-dev/auth/methods/google/server";
import { setupUsernamePassword } from "@convex-dev/auth/methods/username-password/server";
import { setupConvexAuth } from "@convex-dev/auth/server";
import { v } from "convex/values";
import { components, internal } from "./_generated/api";
import { env, query } from "./_generated/server";

const auth = setupConvexAuth({ component: components.auth });

export const { signOut, refreshSession, isAuthenticated } = auth;

export const { signUpWithUsernamePassword, signInWithUsernamePassword } = setupUsernamePassword(auth, {
  component: components.authPassword,
  usernameComponent: components.authUsername,
}).attachUserCallbacks({ createUser: internal.users.createForDevice });

// Google. The app never calls completeSignInWithGoogle itself: users:connect does, as the player on the phone.
export const { startSignInWithGoogle, completeSignInWithGoogle } = setupGoogle(auth, {
  component: components.authGoogle,
  // Sign-in ends on this deployment's /auth/done page, which passes the answer on to the app.
  allowedRedirectOrigins: [env.CONVEX_SITE_URL],
}).attachUserCallbacks({ createUser: internal.users.createForGoogle });

// The ways to sign in besides a username and password. The app shows a button for each one that is on.
export const methods = query({
  args: {},
  returns: v.object({ apple: v.boolean(), google: v.boolean() }),
  handler: async () => ({ apple: false, google: true }),
});
