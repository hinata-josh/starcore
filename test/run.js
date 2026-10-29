// 用法:node test/run.js —— 以 K:\Html5\roblox-studio 的自寫 Luau 直譯器,離線跑 src/shared 純邏輯測試
// (本機沒有 Lune/Rojo;這裡只驗證不碰 Roblox API 的模組。Studio 實測見 docs/studio-checklist.md)
const fs = require('fs');
const path = require('path');
// 專案內附一份直譯器(tools/luau.js),搬到別台機器也能跑;找不到才退回舊路徑
const L = (() => { try { return require('../tools/luau.js'); } catch (e) { return require('K:/Html5/roblox-studio/luau.js'); } })();

const root = path.join(__dirname, '..', 'src', 'shared');
const dirs = ['Logic', 'Data'];
const cache = {};
let pass = 0, fail = 0;

const I = new L.Interp({ output: (k, t) => console.log('   ' + t) });

function loadModule(name) {
  if (cache[name]) return cache[name];
  for (const d of dirs) {
    const f = path.join(root, d, name + '.luau');
    if (!fs.existsSync(f)) continue;
    // Roblox 的 require(script.Parent.X) → 測試環境的 require("X")
    const src = fs.readFileSync(f, 'utf8').replace(/require\(script\.Parent\.(\w+)\)/g, 'require("$1")');
    const r = I.runSync(I.compile(src, name));
    return (cache[name] = r[0]);
  }
  throw new Error('找不到模組 ' + name);
}

I.G.set('require', L.nat('require', (a) => loadModule(a[0])));
I.G.set('check', L.nat('check', (a) => {
  const [name, got, want] = a;
  if (got === want) pass++;
  else { fail++; console.log(`  ✗ ${name}:得到 ${I.tostr(got)},應為 ${I.tostr(want)}`); }
}));

// 用法:node test/run.js [檔名關鍵字] [--fast];--fast 跳過很慢的機器人試玩(playbot,約 40 秒,是調平衡用的,不是發布門檻)
const fast = process.argv.includes('--fast');
const only = process.argv.slice(2).find((a) => !a.startsWith('--'));
const files = fs.readdirSync(__dirname).filter((f) => f.endsWith('.test.luau') && (!only || f.includes(only)) && !(fast && f.includes('playbot')));
for (const f of files) {
  console.log('▶ ' + f);
  try { I.runSync(I.compile(fs.readFileSync(path.join(__dirname, f), 'utf8'), f)); }
  catch (e) { fail++; console.log('  ✗ 例外:' + e.message); }
}
console.log(`\n通過 ${pass},失敗 ${fail}`);
process.exit(fail ? 1 : 0);
