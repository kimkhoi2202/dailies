# Hackathon log

- **Project:** Dailies
- **Event:** The Consumer Mobile Hackathon
- **What it does:** Not documented yet
- **Live app:** not deployed
- **Repo:** private
- **Frontend:** not deployed
- **Convex deployment:** https://blissful-labrador-581.convex.cloud
- **Components:** none
- **Convex features:** none yet
- **Auth:** none
- **AI models:** none
- **Started:** 2026-11-15T18:02:39Z
- **Last updated:** 2026-11-15T18:10:45Z

## Log

### 2026-11-15 - 4f9bf7a
Created the repository with a README, a `.gitignore` and `scripts/wt`, a helper
that keeps every branch in its own sibling worktree and copies ignored env files
into new ones (`scripts/wt`, `README.md`).

### 2026-11-15 - b1e6199
Scaffolded the Expo app with Expo Router and TypeScript at the repository root
and wrapped it in a Convex provider that reads the deployment URL from the
environment (`src/app/_layout.tsx`). Provisioned a Convex dev deployment and
added an empty schema, with no tables or functions yet (`convex/schema.ts`).
