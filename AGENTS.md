# DEGEN

Consumer mobile app for [The Consumer Mobile Hackathon](https://consumermobilehackathon.com) (Sunday, November 15, 2026). The site's tool guides are the source of truth for each sponsor tool; read the linked page before integrating one.

## Hackathon rules

- The project must use Capy, Revyl and Convex, or it isn't eligible for prizes.
- Submissions are due at 6:00 PM Pacific (https://consumermobilehackathon.com/submit). Finalists demo live on a phone.
- All code is written after 10:00 AM on the day. Don't copy in older code.

## Stack

- Native iOS app in Swift (SwiftUI, Swift 5 mode, iOS 18), iPhone only, portrait only. There is no Expo, React Native or JavaScript in the app.
- `project.yml` at the repository root describes the Xcode project for [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Dailies.xcodeproj` is generated and git-ignored: run `xcodegen generate` after adding, moving or deleting a file. Never edit the generated project; change `project.yml`.
- App code is in `Sources/`: `Core` (entry point, catalog, sample content), `DS` (design system), `Live` (navigation, root, play screen, the store), `Convex` (client, device account, decoded rows), `Screens`, `Games`. Fonts and brand images are in `Resources/`. README.md describes each folder.
- The only Swift package is the Convex client, `ConvexMobile` from https://github.com/get-convex/convex-swift. Do not add another package without a reason the owner agreed to.
- Convex backend in `convex/`. The dev deployment is `blissful-jackal-368` in the shared `dailies/dailies` Convex project (client URL `https://blissful-jackal-368.convex.cloud`, HTTP actions URL `https://blissful-jackal-368.convex.site`). Every teammate and cloud machine uses this one deployment through `CONVEX_DEPLOY_KEY`, so whoever pushes last sets the deployed functions; keep `convex/` changes close to `main`.
- npm is the package manager, and it is only used for the Convex backend.
- After any change under `convex/`, run `npx convex dev --once` and fix what it reports.

## Building and checking

A Mac with Xcode and XcodeGen is needed to compile the app. A cloud Linux machine cannot compile it; from there, build on Revyl.

```bash
xcodegen generate
xcodebuild -project Dailies.xcodeproj -scheme Dailies -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
npx tsc --noEmit -p convex      # typecheck the backend
```

- Build before declaring any Swift task done, and run the changed screen or game in a simulator. Launch arguments open the app where you need it without tapping: `-play <game-id>`, `-demo 1` (a scripted player plays), `-lose <seconds>`, `-route <name>`, `-tab <n>`; `LiveLaunch` in `Sources/Live/LiveRoot.swift` lists them all.
- Debug builds are for checking. A build for a phone or for Revyl is Release: the games draw every frame in Swift and are slow without optimisation.
- The simulator build excludes x86_64 because ConvexMobile ships its simulator library for Apple silicon only.

## Games

- Each game is two files in `Sources/Games`: `<Name>Game.swift`, a SwiftUI view made with `init(options: GameOptions, link: GameLink)`, and `<Name>Scene.swift`, a view made with `init(phase: Double, showHUD: Bool)` that draws one moment of the game for covers and the Videos feed. Read `Sources/Games/GameKit.swift` before writing or changing one.
- A game depends on nothing else in the app, prefixes every type with its own name, draws in code plus its own images in `Resources/GameArt.xcassets` (named `<game-id>-<name>`; SwiftUI `Image` only finds catalog images), and calls `link.finish(_:)` exactly once. README.md has the steps for adding one to the catalog and to `convex/seed.ts`.
- Frame rate on a real iPhone matters most: keep the rules in a plain Swift model, draw with `Canvas`, and allocate nothing per frame that can be kept.

## Wording

The app is called DEGEN, in capitals, everywhere a person can read it: under the icon, in the logo, in share text and in store listings. It was first called Dailies, and the repository, the Xcode target and scheme, the bundle id and the Convex project keep that name; do not rename those.

Words on screen are short plain sentences. Never the words win, prize, reward, cash, payout, bonus, bet, wager, jackpot, spin, lucky, token, mint. No exclamation marks, no emoji, no long dashes.

## Secrets and environment

- `.env.local` is git-ignored and is only used by the Convex CLI. The app reads the deployment URL from `ConvexConfig` in `Sources/Convex/ConvexModels.swift`.
- Third-party keys never ship in the app. Copy each one from the machine's environment into Convex with `npx convex env set NAME "$NAME"` and read it only inside a Convex action. Never add a sponsor SDK to the Swift app.
- Cloud machines reach Convex through `CONVEX_DEPLOY_KEY` in the Capy project's environment variables.

## Sponsor tools

| Tool | Guide | How it is used here |
| - | - | - |
| Revyl | https://consumermobilehackathon.com/revyl | Capy builds on Revyl and installs on a cloud phone from a cloud thread: `brew install xcodegen`, `xcodegen generate`, then an unsigned Release simulator build with `xcodebuild`. No Revyl account or key is needed on that path. An unsigned build may have no Keychain, so the device account falls back to UserDefaults. |
| Convex | https://consumermobilehackathon.com/convex | Schema, queries, mutations, actions, Convex Auth with a device account kept in the Keychain, reached from Swift through `ConvexMobile`. Read `convex/_generated/ai/guidelines.md` first. |
| Whop | https://consumermobilehackathon.com/whop | `@whop/sdk` in Convex and the system browser in the app. A Convex action creates the checkout, an HTTP action at `/whop` verifies `payment.succeeded` with `unwrapWebhook`. Unlock from the Convex record the webhook writes. Variables: `WHOP_API_KEY`, `WHOP_WEBHOOK_SECRET`, `WHOP_ENVIRONMENT=sandbox`. |
| Supermemory | https://consumermobilehackathon.com/supermemory | `supermemory` npm package, v5 calls (`supermemory.add(userId, ...)`, `supermemory.search(userId, ...)`), only from a Convex action. Skill in `.agents/skills/supermemory`. Variable: `SUPERMEMORY_API_KEY`. |
| Keiki | https://consumermobilehackathon.com/keiki | The `openai` package pointed at `https://onkeiki.com/api/v1/openai` from a Convex action, with the agent's name as the model and the user's id in `x-conversation-id`. Variable: `KEIKI_API_KEY`. |
| OpenAI | https://consumermobilehackathon.com/openai | Responses API with `gpt-6-luna`, in a Convex action in `convex/ai.ts` in the default Convex runtime. Variable: `OPENAI_API_KEY`. |

## Build log

`hackathon.md` is the public build log the Convex hackathon skill maintains. After meaningful work, update it with `$convex-hackathon-skill`.

## Worktrees

The main checkout stays on `main`; other branches live in `../Dailies-worktrees/<branch>`. Use `scripts/wt new <branch>`, `scripts/wt ls` and `scripts/wt rm <branch>` (see README.md).

<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->
