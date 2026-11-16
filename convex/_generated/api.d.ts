/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as ai from "../ai.js";
import type * as auth from "../auth.js";
import type * as avatar from "../avatar.js";
import type * as chat from "../chat.js";
import type * as clips from "../clips.js";
import type * as community from "../community.js";
import type * as communitySchema from "../communitySchema.js";
import type * as creations from "../creations.js";
import type * as creators from "../creators.js";
import type * as games from "../games.js";
import type * as http from "../http.js";
import type * as items from "../items.js";
import type * as ledger from "../ledger.js";
import type * as lib from "../lib.js";
import type * as library from "../library.js";
import type * as rooms from "../rooms.js";
import type * as rounds from "../rounds.js";
import type * as seed from "../seed.js";
import type * as seedChat from "../seedChat.js";
import type * as seedCommunity from "../seedCommunity.js";
import type * as shop from "../shop.js";
import type * as social from "../social.js";
import type * as users from "../users.js";
import type * as whop from "../whop.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  ai: typeof ai;
  auth: typeof auth;
  avatar: typeof avatar;
  chat: typeof chat;
  clips: typeof clips;
  community: typeof community;
  communitySchema: typeof communitySchema;
  creations: typeof creations;
  creators: typeof creators;
  games: typeof games;
  http: typeof http;
  items: typeof items;
  ledger: typeof ledger;
  lib: typeof lib;
  library: typeof library;
  rooms: typeof rooms;
  rounds: typeof rounds;
  seed: typeof seed;
  seedChat: typeof seedChat;
  seedCommunity: typeof seedCommunity;
  shop: typeof shop;
  social: typeof social;
  users: typeof users;
  whop: typeof whop;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  auth: import("@convex-dev/auth/_generated/component.js").ComponentApi<"auth">;
  authGoogle: import("@convex-dev/auth/components/google/_generated/component.js").ComponentApi<"authGoogle">;
  authPassword: import("@convex-dev/auth/components/password/_generated/component.js").ComponentApi<"authPassword">;
  authUsername: import("@convex-dev/auth/components/username/_generated/component.js").ComponentApi<"authUsername">;
};
