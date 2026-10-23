// Runs simharness.lua in fengari with the addon's files available as strings.
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const addon = process.argv[2];
const harness = fs.readFileSync(path.join(__dirname, 'simharness.lua'));
const files = ['Core.lua', 'Club.lua', 'Roster.lua', 'GuildEvents.lua', 'Alts.lua', 'Attendance.lua', 'Teams.lua', 'Sync.lua', 'Grm.lua', 'Activity.lua', 'Stats.lua', 'Progress.lua', 'Bulk.lua'];

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_newtable(L);
for (const f of files) {
  lua.lua_pushstring(L, to_luastring(f));
  lua.lua_pushstring(L, fs.readFileSync(path.join(addon, f)));
  lua.lua_settable(L, -3);
}
lua.lua_setglobal(L, to_luastring('FILES'));
lua.lua_pushboolean(L, process.argv[3] === 'forever');
lua.lua_setglobal(L, to_luastring('FOREVER'));
if (lauxlib.luaL_loadbuffer(L, harness, null, to_luastring('@simharness.lua')) !== lua.LUA_OK) {
  console.log('load error:', to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.log('run error:', to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
