# Dailies

Consumer mobile app built at [The Consumer Mobile Hackathon](https://consumermobilehackathon.com/) (Sunday, November 15, 2026, YC, San Francisco). The app, the backend, and everything else for the hackathon live in this one repository.

The hackathon's required stack is Capy (writes the app), Revyl (runs it on a device and checks it), and Convex (the backend).

## Worktrees

The main checkout stays on `main`. Every other branch gets its own worktree in a sibling folder, so no worktree sits inside another one and Metro, TypeScript, and watchman never crawl a second copy of the app.

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
