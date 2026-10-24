// Runs simharness.lua in fengari with the addon's files available as strings.
//   node simrun.js <addon>                  PGM's sync simulation (retail)
//   node simrun.js <addon> forever          the same, as WoW Forever
//   node simrun.js <addon> groups [folder]  the group finder's simulation, with
//                                           its files from <addon>/Groups (or
//                                           folder); skipped if there are none
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const addon = process.argv[2];
const mode = process.argv[3];
const files = ['Core.lua', 'Club.lua', 'Roster.lua', 'GuildEvents.lua', 'Alts.lua', 'Attendance.lua', 'Teams.lua', 'Sync.lua', 'Grm.lua', 'Activity.lua', 'Stats.lua', 'Progress.lua', 'Bulk.lua', 'Crafters.lua'];
const groupFiles = ['Core.lua', 'Keystone.lua', 'Status.lua', 'Posts.lua', 'GroupFinder.lua', 'UI/Common.lua', 'UI/Groups.lua', 'UI/Free.lua', 'UI/Keys.lua'];

let harnessName = 'simharness.lua';
let groupsDir = null;
if (mode === 'groups') {
  harnessName = 'simgroups.lua';
  groupsDir = process.argv[4] || path.join(addon, 'Groups');
  if (!fs.existsSync(path.join(groupsDir, 'Core.lua'))) {
    console.log('groups: no group finder files in ' + groupsDir + ', skipped');
    process.exit(0);
  }
}
const harness = fs.readFileSync(path.join(__dirname, harnessName));

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function table(name, list, dir) {
  lua.lua_newtable(L);
  for (const f of list) {
    lua.lua_pushstring(L, to_luastring(f));
    lua.lua_pushstring(L, fs.readFileSync(path.join(dir, f)));
    lua.lua_settable(L, -3);
  }
  lua.lua_setglobal(L, to_luastring(name));
}
table('FILES', files, addon);
if (groupsDir) table('GROUPS', groupFiles, groupsDir);
lua.lua_pushboolean(L, mode === 'forever');
lua.lua_setglobal(L, to_luastring('FOREVER'));
if (lauxlib.luaL_loadbuffer(L, harness, null, to_luastring('@' + harnessName)) !== lua.LUA_OK) {
  console.log('load error:', to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.log('run error:', to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
