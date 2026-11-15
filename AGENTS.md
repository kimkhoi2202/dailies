# Dailies

Consumer mobile app for [The Consumer Mobile Hackathon](https://consumermobilehackathon.com) (Sunday, November 15, 2026). The site's tool guides are the source of truth for each sponsor tool; read the linked page before integrating one.

## Hackathon rules

- The project must use Capy, Revyl and Convex, or it isn't eligible for prizes.
- Submissions are due at 6:00 PM Pacific (https://consumermobilehackathon.com/submit). Finalists demo live on a phone.
- All code is written after 10:00 AM on the day. Don't copy in older code.

## Stack

- Expo SDK 58 with Expo Router and TypeScript at the repository root. Screens live in `src/app/`.
- Convex backend in `convex/`. The dev deployment is `blissful-labrador-581` in the `khoilam/dailies` Convex project (client URL `https://blissful-labrador-581.convex.cloud`, HTTP actions URL `https://blissful-labrador-581.convex.site`).
- npm is the package manager.
- After any change under `convex/`, run `npx convex dev --once` and fix what it reports.

## Secrets and environment

- `.env.local` is git-ignored. Any build made outside this checkout (Revyl, a cloud machine) must set `EXPO_PUBLIC_CONVEX_URL` itself.
- Third-party keys never ship in the app and never go in an `EXPO_PUBLIC_` variable. Copy each one from the machine's environment into Convex with `npx convex env set NAME "$NAME"` and read it only inside a Convex action. Never import a sponsor SDK in the Expo app.
- Cloud machines reach Convex through `CONVEX_DEPLOY_KEY` in the Capy project's environment variables.

## Sponsor tools

| Tool | Guide | How it is used here |
| - | - | - |
| Revyl | https://consumermobilehackathon.com/revyl | Capy builds on Revyl and installs on a cloud phone from a cloud thread: a standalone simulator build with the JavaScript bundled and `EXPO_PUBLIC_CONVEX_URL` set. No Revyl account or key is needed on that path. |
| Convex | https://consumermobilehackathon.com/convex | Schema, queries, mutations, actions, Convex Auth with `expo-secure-store`. Read `convex/_generated/ai/guidelines.md` first. |
| Whop | https://consumermobilehackathon.com/whop | `@whop/sdk` in Convex and `expo-web-browser` in the app. A Convex action creates the checkout, an HTTP action at `/whop` verifies `payment.succeeded` with `unwrapWebhook`. Unlock from the Convex record the webhook writes. Variables: `WHOP_API_KEY`, `WHOP_WEBHOOK_SECRET`, `WHOP_ENVIRONMENT=sandbox`. |
| Supermemory | https://consumermobilehackathon.com/supermemory | `supermemory` npm package, v5 calls (`supermemory.add(userId, ...)`, `supermemory.search(userId, ...)`), only from a Convex action. Skill in `.agents/skills/supermemory`. Variable: `SUPERMEMORY_API_KEY`. |
| Keiki | https://consumermobilehackathon.com/keiki | The `openai` package pointed at `https://onkeiki.com/api/v1/openai` from a Convex action, with the agent's name as the model and the user's id in `x-conversation-id`. Variable: `KEIKI_API_KEY`. |
| OpenAI | https://consumermobilehackathon.com/openai | Responses API with `gpt-6-luna`, in a Convex action in `convex/ai.ts` in the default Convex runtime. Variable: `OPENAI_API_KEY`. |

## Build log

`hackathon.md` is the public build log the Convex hackathon skill maintains. After meaningful work, update it with `$convex-hackathon-skill`.

## Worktrees

The main checkout stays on `main`; other branches live in `../Dailies-worktrees/<branch>`. Use `scripts/wt new <branch>`, `scripts/wt ls` and `scripts/wt rm <branch>` (see README.md).

## Expo

This is an Expo/React Native mobile application. Prioritize mobile-first patterns, performance, and cross-platform compatibility.

## Expo has changed — do not trust your training data

Expo ships breaking changes every SDK release. APIs you remember are likely renamed, moved, or removed. Before writing any code that touches an Expo, EAS, or React Native API:

1. Read the major version of the `expo` package in `package.json`.
2. Fetch the matching versioned docs: `https://docs.expo.dev/versions/v<major>.0.0/`
3. For anything else, fetch https://docs.expo.dev/llms.txt — an index of all Expo docs with corrections to common LLM misconceptions. Follow its links to the specific page you need; never answer from memory.

## Commands

Use `bunx` instead of `npx` if the project uses bun (`bun.lock` present).

```bash
npx expo install <package>  # ALWAYS use instead of npm/yarn/pnpm/bun add — resolves SDK-compatible versions
npx expo start              # start the dev server
npx expo lint               # lint
npx tsc --noEmit            # typecheck
npx expo-doctor             # diagnose dependency and config issues
npx expo install --fix      # fix incompatible package versions
```

Run lint and typecheck before declaring any task done.

## Navigation & Routing

- Use **Expo Router** for all navigation. Routes live in `src/app/` — every file there is a screen, `_layout.tsx` files define navigators. Keep non-route code (components, hooks, utils) outside `src/app/`.
- Import `Link`, `router`, and `useLocalSearchParams` from `expo-router`.
- Docs: https://docs.expo.dev/router/introduction.md

## Building with EAS

Use EAS to build, sign, and submit the app in the cloud (`eas build`, `eas submit`) and to ship over-the-air updates (`eas update`) — no local Xcode or Android Studio required. Run EAS CLI as `bunx eas-cli <command>` in Bun projects, or `npx eas-cli@latest <command>` otherwise; substitute that for bare `eas` in docs examples.
Docs: https://docs.expo.dev/eas/index.md

## Rules

- If `ios/` and `android/` directories do not exist, they are generated (Continuous Native Generation). Never create or edit them by hand — configure native behavior in `app.json` and config plugins.
- Expo Go only includes its bundled native modules. After adding a library with native code, the app needs a development build: `npx expo run:ios|android` locally, or `eas build --profile development`.
- Prefer recommended Expo modules over third-party libraries, and check your available skills before adding dependencies. Docs: https://docs.expo.dev/versions/latest/index.md

<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->
