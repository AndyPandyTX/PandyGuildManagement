# Pandy Guild Management

A guild manager for Midnight and WoW Forever, built for big raiding guilds. See your whole guild at a glance, find a group with guildies first, run as many raid teams as you like, track attendance with no setup, and find out when your guild actually plays. Officers' work is shared automatically with everyone running the addon.

Type **/pgm** to open it (or **/pgg** for the group finder), click the panda button on the minimap, or use the buttons under the Guild & Communities window.

The minimap button can be dragged anywhere around the minimap and works with minimap button collectors. It's also a LibDataBroker launcher, so Titan Panel, ChocolateBar, ElvUI data texts and other broker bars can show it too. Turn it off in Settings or with **/pgm minimap**.

## Features

**Guild overview**
- Members, active this week, at max level, and a vitality score out of 100
- Class mix, race overview, level spread, activity, ranks, professions and Mythic+ spread
- Joins and leaves per week, where online members are, and CSV export

**Roster**
- Search by name, rank, zone, notes, class, race or profession
- Sortable columns, plus filters for online, max level, mains only, away 30d+ and "has the addon"
- Right-click anyone to whisper or invite, or click to open their profile

**Raid teams**
- As many teams as you like, each with a schedule, roles and Core / Trial / Bench status
- Built from the tags in your guild notes, and can be kept in sync with them. Members you remove by hand stay removed.
- Shows which Midnight raid buffs and utility each team is missing
- Attendance per team, counted only at that team's raids

**Raid attendance**
- Recorded automatically when you're in a raid with enough guildies. Nothing to set up.
- Each night is tagged to the team that showed up
- Alts count for their main

**Play-time activity**
- Average and peak online, and the guild's busiest hour of the week
- Average online by hour of day, and a weekday × hour heat map
- For each member: hours played, usual play time and most active day
- Every copy of the addon fills in the hours the others missed

**Alts**
- Found from alt ranks and common guild-note formats ("alt of Natty", "VA/Alt/.../Natty")
- Players link their own characters just by logging into each one, and the whole guild sees it
- Officers can link, unlink or pick a main by hand, and that always wins

**Professions**
- Pick a profession and see everyone who has it, counted by player with alts folded in
- See how many crafters were active this week, with thin professions flagged
- Online first, including players who are on another character right now
- Click a name to open the game's recipe view for that person
- **Who can craft...:** search a recipe or shift-click an item to see every guildie who knows it, online first
- A **Guild crafters** panel on Blizzard's profession window lists who in the guild knows the recipe you're looking at

**Member profiles**
- Join date, M+ score, raid progress (with RaiderIO installed), professions, teams, notes and their characters
- Last 10 raids, history, and a private note only you can see
- Pick any rank below yours and set it in one click, or remove them, if your rank allows it

**Group finder**
- Post a Mythic+ key, raid or delve; guildies ask to join in one click
- See each asker's role, item level, M+ score and whose alt they are, then invite
- Your Group Finder listing goes on the guild board too, and guild groups stand out in Blizzard's windows
- Who's Free and everyone's Keystones, at a glance
- /pgg, and it can be switched off in Settings

**Bulk actions** (officers)
- Kick, promote or demote by rules: time away, rank, level, time in the guild, note text
- Review everyone it picks and untick anyone to spare
- Then press one button or hotkey per batch, several people at a time
- Leaves raid team members alone, and anyone whose alt or main was on recently, unless you say otherwise

**History**
- Every join, rejoin, leave, promotion, demotion, rename and max-level ding, with filters
- Shows who did it: "demoted by Natty", "removed from the guild by Natty", "invited by Natty", even for changes made while you were offline
- When someone leaves or is removed, lists their characters still in the guild

## Guild sync

Everyone running the addon shares one set of data, over hidden guild addon messages:

- **Shared:** raid teams, raid nights, alt links, join dates and play-time activity
- **Never shared:** private notes and your settings
- **Only officers can edit** teams, raid nights and alt links. Players can only link their own characters. By default that's the Guild Master and any rank named Officer or Leader, including officer alts and Raid Leadership. The Guild Master can choose a different cut-off rank instead.
- **Checked by every copy:** each copy checks the sender's guild rank before accepting a change, so an edited copy can't push changes.
- **Catches up:** anyone who logs in late gets caught up by an officer who's online, and play-time hours fill in from any copy
- **Light on traffic:** about one message a second, and nothing is sent inside instances

Open **Addon Users** to see who's running it and who needs to update.

## WoW Forever

The same download runs on WoW Forever. Everything above works there too, with a few differences:

- The level cap is 60, so "max level" and the level bands follow that
- There's no Mythic+, so M+ scores and RaiderIO raid progress are hidden
- The raid-buff checklist is hidden, since it lists Midnight's buffs

## Coming from Guild Roster Manager?

With GRM still enabled, click **Import from GRM** in Settings. It brings over alt groups, join dates, rank history and custom notes. Anything you set by hand is kept, and running it again is safe.

## Midnight notes

- Midnight has no combat log for addons, so raid attendance checks the raid group once a minute and at every boss kill.
- Promote, demote and remove use Blizzard's own commands through buttons you click.
- When the game hides roster data (in some instanced content), the addon skips that read rather than guessing.
- Addons can't write guild notes or the MOTD, which is why there's a private note.

## Feedback

Bug reports and ideas are welcome on [GitHub](https://github.com/AndyPandyTX/PandyGuildManagement/issues).
