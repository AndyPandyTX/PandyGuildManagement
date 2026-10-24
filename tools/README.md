# Tools

Checks to run before a release. They need Node.js; run `npm install` here once.

- `npm run lint` parses every Lua file and lists the globals the addon uses,
  so a typo'd function name or a leaked global stands out.
- `npm test` runs `simharness.lua`: several simulated players load the real
  addon files in a Lua VM (fengari) with stubbed WoW APIs and talk over a fake
  guild channel. It covers guild sync (permissions, catch-up, merges), alts,
  teams, raid nights, activity, Bulk Actions and History credits, once as
  retail and once as WoW Forever. It ends with "N passed, 0 failed".
- `npm test` then runs `simgroups.lua` for the group finder (Pandy Guild
  Groups), with its files from `Groups\`: players post groups, ask and
  invite, fill and close them, schedule and sign up, share keystones (and
  LibKeystone's), list in a fake Group Finder, search, apply, filter and
  switch it off, with records going through the real `Sync.lua`, and every
  page drawn against a stand-in window. It's skipped while there's no
  `Groups\` folder; `npm run test:groups` runs it against the separate
  `PandyGuildGroups` folder next to this addon instead.

This folder isn't part of the addon: `.pkgmeta` keeps it out of the release zip.
