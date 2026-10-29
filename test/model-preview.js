// 3D 模型預覽:在 Roblox 模擬器裡用真的 MonsterModel / BuildingModel 建出怪獸與建築,
// 把零件(形狀/大小/位置/顏色/材質)匯出,用 three.js 畫成一格一格的截圖 → build/model-preview-<組>.png
// 用法:node test/model-preview.js [monsters|defense|all]
// 只是近似外觀(Neon 用自發光、Glass/ForceField 用半透明),比例與造型以這張圖為準。
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const H = require('./ui-harness');

const ROOT = path.join(__dirname, '..');
const OUT = path.join(ROOT, 'build');
const THREE_PATHS = [path.join(ROOT, 'tools', 'three.min.js'), 'K:/Html5/roblox-studio/vendor/three.min.js'];

// 每組要建的東西:{ kind = "monster" | "building", id, size/lv, label }
const GROUPS = {
  monsters: `
local MM = require(game:GetService("ServerScriptService").Server.MonsterModel)
local list = { {"AcidWorm",5,nil}, {"Behemoth",9,nil}, {"BladeMoth",6,nil}, {"PlasmaDrake",9,nil}, {"RiftTitan",22,"👹 裂縫巨獸"}, {"AcidWorm",8,"酸液蟲 ×3"} }
for i, e in list do
	local m = MM.create(e[1], e[2], e[3])
	MM.animate(m, 0.08, 0)
	m.model.Name = "P" .. i .. "|" .. e[1] .. (if e[3] then " " .. e[3] else "")
	m.model.Parent = workspace
end
print("BUILT")
`,
  defense: `
local RS = game:GetService("ReplicatedStorage")
local Buildings = require(RS.Shared.Data.Buildings)
local BM = require(game:GetService("ServerScriptService").Server.BuildingModel)
local FILTER = __FILTER__
local i = 0
for _, def in Buildings.Types do
	if (def.category == "Attack" or def.category == "Defense") and (not FILTER or def.id == FILTER) then
		i += 1
		local m = BM.create(def, 1, CFrame.new(), "x")
		m.Name = string.format("P%02d|%s %s T%d", i, def.id, def.name, def.tier or 1)
		m.Parent = workspace
	end
end
print("BUILT")
`,
};

function dump(rt) {
  const models = [];
  for (const m of rt.workspace.children) {
    if (m.ClassName !== 'Model' || !/^P\d+\|/.test(String(m.p.Name))) continue;
    const parts = [];
    for (const d of m.descendants()) {
      if (!['Part', 'MeshPart', 'WedgePart'].includes(d.ClassName)) continue;
      if (d.p.Transparency >= 1) continue;
      const cf = d.p.CFrame;
      parts.push({
        shape: d.ClassName === 'WedgePart' ? 'Wedge' : (d.p.Shape && d.p.Shape.Name) || 'Block',
        size: [d.p.Size.X, d.p.Size.Y, d.p.Size.Z],
        pos: [cf.x, cf.y, cf.z], m: cf.m,
        color: [d.p.Color.R, d.p.Color.G, d.p.Color.B],
        mat: (d.p.Material && d.p.Material.Name) || 'Plastic',
        tr: d.p.Transparency,
      });
    }
    models.push({ name: String(m.p.Name).replace(/^P\d+\|/, ''), order: String(m.p.Name), parts });
  }
  models.sort((a, b) => (a.order < b.order ? -1 : 1));
  return models;
}

function page(models, threeSrc) {
  return `<!doctype html><meta charset="utf-8"><style>
body{margin:0;background:#1b1f33;font:bold 15px 'Microsoft JhengHei';color:#fff;display:flex;flex-wrap:wrap;width:1500px}
.c{width:300px;height:320px;position:relative}.c span{position:absolute;left:0;right:0;bottom:6px;text-align:center;text-shadow:0 0 3px #000}
canvas{display:block}</style>
<script>${threeSrc}</script><body><script>
const MODELS=${JSON.stringify(models)};
// 共用一個 WebGL(瀏覽器同時最多約 16 個),每格畫完複製到自己的 2D 畫布
const r=new THREE.WebGLRenderer({antialias:true,preserveDrawingBuffer:true});r.setSize(300,290);r.setClearColor(0x2a3050);
// Roblox WedgePart:底面完整、斜面朝 -Z、高的那邊在 +Z
function wedgeGeo(sx,sy,sz){const x=sx/2,y=sy/2,z=sz/2;
  const v=[[-x,-y,-z],[x,-y,-z],[x,-y,z],[-x,-y,z],[-x,y,z],[x,y,z]];
  const f=[[0,2,1],[0,3,2],[3,2,5],[3,5,4],[0,5,1],[0,4,5],[0,3,4],[1,5,2]];
  const pos=[];for(const t of f)for(const i of t)pos.push(...v[i]);
  const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));g.computeVertexNormals();return g;}
for (const md of MODELS){
  const div=document.createElement('div');div.className='c';document.body.appendChild(div);
  const cv=document.createElement('canvas');cv.width=300;cv.height=290;div.appendChild(cv);
  const lab=document.createElement('span');lab.textContent=md.name;div.appendChild(lab);
  const sc=new THREE.Scene();sc.add(new THREE.HemisphereLight(0xdde8ff,0x403830,0.9));
  const sun=new THREE.DirectionalLight(0xffffff,0.9);sun.position.set(-3,6,-4);sc.add(sun);
  const g=new THREE.Group();sc.add(g);
  for(const p of md.parts){
    let geo;const [sx,sy,sz]=p.size;
    if(p.shape==='Ball'){const d=Math.min(sx,sy,sz);geo=new THREE.SphereGeometry(d/2,20,14);}
    else if(p.shape==='Cylinder'){geo=new THREE.CylinderGeometry(Math.min(sy,sz)/2,Math.min(sy,sz)/2,sx,20);geo.rotateZ(Math.PI/2);}
    else if(p.shape==='Wedge') geo=wedgeGeo(sx,sy,sz);
    else geo=new THREE.BoxGeometry(sx,sy,sz);
    const col=new THREE.Color(p.color[0],p.color[1],p.color[2]);
    let mat;
    if(p.mat==='Neon') mat=new THREE.MeshBasicMaterial({color:col.clone().lerp(new THREE.Color(1,1,1),0.25),transparent:p.tr>0,opacity:1-p.tr});
    else if(p.mat==='ForceField') mat=new THREE.MeshBasicMaterial({color:col,transparent:true,opacity:0.18,wireframe:true});
    else if(p.mat==='Glass') mat=new THREE.MeshStandardMaterial({color:col,transparent:true,opacity:Math.max(0.35,1-p.tr-0.2),roughness:0.1,metalness:0.1});
    else mat=new THREE.MeshStandardMaterial({color:col,roughness:p.mat==='Metal'||p.mat==='DiamondPlate'?0.35:0.7,metalness:p.mat==='Metal'||p.mat==='DiamondPlate'?0.6:0.05,transparent:p.tr>0,opacity:1-p.tr,side:p.shape==='Wedge'?THREE.DoubleSide:THREE.FrontSide});
    const mesh=new THREE.Mesh(geo,mat);const m=p.m;
    mesh.matrixAutoUpdate=false;mesh.matrix.set(m[0],m[1],m[2],p.pos[0],m[3],m[4],m[5],p.pos[1],m[6],m[7],m[8],p.pos[2],0,0,0,1);
    g.add(mesh);
  }
  g.updateMatrixWorld(true);
  const box=new THREE.Box3().setFromObject(g);const c=box.getCenter(new THREE.Vector3());const s=box.getSize(new THREE.Vector3()).length();
  const cam=new THREE.PerspectiveCamera(35,300/290,0.1,1000);
  // 從斜前方看(Roblox 的臉朝 -Z)
  cam.position.set(c.x+s*0.75,c.y+s*0.45,c.z-s*1.05);cam.lookAt(c);
  r.render(sc,cam);
  cv.getContext('2d').drawImage(r.domElement,0,0);
}
</script>`;
}

function preview(group) {
  const src = GROUPS[group === "base" ? "defense" : group].replace("__FILTER__", group === "base" ? "\"CommandCenter\"" : "nil");
  const r = H.runClient({ serverSource: src, seconds: 0.5, clients: false, serverModules: true });
  if (r.errors.length) console.log('  ! 執行期錯誤:' + r.errors.slice(0, 3).join(' | '));
  const models = dump(r.rt);
  const threePath = THREE_PATHS.find((p) => fs.existsSync(p));
  fs.mkdirSync(OUT, { recursive: true });
  const html = path.join(OUT, `model-preview-${group}.html`);
  fs.writeFileSync(html, page(models, fs.readFileSync(threePath, 'utf8')));
  const rows = Math.ceil(models.length / 5);
  const png = path.join(OUT, `model-preview-${group}.png`);
  execFileSync('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless=new', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--hide-scrollbars', '--force-device-scale-factor=1', `--window-size=1500,${rows * 320}`, '--virtual-time-budget=4000',
    `--screenshot=${png}`, 'file:///' + html.replace(/\\/g, '/')], { stdio: 'ignore' });
  console.log(`[model-preview] ${group}:${models.length} 個模型 → ${png}`);
  return r.errors.length;
}

const groups = process.argv.slice(2);
let errs = 0;
for (const g of groups.length ? groups : ['monsters', 'defense']) errs += preview(g);
process.exit(errs ? 1 : 0);
