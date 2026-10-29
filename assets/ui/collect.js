// 從 N1-Pro 美術素材挑出本遊戲介面用的圖,複製成好讀的檔名 + 產生 sizes.json(九宮格切片用)。
// 用法:node assets/ui/collect.js   (來源路徑不存在時只檢查現有檔案)
// 對照表就是下面的 PICK:左邊是遊戲內的 key(也是檔名),右邊是 N1 素材的相對路徑。
const fs = require("fs");
const path = require("path");

const SRC = "K:/N1Project/N1-Pro/Client/Assets/design/RawResources/sprite";
const OUT = __dirname;

const PICK = {
  // ── 按鈕 / 面板 ──
  btn_gray: "static/btn_11.png",
  btn_blue: "static/btn_12.png",
  btn_green: "static/btn_13.png",
  btn_red: "static/btn_14.png",
  btn_orange: "static/btn_15.png",
  btn_white: "static/btn_22.png",
  btn_gold: "static/btn_23.png",
  btn_close: "static/btn_close01.png",
  ribbon: "static/bg_teach_name.png",
  title_banner: "static/bg_titletext.png",
  // ── 建築卡片底框(依 tier)──
  card_t1: "ui/frame_td_quility01.png",
  card_t2: "ui/frame_td_quility02.png",
  card_t3: "ui/frame_td_quility03.png",
  card_t4: "ui/frame_td_quility04.png",
  card_t5: "ui/frame_td_quility05.png",
  // ── 建築類別圖示 ──
  cat_Energy: "itemicon/i06206.png",
  cat_Collect: "itemicon/i06221.png",
  cat_Storage: "itemicon/i06227.png",
  cat_Attack: "itemicon/i06234.png",
  cat_Defense: "itemicon/i06235.png",
  cat_Support: "itemicon/i06232.png",
  cat_Tech: "itemicon/i06228.png",
  // ── 資源圖示(key = Items.luau 的 id)──
  item_Ore: "itemicon/i06507.png",
  item_Metal: "itemicon/i06506.png",
  item_Ice: "itemicon/i16006.png",
  item_Biomass: "itemicon/i90070.png",
  item_Scrap: "itemicon/i90015.png",
  item_Sand: "itemicon/i90150.png",
  item_Water: "itemicon/i90019.png",
  item_Coal: "itemicon/i16005.png",
  item_Copper: "itemicon/i90003.png",
  item_Silicon: "itemicon/i90113.png",
  item_Sulfur: "itemicon/i16003.png",
  item_Amber: "itemicon/i90116.png",
  item_Titanium: "itemicon/i05033.png",
  item_Crystal: "itemicon/i90111.png",
  item_LavaCore: "itemicon/i90061.png",
  item_Glowstone: "itemicon/i16004.png",
  item_RareGas: "itemicon/i90084.png",
  item_Plasma: "itemicon/i90147.png",
  item_Stardust: "itemicon/i90055.png",
  item_DarkMatter: "itemicon/i90014.png",
  // ── 其他小圖示 ──
  icon_pickaxe: "itemicon/i90151.png",
  icon_quest: "itemicon/i06220.png",
};

function pngSize(file) {
  const b = fs.readFileSync(file);
  if (b.readUInt32BE(0) !== 0x89504e47) throw new Error("不是 PNG:" + file);
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

const sizes = {};
let copied = 0;
for (const [key, rel] of Object.entries(PICK)) {
  const src = path.join(SRC, rel);
  const dst = path.join(OUT, key + ".png");
  if (fs.existsSync(src)) {
    fs.copyFileSync(src, dst);
    copied++;
  } else if (!fs.existsSync(dst)) {
    console.error("✘ 找不到:" + rel);
    process.exitCode = 1;
    continue;
  }
  sizes[key] = pngSize(dst);
}
fs.writeFileSync(path.join(OUT, "sizes.json"), JSON.stringify(sizes, null, 1) + "\n");
console.log(`[collect] 複製 ${copied} 張,共 ${Object.keys(sizes).length} 張,尺寸寫入 sizes.json`);
