# DEGEN

Consumer mobile app built at [The Consumer Mobile Hackathon](https://consumermobilehackathon.com/) (Sunday, November 15, 2026, YC, San Francisco). The app, the backend, and everything else for the hackathon live in this one repository.

The hackathon's required stack is Capy (writes the app), Revyl (runs it on a device and checks it), and Convex (the backend).

DEGEN (first called Dailies; the repository, the Xcode target and the bundle id keep that name) is a native iOS app written in Swift (SwiftUI). It is a daily feed of small phone games where playing collects gold, with likes, comments, leaderboards and a gold history, all kept in Convex.

## Run it

You need a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate            # writes Dailies.xcodeproj from project.yml (git-ignored, regenerate after adding files)
open Dailies.xcodeproj       # run the Dailies scheme on a simulator or a phone
```

From the command line, for a simulator:

```sh
xcodebuild -project Dailies.xcodeproj -scheme Dailies -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The backend needs Node:

```sh
npm install
npx convex dev --once        # pushes convex/ to the shared dev deployment
```

## How the app is put together

- **`project.yml`** describes the Xcode project: one target, `Dailies`, iOS 18, sources in `Sources/` and `Resources/`, and the Convex Swift client (`ConvexMobile`) as a Swift package.
- **`Sources/Core`** is the app entry (`MockApp.swift`), the game catalog and sample content (`MockData.swift`) and small helpers.
- **`Sources/DS`** is the design system: colours and type in `Theme.swift`, shared components in `Components.swift`.
- **`Sources/Live`** is the running app: navigation (`LiveNav.swift`), the root view, play screen and launch arguments (`LiveRoot.swift`), and the store every screen reads (`LiveStore.swift`).
- **`Sources/Convex`** connects the store to Convex: a device account kept in the Keychain (`DeviceAuth.swift`), the client with live queries and mutations (`ConvexLink.swift`) and the decoded rows (`ConvexModels.swift`).
- **`Sources/Avatar`** is the Dailie, the player's avatar: the item catalog (`AvatarCatalog.swift`, the same list as `convex/items.ts`), the voxel model every item is built from (`VoxelAvatar.swift`), the 3D stage that meshes it in SceneKit (`AvatarStage.swift`), the flat pixel version for small spots and shop cards (`PixelAvatar.swift`), and the store that keeps the look and the items owned in step with Convex (`AvatarStore.swift`).
- **`Sources/Screens`** holds every screen: Home, Videos, You, the game page, gold, leaderboards, comments, search, settings and the studio screens. `WhopMoney.swift` holds the gold packs sheet, creator earnings, and the studio's creator programs; it opens Whop's checkout page in Safari and watches Convex for the result, so no Whop key or SDK is in the app.
- **`Sources/Games`** holds the games. Each game draws itself in Swift and has two files: `<Name>Game.swift`, the playable game, and `<Name>Scene.swift`, which draws one moment of the game for covers and the Videos feed. `GameKit.swift` is the small contract between a game and the app.
- **`convex/`** is the backend: each phone gets its own account (`auth.ts`, `users.ts`), the server starts and finishes rounds and works out gold (`rounds.ts`), and `social.ts`, `games.ts`, `ledger.ts`, `shop.ts` and `rooms.ts` hold likes, comments, leaderboards, the catalog, the gold history, spending and rooms. `items.ts` lists the avatar items and their prices, `avatar.ts` holds a player's look, profile and equipping, and `shop.buy` charges gold for an item on the server. `whop.ts` is where money moves, all of it through Whop: a checkout for a gold pack or for a creator program's budget, and a transfer of a creator's earnings to their Whop account. `http.ts` takes Whop's `payment.succeeded` webhook at `/whop`, checks its signature and hands over what was paid for. `creators.ts` counts views of clips and moves a program's budget to the creators. `npx convex run seed:run` adds the launch games and dresses the seeded players.

## Add a game

1. Write `Sources/Games/<Name>Game.swift`: a SwiftUI view made with `init(options: GameOptions, link: GameLink)` that calls `link.finish(_:)` once when the round is over. Read `GameKit.swift` first; it is short and explains the rules (pausing, the areas the app keeps for its own controls, haptics, the scripted player used for recording).
2. Write `Sources/Games/<Name>Scene.swift`: a view made with `init(phase: Double, showHUD: Bool)` that draws the game at one moment, 0 to 1, on a 402 x 874 stage.
3. Add the game to `Sources/Core/MockData.swift`: a case in `GameKind`, a line in `MockGame.scene`, a `MockGame` entry and a place in `Mock.games`. Add its case to `Sources/Live/GameFactory.swift`. The compiler then points at the few other switches that need the new case.
4. Add the game to `convex/seed.ts` with the same id, then run `npx convex dev --once` and `npx convex run seed:run`.
5. Run `xcodegen generate` and build.

Launch arguments open the app wherever you need it, which is how to test without tapping: `-play <game-id>` starts a round, `-demo 1` lets the scripted player play it, `-lose <seconds>` ends it, `-route <name>` opens a screen. `LiveLaunch` in `Sources/Live/LiveRoot.swift` lists them all.

## Worktrees

The main checkout stays on `main`. Every other branch gets its own worktree in a sibling folder, so no worktree sits inside another one.

```
~/Documents/
├── Dailies/                  main checkout, always on main
└── Dailies-worktrees/
    ├── onboarding/           branch onboarding
    └── feat-paywall/         branch feat/paywall
```

`scripts/wt` manages them and works from any worktree:

```sh
scripts/wt new onboarding        # new branch from origin/main in ../Dailies-worktrees/onboarding
scripts/wt new hotfix some-ref   # branch from another ref
scripts/wt ls                    # list every worktree
scripts/wt rm onboarding         # remove the worktree, delete the branch if merged
```

`wt new` also copies the ignored `.env` files (such as Convex's `.env.local`) from the main checkout and installs dependencies, because neither travels with a new worktree.

Capy threads that start in a new worktree keep theirs under `~/.capy/worktrees`; `scripts/wt ls` lists those too.
