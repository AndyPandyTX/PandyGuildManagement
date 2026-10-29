# Guild group finder

Part of [Pandy Guild & Groups](../README.md) since 0.9.0 (it began as a
separate addon, Pandy Guild Groups). Post a Mythic+ key, a raid or a delve,
and guildies running Pandy Guild & Groups see it and ask to join in one
click. You see who's asking (role, item level, M+ score, and whose alt they
are) and invite with a click.

Type `/pgg`, or open `/pgm` and look under **Groups** in the sidebar. Turn it
off in Settings (Group finder) or with `/pgg off`; its pages then leave the
sidebar and it stops sending and listening. Works on retail (Midnight) and
WoW Forever (dungeons and raids up to 40 there: no keystones, delves or
scores).

## With Blizzard's Group Finder

- **List once.** List a group in the Group Finder and it goes on the guild
  board too: the dungeon, your key's level and the roles still open, worked
  out from who's in your group. Delisting takes it off. Closing it on the
  guild board (or it filling) leaves your listing alone. Turn this off with
  "Post my Group Finder listing to the guild".
- **Applicants on the Groups page.** Everyone who applies is listed under
  "Asking to join" with guild asks, guildies first, each marked Guild or
  Group Finder. Invite and Decline go through the Group Finder.
- **Guild in Blizzard's windows.** Search results led by a guildie, or with
  guildies in them, get a jade edge, and their tooltip says who leads it.
  Guildies in your applicant list get the same edge. Sorting is left to
  Blizzard and Premade Groups Filter, so they never fight.

## M+ scores

Everywhere a score shows (requests, applicants, tooltips on Who's Free and
Keystones) it's written out like RaiderIO does: the character's own score,
then their main's and their warband's when higher, each with the role icons
it was earned on. A dimmed icon is a role that only partly earned it. The
character's score comes from the game; main, warband and roles need RaiderIO.

## Pages

**Groups.** Three views across the top:
- **Browse:** every group in one list, guild posts and Blizzard's Group
  Finder together, each with its dungeon's keystone art. Each row shows
  who leads it (Guild, and "alt of X"), and for five-player groups the
  **comp**: a slot per place, tanks then healers then DPS. A member's slot
  is their class colour with their role on it; an open slot shows the role
  it still wants (brighter when it's one you play). Hover for each
  member's spec and class. Bigger groups and guild posts say
  **Needs: 1 Tank 3 DPS** instead. Guild rows have a jade edge.
  - **Titles:** each Group Finder row shows the listing's own title
    ("+14 Relaxed"), as the game draws it.
  - **Guild:** Guild first, Guild only, Scheduled, and Sort (newest or
    leader rating).
  - **Group Finder:** Mythic+, Raids, Delves or Custom. Clicking one
    searches the Group Finder (the game only searches from a click), and
    **Refresh** runs it again.
  - **The list holds still** until the next search (Refresh, Enter,
    another category) or a filter change: rows keep their places, so
    nothing moves under the cursor. A group that's delisted (or a guild
    post that's closed) stays put, turns red and says **Delisted**; a full
    one says **Full**. Neither can be applied to. The next search clears
    them. A five-player group with no place left for any role you apply
    as says **No room for** that role, with Apply off (right-click still
    offers the roles it has room for).
  - **Filters** panel, like OAK's: **Apply as** (the roles Apply signs you
    up as), playstyle, leader rating, then tick boxes for Fits my role,
    Hide declined, Need or Has tank, Need or Has healer, Need DPS, Battle
    res and Lust. Under them, this season's dungeons with their icons and
    your best key in each: untick one to hide it, or use All and None.
    Reset clears it all.
  - **Searching by key level:** Group Finder titles reach addons as
    protected strings (the game draws them, no addon can read them), so
    the search is Blizzard's: its own search box moves into the Filters
    panel while Browse is open, the way OAK does it, and goes back after
    (the Group Finder has to have been opened once this session). Type keys
    or words and press Enter to search Browse's category. One level also
    finds the keys
    either side of it (10 finds 9 to 11); a range (10-12) is exact. If OAK
    has the box at the time, it's left there and the panel says so.
  - **Apply** sends a Group Finder application with your Apply as roles
    (right-click for one role). On a guild post it's **Ask to join**.
  - **Your requests go to the top** on the next search, whatever the
    filters, tinted by how
    they stand: **Pending** (amber, with a **Cancel** button), **Invited**
    (accept Blizzard's popup), then **Joined** or **Declined** (red). A
    decline stays on top for two minutes, then Hide declined hides it.
  - Hover a row for each member's spec, class and role.
- **My group:** your group across the top: its comp filling in as people
  join (you, then each member in their class colour; hover a slot for who),
  what it still needs, how full it is, listed or guild only, and Close.
  Then everyone asking to join, a row each: their spec's icon by their
  name, Guild tag and main, roles offered, spec, item level, and the
  **Character**, **Main** and **Warband** M+ scores in their own columns,
  each with the roles it was earned on. Invite and Decline on each.
- **Post a group:** the form below, and the Group Finder and ping settings.

Listing a group in the Group Finder opens the window on My group.
Browsing groups in Blizzard's window, or applying to one (here, in the
Group Finder or in OAK), opens it on Browse.
Delisting goes back to Browse. Pick which of these pop the window up under
**Pop up on** (Listing, Applying, Browsing), in Settings or on Post a group;
untick all three and it only opens when you open it. It never opens in
combat. `/pgg mine` and `/pgg post` open those views.

The form and the rest of this section describe Post a group and how guild
posts behave:
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

**Keystones.** Everyone's key this week. Click a column to sort by key
level, dungeon, who, M+ score or when it was seen (click again to flip it).
**Online only** is on to start with, and hides offline characters, yours
included. **Mine first** (off to start with) pins your own characters' keys
to the top, tinted so it's clear why they're out of order. On your own key:
- **List** opens the Group Finder. Click Dungeons, then Start a Group, and
  Blizzard fills in your keystone; then List Group. That's as far as an
  addon may go: Start a Group's form is protected, and filling it in from
  addon code gets blocked.
- **Post** fills in a guild post for it.

**Tell the guild** (on My group, or `/pgg tell`) says in guild chat, with
your keystone's link: "[Keystone: The Blinding Vale (14)] - needs 1 Tank, 2
DPS. Whisper me to join!" Change the wording on Post a group: `{key}`,
`{needs}` and `{name}` are filled in. At most once a minute, and never from
inside an instance. `/pgg list` opens the Group Finder to list your key.
Guildies without this module show up too if they run anything with
LibKeystone (BigWigs, LittleWigs, EllesmereUI and others): the page asks
them, at most every two minutes. A key someone hides from the guild stays
hidden.

## LFG Chat (WoW Forever)

Classic players group in chat, so on Forever the **LFG Chat** page reads the
channels you're in (LookingForGroup, General, Trade, World...) and guild
chat. What others said isn't sent or saved; it starts empty at login.

- **What counts:** LFM, LF1M..., "lf 2 dps", "need a tank", "looking for a
  healer" or a class ("LF priest") make a group looking for more; LFG, "lf
  group" or "LF strat" a player looking; WTS, WTB, WTT and "LF enchanter"
  (or another crafter) trade. A bare "need" ("need a summon") is just talk,
  and so is a line that asks for nothing.
- **Where:** every Forever dungeon and raid, by the names and short forms
  people type: "dm" is the Deadmines, "dm e/w/n" or "tribute" Dire Maul,
  "sm cath" Scarlet Monastery, "strat ud", "krol'dok", "ony". "dm me" and
  "pm me" are messages, not dungeons. Scarlet Monastery's wings need the
  "sm" ("sm gy"), so "graveyard" alone is nothing.
- **The board:** a heading per dungeon and raid, lowest level first, then
  quests and other groups, then trade. Each person's newest line, for 15
  minutes. Filters for dungeons, raids, quests, trade, players looking and
  your level (within two of a dungeon's range), and a search.
- **Clicks:** whisper; shift-click /who; ctrl-click invite; right-click for
  all of them (and a guildie's profile).
- It only repaints while it's the page showing, so busy Trade chat costs
  nothing elsewhere.

- **Your own line:** a box along the bottom keeps your LFM or LFG text (saved,
  so it's there next session). Pick a channel from the ones you're in (it
  starts on LookingForGroup, else World) and press Send or Enter. It won't
  send twice within 5 seconds, and the game only lets it send from a click
  or a key press.

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
- Scheduled groups stay until two hours after they start. One closed while
  you were offline goes when you log in: its leader says so again when
  asked what's posted.

A `/reload` keeps your open post.

## Midnight notes

- **No addon messages in instances.** Posting, asking and answering are
  turned off there, with a line saying why, so nothing stale goes out later.
- **Invites and Group Finder listings need a real click**, so every invite
  is a button you press.
- **Secret values** go through Pandy Guild & Groups' `PGM.Plain`: item
  level, roles, group members and keystones are read only when the game
  shows them.

## Guild traffic

It all rides Pandy Guild & Groups' guild sync, under the record letter
`G`. A post is one message, plus a heartbeat every 4 minutes. A status goes
out when it changes (at most once a minute) and every 10 minutes. Logging in
costs four messages. See [DESIGN.md](DESIGN.md) for every message.
