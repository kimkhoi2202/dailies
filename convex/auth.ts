import { setupUsernamePassword } from "@convex-dev/auth/methods/username-password/server";
import { setupConvexAuth } from "@convex-dev/auth/server";
import { v } from "convex/values";
import { components, internal } from "./_generated/api";
import { query } from "./_generated/server";

const auth = setupConvexAuth({ component: components.auth });

export const { signOut, refreshSession, isAuthenticated } = auth;

export const { signUpWithUsernamePassword, signInWithUsernamePassword } = setupUsernamePassword(auth, {
  component: components.authPassword,
  usernameComponent: components.authUsername,
}).attachUserCallbacks({ createUser: internal.users.createForDevice });

// The ways to sign in besides a username and password. The app shows a button for each one that is on.
export const methods = query({
  args: {},
  returns: v.object({ apple: v.boolean(), google: v.boolean() }),
  handler: async () => ({ apple: false, google: false }),
});
