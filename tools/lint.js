const fs = require('fs'), path = require('path');
const luaparse = require('./node_modules/luaparse');
const root = process.argv[2];
const files = [];
(function walk(d){ for (const f of fs.readdirSync(d)) { const p = path.join(d,f); if (fs.statSync(p).isDirectory()) { if (!['tools','node_modules','.git','preview'].includes(f)) walk(p); } else if (p.endsWith('.lua')) files.push(p);} })(root);
const globals = new Map(), defined = {PGM:new Set(), UI:new Set(), W:new Set()}, used = {PGM:new Map(), UI:new Map(), W:new Map()};
let bad = 0;
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  let ast;
  try { ast = luaparse.parse(src, { luaVersion: '5.1', scope: true, locations: true }); }
  catch (e) { console.log('SYNTAX', path.relative(root,f), e.message); bad++; continue; }
  const rel = path.relative(root, f);
  (function visit(n, parent){
    if (!n || typeof n !== 'object') return;
    if (Array.isArray(n)) { n.forEach(x=>visit(x,parent)); return; }
    if (n.type === 'Identifier' && n.isLocal === false) {
      const k = n.name; if (!globals.has(k)) globals.set(k, rel+':'+n.loc.start.line);
    }
    if (n.type === 'FunctionDeclaration' && n.identifier && n.identifier.type === 'MemberExpression') {
      const b = n.identifier.base; if (b.type==='Identifier' && defined[b.name]) defined[b.name].add(n.identifier.identifier.name);
    }
    if (n.type === 'AssignmentStatement') n.variables.forEach(v => { if (v.type==='MemberExpression' && v.base.type==='Identifier' && defined[v.base.name]) defined[v.base.name].add(v.identifier.name); });
    if (n.type === 'MemberExpression' && n.base.type==='Identifier' && used[n.base.name]) {
      const m = used[n.base.name]; if (!m.has(n.identifier.name)) m.set(n.identifier.name, rel+':'+n.loc.start.line);
    }
    for (const k in n) if (k !== 'loc' && k!=='range') visit(n[k], n);
  })(ast);
}
// Set as fields rather than declared as functions, so the walk can't see them.
const SET_ELSEWHERE = new Set(['UI.frame', 'UI.current']);
for (const t of ['PGM','UI','W']) for (const [k,loc] of used[t]) if (!defined[t].has(k) && !SET_ELSEWHERE.has(t+'.'+k)) console.log('UNDEFINED', t+'.'+k, loc);
console.log('GLOBALS:', [...globals.keys()].sort().join(' '));
console.log(files.length, 'files,', bad, 'syntax errors');
