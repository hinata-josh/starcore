// 語法檢查:所有 src/**/*.luau 都要能被解析(含 Roblox 端檔案,它們無法離線執行)
const fs = require('fs'), path = require('path');
// 專案內附一份直譯器(tools/luau.js),搬到別台機器也能跑;找不到才退回舊路徑
const L = (() => { try { return require('../tools/luau.js'); } catch (e) { return require('K:/Html5/roblox-studio/luau.js'); } })();
let bad = 0, n = 0;
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name);
    if (e.isDirectory()) walk(f);
    else if (f.endsWith('.luau')) {
      n++;
      try { L.parse(fs.readFileSync(f, 'utf8'), e.name); } catch (err) { bad++; console.log('✗ ' + f + '\n   ' + err.message); }
    }
  }
})(path.join(__dirname, '..', 'src'));
console.log(`語法檢查 ${n} 檔,錯誤 ${bad}`);
process.exit(bad ? 1 : 0);
