# Pandy Guild Groups: design

A guild group finder that plugs into Pandy Guild Management (PGM). Guildies
post a group (a Mythic+ key, a raid, a delve, anything), everyone running the
module sees it, and one click asks to join. The leader sees who's asking
(role, item level, M+ score, and whose alt they are) and invites with a click.

It's a module, not a fork: it needs PGM (`## Dependencies`), reuses its roster,
alts, teams, scores, officer check, window and guild sync, and adds pages to
PGM's window under a new **Modules** heading.

## Screens

All three are pages in the PGM window, in the sidebar's **Modules** section.
`/pgg` opens the first one.

### Groups

The board. Top to bottom:

- **Your group** (only while you have a post): what it is, the roles still
  needed as coloured pips, a "Guild only for 4:12" countdown, then
  - **Requests**: one row each: name in class colour, "alt of Natty" when
    it's an alt, asked-for role, item level, M+ score (in the game's score
    colour), their note. **Invite** and **Decline** buttons. Invite is a real
    click, so it's allowed in Midnight.
  - **Edit**, **Close**, and once the guild-first time is up, **Find PuGs**
    (opens Blizzard's Group Finder on the right category, where you click
    List Group yourself: listings need a real click too).
- **Post a group**: kind chips (Mythic+, Raid, Delve, Other); what (your
  keystone is filled in, or pick a dungeon / raid / tier); level; size; role
  counts (Tank / Healer / DPS, each a small stepper); note; "Team only"
  (pick one of your raid teams); "Guild first for N min"; **Post**.
- **Guild groups**: a list. Kind icon, what and level, leader (class colour,
  and their main if it's an alt), roles needed as pips, note, age. A role
  you can play that's needed is lit. **Ask to join** on each row, with your
  role picked from your spec (right-click for another role). It turns into
  "Asked..." then "Invited" or "Declined". Filters: kind chips, "Needs my
  role".
- Empty state: "No guild groups right now. Post one, or check Who's free."

### Who's free

Online guildies, max level first, grouped by state:

- **Free**: running the module, not in a group, not in an instance.
- **Looking**: free and ticked "I'm up for a group" (with which kinds).
- **In a group**: party or raid size.
- **Busy / unknown**: online but silent (in an instance, where addons can't
  talk), or not running the module.

Columns: name (main shown for alts), role they play, item level, M+ score,
keystone, zone, state. Right-click to whisper or invite (PGM's own member
menu). Your own "I'm up for" chips sit at the top.

### Keystones

Everyone's current keystone, across the guild, grouped by dungeon or sorted
by level. Alts are folded under their main ("Natty: +12 Skyreach, alt
Demonpandy: +9 Ara-Kara"). Each row: "Post a group for this key" if it's
yours, or "Ask" (whisper) for someone else's. Keys older than the weekly
reset drop off.

### Schedule (nice to have, in the Groups page)

A post with a start time is a **scheduled group**. It's listed under
"Coming up", sign up with a role instead of asking to join. The leader sees
signups; at start time they get a chat line and a toast, and **Invite next**
on the post invites one signup per click (the game only allows invites from
a real click).

### Pings

When a post needs a role you play, you're free, and the kind is one you
ticked, you get one chat line and a soft sound ("Natty's +12 Skyreach needs a
Healer. /pgg to ask"). At most one ping a minute, never in combat, never
in an instance. Settings on the Groups page: on/off, which kinds, which roles.

## Sync messages

Everything rides PGM's guild sync: `PGM.SyncSend` queues a record on PGM's
one shared queue (about one message a second for the whole guild, 255 bytes
each) and `PGM.SyncRegister` routes incoming records here. PGM reserves the
record letter **G** for this module; every message is `"1G"`, then a
sub-type, then fields joined by `\031`.

| Sub | Fields | Meaning |
|---|---|---|
| `P` | id u kind what level size needT needH needD have team start pugAt lfg note | a post, new or changed (whole post every time; the same `u` again is a heartbeat) |
| `X` | id u why | post closed (`f` full, `c` closed, `l` no longer the leader) |
| `Q` | | "what's posted?" (on login). Each leader answers with their own `P`, after a random wait |
| `A` | id leader role ilvl spec note | ask to join, addressed to the leader |
| `C` | id leader | withdraw an ask |
| `Y` | id asker answer | the leader's answer: `i` invited, `d` declined, `f` full |
| `U` | id u role state | sign up for a scheduled group (`i` in, `x` out) |
| `S` | state size kinds role ilvl score | "my status" beacon: `f` free, `l` looking, `g` grouped |
| `K` | guid u map level [guid u map level ...] | keystones, packed |
| `W` | since | "keys newer than since, please" (on login) |
| `V` | target | "I'll send them" (others stand down) |

- **Who may send what.** A `P` or `X` only counts from the post's leader
  (the id starts with the leader's GUID tail, and the sender must match). An
  `A`, `C` or `U` is about the sender only. A `Y` only from that post's
  leader. Keystones are low stakes, so a `K` counts from anyone (that's
  what lets a catch-up relay them): newest wins, a stamp can't run more
  than 5 minutes ahead, and keys from before the weekly reset are dropped.
- **Merging.** `u` is a PGM stamp; newest wins, per post and per signup.
  Seeing a message twice changes nothing.
- **Budget.** A post is one message, re-sent when it changes and every 4
  minutes as a heartbeat. A status beacon goes out on change (at most one a
  minute) and every 10 minutes. Login costs one `Q`, one `W`, one `S`, and
  one `K`. Everything else is a click.
- **Midnight.** Addon messages don't work inside instances. Every send
  first checks `PGM.SyncBlocked()`: posting, asking and answering are
  disabled there, with a line saying why, so nothing stale sits in the queue
  and goes out an hour later. Incoming fields go through `PGM.Plain`, as do
  item level, roles, group members and keystone reads.
- **Cleanup.** A post closes:
  - when it's full: the leader's copy counts the group and the asked-for
    roles that joined, then sends `X f`
  - when the leader cancels, leaves the group or disbands
  - when the leader logs off: every copy drops their posts when PGM's
    roster shows them offline
  - when it goes quiet: 10 minutes without a heartbeat (the leader went
    into an instance and can't talk), it's dropped
  Scheduled posts are kept until 2 hours after their start time.
- **Team only** is a view filter. Addon messages go to the whole guild, so
  other teams' copies hold the post but don't show it. It isn't secret.

## What PGM needs to add

1. **A Modules section in the sidebar.** `UI:AddTab` takes
   `{ module = true, icon = path }`. Module tabs go under a **Modules**
   heading at the bottom of the sidebar, made only when one exists. A tab
   added after the window was built rebuilds the sidebar instead of
   breaking it. `/pgm <tab id>` opens any tab, modules' included.
2. **Reserved sync record letters.** Core uses
   `H V O R E T K M A S P D C J B W Y Z`. Reserved for modules:
   `G` (Pandy Guild Groups), and `F I L N Q U X` for future ones.
   `PGM.SyncRegister(letter, fn)` claims one, and refuses a core letter or
   one already taken. Module records aren't officer-only and aren't kept
   at logout; the module checks its own senders.
3. **`PGM.SyncBlocked()`**: true while addon messages can't go out
   (instances, chat lockdown), so a module can say so instead of queuing.
4. **`UI:QueueRefresh()`**: the debounced repaint PGM already uses, for
   module events.
5. **A stable function list**, `PGM.API = 1`, and `PGM.RegisterModule`
   (name, version, the API it needs). Within one API number these keep
   their names, arguments and results:
   - values: `PGM.Plain`, `PGM.Now`, `PGM.Stamp`, `PGM.Print`, `PGM.Debug`,
     `PGM.GuildDB`, `PGM.GuildKey`, `PGM.opt`, `PGM.IS_FOREVER`,
     `PGM.MaxLevel`, `PGM.NameLess`, `PGM.SplitName`
   - look: `PGM.C`, `PGM.Hex`, `PGM.ClassHex`, `PGM.ColorName`,
     `PGM.ClassColor`, `PGM.AgoText`, `PGM.Date`, `PGM.ROLE_LABEL`,
     `PGM.ROLE_COLOR`
   - members: `PGM:MyGuid`, `PGM:MainOf`, `PGM:KnownMain`, `PGM:IsAlt`,
     `PGM:GroupOf`, `PGM:FindMember`, `PGM:MPlusScore`, `PGM:ScoreColor`
   - teams: `PGM:Teams`, `PGM:TeamById`, `PGM:TeamsOf`
   - officers: `PGM:CanEdit`, `PGM:IsOfficerRec`
   - events: `PGM:On` with `ROSTER`, `TEAMS`, `SYNC`, `LOGIN`
   - sync: `PGM.SyncSend`, `PGM.SyncRegister`, `PGM.SyncBlocked`,
     `PGM.SyncNorm`, `PGM.SyncIsMe`, `PGM.SyncHandlers`
   - window: `UI:AddTab`, `UI:Show`, `UI:Refresh`, `UI:QueueRefresh`,
     `UI:MemberMenu`, `UI:OpenProfile`, `UI:Whisper`, `UI:Invite`, and
     the widgets in `UI.W`

## Files

```
PandyGuildGroups.toc   ## Dependencies: PandyGuildManagement
Core.lua               namespace, saved data, API check, slash command
Keystone.lua           my keystone, everyone's keystones, K/W/V
Status.lua             my state (free / looking / grouped), S beacons, who's free
Posts.lua              posts, asks, answers, signups, cleanup, pings
UI/Common.lua          shared page pieces, start-time parsing
UI/Groups.lua          the Groups page
UI/Free.lua            the Who's free page
UI/Keys.lua            the Keystones page
```

Saved: `PandyGuildGroupsDB` (settings, the keystones seen, scheduled posts
and signups), filed per guild with PGM's guild key, like PGM's own data.
