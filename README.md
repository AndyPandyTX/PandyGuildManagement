# Pandy Guild Groups

A guild group finder, as a module for
[Pandy Guild Management](https://github.com/AndyPandyTX/PandyGuildManagement).
Post a Mythic+ key, a raid or a delve, and guildies running the module see it
and ask to join in one click. You see who's asking (role, item level, M+ score,
and whose alt they are) and invite with a click.

Type `/pgg`, or open `/pgm` and look under **Modules** in the sidebar.

Needs Pandy Guild Management 0.9.0 or newer. Works on retail (Midnight) and WoW
Forever (no keystones there).

## Pages

**Groups.** The board.
- **Post a group:** Mythic+, Raid, Delve or Other; what and level (your own
  keystone is filled in); size; the roles you still need; a note; and when it
  starts. Leave Start empty for now, or type `20:30`, `Sat 20:30` or `+30`
  for a scheduled group.
- **Show to:** everyone, or one raid team. Team-only posts are a view filter:
  the whole guild's copies hold them, other teams just don't see them.
- **Guild first:** for 5, 10 or 15 minutes only guildies can see your post,
  then **Find PuGs** opens Blizzard's Group Finder. Listing the group there
  is your own click (the game requires it).
- **Your group:** what's still needed, and everyone asking to join, with
  role, spec, item level, M+ score and their main's name for alts.
  **Invite** and **Decline** on each.
- **Guild groups:** everyone's posts, live ones first, then scheduled ones by
  start time. **Ask to join** picks your role from your spec; right-click to
  ask as another role, or to whisper the leader. Scheduled ones have **Sign
  up** instead, and their leader gets **Invite next**, one signup per click.
- **Pings:** a chat line and a soft sound when a group needs a role you play,
  for the kinds you pick. Never in combat, in an instance or while grouped,
  and at most once a minute.

**Who's Free.** Online guildies: looking, free, in a group, busy or away, or
without the module. Role, item level, M+ score, keystone and zone. Tick
**I'm up for a group** (and for what) to show as looking.

**Keystones.** Everyone's key this week, highest first or by dungeon, with
alts under their main. **Post a group** on your own key fills in the form.

## How posts clean up

- Full: your copy counts who joins (by their assigned role, or the role
  they asked as) and closes the post when the group's full or nothing's
  needed.
- Closed by you, or you stop being the group leader.
- You log off: everyone drops your post when the guild roster shows you
  offline.
- You go quiet: inside an instance addons can't talk, so a post with no
  heartbeat for 10 minutes is dropped. It comes back if you leave and it's
  still open.
- Scheduled groups stay until two hours after they start.

A `/reload` keeps your open post.

## Midnight notes

- **No addon messages in instances.** Posting, asking and answering are
  turned off there, with a line saying why, so nothing stale goes out later.
- **Invites and Group Finder listings need a real click**, so every invite
  is a button you press.
- **Secret values** go through Pandy Guild Management's `PGM.Plain`: item
  level, roles, group members and keystones are read only when the game
  shows them.

## Guild traffic

It all rides Pandy Guild Management's guild sync, under the record letter
`G`. A post is one message, plus a heartbeat every 4 minutes. A status goes
out when it changes (at most once a minute) and every 10 minutes. Logging in
costs four messages. See [DESIGN.md](DESIGN.md) for every message.
