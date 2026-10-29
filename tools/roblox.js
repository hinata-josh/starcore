/* roblox.js — 在 Luau 直譯器上模擬 Roblox 執行環境
 * 資料型別(Vector3/CFrame/Color3/UDim2/Enum…)、Instance 樹、服務(Players/RunService/TweenService…)、
 * 排程器(task.wait/事件執行緒)、簡易物理(重力/碰撞/Touched)、角色控制、GUI 資料模型。
 * 不碰 DOM / Three.js：畫面由 app.js 讀這裡的狀態去畫，所以 Node 也能直接跑測試。
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./luau.js'));
  else root.Rbx = factory(root.Luau);
})(typeof globalThis !== 'undefined' ? globalThis : this, function (L) {
'use strict';
const { LuaTable, LuaError, Coroutine, nat, truthy, luaType, luauTypeof, numToStr, str2num, checkNum, checkStr, checkTab } = L;
const nowMs = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());
const fmtN = (n) => numToStr(n);

// ===================================================================
// 資料型別
// ===================================================================
function memberErr(I, k, type) { return I.rtErr(`${typeof k === 'string' ? k : I.tostr(k)} is not a valid member of ${type}`); }
function selfOf(a, I, Cls, name) {
  const s = a[0];
  if (!(s instanceof Cls)) throw I.rtErr(`Expected ':' not '.' calling member function ${name}`);
  return s;
}
function methods(Cls, defs) {
  const out = {};
  for (const k in defs) { const f = defs[k]; out[k] = nat(k, (a, I) => f(selfOf(a, I, Cls, k), a, I)); }
  return out;
}

class Vector3 {
  constructor(x, y, z) { this.X = x || 0; this.Y = y || 0; this.Z = z || 0; }
  get luaType() { return 'Vector3'; }
  add(o) { return new Vector3(this.X + o.X, this.Y + o.Y, this.Z + o.Z); }
  sub(o) { return new Vector3(this.X - o.X, this.Y - o.Y, this.Z - o.Z); }
  mul(s) { return new Vector3(this.X * s, this.Y * s, this.Z * s); }
  dot(o) { return this.X * o.X + this.Y * o.Y + this.Z * o.Z; }
  cross(o) { return new Vector3(this.Y * o.Z - this.Z * o.Y, this.Z * o.X - this.X * o.Z, this.X * o.Y - this.Y * o.X); }
  get mag() { return Math.sqrt(this.X * this.X + this.Y * this.Y + this.Z * this.Z); }
  unit() { const m = this.mag; return m === 0 ? new Vector3(NaN, NaN, NaN) : new Vector3(this.X / m, this.Y / m, this.Z / m); }
  lerp(o, t) { return new Vector3(this.X + (o.X - this.X) * t, this.Y + (o.Y - this.Y) * t, this.Z + (o.Z - this.Z) * t); }
  luaIndex(k, I) {
    switch (k) {
      case 'X': case 'x': return this.X;
      case 'Y': case 'y': return this.Y;
      case 'Z': case 'z': return this.Z;
      case 'Magnitude': case 'magnitude': return this.mag;
      case 'Unit': case 'unit': return this.unit();
    }
    const m = V3M[k];
    if (m) return m;
    throw memberErr(I, k, 'Vector3');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaArith(op, o, rev, I) {
    switch (op) {
      case '+': if (o instanceof Vector3) return this.add(o); break;
      case '-': if (o instanceof Vector3) return rev ? o.sub(this) : this.sub(o); break;
      case '*':
        if (typeof o === 'number') return this.mul(o);
        if (o instanceof Vector3) return new Vector3(this.X * o.X, this.Y * o.Y, this.Z * o.Z);
        break;
      case '/':
        if (typeof o === 'number') return rev ? new Vector3(o / this.X, o / this.Y, o / this.Z) : new Vector3(this.X / o, this.Y / o, this.Z / o);
        if (o instanceof Vector3) return rev ? new Vector3(o.X / this.X, o.Y / this.Y, o.Z / this.Z) : new Vector3(this.X / o.X, this.Y / o.Y, this.Z / o.Z);
        break;
      case '//':
        if (typeof o === 'number' && !rev) return new Vector3(Math.floor(this.X / o), Math.floor(this.Y / o), Math.floor(this.Z / o));
        if (o instanceof Vector3 && !rev) return new Vector3(Math.floor(this.X / o.X), Math.floor(this.Y / o.Y), Math.floor(this.Z / o.Z));
        break;
      case 'unm': return this.mul(-1);
    }
    return undefined;
  }
  luaEq(o) { return o instanceof Vector3 && o.X === this.X && o.Y === this.Y && o.Z === this.Z; }
  luaToString() { return `${fmtN(this.X)}, ${fmtN(this.Y)}, ${fmtN(this.Z)}`; }
}
const V3 = (x, y, z) => new Vector3(x, y, z);
const V3M = methods(Vector3, {
  Lerp: (s, a, I) => s.lerp(argV3(I, a, 1, 'Lerp'), checkNum(I, a, 2, 'Lerp')),
  Dot: (s, a, I) => s.dot(argV3(I, a, 1, 'Dot')),
  Cross: (s, a, I) => s.cross(argV3(I, a, 1, 'Cross')),
  FuzzyEq: (s, a, I) => { const o = argV3(I, a, 1, 'FuzzyEq'), e = a[2] === undefined ? 1e-5 : a[2]; return Math.abs(s.X - o.X) <= e && Math.abs(s.Y - o.Y) <= e && Math.abs(s.Z - o.Z) <= e; },
  Abs: (s) => V3(Math.abs(s.X), Math.abs(s.Y), Math.abs(s.Z)),
  Floor: (s) => V3(Math.floor(s.X), Math.floor(s.Y), Math.floor(s.Z)),
  Ceil: (s) => V3(Math.ceil(s.X), Math.ceil(s.Y), Math.ceil(s.Z)),
  Sign: (s) => V3(Math.sign(s.X), Math.sign(s.Y), Math.sign(s.Z)),
  Min: (s, a, I) => { const o = argV3(I, a, 1, 'Min'); return V3(Math.min(s.X, o.X), Math.min(s.Y, o.Y), Math.min(s.Z, o.Z)); },
  Max: (s, a, I) => { const o = argV3(I, a, 1, 'Max'); return V3(Math.max(s.X, o.X), Math.max(s.Y, o.Y), Math.max(s.Z, o.Z)); },
  Angle: (s, a, I) => { const o = argV3(I, a, 1, 'Angle'); return Math.acos(Math.max(-1, Math.min(1, s.dot(o) / (s.mag * o.mag || 1)))); },
});
function argV3(I, a, i, fname) { const v = a[i]; if (v instanceof Vector3) return v; throw I.argErr(i, fname, `Vector3 expected, got ${luauTypeof(v)}`); }

class Vector2 {
  constructor(x, y) { this.X = x || 0; this.Y = y || 0; }
  get luaType() { return 'Vector2'; }
  get mag() { return Math.hypot(this.X, this.Y); }
  luaIndex(k, I) {
    switch (k) {
      case 'X': case 'x': return this.X;
      case 'Y': case 'y': return this.Y;
      case 'Magnitude': return this.mag;
      case 'Unit': { const m = this.mag; return new Vector2(this.X / m, this.Y / m); }
    }
    const m = V2M[k];
    if (m) return m;
    throw memberErr(I, k, 'Vector2');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaArith(op, o, rev) {
    switch (op) {
      case '+': if (o instanceof Vector2) return new Vector2(this.X + o.X, this.Y + o.Y); break;
      case '-': if (o instanceof Vector2) return rev ? new Vector2(o.X - this.X, o.Y - this.Y) : new Vector2(this.X - o.X, this.Y - o.Y); break;
      case '*': if (typeof o === 'number') return new Vector2(this.X * o, this.Y * o); if (o instanceof Vector2) return new Vector2(this.X * o.X, this.Y * o.Y); break;
      case '/': if (typeof o === 'number' && !rev) return new Vector2(this.X / o, this.Y / o); if (o instanceof Vector2 && !rev) return new Vector2(this.X / o.X, this.Y / o.Y); break;
      case 'unm': return new Vector2(-this.X, -this.Y);
    }
    return undefined;
  }
  luaEq(o) { return o instanceof Vector2 && o.X === this.X && o.Y === this.Y; }
  luaToString() { return `${fmtN(this.X)}, ${fmtN(this.Y)}`; }
}
const V2M = methods(Vector2, {
  Lerp: (s, a, I) => { const o = a[1], t = checkNum(I, a, 2, 'Lerp'); return new Vector2(s.X + (o.X - s.X) * t, s.Y + (o.Y - s.Y) * t); },
  Dot: (s, a) => s.X * a[1].X + s.Y * a[1].Y,
  Cross: (s, a) => s.X * a[1].Y - s.Y * a[1].X,
});

class Color3 {
  constructor(r, g, b) { this.R = r || 0; this.G = g || 0; this.B = b || 0; }
  get luaType() { return 'Color3'; }
  luaIndex(k, I) {
    switch (k) { case 'R': case 'r': return this.R; case 'G': case 'g': return this.G; case 'B': case 'b': return this.B; }
    const m = C3M[k];
    if (m) return m;
    throw memberErr(I, k, 'Color3');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaEq(o) { return o instanceof Color3 && o.R === this.R && o.G === this.G && o.B === this.B; }
  luaToString() { return `${fmtN(this.R)}, ${fmtN(this.G)}, ${fmtN(this.B)}`; }
  lerp(o, t) { return new Color3(this.R + (o.R - this.R) * t, this.G + (o.G - this.G) * t, this.B + (o.B - this.B) * t); }
  hex() { const h = (x) => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, '0'); return h(this.R) + h(this.G) + h(this.B); }
  static rgb(r, g, b) { return new Color3(r / 255, g / 255, b / 255); }
  static hsv(h, s, v) {
    const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
    switch (((i % 6) + 6) % 6) {
      case 0: return new Color3(v, t, p); case 1: return new Color3(q, v, p); case 2: return new Color3(p, v, t);
      case 3: return new Color3(p, q, v); case 4: return new Color3(t, p, v); default: return new Color3(v, p, q);
    }
  }
}
const C3M = methods(Color3, {
  Lerp: (s, a, I) => s.lerp(a[1], checkNum(I, a, 2, 'Lerp')),
  ToHSV: (s) => {
    const mx = Math.max(s.R, s.G, s.B), mn = Math.min(s.R, s.G, s.B), d = mx - mn;
    let h = 0;
    if (d) { if (mx === s.R) h = ((s.G - s.B) / d) % 6; else if (mx === s.G) h = (s.B - s.R) / d + 2; else h = (s.R - s.G) / d + 4; h /= 6; if (h < 0) h += 1; }
    return [h, mx ? d / mx : 0, mx];
  },
  ToHex: (s) => s.hex().toUpperCase(),
});

const BRICK_COLORS = [
  [1, 'White', 242, 243, 243], [194, 'Medium stone grey', 163, 162, 165], [199, 'Dark stone grey', 99, 95, 98], [26, 'Black', 27, 42, 53],
  [21, 'Bright red', 196, 40, 28], [23, 'Bright blue', 13, 105, 172], [37, 'Bright green', 75, 151, 75], [24, 'Bright yellow', 245, 205, 48],
  [106, 'Bright orange', 218, 133, 65], [1004, 'Really red', 255, 0, 0], [1010, 'Really blue', 0, 0, 255], [1020, 'Lime green', 0, 255, 0],
  [1009, 'New Yeller', 255, 255, 0], [1001, 'Institutional white', 248, 248, 248], [1003, 'Really black', 17, 17, 17], [1032, 'Hot pink', 255, 0, 191],
  [1015, 'Magenta', 170, 0, 170], [1013, 'Toothpaste', 0, 255, 255], [1019, 'Cyan', 4, 175, 236], [1005, 'Deep orange', 255, 176, 0],
  [153, 'Sand red', 149, 121, 119], [192, 'Reddish brown', 105, 64, 40], [217, 'Brown', 124, 92, 70], [151, 'Sand green', 120, 144, 130],
  [107, 'Bright bluish green', 0, 143, 156], [1006, 'Alder', 180, 128, 255], [104, 'Bright violet', 107, 50, 124], [1031, 'Royal purple', 98, 37, 209],
  [119, 'Br. yellowish green', 164, 189, 71], [18, 'Nougat', 204, 142, 105], [125, 'Light orange', 234, 184, 146], [1025, 'Pastel orange', 255, 201, 201],
  [1024, 'Pastel light blue', 175, 221, 255], [1026, 'Pastel violet', 177, 167, 255], [1029, 'Pastel yellow', 255, 255, 204], [1030, 'Pastel brown', 255, 204, 153],
  [1028, 'Pastel green', 204, 255, 204], [1012, 'Deep blue', 33, 84, 185], [1011, 'Navy blue', 0, 32, 96], [1021, 'Camo', 58, 125, 21],
  [1022, 'Grime', 127, 142, 100], [141, 'Earth green', 39, 70, 45], [1027, 'Teal', 159, 243, 233], [1016, 'Pink', 255, 102, 204],
  [1017, 'Deep orange', 255, 175, 0], [1018, 'Teal', 18, 238, 212], [1014, 'CGA brown', 170, 85, 0], [1002, 'Mid gray', 205, 205, 205],
  [1023, 'Lavender', 140, 91, 159], [1007, 'Dusty Rose', 163, 75, 75], [1008, 'Olive', 193, 190, 66], [5, 'Brick yellow', 215, 197, 154],
  [28, 'Dark green', 40, 127, 71], [102, 'Medium blue', 110, 153, 202], [45, 'Light blue', 180, 210, 228], [38, 'Dark orange', 160, 95, 53],
  [208, 'Light stone grey', 229, 228, 223], [101, 'Medium red', 218, 134, 122], [9, 'Light reddish violet', 232, 186, 200], [226, 'Cool yellow', 253, 234, 141],
];
class BrickColor {
  constructor(entry) { this.Number = entry[0]; this.Name = entry[1]; this.Color = Color3.rgb(entry[2], entry[3], entry[4]); }
  get luaType() { return 'BrickColor'; }
  luaIndex(k, I) {
    switch (k) {
      case 'Name': return this.Name; case 'Number': return this.Number; case 'Color': return this.Color;
      case 'r': return this.Color.R; case 'g': return this.Color.G; case 'b': return this.Color.B;
    }
    throw memberErr(I, k, 'BrickColor');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaEq(o) { return o instanceof BrickColor && o.Number === this.Number; }
  luaToString() { return this.Name; }
  static byName(n) { const e = BRICK_COLORS.find(b => b[1].toLowerCase() === String(n).toLowerCase()); return new BrickColor(e || BRICK_COLORS[1]); }
  static byNumber(n) { const e = BRICK_COLORS.find(b => b[0] === n); return new BrickColor(e || BRICK_COLORS[1]); }
  static closest(c) {
    let best = BRICK_COLORS[1], bd = Infinity;
    for (const b of BRICK_COLORS) { const d = (b[2] / 255 - c.R) ** 2 + (b[3] / 255 - c.G) ** 2 + (b[4] / 255 - c.B) ** 2; if (d < bd) { bd = d; best = b; } }
    return new BrickColor(best);
  }
}

// ---- CFrame：位置 + 3x3 旋轉矩陣(列優先 r00 r01 r02 r10 ...) ----
class CFrame {
  constructor(x, y, z, m) { this.x = x || 0; this.y = y || 0; this.z = z || 0; this.m = m || [1, 0, 0, 0, 1, 0, 0, 0, 1]; }
  get luaType() { return 'CFrame'; }
  get pos() { return V3(this.x, this.y, this.z); }
  col(i) { const m = this.m; return V3(m[i], m[3 + i], m[6 + i]); }
  mul(o) {
    const a = this.m, b = o.m, r = new Array(9);
    for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
    const p = this.point(o.x, o.y, o.z);
    return new CFrame(p.X, p.Y, p.Z, r);
  }
  point(x, y, z) { const m = this.m; return V3(m[0] * x + m[1] * y + m[2] * z + this.x, m[3] * x + m[4] * y + m[5] * z + this.y, m[6] * x + m[7] * y + m[8] * z + this.z); }
  vec(x, y, z) { const m = this.m; return V3(m[0] * x + m[1] * y + m[2] * z, m[3] * x + m[4] * y + m[5] * z, m[6] * x + m[7] * y + m[8] * z); }
  inv() {
    const m = this.m, t = [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]];
    const c = new CFrame(0, 0, 0, t);
    const p = c.vec(-this.x, -this.y, -this.z);
    return new CFrame(p.X, p.Y, p.Z, t);
  }
  withPos(v) { return new CFrame(v.X, v.Y, v.Z, this.m); }
  rotOnly() { return new CFrame(0, 0, 0, this.m); }
  toQuat() {
    const m = this.m, tr = m[0] + m[4] + m[8];
    let w, x, y, z;
    if (tr > 0) { const s = Math.sqrt(tr + 1) * 2; w = 0.25 * s; x = (m[7] - m[5]) / s; y = (m[2] - m[6]) / s; z = (m[3] - m[1]) / s; }
    else if (m[0] > m[4] && m[0] > m[8]) { const s = Math.sqrt(1 + m[0] - m[4] - m[8]) * 2; w = (m[7] - m[5]) / s; x = 0.25 * s; y = (m[1] + m[3]) / s; z = (m[2] + m[6]) / s; }
    else if (m[4] > m[8]) { const s = Math.sqrt(1 + m[4] - m[0] - m[8]) * 2; w = (m[2] - m[6]) / s; x = (m[1] + m[3]) / s; y = 0.25 * s; z = (m[5] + m[7]) / s; }
    else { const s = Math.sqrt(1 + m[8] - m[0] - m[4]) * 2; w = (m[3] - m[1]) / s; x = (m[2] + m[6]) / s; y = (m[5] + m[7]) / s; z = 0.25 * s; }
    return [x, y, z, w];
  }
  static fromQuat(px, py, pz, x, y, z, w) {
    const n = Math.hypot(x, y, z, w) || 1; x /= n; y /= n; z /= n; w /= n;
    return new CFrame(px, py, pz, [
      1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
      2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
      2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]);
  }
  lerp(o, t) {
    const a = this.toQuat(), b = o.toQuat();
    let d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
    if (d < 0) { b[0] = -b[0]; b[1] = -b[1]; b[2] = -b[2]; b[3] = -b[3]; d = -d; }
    let s0, s1;
    if (d > 0.9995) { s0 = 1 - t; s1 = t; }
    else { const th = Math.acos(d), sn = Math.sin(th); s0 = Math.sin((1 - t) * th) / sn; s1 = Math.sin(t * th) / sn; }
    return CFrame.fromQuat(this.x + (o.x - this.x) * t, this.y + (o.y - this.y) * t, this.z + (o.z - this.z) * t,
      a[0] * s0 + b[0] * s1, a[1] * s0 + b[1] * s1, a[2] * s0 + b[2] * s1, a[3] * s0 + b[3] * s1);
  }
  static rx(a) { const c = Math.cos(a), s = Math.sin(a); return [1, 0, 0, 0, c, -s, 0, s, c]; }
  static ry(a) { const c = Math.cos(a), s = Math.sin(a); return [c, 0, s, 0, 1, 0, -s, 0, c]; }
  static rz(a) { const c = Math.cos(a), s = Math.sin(a); return [c, -s, 0, s, c, 0, 0, 0, 1]; }
  static mm(a, b) { const r = new Array(9); for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]; return r; }
  static anglesXYZ(x, y, z) { return new CFrame(0, 0, 0, CFrame.mm(CFrame.mm(CFrame.rx(x), CFrame.ry(y)), CFrame.rz(z))); }
  static anglesYXZ(x, y, z) { return new CFrame(0, 0, 0, CFrame.mm(CFrame.mm(CFrame.ry(y), CFrame.rx(x)), CFrame.rz(z))); }
  toXYZ() { const m = this.m; return [Math.atan2(-m[5], m[8]), Math.asin(Math.max(-1, Math.min(1, m[2]))), Math.atan2(-m[1], m[0])]; }
  toYXZ() { const m = this.m; return [Math.asin(Math.max(-1, Math.min(1, -m[5]))), Math.atan2(m[2], m[8]), Math.atan2(m[3], m[4])]; }
  static lookAt(eye, target, up) {
    up = up || V3(0, 1, 0);
    let f = target.sub(eye);
    if (f.mag < 1e-9) return new CFrame(eye.X, eye.Y, eye.Z);
    f = f.unit();
    let r = f.cross(up);
    if (r.mag < 1e-6) r = f.cross(V3(0, 0, Math.abs(f.Y) > 0 ? -1 : 1));
    r = r.unit();
    const u = r.cross(f);
    return new CFrame(eye.X, eye.Y, eye.Z, [r.X, u.X, -f.X, r.Y, u.Y, -f.Y, r.Z, u.Z, -f.Z]);
  }
  luaIndex(k, I) {
    switch (k) {
      case 'Position': case 'p': return this.pos;
      case 'X': case 'x': return this.x;
      case 'Y': case 'y': return this.y;
      case 'Z': case 'z': return this.z;
      case 'LookVector': case 'lookVector': return this.col(2).mul(-1);
      case 'RightVector': case 'rightVector': return this.col(0);
      case 'UpVector': case 'upVector': return this.col(1);
      case 'XVector': return V3(this.m[0], this.m[1], this.m[2]);
      case 'YVector': return V3(this.m[3], this.m[4], this.m[5]);
      case 'ZVector': return V3(this.m[6], this.m[7], this.m[8]);
      case 'Rotation': return this.rotOnly();
    }
    const m = CFM[k];
    if (m) return m;
    throw memberErr(I, k, 'CFrame');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaArith(op, o, rev) {
    if (op === '*' && !rev) {
      if (o instanceof CFrame) return this.mul(o);
      if (o instanceof Vector3) return this.point(o.X, o.Y, o.Z);
    }
    if (op === '+' && o instanceof Vector3) return new CFrame(this.x + o.X, this.y + o.Y, this.z + o.Z, this.m);
    if (op === '-' && o instanceof Vector3 && !rev) return new CFrame(this.x - o.X, this.y - o.Y, this.z - o.Z, this.m);
    return undefined;
  }
  luaEq(o) { return o instanceof CFrame && o.x === this.x && o.y === this.y && o.z === this.z && o.m.every((v, i) => v === this.m[i]); }
  luaToString() { return [this.x, this.y, this.z, ...this.m].map(fmtN).join(', '); }
}
function argCF(I, a, i, fname) { const v = a[i]; if (v instanceof CFrame) return v; throw I.argErr(i, fname, `CFrame expected, got ${luauTypeof(v)}`); }
const CFM = methods(CFrame, {
  Inverse: (s) => s.inv(),
  Lerp: (s, a, I) => s.lerp(argCF(I, a, 1, 'Lerp'), checkNum(I, a, 2, 'Lerp')),
  ToWorldSpace: (s, a) => a.slice(1).map(c => s.mul(c)),
  ToObjectSpace: (s, a) => a.slice(1).map(c => s.inv().mul(c)),
  PointToWorldSpace: (s, a) => a.slice(1).map(v => s.point(v.X, v.Y, v.Z)),
  PointToObjectSpace: (s, a) => { const iv = s.inv(); return a.slice(1).map(v => iv.point(v.X, v.Y, v.Z)); },
  VectorToWorldSpace: (s, a) => a.slice(1).map(v => s.vec(v.X, v.Y, v.Z)),
  VectorToObjectSpace: (s, a) => { const iv = s.inv(); return a.slice(1).map(v => iv.vec(v.X, v.Y, v.Z)); },
  ToEulerAnglesXYZ: (s) => s.toXYZ(),
  ToEulerAnglesYXZ: (s) => s.toYXZ(),
  ToOrientation: (s) => s.toYXZ(),
  GetComponents: (s) => [s.x, s.y, s.z, ...s.m],
  components: (s) => [s.x, s.y, s.z, ...s.m],
  ToAxisAngle: (s) => { const q = s.toQuat(); const ang = 2 * Math.acos(Math.min(1, Math.abs(q[3]))); const sn = Math.sqrt(1 - q[3] * q[3]) || 1; const sg = q[3] < 0 ? -1 : 1; return [V3(q[0] / sn * sg, q[1] / sn * sg, q[2] / sn * sg), ang]; },
});

class UDim {
  constructor(s, o) { this.Scale = s || 0; this.Offset = o || 0; }
  get luaType() { return 'UDim'; }
  luaIndex(k, I) { if (k === 'Scale') return this.Scale; if (k === 'Offset') return this.Offset; throw memberErr(I, k, 'UDim'); }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaArith(op, o, rev) {
    if (!(o instanceof UDim)) return undefined;
    if (op === '+') return new UDim(this.Scale + o.Scale, this.Offset + o.Offset);
    if (op === '-') return rev ? new UDim(o.Scale - this.Scale, o.Offset - this.Offset) : new UDim(this.Scale - o.Scale, this.Offset - o.Offset);
    return undefined;
  }
  luaEq(o) { return o instanceof UDim && o.Scale === this.Scale && o.Offset === this.Offset; }
  luaToString() { return `${fmtN(this.Scale)}, ${fmtN(this.Offset)}`; }
}
class UDim2 {
  constructor(xs, xo, ys, yo) { this.X = new UDim(xs, xo); this.Y = new UDim(ys, yo); }
  get luaType() { return 'UDim2'; }
  luaIndex(k, I) {
    switch (k) { case 'X': case 'Width': return this.X; case 'Y': case 'Height': return this.Y; }
    if (k === 'Lerp') return UDIM2_LERP;
    throw memberErr(I, k, 'UDim2');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  lerp(o, t) { const f = (a, b) => a + (b - a) * t; return new UDim2(f(this.X.Scale, o.X.Scale), f(this.X.Offset, o.X.Offset), f(this.Y.Scale, o.Y.Scale), f(this.Y.Offset, o.Y.Offset)); }
  luaArith(op, o, rev) {
    if (!(o instanceof UDim2)) return undefined;
    const a = rev ? o : this, b = rev ? this : o;
    if (op === '+') return new UDim2(this.X.Scale + o.X.Scale, this.X.Offset + o.X.Offset, this.Y.Scale + o.Y.Scale, this.Y.Offset + o.Y.Offset);
    if (op === '-') return new UDim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset);
    return undefined;
  }
  luaEq(o) { return o instanceof UDim2 && this.X.luaEq(o.X) && this.Y.luaEq(o.Y); }
  luaToString() { return `{${this.X.luaToString()}}, {${this.Y.luaToString()}}`; }
}
const UDIM2_LERP = nat('Lerp', (a, I) => selfOf(a, I, UDim2, 'Lerp').lerp(a[1], checkNum(I, a, 2, 'Lerp')));

class NumberRange {
  constructor(a, b) { this.Min = a; this.Max = b === undefined ? a : b; }
  get luaType() { return 'NumberRange'; }
  luaIndex(k, I) { if (k === 'Min') return this.Min; if (k === 'Max') return this.Max; throw memberErr(I, k, 'NumberRange'); }
  luaToString() { return `${fmtN(this.Min)} ${fmtN(this.Max)}`; }
}

class TweenInfo {
  constructor(t, style, dir, rep, rev, delay) { this.Time = t; this.EasingStyle = style; this.EasingDirection = dir; this.RepeatCount = rep; this.Reverses = rev; this.DelayTime = delay; }
  get luaType() { return 'TweenInfo'; }
  luaIndex(k, I) { if (k in this) return this[k]; throw memberErr(I, k, 'TweenInfo'); }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaToString() { return `Time:${fmtN(this.Time)} DelayTime:${fmtN(this.DelayTime)} RepeatCount:${this.RepeatCount} Reverses:${this.Reverses} EasingDirection:${this.EasingDirection.Name} EasingStyle:${this.EasingStyle.Name}`; }
}

class RaycastParams {
  constructor() { this.FilterDescendantsInstances = new LuaTable(); this.FilterType = null; this.IgnoreWater = false; this.CollisionGroup = 'Default'; this.RespectCanCollide = false; }
  get luaType() { return 'RaycastParams'; }
  luaIndex(k, I) {
    if (k === 'AddToFilter') return RP_ADD;
    if (k in this) return this[k];
    throw memberErr(I, k, 'RaycastParams');
  }
  luaNewIndex(k, v, I) { if (!(k in this)) throw memberErr(I, k, 'RaycastParams'); this[k] = v; }
  luaToString() { return 'RaycastParams{}'; }
}
const RP_ADD = nat('AddToFilter', (a) => { const s = a[0]; const v = a[1]; if (v instanceof LuaTable) { for (const x of v.arr) s.FilterDescendantsInstances.set(s.FilterDescendantsInstances.length() + 1, x); } else s.FilterDescendantsInstances.set(s.FilterDescendantsInstances.length() + 1, v); });

class RaycastResult {
  constructor(inst, pos, normal, dist, material) { this.Instance = inst; this.Position = pos; this.Normal = normal; this.Distance = dist; this.Material = material; }
  get luaType() { return 'RaycastResult'; }
  luaIndex(k, I) { if (k in this) return this[k]; throw memberErr(I, k, 'RaycastResult'); }
  luaToString() { return 'RaycastResult{' + this.Instance.p.Name + '}'; }
}

// ---- Enum ----
class EnumItem {
  constructor(type, name, value) { this.EnumType = type; this.Name = name; this.Value = value; }
  get luaType() { return 'EnumItem'; }
  luaIndex(k, I) {
    if (k === 'Name') return this.Name;
    if (k === 'Value') return this.Value;
    if (k === 'EnumType') return this.EnumType;
    if (k === 'IsA') return ENUM_ISA;
    throw memberErr(I, k, `"Enum.${this.EnumType.name}.${this.Name}"`);
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaToString() { return `Enum.${this.EnumType.name}.${this.Name}`; }
}
const ENUM_ISA = nat('IsA', (a) => a[0].EnumType.name === a[1]);
class EnumType {
  constructor(name, items) {
    this.name = name; this.items = {}; this.list = [];
    items.forEach((n, i) => { const it = new EnumItem(this, n, i); this.items[n] = it; this.list.push(it); });
  }
  get luaType() { return 'Enum'; }
  luaIndex(k, I) {
    const it = this.items[k];
    if (it) return it;
    if (k === 'GetEnumItems') return nat('GetEnumItems', () => LuaTable.from(this.list));
    throw I.rtErr(`${k} is not a valid member of "Enum.${this.name}"`);
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaToString() { return this.name; }
  get(v) { if (v instanceof EnumItem) return v.EnumType === this ? v : null; if (typeof v === 'string') return this.items[v] || null; if (typeof v === 'number') return this.list.find(x => x.Value === v) || null; return null; }
}
const KEYS = ['Unknown', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  'Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Space', 'Return', 'Tab', 'Backspace', 'Escape',
  'LeftShift', 'RightShift', 'LeftControl', 'RightControl', 'LeftAlt', 'RightAlt', 'Up', 'Down', 'Left', 'Right',
  'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12', 'Minus', 'Equals', 'Comma', 'Period', 'Slash', 'Semicolon', 'Quote',
  'LeftBracket', 'RightBracket', 'BackSlash', 'Backquote', 'Delete', 'Insert', 'Home', 'End', 'PageUp', 'PageDown', 'CapsLock',
  'ButtonA', 'ButtonB', 'ButtonX', 'ButtonY', 'ButtonR1', 'ButtonL1', 'ButtonR2', 'ButtonL2', 'Thumbstick1', 'Thumbstick2'];
const ENUMS = {};
for (const [n, items] of Object.entries({
  PartType: ['Ball', 'Block', 'Cylinder', 'Wedge', 'CornerWedge'],
  Material: ['Plastic', 'SmoothPlastic', 'Neon', 'Wood', 'WoodPlanks', 'Marble', 'Slate', 'Concrete', 'Granite', 'Brick', 'Pebble', 'Cobblestone', 'Rock',
    'Sandstone', 'Basalt', 'CrackedLava', 'Limestone', 'Pavement', 'CorrodedMetal', 'DiamondPlate', 'Foil', 'Metal', 'Grass', 'LeafyGrass', 'Sand', 'Fabric',
    'Snow', 'Mud', 'Ground', 'Asphalt', 'Salt', 'Ice', 'Glacier', 'Glass', 'ForceField', 'Air', 'Water', 'Cardboard', 'Carpet', 'Leather', 'Plaster', 'Rubber'],
  EasingStyle: ['Linear', 'Sine', 'Back', 'Quad', 'Quart', 'Quint', 'Bounce', 'Elastic', 'Exponential', 'Circular', 'Cubic'],
  EasingDirection: ['In', 'Out', 'InOut'],
  PlaybackState: ['Begin', 'Delayed', 'Playing', 'Paused', 'Completed', 'Cancelled'],
  KeyCode: KEYS,
  UserInputType: ['MouseButton1', 'MouseButton2', 'MouseButton3', 'MouseWheel', 'MouseMovement', 'Touch', 'Keyboard', 'Focus', 'Accelerometer', 'Gyro', 'Gamepad1', 'TextInput', 'None'],
  UserInputState: ['Begin', 'Change', 'End', 'Cancel', 'None'],
  HumanoidStateType: ['FallingDown', 'Running', 'RunningNoPhysics', 'Climbing', 'StrafingNoPhysics', 'Ragdoll', 'GettingUp', 'Jumping', 'Landed', 'Flying', 'Freefall', 'Seated', 'PlatformStanding', 'Dead', 'Swimming', 'Physics', 'None'],
  RaycastFilterType: ['Exclude', 'Include', 'Blacklist', 'Whitelist'],
  CameraType: ['Fixed', 'Attach', 'Watch', 'Track', 'Follow', 'Custom', 'Scriptable', 'Orbital'],
  Font: ['Legacy', 'Arial', 'ArialBold', 'SourceSans', 'SourceSansBold', 'SourceSansLight', 'SourceSansItalic', 'Bodoni', 'Garamond', 'Cartoon', 'Code', 'Highway', 'SciFi', 'Arcade', 'Fantasy', 'Antique', 'SourceSansSemibold', 'Gotham', 'GothamMedium', 'GothamBold', 'GothamBlack', 'FredokaOne', 'Bangers', 'Creepster', 'IndieFlower', 'LuckiestGuy', 'Oswald', 'PermanentMarker', 'Roboto', 'RobotoMono', 'Ubuntu', 'Nunito', 'BuilderSans', 'BuilderSansBold'],
  TextXAlignment: ['Left', 'Center', 'Right'],
  TextYAlignment: ['Top', 'Center', 'Bottom'],
  FillDirection: ['Horizontal', 'Vertical'],
  HorizontalAlignment: ['Center', 'Left', 'Right'],
  VerticalAlignment: ['Center', 'Top', 'Bottom'],
  SortOrder: ['Name', 'Custom', 'LayoutOrder'],
  ZIndexBehavior: ['Global', 'Sibling'],
  SurfaceType: ['Smooth', 'Glue', 'Weld', 'Studs', 'Inlet', 'Universal', 'Hinge', 'Motor', 'SteppingMotor', 'SmoothNoOutlines'],
  NormalId: ['Right', 'Top', 'Back', 'Left', 'Bottom', 'Front'],
  MouseBehavior: ['Default', 'LockCenter', 'LockCurrentPosition'],
  ContextActionResult: ['Sink', 'Pass'],
  HumanoidRigType: ['R6', 'R15'],
  SortDirection: ['Ascending', 'Descending'],
  AutomaticSize: ['None', 'X', 'Y', 'XY'],
  ScaleType: ['Stretch', 'Slice', 'Tile', 'Fit', 'Crop'],
  ApplyStrokeMode: ['Contextual', 'Border'],
  RollOffMode: ['Inverse', 'Linear', 'LinearSquare', 'InverseTapered'],
  ExplosionType: ['NoCraters', 'Craters'],
  ActuatorRelativeTo: ['Attachment0', 'Attachment1', 'World'],
  VelocityConstraintMode: ['Line', 'Plane', 'Vector'],
})) ENUMS[n] = new EnumType(n, items);
const ENUM_ROOT = {
  get luaType() { return 'Enums'; },
  luaIndex(k, I) {
    if (ENUMS[k]) return ENUMS[k];
    if (k === 'GetEnums') return nat('GetEnums', () => LuaTable.from(Object.values(ENUMS)));
    throw I.rtErr(`${k} is not a valid member of "Enum"`);
  },
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); },
  luaToString() { return 'Enums'; },
};
const E = (t, n) => ENUMS[t].items[n];

// ===================================================================
// 事件
// ===================================================================
class Connection {
  constructor(sig, fn, once) { this.sig = sig; this.fn = fn; this.once = once; this.connected = true; }
  get luaType() { return 'RBXScriptConnection'; }
  luaIndex(k, I) {
    if (k === 'Connected') return this.connected;
    if (k === 'Disconnect' || k === 'disconnect') return CONN_DISCONNECT;
    throw memberErr(I, k, 'RBXScriptConnection');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  disconnect() { if (!this.connected) return; this.connected = false; const i = this.sig.conns.indexOf(this); if (i >= 0) this.sig.conns.splice(i, 1); }
  luaToString() { return 'Connection'; }
}
const CONN_DISCONNECT = nat('Disconnect', (a) => { if (a[0] instanceof Connection) a[0].disconnect(); });
class Signal {
  constructor(rt, name) { this.rt = rt; this.name = name; this.conns = []; this.waiters = []; }
  get luaType() { return 'RBXScriptSignal'; }
  luaIndex(k, I) {
    switch (k) {
      case 'Connect': case 'connect': case 'ConnectParallel': return SIG_CONNECT;
      case 'Once': return SIG_ONCE;
      case 'Wait': case 'wait': return SIG_WAIT;
    }
    throw memberErr(I, k, 'RBXScriptSignal');
  }
  luaNewIndex(k, v, I) { throw I.rtErr(`${k} cannot be assigned to`); }
  luaToString() { return 'Signal ' + this.name; }
  connect(fn, once) { const c = new Connection(this, fn, once); this.conns.push(c); return c; }
  clear() { for (const c of this.conns) c.connected = false; this.conns = []; }
}
const sigSelf = (a, I, n) => { if (!(a[0] instanceof Signal)) throw I.rtErr(`Expected ':' not '.' calling member function ${n}`); return a[0]; };
const checkFn = (I, a, i, n) => { if (luaType(a[i]) !== 'function') throw I.argErr(i, n, `function expected, got ${luauTypeof(a[i])}`); return a[i]; };
const SIG_CONNECT = nat('Connect', (a, I) => sigSelf(a, I, 'Connect').connect(checkFn(I, a, 1, 'Connect'), false));
const SIG_ONCE = nat('Once', (a, I) => sigSelf(a, I, 'Once').connect(checkFn(I, a, 1, 'Once'), true));
const SIG_WAIT = nat('Wait', function* (a, I) { const s = sigSelf(a, I, 'Wait'); const r = yield { k: 'signal', signal: s }; return r || []; });

// ===================================================================
// Instance
// ===================================================================
const REF = { ref: true };
const CLASSES = {};
function defClass(name, base, spec = {}) {
  CLASSES[name] = {
    name, base: base ? CLASSES[base] : null,
    props: spec.props || {}, methods: spec.methods || {}, events: spec.events || [], virt: spec.virt || {},
    readonly: spec.readonly || [], notCreatable: !!spec.notCreatable, service: !!spec.service, init: spec.init, onSet: spec.onSet,
    valueChanged: !!spec.valueChanged, all: null,
  };
}
function flat(cls) {
  if (cls.all) return cls.all;
  const b = cls.base ? flat(cls.base) : { props: {}, types: {}, methods: {}, events: new Set(), virt: {}, readonly: new Set(), chain: [], onSet: [], inits: [] };
  const all = {
    props: { ...b.props }, types: { ...b.types }, methods: { ...b.methods }, events: new Set(b.events), virt: { ...b.virt },
    readonly: new Set(b.readonly), chain: [cls.name, ...b.chain], onSet: cls.onSet ? [...b.onSet, cls.onSet] : b.onSet, inits: cls.init ? [...b.inits, cls.init] : b.inits,
  };
  for (const [k, d] of Object.entries(cls.props)) { all.props[k] = d; all.types[k] = typeOfDefault(d); }
  for (const [k, f] of Object.entries(cls.methods)) all.methods[k] = f;
  for (const e of cls.events) all.events.add(e);
  Object.assign(all.virt, cls.virt);
  for (const r of cls.readonly) all.readonly.add(r);
  cls.all = all;
  return all;
}
function typeOfDefault(d) {
  if (d === REF) return 'Instance';
  if (d && d.any) return 'any';
  const v = typeof d === 'function' ? d() : d;
  if (v instanceof EnumItem) return { enum: v.EnumType };
  const t = luauTypeof(v);
  return t;
}
function defaultVal(d) { if (d === REF) return null; if (d && d.any) return d.v; return typeof d === 'function' ? d() : d; }
const ANY = (v) => ({ any: true, v });

let instIds = 0;
class Instance {
  constructor(rt, className) {
    const cls = CLASSES[className];
    this.rt = rt; this.cls = cls; this.ClassName = className; this.id = ++instIds;
    const all = flat(cls);
    this.p = {};
    for (const k in all.props) this.p[k] = defaultVal(all.props[k]);
    this.p.Name = className;
    this.children = []; this.parent = null; this.sig = null; this.attrs = null; this.destroyed = false; this.parentLocked = false;
    for (const f of all.inits) f(this, rt);
  }
  get luaType() { return 'Instance'; }
  luaToString() { return this.p.Name; }
  get Name() { return this.p.Name; }
  isA(n) { return n === 'Instance' || this.cls.all.chain.includes(n); }
  fullName() {
    const parts = [];
    for (let x = this; x && x.ClassName !== 'DataModel'; x = x.parent) parts.unshift(x.p.Name);
    return parts.join('.');
  }
  findChild(name) { for (const c of this.children) if (c.p.Name === name) return c; return null; }
  descendants(out = []) { for (const c of this.children) { out.push(c); c.descendants(out); } return out; }
  isDescendantOf(a) { for (let x = this.parent; x; x = x.parent) if (x === a) return true; return false; }
  signal(name) {
    if (!this.sig) this.sig = {};
    return this.sig[name] || (this.sig[name] = new Signal(this.rt, name));
  }
  fire(name, args) { const s = this.sig && this.sig[name]; if (s && (s.conns.length || s.waiters.length)) this.rt.fire(s, args); }
  changed(k) {
    if (!this.sig) return;
    if (this.cls.all.chain.includes('ValueBase')) { if (k === 'Value') this.fire('Changed', [this.p.Value]); }
    else this.fire('Changed', [k]);
    this.fire('prop:' + k, []);
  }
  luaIndex(k, I) {
    if (typeof k !== 'string') throw I.rtErr(`attempt to index Instance with ${luauTypeof(k)}`);
    const all = this.cls.all;
    if (k === 'Parent') return this.parent || undefined;
    if (k === 'ClassName') return this.ClassName;
    const vt = all.virt[k];
    if (vt) return vt.get(this, I);
    if (k in all.props) { const v = this.p[k]; return v === null ? undefined : v; }
    const m = all.methods[k];
    if (m) return m;
    if (all.events.has(k)) return this.signal(k);
    const c = this.findChild(k);
    if (c) return c;
    throw I.rtErr(`${k} is not a valid member of ${this.ClassName} "${this.fullName()}"`);
  }
  luaNewIndex(k, v, I) {
    if (k === 'Parent') { this.setParent(v === undefined ? null : v, I); return; }
    const all = this.cls.all;
    const vt = all.virt[k];
    if (vt) {
      if (!vt.set) throw I.rtErr(`Unable to assign property ${k}. Property is read only`);
      vt.set(this, v, I);
      this.changed(k);
      return;
    }
    if (k in all.props) {
      if (all.readonly.has(k)) throw I.rtErr(`Unable to assign property ${k}. Property is read only`);
      this.set(k, this.coerce(k, v, I), I);
      return;
    }
    if (all.methods[k] || all.events.has(k) || k === 'ClassName') throw I.rtErr(`Unable to assign property ${k}. Property is read only`);
    throw I.rtErr(`${k} is not a valid member of ${this.ClassName} "${this.fullName()}"`);
  }
  set(k, v, I) {
    const old = this.p[k];
    if (old === v || (old && old.luaEq && old.luaEq(v))) return;
    this.p[k] = v;
    for (const f of this.cls.all.onSet) f(this, k, v, old, I);
    this.changed(k);
  }
  coerce(k, v, I) {
    const t = this.cls.all.types[k];
    if (t === 'any') return v;
    if (t === 'number') {
      if (typeof v === 'number') return this.ClassName === 'IntValue' && k === 'Value' ? Math.round(v) : v;
      if (typeof v === 'string') { const n = str2num(v); if (n !== undefined) return n; }
    } else if (t === 'string') {
      if (typeof v === 'string') return v;
      if (typeof v === 'number') return numToStr(v);
    } else if (t === 'boolean') {
      if (typeof v === 'boolean') return v;
    } else if (t === 'Instance') {
      if (v === undefined || v === null) return null;
      if (v instanceof Instance) return v;
    } else if (t && t.enum) {
      const it = t.enum.get(v);
      if (it) return it;
      throw I.rtErr(`Unable to assign property ${k}. Expected EnumItem of type Enum.${t.enum.name}, got ${luauTypeof(v) === 'string' ? `'${v}'` : luauTypeof(v)}`);
    } else if (luauTypeof(v) === t) return v;
    const tn = t && t.enum ? 'EnumItem' : t;
    throw I.rtErr(`Unable to assign property ${k}. ${tn} expected, got ${luauTypeof(v)}`);
  }
  setParent(np, I) {
    if (np !== null && !(np instanceof Instance)) throw I.rtErr(`Unable to assign property Parent. Instance expected, got ${luauTypeof(np)}`);
    if (np === this.parent) return;
    if (this.parentLocked) throw I.rtErr(`The Parent property of ${this.p.Name} is locked, current parent: NULL, new parent ${np ? np.p.Name : 'NULL'}`);
    if (this.cls.service) throw I.rtErr(`The Parent property of ${this.p.Name} is locked`);
    if (np && (np === this || np.isDescendantOf(this))) throw I.rtErr(`Attempt to set ${this.fullName()} as its own parent`);
    this.rawParent(np);
  }
  rawParent(np) {
    const old = this.parent;
    if (old) {
      const i = old.children.indexOf(this);
      if (i >= 0) old.children.splice(i, 1);
      old.fire('ChildRemoved', [this]);
      for (let a = old; a; a = a.parent) a.fire('DescendantRemoving', [this]);
    }
    this.parent = np;
    if (np) {
      np.children.push(this);
      np.fire('ChildAdded', [this]);
      for (let a = np; a; a = a.parent) a.fire('DescendantAdded', [this]);
    }
    this.changed('Parent');
    this.fire('AncestryChanged', [this, np || undefined]);
    this.rt.onReparent(this, old, np);
  }
  clone() {
    if (!this.p.Archivable) return null;
    const c = new Instance(this.rt, this.ClassName);
    c.p = { ...this.p };
    if (this.attrs) c.attrs = new Map(this.attrs);
    if (this.source !== undefined) c.source = this.source;
    if (this.tags) c.tags = new Set(this.tags);
    for (const ch of this.children) { const cc = ch.clone(); if (cc) { cc.parent = c; c.children.push(cc); } }
    // 模型內參照(PrimaryPart 等)指到複製後對應的物件
    const map = new Map();
    const walk = (a, b) => { map.set(a, b); a.children.filter(x => x.p.Archivable).forEach((x, i) => walk(x, b.children[i])); };
    walk(this, c);
    const fix = (x) => { for (const k in x.p) { const v = x.p[k]; if (v instanceof Instance && map.has(v)) x.p[k] = map.get(v); } x.children.forEach(fix); };
    fix(c);
    return c;
  }
  destroy() {
    if (this.destroyed) return;
    this.fire('Destroying', []);
    for (const ch of this.children.slice()) ch.destroy();
    if (this.parent) this.rawParent(null);
    this.parentLocked = true;
    this.destroyed = true;
    if (this.sig) for (const k in this.sig) this.sig[k].clear();
  }
}
function instSelf(a, I, name) {
  const s = a[0];
  if (!(s instanceof Instance)) throw I.rtErr(`Expected ':' not '.' calling member function ${name}`);
  return s;
}
const RETURNS_VALUE = /^(Find|WaitForChild|GetAttribute|Get|Raycast|Clone|Is|Has|Can|Invoke)/;
function M(defs) {
  const out = {};
  for (const k in defs) {
    const f = defs[k];
    const one = RETURNS_VALUE.test(k);
    out[k] = f instanceof Object.getPrototypeOf(function* () {}).constructor
      ? nat(k, function* (a, I) { const r = yield* f(instSelf(a, I, k), a, I); return r === undefined && one ? [undefined] : r; })
      : nat(k, (a, I) => { const r = f(instSelf(a, I, k), a, I); return r === undefined && one ? [undefined] : r; });
  }
  return out;
}
function argInst(I, a, i, fname, allowNil) {
  const v = a[i];
  if (v instanceof Instance) return v;
  if (allowNil && (v === undefined || v === null)) return null;
  throw I.argErr(i, fname, `Instance expected, got ${luauTypeof(v)}`);
}

// ---------- 類別定義 ----------
defClass('Instance', null, {
  props: { Name: 'Instance', Archivable: true },
  readonly: [],
  events: ['ChildAdded', 'ChildRemoved', 'DescendantAdded', 'DescendantRemoving', 'Changed', 'AncestryChanged', 'Destroying', 'AttributeChanged'],
  methods: M({
    Destroy: (s) => s.destroy(),
    Remove: (s) => s.rawParent(null),
    Clone: (s) => s.clone() || undefined,
    ClearAllChildren: (s) => { for (const c of s.children.slice()) c.destroy(); },
    FindFirstChild: (s, a, I) => {
      const n = checkStr(I, a, 1, 'FindFirstChild');
      if (truthy(a[2])) return s.descendants().find(x => x.p.Name === n);
      return s.findChild(n) || undefined;
    },
    FindFirstChildOfClass: (s, a, I) => s.children.find(x => x.ClassName === checkStr(I, a, 1, 'FindFirstChildOfClass')),
    FindFirstChildWhichIsA: (s, a, I) => { const n = checkStr(I, a, 1, 'FindFirstChildWhichIsA'); return (truthy(a[2]) ? s.descendants() : s.children).find(x => x.isA(n)); },
    FindFirstAncestor: (s, a, I) => { const n = checkStr(I, a, 1, 'FindFirstAncestor'); for (let x = s.parent; x; x = x.parent) if (x.p.Name === n) return x; },
    FindFirstAncestorOfClass: (s, a, I) => { const n = checkStr(I, a, 1, 'FindFirstAncestorOfClass'); for (let x = s.parent; x; x = x.parent) if (x.ClassName === n) return x; },
    FindFirstAncestorWhichIsA: (s, a, I) => { const n = checkStr(I, a, 1, 'FindFirstAncestorWhichIsA'); for (let x = s.parent; x; x = x.parent) if (x.isA(n)) return x; },
    FindFirstDescendant: (s, a, I) => { const n = checkStr(I, a, 1, 'FindFirstDescendant'); return s.descendants().find(x => x.p.Name === n); },
    GetChildren: (s) => LuaTable.from(s.children.slice()),
    GetDescendants: (s) => LuaTable.from(s.descendants()),
    IsA: (s, a, I) => s.isA(checkStr(I, a, 1, 'IsA')),
    IsDescendantOf: (s, a, I) => s.isDescendantOf(argInst(I, a, 1, 'IsDescendantOf')),
    IsAncestorOf: (s, a, I) => argInst(I, a, 1, 'IsAncestorOf').isDescendantOf(s),
    GetFullName: (s) => s.fullName(),
    GetDebugId: (s) => 'ID_' + s.id,
    WaitForChild: function* (s, a, I) {
      const n = checkStr(I, a, 1, 'WaitForChild');
      const c = s.findChild(n);
      if (c) return c;
      const timeout = a[2] === undefined ? null : checkNum(I, a, 2, 'WaitForChild');
      const r = yield { k: 'poll', fn: () => s.findChild(n), timeout, warn: timeout === null ? `Infinite yield possible on '${s.fullName()}:WaitForChild("${n}")'` : null };
      return r && r[0] ? r[0] : undefined;
    },
    GetAttribute: (s, a, I) => s.attrs ? s.attrs.get(checkStr(I, a, 1, 'GetAttribute')) : undefined,
    SetAttribute: (s, a, I) => {
      const k = checkStr(I, a, 1, 'SetAttribute');
      if (!s.attrs) s.attrs = new Map();
      if (a[2] === undefined) s.attrs.delete(k); else s.attrs.set(k, a[2]);
      s.fire('AttributeChanged', [k]);
      s.fire('attr:' + k, []);
    },
    GetAttributes: (s) => { const t = new LuaTable(); if (s.attrs) for (const [k, v] of s.attrs) t.set(k, v); return t; },
    GetPropertyChangedSignal: (s, a, I) => {
      const k = checkStr(I, a, 1, 'GetPropertyChangedSignal');
      const all = s.cls.all;
      if (!(k in all.props) && !all.virt[k] && k !== 'Parent' && k !== 'Name') throw I.rtErr(`${k} is not a valid property name.`);
      return s.signal('prop:' + k);
    },
    GetAttributeChangedSignal: (s, a, I) => s.signal('attr:' + checkStr(I, a, 1, 'GetAttributeChangedSignal')),
    AddTag: (s, a, I) => { s.rt.addTag(s, checkStr(I, a, 1, 'AddTag')); },
    RemoveTag: (s, a, I) => { s.rt.removeTag(s, checkStr(I, a, 1, 'RemoveTag')); },
    HasTag: (s, a, I) => !!(s.tags && s.tags.has(checkStr(I, a, 1, 'HasTag'))),
    GetTags: (s) => LuaTable.from(s.tags ? [...s.tags] : []),
    isA: (s, a, I) => s.isA(checkStr(I, a, 1, 'isA')),
    findFirstChild: (s, a, I) => s.findChild(checkStr(I, a, 1, 'findFirstChild')) || undefined,
    getChildren: (s) => LuaTable.from(s.children.slice()),
    destroy: (s) => s.destroy(),
    clone: (s) => s.clone() || undefined,
  }),
});

// ---- 3D 零件 ----
function partSize(s) { return s.p.Size; }
function partVolume(s) { const v = s.p.Size; return v.X * v.Y * v.Z; }
defClass('PVInstance', 'Instance', { notCreatable: true });
defClass('BasePart', 'PVInstance', {
  notCreatable: true,
  props: {
    Size: () => V3(4, 1, 2), CFrame: () => new CFrame(0, 0.5, 0), Color: () => Color3.rgb(163, 162, 165), Transparency: 0, Reflectance: 0,
    Anchored: false, CanCollide: true, CanTouch: true, CanQuery: true, Locked: false, Massless: false, CastShadow: true,
    Material: () => E('Material', 'Plastic'), AssemblyLinearVelocity: () => V3(0, 0, 0), AssemblyAngularVelocity: () => V3(0, 0, 0),
    TopSurface: () => E('SurfaceType', 'Smooth'), BottomSurface: () => E('SurfaceType', 'Smooth'), CollisionGroup: 'Default',
  },
  virt: {
    Position: { get: (s) => s.p.CFrame.pos, set: (s, v, I) => { if (!(v instanceof Vector3)) throw I.rtErr(`Unable to assign property Position. Vector3 expected, got ${luauTypeof(v)}`); s.setCF(s.p.CFrame.withPos(v)); } },
    Orientation: {
      get: (s) => { const r = s.p.CFrame.toYXZ(); return V3(r[0] * 180 / Math.PI, r[1] * 180 / Math.PI, r[2] * 180 / Math.PI); },
      set: (s, v, I) => {
        if (!(v instanceof Vector3)) throw I.rtErr(`Unable to assign property Orientation. Vector3 expected, got ${luauTypeof(v)}`);
        const d = Math.PI / 180, c = CFrame.anglesYXZ(v.X * d, v.Y * d, v.Z * d);
        s.setCF(new CFrame(s.p.CFrame.x, s.p.CFrame.y, s.p.CFrame.z, c.m));
      },
    },
    Rotation: {
      get: (s) => { const r = s.p.CFrame.toXYZ(); return V3(r[0] * 180 / Math.PI, r[1] * 180 / Math.PI, r[2] * 180 / Math.PI); },
      set: (s, v) => { const d = Math.PI / 180, c = CFrame.anglesXYZ(v.X * d, v.Y * d, v.Z * d); s.setCF(new CFrame(s.p.CFrame.x, s.p.CFrame.y, s.p.CFrame.z, c.m)); },
    },
    BrickColor: {
      get: (s) => BrickColor.closest(s.p.Color),
      set: (s, v, I) => { if (!(v instanceof BrickColor)) throw I.rtErr(`Unable to assign property BrickColor. BrickColor expected, got ${luauTypeof(v)}`); s.set('Color', v.Color, I); },
    },
    Velocity: { get: (s) => s.p.AssemblyLinearVelocity, set: (s, v) => { s.p.AssemblyLinearVelocity = v; } },
    Mass: { get: (s) => s.p.Massless ? 0 : partVolume(s) * 0.7 },
    AssemblyMass: { get: (s) => partVolume(s) * 0.7 },
    ExtentsSize: { get: (s) => s.p.Size },
  },
  readonly: [],
  events: ['Touched', 'TouchEnded'],
  init: (s) => { s.setCF = (cf) => s.set('CFrame', cf); },
  onSet: (s, k, v, old) => {
    if (k === 'Size') {
      if (s.p.Shape && s.p.Shape.Name === 'Ball') { const m = Math.min(v.X, v.Y, v.Z); s.p.Size = V3(m, m, m); }
      else if (v.X < 0.001 || v.Y < 0.001 || v.Z < 0.001) s.p.Size = V3(Math.max(0.001, v.X), Math.max(0.001, v.Y), Math.max(0.001, v.Z));
    }
    if (k === 'Shape' && v.Name === 'Ball') { const z = s.p.Size, m = Math.min(z.X, z.Y, z.Z); s.p.Size = V3(m, m, m); }
    if (k === 'Anchored' && v) s.p.AssemblyLinearVelocity = V3(0, 0, 0);
    if (k === 'CFrame') { s.fire('prop:Position', []); s.fire('prop:Orientation', []); }
  },
  methods: M({
    GetMass: (s) => s.p.Massless ? 0 : partVolume(s) * 0.7,
    GetTouchingParts: (s) => LuaTable.from(s.rt.touchingParts(s)),
    ApplyImpulse: (s, a, I) => { const imp = argV3(I, a, 1, 'ApplyImpulse'); const m = partVolume(s) * 0.7 || 1; s.p.AssemblyLinearVelocity = s.p.AssemblyLinearVelocity.add(imp.mul(1 / m)); },
    ApplyAngularImpulse: () => {},
    GetPivot: (s) => s.p.CFrame,
    PivotTo: (s, a, I) => s.setCF(argCF(I, a, 1, 'PivotTo')),
    BreakJoints: () => {},
    GetConnectedParts: (s) => LuaTable.from([s]),
    GetNetworkOwner: () => undefined,
    SetNetworkOwner: () => {},
    CanCollideWith: (s, a) => !!(a[0] && a[0].p.CanCollide),
    GetVelocityAtPosition: (s) => s.p.AssemblyLinearVelocity,
  }),
});
defClass('Part', 'BasePart', { props: { Shape: () => E('PartType', 'Block') } });
defClass('SpawnLocation', 'Part', { props: { Enabled: true, Duration: 10, Neutral: true, AllowTeamChangeOnTouch: false } });
defClass('WedgePart', 'BasePart', {});
defClass('CornerWedgePart', 'BasePart', {});
defClass('TrussPart', 'BasePart', {});
defClass('MeshPart', 'BasePart', { props: { MeshId: '', TextureID: '' } });
defClass('UnionOperation', 'BasePart', {});
defClass('Terrain', 'BasePart', { notCreatable: true });
defClass('Seat', 'Part', { props: { Disabled: false, Occupant: REF } });

defClass('Model', 'PVInstance', {
  props: { PrimaryPart: REF, WorldPivot: () => new CFrame() },
  methods: M({
    GetPivot: (s) => s.rt.modelPivot(s),
    PivotTo: (s, a, I) => s.rt.modelPivotTo(s, argCF(I, a, 1, 'PivotTo')),
    SetPrimaryPartCFrame: (s, a, I) => { if (!s.p.PrimaryPart) throw I.rtErr('Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.'); s.rt.modelPivotTo(s, argCF(I, a, 1, 'SetPrimaryPartCFrame')); },
    GetPrimaryPartCFrame: (s) => s.p.PrimaryPart ? s.p.PrimaryPart.p.CFrame : undefined,
    MoveTo: (s, a, I) => {
      const v = argV3(I, a, 1, 'MoveTo');
      const [cf, size] = s.rt.modelBounds(s);
      const d = V3(v.X - cf.x, v.Y + size.Y / 2 - cf.y, v.Z - cf.z);
      for (const p of s.rt.modelParts(s)) p.setCF(new CFrame(p.p.CFrame.x + d.X, p.p.CFrame.y + d.Y, p.p.CFrame.z + d.Z, p.p.CFrame.m));
    },
    TranslateBy: (s, a, I) => { const v = argV3(I, a, 1, 'TranslateBy'); const p = s.rt.modelPivot(s); s.rt.modelPivotTo(s, p.withPos(p.pos.add(v))); },
    GetBoundingBox: (s) => s.rt.modelBounds(s),
    GetExtentsSize: (s) => s.rt.modelBounds(s)[1],
    BreakJoints: () => {},
    MakeJoints: () => {},
    ScaleTo: () => {},
    GetScale: () => 1,
  }),
});
defClass('Folder', 'Instance', {});
defClass('Configuration', 'Instance', {});
defClass('Workspace', 'Model', {
  service: true, notCreatable: true,
  props: { Gravity: 196.2, FallenPartsDestroyHeight: -500, CurrentCamera: REF, DistributedGameTime: 0 },
  methods: M({
    Raycast: (s, a, I) => {
      const o = argV3(I, a, 1, 'Raycast'), d = argV3(I, a, 2, 'Raycast');
      const prm = a[3] instanceof RaycastParams ? a[3] : null;
      const r = s.rt.raycast(o, d, s.rt.rayFilter(prm));
      return r ? new RaycastResult(r.part, r.pos, r.normal, r.dist, r.part.p.Material) : undefined;
    },
    GetPartBoundsInRadius: (s, a, I) => { const c = argV3(I, a, 1, 'GetPartBoundsInRadius'), r = checkNum(I, a, 2, 'GetPartBoundsInRadius'); return LuaTable.from(s.rt.partsInRadius(c, r)); },
    GetPartBoundsInBox: (s, a, I) => { const cf = argCF(I, a, 1, 'GetPartBoundsInBox'), sz = argV3(I, a, 2, 'GetPartBoundsInBox'); return LuaTable.from(s.rt.partsInBox(cf.pos, sz.mul(0.5))); },
    GetPartsInPart: (s, a, I) => { const p = argInst(I, a, 1, 'GetPartsInPart'); return LuaTable.from(s.rt.touchingParts(p)); },
    GetServerTimeNow: (s) => Date.now() / 1000,
    GetRealPhysicsFPS: () => 60,
    FindPartOnRay: (s, a) => { const ray = a[1]; const r = ray && s.rt.raycast(ray.o, ray.d, () => true); return r ? [r.part, r.pos, r.normal, r.part.p.Material] : [undefined, ray ? ray.o.add(ray.d) : undefined]; },
  }),
});
defClass('Camera', 'Instance', {
  props: { CFrame: () => new CFrame(0, 20, 30), FieldOfView: 70, CameraType: () => E('CameraType', 'Custom'), CameraSubject: REF, Focus: () => new CFrame(), ViewportSize: () => new Vector2(1280, 720) },
  methods: M({
    ScreenPointToRay: (s, a) => s.rt.screenRay(a[1], a[2]),
    ViewportPointToRay: (s, a) => s.rt.screenRay(a[1], a[2]),
    WorldToScreenPoint: (s, a) => s.rt.worldToScreen(a[1]),
    WorldToViewportPoint: (s, a) => s.rt.worldToScreen(a[1]),
  }),
});
defClass('DataModel', 'Instance', {
  notCreatable: true,
  props: { PlaceId: 0, GameId: 0, JobId: '', CreatorId: 0, PlaceVersion: 1 },
  methods: M({
    GetService: (s, a, I) => s.rt.getService(checkStr(I, a, 1, 'GetService'), I),
    FindService: (s, a, I) => s.findChild(checkStr(I, a, 1, 'FindService')) || undefined,
    IsLoaded: () => true,
    BindToClose: () => {},
  }),
  events: ['Loaded'],
});

// ---- 值物件 ----
defClass('ValueBase', 'Instance', { notCreatable: true });
for (const [n, d] of [['IntValue', 0], ['NumberValue', 0], ['StringValue', ''], ['BoolValue', false], ['ObjectValue', REF],
  ['Vector3Value', () => V3(0, 0, 0)], ['Color3Value', () => new Color3(0, 0, 0)], ['CFrameValue', () => new CFrame()], ['BrickColorValue', () => BrickColor.byNumber(194)]]) {
  defClass(n, 'ValueBase', { props: { Value: d } });
}

// ---- 腳本 ----
defClass('LuaSourceContainer', 'Instance', { notCreatable: true });
defClass('BaseScript', 'LuaSourceContainer', { notCreatable: true, props: { Enabled: true, Disabled: false } });
defClass('Script', 'BaseScript', { virt: { Source: { get: (s) => s.source || '' } } });
defClass('LocalScript', 'Script', {});
defClass('ModuleScript', 'LuaSourceContainer', { virt: { Source: { get: (s) => s.source || '' } } });

// ---- 服務 ----
defClass('Players', 'Instance', {
  service: true, notCreatable: true,
  props: { LocalPlayer: REF, MaxPlayers: 8, RespawnTime: 3, CharacterAutoLoads: true },
  readonly: ['LocalPlayer'],
  events: ['PlayerAdded', 'PlayerRemoving'],
  methods: M({
    GetPlayers: (s) => LuaTable.from(s.children.filter(c => c.ClassName === 'Player')),
    GetPlayerFromCharacter: (s, a) => s.children.find(c => c.ClassName === 'Player' && c.p.Character && c.p.Character === a[1]),
    GetPlayerByUserId: (s, a) => s.children.find(c => c.ClassName === 'Player' && c.p.UserId === a[1]),
    GetNameFromUserIdAsync: (s, a) => 'Player' + a[1],
    GetUserIdFromNameAsync: () => 1,
    GetUserThumbnailAsync: () => ['', true],
  }),
});
defClass('Player', 'Instance', {
  notCreatable: true,
  props: { UserId: 1, DisplayName: 'Player1', Character: REF, Team: REF, TeamColor: () => BrickColor.byNumber(194), Neutral: true, AccountAge: 365, MembershipType: ANY(null), CameraMaxZoomDistance: 128, CameraMinZoomDistance: 0.5, RespawnLocation: REF, CanLoadCharacterAppearance: true },
  events: ['CharacterAdded', 'CharacterRemoving', 'CharacterAppearanceLoaded', 'Chatted', 'Idled'],
  methods: M({
    LoadCharacter: (s) => s.rt.spawnCharacter(s),
    GetMouse: (s) => s.rt.getMouse(),
    Kick: (s, a) => { s.rt.emit('error', `你被踢出遊戲：${a[1] === undefined ? '' : s.rt.I.tostr(a[1])}`); s.rt.removeCharacter(s); },
    IsInGroup: () => false,
    GetRankInGroup: () => 0,
    GetRoleInGroup: () => 'Guest',
    HasAppearanceLoaded: () => true,
    IsFriendsWith: () => false,
    GetFriendsOnline: () => new LuaTable(),
    DistanceFromCharacter: (s, a) => { const r = s.p.Character && s.p.Character.findChild('HumanoidRootPart'); return r ? r.p.CFrame.pos.sub(a[1]).mag : 0; },
    GetNetworkPing: () => 0,
  }),
});
defClass('Backpack', 'Instance', {});
defClass('PlayerGui', 'Instance', { notCreatable: true });
defClass('PlayerScripts', 'Instance', { notCreatable: true });
defClass('StarterGear', 'Instance', {});
defClass('Lighting', 'Instance', {
  service: true, notCreatable: true,
  props: { ClockTime: 14, Brightness: 2, Ambient: () => Color3.rgb(70, 70, 70), OutdoorAmbient: () => Color3.rgb(128, 128, 128), FogEnd: 100000, FogStart: 0, FogColor: () => Color3.rgb(192, 192, 192), GlobalShadows: true, ExposureCompensation: 0, ColorShift_Top: () => new Color3(0, 0, 0), ColorShift_Bottom: () => new Color3(0, 0, 0), GeographicLatitude: 41.7 },
  virt: {
    TimeOfDay: {
      get: (s) => { const t = s.p.ClockTime; const h = Math.floor(t), m = Math.floor((t - h) * 60), sec = Math.floor(((t - h) * 60 - m) * 60); return [h, m, sec].map(x => String(x).padStart(2, '0')).join(':'); },
      set: (s, v) => { const [h, m, sec] = String(v).split(':').map(Number); s.set('ClockTime', (((h || 0) + (m || 0) / 60 + (sec || 0) / 3600) % 24 + 24) % 24); },
    },
  },
  onSet: (s, k, v) => { if (k === 'ClockTime') s.p.ClockTime = ((v % 24) + 24) % 24; },
  methods: M({
    GetMinutesAfterMidnight: (s) => s.p.ClockTime * 60,
    SetMinutesAfterMidnight: (s, a, I) => s.set('ClockTime', checkNum(I, a, 1, 'SetMinutesAfterMidnight') / 60),
    GetSunDirection: (s) => s.rt.sunDir(),
    GetMoonDirection: (s) => s.rt.sunDir().mul(-1),
  }),
});
for (const n of ['ReplicatedStorage', 'ServerScriptService', 'ServerStorage', 'StarterGui', 'StarterPack', 'StarterPlayer', 'SoundService', 'Teams', 'Chat', 'ReplicatedFirst', 'TextChatService', 'LocalizationService', 'MarketplaceService', 'BadgeService', 'GroupService', 'PolicyService', 'SocialService', 'TeleportService', 'PhysicsService', 'ProximityPromptService', 'GuiService', 'VRService', 'HapticService', 'StarterPlayerScripts', 'StarterCharacterScripts']) {
  defClass(n, 'Instance', { service: !['StarterPlayerScripts', 'StarterCharacterScripts'].includes(n), notCreatable: true });
}
CLASSES.StarterPlayer.props = { CharacterWalkSpeed: 16, CharacterJumpPower: 50, CameraMaxZoomDistance: 128, CameraMinZoomDistance: 0.5 };
CLASSES.MarketplaceService.methods = M({ PromptProductPurchase: () => {}, PromptGamePassPurchase: () => {}, UserOwnsGamePassAsync: () => false, GetProductInfo: () => new LuaTable() });
CLASSES.MarketplaceService.events = ['PromptGamePassPurchaseFinished', 'PromptProductPurchaseFinished'];
CLASSES.BadgeService.methods = M({ AwardBadge: () => true, UserHasBadgeAsync: () => false });
CLASSES.TeleportService.methods = M({ Teleport: (s) => { s.rt.emit('warn', 'TeleportService 在這裡不會真的傳送'); } });
CLASSES.PhysicsService.methods = M({ RegisterCollisionGroup: () => {}, CollisionGroupSetCollidable: () => {}, CreateCollisionGroup: () => {}, SetPartCollisionGroup: () => {} });
CLASSES.StarterGui.methods = M({ SetCoreGuiEnabled: () => {}, SetCore: (s, a) => { if (a[1] === 'SendNotification' && a[2] instanceof LuaTable) s.rt.emit('info', `🔔 ${s.rt.I.tostr(a[2].get('Title'))}：${s.rt.I.tostr(a[2].get('Text'))}`); }, GetCoreGuiEnabled: () => true });
CLASSES.ProximityPromptService.props = { Enabled: true };
defClass('Team', 'Instance', { props: { TeamColor: () => BrickColor.byNumber(194), AutoAssignable: true }, methods: M({ GetPlayers: () => new LuaTable() }) });

defClass('RunService', 'Instance', {
  service: true, notCreatable: true,
  events: ['Heartbeat', 'RenderStepped', 'Stepped', 'PreSimulation', 'PostSimulation', 'PreRender'],
  methods: M({
    IsClient: () => true, IsServer: () => true, IsStudio: () => true, IsRunning: () => true, IsRunMode: () => true, IsEdit: () => false,
    BindToRenderStep: (s, a, I) => { s.rt.renderBinds.set(checkStr(I, a, 1, 'BindToRenderStep'), { pri: checkNum(I, a, 2, 'BindToRenderStep'), fn: a[3] }); },
    UnbindFromRenderStep: (s, a) => { s.rt.renderBinds.delete(a[1]); },
  }),
});
defClass('TweenService', 'Instance', {
  service: true, notCreatable: true,
  methods: M({
    Create: (s, a, I) => s.rt.createTween(argInst(I, a, 1, 'Create'), a[2], a[3], I),
    GetValue: (s, a, I) => ease(checkNum(I, a, 1, 'GetValue'), a[2], a[3]),
    SmoothDamp: (s, a) => [a[2], a[3]],
  }),
});
defClass('TweenBase', 'Instance', { notCreatable: true });
defClass('Tween', 'TweenBase', {
  notCreatable: true,
  props: { PlaybackState: () => E('PlaybackState', 'Begin'), Instance: REF, TweenInfo: ANY(null) },
  readonly: ['PlaybackState', 'Instance', 'TweenInfo'],
  events: ['Completed'],
  methods: M({
    Play: (s) => s.rt.playTween(s),
    Pause: (s) => { if (s.tw && s.tw.active) { s.tw.active = false; s.set('PlaybackState', E('PlaybackState', 'Paused')); } },
    Cancel: (s) => s.rt.stopTween(s, 'Cancelled'),
  }),
});
defClass('Debris', 'Instance', {
  service: true, notCreatable: true,
  methods: M({ AddItem: (s, a, I) => { const it = argInst(I, a, 1, 'AddItem'); const t = a[2] === undefined ? 10 : checkNum(I, a, 2, 'AddItem'); s.rt.timer(t, () => it.destroy()); }, addItem: (s, a) => { const it = a[1]; s.rt.timer(a[2] === undefined ? 10 : a[2], () => it.destroy()); } }),
});
defClass('UserInputService', 'Instance', {
  service: true, notCreatable: true,
  props: { MouseEnabled: true, KeyboardEnabled: true, TouchEnabled: false, GamepadEnabled: false, MouseBehavior: () => E('MouseBehavior', 'Default'), MouseIconEnabled: true },
  events: ['InputBegan', 'InputEnded', 'InputChanged', 'JumpRequest', 'TouchTap', 'TouchStarted', 'TouchEnded', 'TextBoxFocused', 'TextBoxFocusReleased'],
  methods: M({
    IsKeyDown: (s, a) => { const k = a[1]; return !!(k && k.Name && s.rt.keysDown.has(k.Name)); },
    IsMouseButtonPressed: (s, a) => !!(a[1] && s.rt.mouseDown.has(a[1].Name)),
    GetKeysPressed: (s) => LuaTable.from([...s.rt.keysDown].map(k => s.rt.inputObject(k, 'Keyboard', 'Begin'))),
    GetMouseLocation: (s) => new Vector2(s.rt.mouse.x, s.rt.mouse.y),
    GetMouseDelta: () => new Vector2(0, 0),
    GetFocusedTextBox: () => undefined,
    GetLastInputType: () => E('UserInputType', 'Keyboard'),
  }),
});
defClass('ContextActionService', 'Instance', {
  service: true, notCreatable: true,
  methods: M({
    BindAction: (s, a, I) => { const name = checkStr(I, a, 1, 'BindAction'); s.rt.actions.set(name, { fn: a[2], keys: a.slice(4).filter(k => k instanceof EnumItem).map(k => k.Name) }); },
    BindActionAtPriority: (s, a, I) => { const name = checkStr(I, a, 1, 'BindActionAtPriority'); s.rt.actions.set(name, { fn: a[2], keys: a.slice(5).filter(k => k instanceof EnumItem).map(k => k.Name) }); },
    UnbindAction: (s, a) => { s.rt.actions.delete(a[1]); },
    SetTitle: () => {}, SetPosition: () => {}, SetImage: () => {}, GetButton: () => undefined,
  }),
});
defClass('HttpService', 'Instance', {
  service: true, notCreatable: true,
  props: { HttpEnabled: false },
  methods: M({
    JSONEncode: (s, a, I) => JSON.stringify(toJSON(a[1], I)),
    JSONDecode: (s, a, I) => { try { return fromJSON(JSON.parse(checkStr(I, a, 1, 'JSONDecode'))); } catch (e) { throw I.rtErr("Can't parse JSON"); } },
    GenerateGUID: (s, a) => { const g = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }).toUpperCase(); return a[1] === false ? g : '{' + g + '}'; },
    UrlEncode: (s, a, I) => encodeURIComponent(checkStr(I, a, 1, 'UrlEncode')),
    GetAsync: (s, a, I) => { throw I.rtErr('HTTP 請求在這個網頁編輯器裡被停用 (Http requests are not enabled)'); },
    PostAsync: (s, a, I) => { throw I.rtErr('HTTP 請求在這個網頁編輯器裡被停用 (Http requests are not enabled)'); },
  }),
});
defClass('CollectionService', 'Instance', {
  service: true, notCreatable: true,
  methods: M({
    AddTag: (s, a, I) => s.rt.addTag(argInst(I, a, 1, 'AddTag'), checkStr(I, a, 2, 'AddTag')),
    RemoveTag: (s, a, I) => s.rt.removeTag(argInst(I, a, 1, 'RemoveTag'), checkStr(I, a, 2, 'RemoveTag')),
    HasTag: (s, a, I) => { const i = argInst(I, a, 1, 'HasTag'); return !!(i.tags && i.tags.has(checkStr(I, a, 2, 'HasTag'))); },
    GetTagged: (s, a, I) => { const t = checkStr(I, a, 1, 'GetTagged'); return LuaTable.from(s.rt.allInstances().filter(i => i.tags && i.tags.has(t) && !i.destroyed)); },
    GetTags: (s, a, I) => { const i = argInst(I, a, 1, 'GetTags'); return LuaTable.from(i.tags ? [...i.tags] : []); },
    GetInstanceAddedSignal: (s, a, I) => s.signal('tagAdded:' + checkStr(I, a, 1, 'GetInstanceAddedSignal')),
    GetInstanceRemovedSignal: (s, a, I) => s.signal('tagRemoved:' + checkStr(I, a, 1, 'GetInstanceRemovedSignal')),
    GetAllTags: (s) => { const set = new Set(); for (const i of s.rt.allInstances()) if (i.tags) for (const t of i.tags) set.add(t); return LuaTable.from([...set]); },
  }),
});
defClass('DataStoreService', 'Instance', {
  service: true, notCreatable: true,
  methods: M({
    GetDataStore: (s, a, I) => s.rt.dataStore(checkStr(I, a, 1, 'GetDataStore'), a[2] === undefined ? '' : I.tostr(a[2])),
    GetOrderedDataStore: (s, a, I) => s.rt.dataStore('ordered:' + checkStr(I, a, 1, 'GetOrderedDataStore'), ''),
  }),
});
defClass('GlobalDataStore', 'Instance', {
  notCreatable: true,
  methods: M({
    GetAsync: (s, a, I) => s.rt.dsGet(s, I.tostr(a[1])),
    SetAsync: (s, a, I) => { s.rt.dsSet(s, I.tostr(a[1]), a[2], I); },
    UpdateAsync: (s, a, I) => { const k = I.tostr(a[1]); const nv = I.callSync(a[2], [s.rt.dsGet(s, k)])[0]; if (nv !== undefined) s.rt.dsSet(s, k, nv, I); return nv; },
    IncrementAsync: (s, a, I) => { const k = I.tostr(a[1]); const nv = (s.rt.dsGet(s, k) || 0) + (a[2] === undefined ? 1 : a[2]); s.rt.dsSet(s, k, nv, I); return nv; },
    RemoveAsync: (s, a, I) => { const k = I.tostr(a[1]); const v = s.rt.dsGet(s, k); s.rt.dsSet(s, k, undefined, I); return v; },
  }),
});
defClass('MessagingService', 'Instance', { service: true, notCreatable: true, methods: M({ PublishAsync: () => {}, SubscribeAsync: () => ({ luaIndex: () => nat('Disconnect', () => {}) }) }) });
defClass('PathfindingService', 'Instance', { service: true, notCreatable: true, methods: M({ CreatePath: (s, a, I) => { throw I.rtErr('PathfindingService 尚未支援'); } }) });

// ---- 事件物件 ----
defClass('BindableEvent', 'Instance', {
  events: ['Event'],
  methods: M({ Fire: (s, a) => s.fire('Event', a.slice(1)) }),
});
defClass('BindableFunction', 'Instance', {
  props: { OnInvoke: ANY(undefined) },
  methods: M({
    Invoke: function* (s, a, I) { const f = s.p.OnInvoke; if (f === undefined) throw I.rtErr('BindableFunction:Invoke() 沒有設定 OnInvoke'); return yield* I.call(f, a.slice(1)); },
  }),
});
defClass('RemoteEvent', 'Instance', {
  events: ['OnServerEvent', 'OnClientEvent'],
  methods: M({
    FireServer: (s, a) => s.fire('OnServerEvent', [s.rt.localPlayer, ...a.slice(1)]),
    FireClient: (s, a) => s.fire('OnClientEvent', a.slice(2)),
    FireAllClients: (s, a) => s.fire('OnClientEvent', a.slice(1)),
  }),
});
defClass('UnreliableRemoteEvent', 'RemoteEvent', {});
defClass('RemoteFunction', 'Instance', {
  props: { OnServerInvoke: ANY(undefined), OnClientInvoke: ANY(undefined) },
  methods: M({
    InvokeServer: function* (s, a, I) { const f = s.p.OnServerInvoke; if (f === undefined) throw I.rtErr('RemoteFunction 沒有設定 OnServerInvoke'); return yield* I.call(f, [s.rt.localPlayer, ...a.slice(1)]); },
    InvokeClient: function* (s, a, I) { const f = s.p.OnClientInvoke; if (f === undefined) throw I.rtErr('RemoteFunction 沒有設定 OnClientInvoke'); return yield* I.call(f, a.slice(2)); },
  }),
});

// ---- 角色 ----
defClass('Humanoid', 'Instance', {
  props: {
    Health: 100, MaxHealth: 100, WalkSpeed: 16, JumpPower: 50, JumpHeight: 7.2, UseJumpPower: true, HipHeight: 0, AutoRotate: true,
    Jump: false, Sit: false, PlatformStand: false, MoveDirection: () => V3(0, 0, 0), DisplayName: '', FloorMaterial: () => E('Material', 'Air'),
    RigType: () => E('HumanoidRigType', 'R6'), WalkToPoint: () => V3(0, 0, 0), BreakJointsOnDeath: true, RequiresNeck: true, NameDisplayDistance: 100, HealthDisplayDistance: 100,
    SeatPart: REF, RootPart: REF, CameraOffset: () => V3(0, 0, 0), EvaluateStateMachine: true,
  },
  readonly: ['MoveDirection', 'FloorMaterial', 'RootPart', 'SeatPart'],
  events: ['Died', 'HealthChanged', 'Running', 'Jumping', 'FreeFalling', 'Touched', 'MoveToFinished', 'StateChanged', 'Seated', 'Climbing'],
  onSet: (s, k, v, old) => {
    if (k === 'Health') {
      const h = Math.min(Math.max(v, 0), s.p.MaxHealth);
      s.p.Health = h;
      if (h !== old) s.fire('HealthChanged', [h]);
      if (h <= 0 && old > 0) s.rt.killHumanoid(s);
    }
    if (k === 'MaxHealth' && s.p.Health > v) s.set('Health', v);
  },
  methods: M({
    TakeDamage: (s, a, I) => { const d = checkNum(I, a, 1, 'TakeDamage'); if (s.findForceField()) return; s.set('Health', s.p.Health - d, I); },
    Move: (s, a, I) => { s.ctl.scriptMove = argV3(I, a, 1, 'Move'); },
    MoveTo: (s, a, I) => { s.ctl.moveTo = argV3(I, a, 1, 'MoveTo'); s.ctl.moveToStart = s.rt.time; },
    GetState: (s) => E('HumanoidStateType', s.ctl.dead ? 'Dead' : s.ctl.grounded ? 'Running' : 'Freefall'),
    ChangeState: (s, a) => { if (a[1] && a[1].Name === 'Jumping') s.ctl.wantJump = true; if (a[1] && a[1].Name === 'Dead') s.set('Health', 0); },
    SetStateEnabled: () => {},
    GetStateEnabled: () => true,
    LoadAnimation: (s) => s.rt.fakeAnimTrack(),
    EquipTool: () => {}, UnequipTools: () => {},
    GetAppliedDescription: () => undefined,
    ApplyDescription: () => {},
    GetLimb: () => undefined,
    RemoveAccessories: () => {},
    GetAccessories: () => new LuaTable(),
  }),
  init: (s) => {
    s.ctl = { vy: 0, grounded: false, dead: false };
    s.findForceField = () => s.parent && s.parent.children.some(c => c.ClassName === 'ForceField');
  },
});
defClass('Animator', 'Instance', { methods: M({ LoadAnimation: (s) => s.rt.fakeAnimTrack() }) });
defClass('Animation', 'Instance', { props: { AnimationId: '' } });
defClass('ForceField', 'Instance', { props: { Visible: true } });
defClass('Tool', 'Model', { props: { RequiresHandle: true, CanBeDropped: true, ToolTip: '', Enabled: true, TextureId: '', Grip: () => new CFrame() }, events: ['Activated', 'Deactivated', 'Equipped', 'Unequipped'], methods: M({ Activate: (s) => s.fire('Activated', []), Deactivate: () => {} }) });
defClass('HopperBin', 'Instance', {});

// ---- 互動 ----
defClass('ClickDetector', 'Instance', { props: { MaxActivationDistance: 32, CursorIcon: '' }, events: ['MouseClick', 'RightMouseClick', 'MouseHoverEnter', 'MouseHoverLeave'] });
defClass('ProximityPrompt', 'Instance', {
  props: { ActionText: 'Interact', ObjectText: '', HoldDuration: 0, MaxActivationDistance: 10, KeyboardKeyCode: () => E('KeyCode', 'E'), Enabled: true, RequiresLineOfSight: true },
  events: ['Triggered', 'TriggerEnded', 'PromptShown', 'PromptHidden', 'PromptButtonHoldBegan', 'PromptButtonHoldEnded'],
  methods: M({ InputHoldBegin: () => {}, InputHoldEnd: () => {} }),
});

// ---- 效果 / 物理物件(多半只是容器，讓腳本不會出錯) ----
defClass('Explosion', 'Instance', { props: { Position: () => V3(0, 0, 0), BlastRadius: 4, BlastPressure: 500000, DestroyJointRadiusPercent: 1, ExplosionType: () => E('ExplosionType', 'Craters'), Visible: true }, events: ['Hit'] });
defClass('PointLight', 'Instance', { props: { Brightness: 1, Range: 8, Color: () => new Color3(1, 1, 1), Enabled: true, Shadows: false } });
defClass('SpotLight', 'PointLight', { props: { Angle: 90, Face: () => E('NormalId', 'Front') } });
defClass('SurfaceLight', 'SpotLight', {});
defClass('Sound', 'Instance', {
  props: { SoundId: '', Volume: 0.5, Playing: false, Looped: false, PlaybackSpeed: 1, TimePosition: 0, TimeLength: 0, IsPlaying: false, RollOffMaxDistance: 10000, PlayOnRemove: false },
  events: ['Ended', 'Played', 'Loaded', 'Stopped', 'Paused', 'Resumed', 'DidLoop'],
  methods: M({ Play: (s) => { s.p.Playing = true; s.p.IsPlaying = true; s.fire('Played', [s.p.SoundId]); s.rt.emitEffect({ k: 'sound', inst: s }); }, Stop: (s) => { s.p.Playing = false; s.p.IsPlaying = false; s.fire('Stopped', []); }, Pause: (s) => { s.p.Playing = false; }, Resume: (s) => { s.p.Playing = true; } }),
});
defClass('SoundGroup', 'Instance', { props: { Volume: 0.5 } });
for (const n of ['Attachment', 'Bone']) defClass(n, 'Instance', { props: { CFrame: () => new CFrame(), Visible: false }, virt: { Position: { get: (s) => s.p.CFrame.pos, set: (s, v) => { s.p.CFrame = s.p.CFrame.withPos(v); } }, WorldPosition: { get: (s) => (s.parent && s.parent.p.CFrame ? s.parent.p.CFrame.mul(s.p.CFrame).pos : s.p.CFrame.pos) }, WorldCFrame: { get: (s) => (s.parent && s.parent.p.CFrame ? s.parent.p.CFrame.mul(s.p.CFrame) : s.p.CFrame) } } });
defClass('JointInstance', 'Instance', { notCreatable: true, props: { Part0: REF, Part1: REF, C0: () => new CFrame(), C1: () => new CFrame(), Enabled: true } });
for (const n of ['Weld', 'Motor6D', 'ManualWeld', 'Snap', 'Glue', 'Motor']) defClass(n, 'JointInstance', {});
CLASSES.Motor6D.props = { CurrentAngle: 0, DesiredAngle: 0, MaxVelocity: 0.1, Transform: () => new CFrame() };
defClass('WeldConstraint', 'Instance', { props: { Part0: REF, Part1: REF, Enabled: true, Active: true } });
defClass('Constraint', 'Instance', { notCreatable: true, props: { Attachment0: REF, Attachment1: REF, Enabled: true, Visible: false, Color: () => BrickColor.byNumber(23) } });
for (const n of ['RopeConstraint', 'RodConstraint', 'SpringConstraint', 'HingeConstraint', 'BallSocketConstraint', 'PrismaticConstraint', 'CylindricalConstraint', 'AlignOrientation', 'AngularVelocity', 'Torque', 'NoCollisionConstraint', 'UniversalConstraint', 'PlaneConstraint']) defClass(n, 'Constraint', { props: { Length: 5, MaxForce: Infinity, Responsiveness: 10 } });
defClass('LinearVelocity', 'Constraint', { props: { VectorVelocity: () => V3(0, 0, 0), MaxForce: 1000, RelativeTo: () => E('ActuatorRelativeTo', 'World'), VelocityConstraintMode: () => E('VelocityConstraintMode', 'Vector') } });
defClass('AlignPosition', 'Constraint', { props: { Position: () => V3(0, 0, 0), MaxForce: 10000, Responsiveness: 10, RigidityEnabled: false, Mode: ANY(null) } });
defClass('VectorForce', 'Constraint', { props: { Force: () => V3(0, 0, 0), ApplyAtCenterOfMass: true } });
defClass('BodyMover', 'Instance', { notCreatable: true });
defClass('BodyVelocity', 'BodyMover', { props: { Velocity: () => V3(0, 2, 0), MaxForce: () => V3(4000, 4000, 4000), P: 1250 } });
defClass('BodyPosition', 'BodyMover', { props: { Position: () => V3(0, 50, 0), MaxForce: () => V3(4000, 4000, 4000), P: 10000, D: 1250 } });
defClass('BodyGyro', 'BodyMover', { props: { CFrame: () => new CFrame(), MaxTorque: () => V3(400000, 0, 400000), P: 3000, D: 500 } });
defClass('BodyForce', 'BodyMover', { props: { Force: () => V3(0, 0, 0) } });
defClass('BodyAngularVelocity', 'BodyMover', { props: { AngularVelocity: () => V3(0, 2, 0), MaxTorque: () => V3(4000, 4000, 4000), P: 1250 } });
defClass('BodyThrust', 'BodyMover', { props: { Force: () => V3(0, 0, 0), Location: () => V3(0, 0, 0) } });
for (const n of ['ParticleEmitter', 'Fire', 'Smoke', 'Sparkles', 'Trail', 'Beam', 'Highlight', 'SelectionBox', 'Decal', 'Texture', 'SpecialMesh', 'BlockMesh', 'CylinderMesh', 'SurfaceAppearance', 'Shirt', 'Pants', 'ShirtGraphic', 'BodyColors', 'Accessory', 'Hat', 'CharacterMesh', 'Sky', 'Atmosphere', 'BloomEffect', 'BlurEffect', 'ColorCorrectionEffect', 'SunRaysEffect', 'DepthOfFieldEffect', 'Clouds', 'Dialog', 'DialogChoice', 'Message', 'Hint', 'PackageLink', 'StringValue_Dummy']) {
  defClass(n, 'Instance', { props: { Enabled: true, Color: ANY(undefined), Size: ANY(undefined), Heat: 9, Texture: '', Transparency: ANY(0), Rate: 20, Lifetime: ANY(undefined), Speed: ANY(undefined), FillColor: () => Color3.rgb(255, 0, 0), OutlineColor: () => new Color3(1, 1, 1), FillTransparency: 0.5, OutlineTransparency: 0, Adornee: REF, Scale: () => V3(1, 1, 1), MeshType: ANY(null), MeshId: '', TextureId: '', Face: ANY(null), Text: '', Opacity: 0.5, RiseVelocity: 1, SparkleColor: () => new Color3(1, 1, 1), SecondaryColor: () => new Color3(1, 0.5, 0), Intensity: 1, Density: 0.3, Brightness: 1, Spread: 1 }, methods: M({ Emit: () => {}, Clear: () => {} }) });
}
CLASSES.Sky.props = { SkyboxBk: '', SkyboxDn: '', SkyboxFt: '', SkyboxLf: '', SkyboxRt: '', SkyboxUp: '', CelestialBodiesShown: true, StarCount: 3000 };

// ---- GUI ----
defClass('LayerCollector', 'Instance', { notCreatable: true, props: { Enabled: true, ResetOnSpawn: true, ZIndexBehavior: () => E('ZIndexBehavior', 'Sibling') } });
defClass('ScreenGui', 'LayerCollector', { props: { DisplayOrder: 0, IgnoreGuiInset: false } });
defClass('BillboardGui', 'LayerCollector', { props: { Adornee: REF, Size: () => new UDim2(0, 100, 0, 50), StudsOffset: () => V3(0, 0, 0), ExtentsOffset: () => V3(0, 0, 0), AlwaysOnTop: false, MaxDistance: Infinity, LightInfluence: 1, ClipsDescendants: false } });
defClass('SurfaceGui', 'LayerCollector', { props: { Adornee: REF, Face: () => E('NormalId', 'Front'), CanvasSize: () => new Vector2(800, 600) } });
defClass('GuiBase2d', 'Instance', { notCreatable: true, virt: { AbsoluteSize: { get: (s) => s.rt.guiAbs(s).size }, AbsolutePosition: { get: (s) => s.rt.guiAbs(s).pos } } });
defClass('GuiObject', 'GuiBase2d', {
  notCreatable: true,
  props: {
    Position: () => new UDim2(0, 0, 0, 0), Size: () => new UDim2(0, 100, 0, 100), AnchorPoint: () => new Vector2(0, 0), Rotation: 0,
    BackgroundColor3: () => Color3.rgb(255, 255, 255), BackgroundTransparency: 0, BorderColor3: () => Color3.rgb(27, 42, 53), BorderSizePixel: 1,
    Visible: true, ZIndex: 1, LayoutOrder: 0, ClipsDescendants: false, Active: false, Selectable: false, AutomaticSize: () => E('AutomaticSize', 'None'), Interactable: true,
  },
  events: ['MouseEnter', 'MouseLeave', 'InputBegan', 'InputEnded', 'MouseMoved'],
  methods: M({
    TweenPosition: (s, a, I) => { s.rt.guiTween(s, { Position: a[1] }, a[2], a[3], a[4], I); return true; },
    TweenSize: (s, a, I) => { s.rt.guiTween(s, { Size: a[1] }, a[2], a[3], a[4], I); return true; },
    TweenSizeAndPosition: (s, a, I) => { s.rt.guiTween(s, { Size: a[1], Position: a[2] }, a[3], a[4], a[5], I); return true; },
  }),
});
defClass('Frame', 'GuiObject', {});
defClass('ScrollingFrame', 'GuiObject', { props: { CanvasSize: () => new UDim2(0, 0, 2, 0), ScrollBarThickness: 12, ScrollingEnabled: true, CanvasPosition: () => new Vector2(0, 0) } });
const TEXT_PROPS = { Text: 'Label', TextColor3: () => Color3.rgb(27, 42, 53), TextSize: 14, TextScaled: false, TextWrapped: false, Font: () => E('Font', 'SourceSans'), TextTransparency: 0, TextStrokeTransparency: 1, TextStrokeColor3: () => new Color3(0, 0, 0), TextXAlignment: () => E('TextXAlignment', 'Center'), TextYAlignment: () => E('TextYAlignment', 'Center'), RichText: false, LineHeight: 1, MaxVisibleGraphemes: -1 };
defClass('TextLabel', 'GuiObject', { props: { ...TEXT_PROPS } });
defClass('TextButton', 'GuiObject', { props: { ...TEXT_PROPS, Text: 'Button', AutoButtonColor: true, Modal: false, Selected: false }, events: ['MouseButton1Click', 'MouseButton1Down', 'MouseButton1Up', 'MouseButton2Click', 'Activated'] });
defClass('TextBox', 'GuiObject', { props: { ...TEXT_PROPS, Text: '', PlaceholderText: '', PlaceholderColor3: () => Color3.rgb(178, 178, 178), ClearTextOnFocus: true, MultiLine: false, TextEditable: true }, events: ['FocusLost', 'Focused'], methods: M({ CaptureFocus: () => {}, ReleaseFocus: () => {}, IsFocused: () => false }) });
defClass('ImageLabel', 'GuiObject', { props: { Image: '', ImageColor3: () => new Color3(1, 1, 1), ImageTransparency: 0, ScaleType: () => E('ScaleType', 'Stretch') } });
defClass('ImageButton', 'ImageLabel', { props: { AutoButtonColor: true }, events: ['MouseButton1Click', 'MouseButton1Down', 'MouseButton1Up', 'Activated'] });
defClass('ViewportFrame', 'GuiObject', {});
defClass('UIComponent', 'Instance', { notCreatable: true });
defClass('UICorner', 'UIComponent', { props: { CornerRadius: () => new UDim(0, 8) } });
defClass('UIStroke', 'UIComponent', { props: { Color: () => new Color3(0, 0, 0), Thickness: 1, Transparency: 0, Enabled: true, ApplyStrokeMode: () => E('ApplyStrokeMode', 'Contextual') } });
defClass('UIPadding', 'UIComponent', { props: { PaddingTop: () => new UDim(0, 0), PaddingBottom: () => new UDim(0, 0), PaddingLeft: () => new UDim(0, 0), PaddingRight: () => new UDim(0, 0) } });
defClass('UIListLayout', 'UIComponent', { props: { FillDirection: () => E('FillDirection', 'Vertical'), Padding: () => new UDim(0, 0), SortOrder: () => E('SortOrder', 'LayoutOrder'), HorizontalAlignment: () => E('HorizontalAlignment', 'Left'), VerticalAlignment: () => E('VerticalAlignment', 'Top') } });
defClass('UIGridLayout', 'UIComponent', { props: { CellSize: () => new UDim2(0, 100, 0, 100), CellPadding: () => new UDim2(0, 5, 0, 5), SortOrder: () => E('SortOrder', 'LayoutOrder'), FillDirection: () => E('FillDirection', 'Horizontal') } });
defClass('UIGradient', 'UIComponent', { props: { Color: ANY(undefined), Rotation: 0, Transparency: ANY(undefined), Offset: () => new Vector2(0, 0), Enabled: true } });
defClass('UIAspectRatioConstraint', 'UIComponent', { props: { AspectRatio: 1 } });
defClass('UISizeConstraint', 'UIComponent', { props: { MinSize: () => new Vector2(0, 0), MaxSize: () => new Vector2(Infinity, Infinity) } });
defClass('UITextSizeConstraint', 'UIComponent', { props: { MinTextSize: 1, MaxTextSize: 100 } });
defClass('UIScale', 'UIComponent', { props: { Scale: 1 } });

// ---- 雜項 ----
defClass('Mouse', 'Instance', {
  notCreatable: true,
  props: { Icon: '', TargetFilter: REF },
  virt: {
    Hit: { get: (s) => s.rt.mouseHit().cf },
    Target: { get: (s) => s.rt.mouseHit().part || undefined },
    X: { get: (s) => s.rt.mouse.x }, Y: { get: (s) => s.rt.mouse.y },
    ViewSizeX: { get: (s) => s.rt.viewport.w }, ViewSizeY: { get: (s) => s.rt.viewport.h },
    UnitRay: { get: (s) => s.rt.mouseRay() },
    Origin: { get: (s) => { const r = s.rt.mouseRay(); return new CFrame(r.o.X, r.o.Y, r.o.Z); } },
  },
  events: ['Button1Down', 'Button1Up', 'Button2Down', 'Button2Up', 'Move', 'KeyDown', 'KeyUp', 'WheelForward', 'WheelBackward', 'Idle'],
});
defClass('InputObject', 'Instance', { notCreatable: true, props: { KeyCode: () => E('KeyCode', 'Unknown'), UserInputType: () => E('UserInputType', 'None'), UserInputState: () => E('UserInputState', 'None'), Position: () => V3(0, 0, 0), Delta: () => V3(0, 0, 0) } });
defClass('AnimationTrack', 'Instance', { notCreatable: true, props: { IsPlaying: false, Length: 1, Looped: false, Speed: 1, TimePosition: 0, WeightCurrent: 1, Priority: ANY(null) }, events: ['Stopped', 'Ended', 'DidLoop', 'KeyframeReached'], methods: M({ Play: (s) => { s.p.IsPlaying = true; }, Stop: (s) => { s.p.IsPlaying = false; s.fire('Stopped', []); }, AdjustSpeed: () => {}, AdjustWeight: () => {}, GetMarkerReachedSignal: (s) => s.signal('marker') }) });

// ---- 緩動 ----
function ease(t, style, dir) {
  const sn = style && style.Name || 'Quad', dn = dir && dir.Name || 'Out';
  const f = EASE[sn] || EASE.Quad;
  if (sn === 'Linear') return t;
  if (dn === 'In') return f(t);
  if (dn === 'Out') return 1 - f(1 - t);
  return t < 0.5 ? f(t * 2) / 2 : 1 - f((1 - t) * 2) / 2;
}
const EASE = {
  Linear: t => t, Sine: t => 1 - Math.cos(t * Math.PI / 2), Quad: t => t * t, Cubic: t => t * t * t, Quart: t => t ** 4, Quint: t => t ** 5,
  Exponential: t => t === 0 ? 0 : Math.pow(2, 10 * t - 10), Circular: t => 1 - Math.sqrt(1 - t * t),
  Back: t => { const s = 1.70158; return t * t * ((s + 1) * t - s); },
  Elastic: t => t === 0 || t === 1 ? t : -Math.pow(2, 10 * t - 10) * Math.sin((t * 10 - 10.75) * (2 * Math.PI / 3)),
  Bounce: t => 1 - bounceOut(1 - t),
};
function bounceOut(t) {
  const n = 7.5625, d = 2.75;
  if (t < 1 / d) return n * t * t;
  if (t < 2 / d) return n * (t -= 1.5 / d) * t + 0.75;
  if (t < 2.5 / d) return n * (t -= 2.25 / d) * t + 0.9375;
  return n * (t -= 2.625 / d) * t + 0.984375;
}
function lerpVal(a, b, t) {
  if (typeof a === 'number' && typeof b === 'number') return a + (b - a) * t;
  if (a instanceof Vector3) return a.lerp(b, t);
  if (a instanceof Color3) return a.lerp(b, t);
  if (a instanceof CFrame) return a.lerp(b, t);
  if (a instanceof UDim2) return a.lerp(b, t);
  if (a instanceof Vector2) return new Vector2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);
  if (a instanceof UDim) return new UDim(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t);
  return t >= 1 ? b : a;
}

// ---- JSON ----
function toJSON(v, I, depth = 0) {
  if (depth > 100) throw I.rtErr('Cannot convert cyclic table to JSON');
  if (v instanceof LuaTable) {
    const n = v.length();
    const keys = v.keyList();
    if (keys.length === n && n > 0) return v.arr.map(x => toJSON(x, I, depth + 1));
    if (keys.length === 0) return [];
    const o = {};
    for (const k of keys) o[typeof k === 'number' ? numToStr(k) : String(k)] = toJSON(v.get(k), I, depth + 1);
    return o;
  }
  if (v === undefined) return null;
  if (typeof v === 'number' || typeof v === 'string' || typeof v === 'boolean') return v;
  throw I.rtErr(`Cannot convert ${luauTypeof(v)} to JSON`);
}
function fromJSON(j) {
  if (Array.isArray(j)) return LuaTable.from(j.map(fromJSON));
  if (j && typeof j === 'object') { const t = new LuaTable(); for (const k in j) t.set(k, fromJSON(j[k])); return t; }
  return j === null ? undefined : j;
}

// ===================================================================
// 執行期
// ===================================================================
class RThread {
  constructor(gen, name) { this.gen = gen; this.name = name; this.stack = []; this.stack.pcall = 0; this.state = 'ready'; this.resume = undefined; this.handle = null; }
}

class Runtime {
  constructor(opts = {}) {
    this.opts = opts;
    this.out = opts.output || ((k, t) => console.log(t));
    this.I = new L.Interp({ output: (k, t) => this.emit(k, t) });
    this.I.rand = Math.random;
    this.time = 0; this.frame = 0;
    this.queue = []; this.sleepers = []; this.pollers = []; this.timers = [];
    this.paused = null; this.stopped = false; this.started = false;
    this.tweens = new Set(); this.renderBinds = new Map(); this.actions = new Map();
    this.keysDown = new Set(); this.mouseDown = new Set();
    this.mouse = { x: 0, y: 0, ray: null }; this.viewport = { w: 1280, h: 720 };
    this.effects = []; this.touching = new Map(); this.wsDirty = true; this.wsParts = []; this.prevCF = new Map();
    this.dsData = opts.dataStore || {};
    this.scriptMap = new Map(); this.chunkToScript = new Map();
    this.cam = { yaw: 0, pitch: 0.35, dist: 18, cf: null };
    this.buildWorld();
    installGlobals(this);
  }
  emit(kind, text, extra) { this.out(kind, text, extra); }
  emitEffect(e) { this.effects.push(e); }
  new(cls) { return new Instance(this, cls); }

  // ---------- 世界 ----------
  buildWorld() {
    const game = this.game = this.new('DataModel');
    game.p.Name = 'Game';
    const svc = (n) => { const s = this.new(n); s.p.Name = n; s.rawParent(game); return s; };
    this.workspace = svc('Workspace');
    for (const n of ['Players', 'Lighting', 'ReplicatedFirst', 'ReplicatedStorage', 'ServerScriptService', 'ServerStorage', 'StarterGui', 'StarterPack', 'StarterPlayer', 'Teams', 'SoundService', 'Chat']) svc(n);
    const sp = this.game.findChild('StarterPlayer');
    for (const n of ['StarterPlayerScripts', 'StarterCharacterScripts']) { const s = this.new(n); s.p.Name = n; s.rawParent(sp); }
    const cam = this.new('Camera');
    cam.p.Name = 'Camera';
    cam.rawParent(this.workspace);
    this.workspace.p.CurrentCamera = cam;
    this.camera = cam;
    const base = this.new('Part');
    base.p.Name = 'Baseplate';
    base.p.Size = V3(512, 20, 512);
    base.p.CFrame = new CFrame(0, -10, 0);
    base.p.Anchored = true; base.p.Locked = true;
    base.p.Color = Color3.rgb(91, 93, 105);
    base.rawParent(this.workspace);
    const spawn = this.new('SpawnLocation');
    spawn.p.Name = 'SpawnLocation';
    spawn.p.Size = V3(12, 1, 12);
    spawn.p.CFrame = new CFrame(0, 0.5, 0);
    spawn.p.Anchored = true;
    spawn.p.Color = Color3.rgb(163, 162, 165);
    spawn.rawParent(this.workspace);
    const players = this.game.findChild('Players');
    const pl = this.localPlayer = this.new('Player');
    pl.p.Name = 'Player1'; pl.p.DisplayName = 'Player1';
    for (const n of ['Backpack', 'PlayerGui', 'PlayerScripts']) { const c = this.new(n); c.p.Name = n; c.rawParent(pl); }
    players.p.LocalPlayer = pl;
    this.players = players;
  }
  getService(name, I) {
    let s = this.game.children.find(c => c.ClassName === name);
    if (s) return s;
    const cls = CLASSES[name];
    if (!cls || !cls.service) throw I.rtErr(`'${name}' is not a valid Service name`);
    s = this.new(name);
    s.p.Name = name;
    s.rawParent(this.game);
    return s;
  }
  allInstances() { return [this.game, ...this.game.descendants()]; }
  addTag(inst, tag) {
    if (!inst.tags) inst.tags = new Set();
    if (inst.tags.has(tag)) return;
    inst.tags.add(tag);
    const cs = this.game.children.find(c => c.ClassName === 'CollectionService');
    if (cs) cs.fire('tagAdded:' + tag, [inst]);
  }
  removeTag(inst, tag) {
    if (!inst.tags || !inst.tags.has(tag)) return;
    inst.tags.delete(tag);
    const cs = this.game.children.find(c => c.ClassName === 'CollectionService');
    if (cs) cs.fire('tagRemoved:' + tag, [inst]);
  }
  onReparent(inst, oldP, newP) {
    const ws = this.workspace;
    if (!ws) return;
    if ((oldP && (oldP === ws || oldP.isDescendantOf(ws))) || (newP && (newP === ws || newP.isDescendantOf(ws)))) this.wsDirty = true;
    if (inst.ClassName === 'Explosion' && newP && (newP === ws || newP.isDescendantOf(ws)) && this.started) this.explode(inst);
    if (this.started && newP && inst.ClassName === 'Script' && inst.source !== undefined && !inst.ran && (newP === ws || newP.isDescendantOf(ws) || newP.isDescendantOf(this.game.findChild('ServerScriptService')))) this.runScriptInst(inst);
  }
  workspaceParts() {
    if (this.wsDirty) {
      this.wsParts = this.workspace.descendants().filter(i => i.p.Size instanceof Vector3 && i.p.CFrame instanceof CFrame && i.isA('BasePart'));
      this.wsDirty = false;
    }
    return this.wsParts;
  }
  modelParts(m) { return m.descendants().filter(i => i.isA('BasePart')); }
  modelPivot(m) {
    if (m.p.PrimaryPart) return m.p.PrimaryPart.p.CFrame;
    const parts = this.modelParts(m);
    if (!parts.length) return m.p.WorldPivot || new CFrame();
    const [cf] = this.modelBounds(m);
    return cf;
  }
  modelPivotTo(m, cf) {
    const cur = this.modelPivot(m);
    const delta = cf.mul(cur.inv());
    for (const p of this.modelParts(m)) p.setCF(delta.mul(p.p.CFrame));
    if (!m.p.PrimaryPart && !this.modelParts(m).length) m.p.WorldPivot = cf;
  }
  modelBounds(m) {
    const parts = this.modelParts(m);
    if (!parts.length) return [new CFrame(), V3(0, 0, 0)];
    let mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
    for (const p of parts) { const b = aabb(p); for (let i = 0; i < 3; i++) { mn[i] = Math.min(mn[i], b[i]); mx[i] = Math.max(mx[i], b[i + 3]); } }
    return [new CFrame((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2), V3(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2])];
  }
  sunDir() {
    const t = (this.game.findChild('Lighting').p.ClockTime - 6) / 12 * Math.PI;
    return V3(Math.cos(t) * 0.6, Math.sin(t), 0.4).unit();
  }

  // ---------- DataStore(存在瀏覽器) ----------
  dataStore(name, scope) {
    const ds = this.new('GlobalDataStore');
    ds.p.Name = name;
    ds.dsKey = name + '/' + scope;
    return ds;
  }
  dsGet(ds, k) {
    const store = this.dsData[ds.dsKey];
    if (!store || !(k in store)) return undefined;
    return fromJSON(store[k]);
  }
  dsSet(ds, k, v, I) {
    const store = this.dsData[ds.dsKey] || (this.dsData[ds.dsKey] = {});
    if (v === undefined) delete store[k]; else store[k] = toJSON(v, I);
    if (this.opts.onDataStore) this.opts.onDataStore(this.dsData);
  }

  // ---------- 腳本 ----------
  // scripts: [{id, name, type:'Script'|'LocalScript'|'ModuleScript', parent:'ServerScriptService'|..., source}]
  load(scripts) {
    const parentOf = (n) => {
      if (n === 'StarterPlayerScripts' || n === 'StarterCharacterScripts') return this.game.findChild('StarterPlayer').findChild(n);
      if (n === 'Workspace') return this.workspace;
      return this.game.findChild(n) || this.game.findChild('ServerScriptService');
    };
    for (const s of scripts) {
      const inst = this.new(s.type);
      inst.p.Name = s.name;
      inst.source = s.source;
      inst.scriptId = s.id;
      if (s.disabled) inst.p.Enabled = false;
      inst.rawParent(parentOf(s.parent));
      this.scriptMap.set(s.id, inst);
    }
  }
  chunkName(inst) { return inst.fullName(); }
  setBreakpoints(scriptId, lines) {
    const inst = this.scriptMap.get(scriptId);
    this.bpByScript = this.bpByScript || new Map();
    this.bpByScript.set(scriptId, lines);
    if (!inst) return;
    for (const ch of this.chunksOf(scriptId)) this.I.setBreakpoints(ch, lines);
  }
  chunksOf(scriptId) { const out = []; for (const [ch, id] of this.chunkToScript) if (id === scriptId) out.push(ch); return out; }
  registerChunk(inst) {
    const ch = this.chunkName(inst);
    this.chunkToScript.set(ch, inst.scriptId);
    const lines = this.bpByScript && this.bpByScript.get(inst.scriptId);
    if (lines) this.I.setBreakpoints(ch, lines);
    return ch;
  }
  compileInst(inst) {
    const ch = this.registerChunk(inst);
    try {
      return this.I.compile(inst.source, ch, this.I.newEnv(), { script: inst });
    } catch (e) {
      if (e.isSyntax) {
        this.emit('error', `${ch}:${e.luaLine}: ${e.message}`, { chunk: ch, line: e.luaLine, scriptId: inst.scriptId });
        return null;
      }
      throw e;
    }
  }
  runScriptInst(inst) {
    if (inst.ran || !inst.p.Enabled || inst.p.Disabled) return;
    inst.ran = true;
    const fn = this.compileInst(inst);
    if (!fn) return;
    const th = this.newThread(fn, [], inst.fullName());
    this.queue.push(th);
  }
  start() {
    this.started = true;
    const sss = this.game.findChild('ServerScriptService');
    const servers = [...sss.descendants(), ...this.workspace.descendants()].filter(i => i.ClassName === 'Script');
    for (const s of servers) this.runScriptInst(s);
    this.runQueue(true);
    this.timer(0.05, () => this.playerJoin());
  }
  playerJoin() {
    const pl = this.localPlayer;
    if (pl.parent) return;
    pl.rawParent(this.players);
    this.players.fire('PlayerAdded', [pl]);
    // LocalScript：從 StarterPlayerScripts 複製到 PlayerScripts 後執行
    const sps = this.game.findChild('StarterPlayer').findChild('StarterPlayerScripts');
    const ps = pl.findChild('PlayerScripts');
    for (const s of sps.children.slice()) {
      const c = s.clone();
      c.scriptId = s.scriptId;
      c.rawParent(ps);
      this.scriptMap.set(s.scriptId, c);
      if (c.ClassName === 'LocalScript' || c.ClassName === 'Script') this.runScriptInst(c);
    }
    // StarterGui 裡的 LocalScript 也跑(放在 ScreenGui 裡的常見寫法)
    if (this.players.p.CharacterAutoLoads) this.timer(0.15, () => this.spawnCharacter(pl));
  }
  newThread(fn, args, name) {
    const th = new RThread(this.I.drive(this.I.call(fn, args || [])), name);
    const h = new Coroutine(null);
    h.status = 'suspended';
    h.rthread = th;
    th.handle = h;
    return th;
  }
  runThread(th) {
    const I = this.I;
    const ps = I.stack, pc = this.cur, pco = I.curCo;
    I.stack = th.stack; this.cur = th; I.curCo = null;
    th.state = 'running';
    if (th.handle) th.handle.status = 'running';
    let r;
    try {
      const v = th.resume;
      th.resume = undefined;
      r = th.gen.next(v);
    } catch (e) {
      th.state = 'dead';
      if (th.handle) th.handle.status = 'dead';
      I.stack = th.stack;
      this.reportError(e);
      return null;
    } finally { I.stack = ps; this.cur = pc; I.curCo = pco; }
    if (r.done) { th.state = 'dead'; if (th.handle) th.handle.status = 'dead'; return null; }
    if (th.handle) th.handle.status = 'suspended';
    return r.value;
  }
  reportError(e) {
    const I = this.I;
    const le = I.wrapJsError(e);
    let msg = typeof le.value === 'string' ? le.value : le.value === undefined ? 'Error occurred, no output from Lua.' : I.tostr(le.value);
    const tb = le.traceback || [];
    const top = tb[0];
    this.emit('error', msg, { chunk: le.chunk || (top && top.chunk), line: le.luaLine || (top && top.line), scriptId: this.chunkToScript.get(le.chunk || (top && top.chunk)), traceback: tb });
    if (tb.length) {
      this.emit('stack', 'Stack Begin');
      for (const f of tb) this.emit('stack', `Script '${f.chunk}', Line ${f.line}${f.name && f.name !== 'main chunk' ? ' - function ' + f.name : ''}`, { chunk: f.chunk, line: f.line, scriptId: this.chunkToScript.get(f.chunk) });
      this.emit('stack', 'Stack End');
    }
  }
  handle(th, sig) {
    if (sig.k !== 'budget') th.busySince = undefined;
    switch (sig.k) {
      case 'wait':
        th.state = 'wait'; th.waitStart = this.time; th.wakeAt = this.time + Math.max(0, sig.t || 0);
        this.sleepers.push(th);
        break;
      case 'budget':
        th.state = 'ready'; this.queue.push(th);
        if (th.busySince === undefined) th.busySince = nowMs();
        else if (!th.busyWarned && nowMs() - th.busySince > 4000) {
          th.busyWarned = true;
          const f = th.stack[th.stack.length - 1];
          this.emit('warn', `⚠ ${f ? f.chunk + ' 第 ' + f.line + ' 行附近' : th.name} 的迴圈已經連續跑了好幾秒都沒有 task.wait()，整個遊戲會變很卡。在迴圈裡加一行 task.wait() 吧！`, f ? { chunk: f.chunk, line: f.line, scriptId: this.chunkToScript.get(f.chunk) } : undefined);
        }
        return;
      case 'pause':
        th.state = 'paused';
        this.paused = { th, sig };
        this.I.dbg.pauseStack = sig.stack; this.I.dbg.pauseDepth = sig.stack.length;
        if (this.opts.onPause) this.opts.onPause(sig, th);
        break;
      case 'signal':
        th.state = 'signal'; sig.signal.waiters.push(th);
        break;
      case 'poll':
        th.state = 'poll'; th.poll = sig.fn; th.pollEnd = sig.timeout === null || sig.timeout === undefined ? Infinity : this.time + sig.timeout;
        th.pollWarn = sig.warn ? { at: this.time + 5, msg: sig.warn } : null;
        this.pollers.push(th);
        break;
      case 'suspend':
        th.state = 'suspended';
        break;
      case 'coyield':
        th.state = 'suspended';
        break;
      default:
        th.state = 'dead';
    }
  }
  runQueue(force) {
    const t0 = nowMs();
    while (this.queue.length && !this.paused && !this.stopped) {
      if (!force && nowMs() - t0 > 30) break;
      const th = this.queue.shift();
      if (th.state === 'dead') continue;
      const sig = this.runThread(th);
      if (sig) this.handle(th, sig);
      if (force && nowMs() - t0 > 60) break;
    }
  }
  fire(sig, args) {
    for (const c of sig.conns.slice()) {
      if (!c.connected) continue;
      if (c.once) c.disconnect();
      this.queue.push(this.newThread(c.fn, args, 'event:' + sig.name));
    }
    if (sig.waiters.length) {
      const ws = sig.waiters;
      sig.waiters = [];
      for (const th of ws) { if (th.state === 'dead') continue; th.resume = args; th.state = 'ready'; this.queue.push(th); }
    }
  }
  timer(t, fn) { this.timers.push({ at: this.time + t, fn }); }
  callLater(fn, args, t) {
    const th = this.newThread(fn, args, 'delay');
    th.state = 'wait'; th.waitStart = this.time; th.wakeAt = this.time + t; th.delayed = true;
    this.sleepers.push(th);
    return th;
  }

  // ---------- 除錯 ----------
  resume(mode) {
    if (!this.paused) return;
    const { th } = this.paused;
    this.paused = null;
    this.I.setMode(mode || 'run');
    th.state = 'ready';
    this.queue.unshift(th);
  }
  requestPause() { this.I.setMode('pause'); }
  stop() { this.stopped = true; this.paused = null; this.queue = []; this.sleepers = []; this.pollers = []; }

  // ---------- 每格 ----------
  step(dt) {
    if (this.stopped || this.paused) return;
    dt = Math.min(Math.max(dt, 0), 0.1);
    this.time += dt; this.frame++;
    this.workspace.p.DistributedGameTime = this.time;
    // 計時器
    if (this.timers.length) {
      const due = this.timers.filter(t => t.at <= this.time);
      if (due.length) { this.timers = this.timers.filter(t => t.at > this.time); for (const t of due) { try { t.fn(); } catch (e) { this.reportError(e); } } }
    }
    // 喚醒 wait
    if (this.sleepers.length) {
      const keep = [];
      for (const th of this.sleepers) {
        if (th.state !== 'wait') continue;
        if (th.wakeAt <= this.time) { th.state = 'ready'; if (!th.delayed) th.resume = [this.time - th.waitStart, this.time]; th.delayed = false; this.queue.push(th); }
        else keep.push(th);
      }
      this.sleepers = keep;
    }
    if (this.pollers.length) {
      const keep = [];
      for (const th of this.pollers) {
        if (th.state !== 'poll') continue;
        let v;
        try { v = th.poll(); } catch (e) { v = null; }
        if (v) { th.state = 'ready'; th.resume = [v]; this.queue.push(th); }
        else if (this.time >= th.pollEnd) { th.state = 'ready'; th.resume = [undefined]; this.queue.push(th); }
        else { if (th.pollWarn && this.time >= th.pollWarn.at) { this.emit('warn', th.pollWarn.msg); th.pollWarn = null; } keep.push(th); }
      }
      this.pollers = keep;
    }
    const rs = this.game.findChild('RunService') || null;
    if (rs) {
      for (const b of [...this.renderBinds.values()].sort((a, b) => a.pri - b.pri)) this.queue.push(this.newThread(b.fn, [dt], 'renderstep'));
      rs.fire('RenderStepped', [dt]); rs.fire('PreRender', [dt]);
      rs.fire('Stepped', [this.time, dt]); rs.fire('PreSimulation', [dt]);
    }
    this.updateTweens(dt);
    try { this.physics(dt); } catch (e) { this.reportError(e); }
    if (rs) { rs.fire('Heartbeat', [dt]); rs.fire('PostSimulation', [dt]); }
    this.runQueue(false);
  }

  // ---------- Tween ----------
  createTween(inst, info, goals, I) {
    if (!(info instanceof TweenInfo)) throw I.argErr(2, 'Create', `TweenInfo expected, got ${luauTypeof(info)}`);
    if (!(goals instanceof LuaTable)) throw I.argErr(3, 'Create', `table expected, got ${luauTypeof(goals)}`);
    const props = {};
    for (const k of goals.keyList()) {
      if (typeof k !== 'string') continue;
      const all = inst.cls.all;
      if (!(k in all.props) && !all.virt[k]) throw I.rtErr(`TweenService:Create property named '${k}' cannot be tweened due to type mismatch (property is not a valid member)`);
      const cur = inst.luaIndex(k, I), v = goals.get(k);
      if (luauTypeof(cur) !== luauTypeof(v) && !(typeof cur === 'number' && typeof v === 'number')) throw I.rtErr(`TweenService:Create property named '${k}' cannot be tweened due to type mismatch (property is a '${luauTypeof(cur)}', but given type is '${luauTypeof(v)}')`);
      props[k] = v;
    }
    const tw = this.new('Tween');
    tw.p.Instance = inst; tw.p.TweenInfo = info;
    tw.tw = { inst, info, props, active: false, elapsed: 0, from: null };
    return tw;
  }
  playTween(tw) {
    const t = tw.tw;
    if (t.active) return;
    if (!t.from || tw.p.PlaybackState.Name === 'Completed' || tw.p.PlaybackState.Name === 'Cancelled') {
      t.from = {}; t.elapsed = 0; t.rep = 0;
      for (const k in t.props) t.from[k] = t.inst.luaIndex(k, this.I);
    }
    // 同一個屬性只能被最新的 tween 控制
    for (const o of this.tweens) if (o !== tw && o.tw.inst === t.inst && Object.keys(o.tw.props).some(k => k in t.props)) this.stopTween(o, 'Cancelled');
    t.active = true;
    this.tweens.add(tw);
    tw.set('PlaybackState', E('PlaybackState', t.info.DelayTime > 0 ? 'Delayed' : 'Playing'));
  }
  stopTween(tw, state) {
    if (!tw.tw) return;
    tw.tw.active = false;
    this.tweens.delete(tw);
    if (tw.p.PlaybackState.Name !== 'Completed') { tw.set('PlaybackState', E('PlaybackState', state)); tw.fire('Completed', [E('PlaybackState', state)]); }
  }
  updateTweens(dt) {
    for (const tw of [...this.tweens]) {
      const t = tw.tw;
      if (!t.active) continue;
      if (t.inst.destroyed) { this.stopTween(tw, 'Cancelled'); continue; }
      t.elapsed += dt;
      const info = t.info;
      let el = t.elapsed - info.DelayTime;
      if (el < 0) continue;
      if (tw.p.PlaybackState.Name === 'Delayed') tw.set('PlaybackState', E('PlaybackState', 'Playing'));
      const dur = Math.max(info.Time, 1e-6);
      const cycle = info.Reverses ? dur * 2 : dur;
      let done = false;
      if (el >= cycle) {
        if (info.RepeatCount < 0 || t.rep < info.RepeatCount) { t.rep++; t.elapsed -= cycle; el -= cycle; }
        else { el = cycle; done = true; }
      }
      let a = el <= dur ? el / dur : 2 - el / dur;
      if (info.Reverses && done) a = 0;
      const e = ease(Math.min(Math.max(a, 0), 1), info.EasingStyle, info.EasingDirection);
      for (const k in t.props) {
        const v = done && !info.Reverses ? t.props[k] : lerpVal(t.from[k], t.props[k], e);
        this.setProp(t.inst, k, v);
      }
      if (done) {
        t.active = false;
        this.tweens.delete(tw);
        tw.set('PlaybackState', E('PlaybackState', 'Completed'));
        tw.fire('Completed', [E('PlaybackState', 'Completed')]);
      }
    }
  }
  setProp(inst, k, v) {
    const vt = inst.cls.all.virt[k];
    if (vt && vt.set) { vt.set(inst, v, this.I); inst.changed(k); }
    else inst.set(k, v, this.I);
  }
  guiTween(inst, props, dir, style, time, I) {
    const goals = LuaTable.fromObject(props);
    const info = new TweenInfo(time === undefined ? 1 : time, style instanceof EnumItem ? style : E('EasingStyle', 'Quad'), dir instanceof EnumItem ? dir : E('EasingDirection', 'Out'), 0, false, 0);
    this.playTween(this.createTween(inst, info, goals, I));
  }
  fakeAnimTrack() { const t = this.new('AnimationTrack'); return t; }

  // ---------- 角色 ----------
  spawnCharacter(pl) {
    this.removeCharacter(pl);
    const m = this.new('Model');
    m.p.Name = pl.p.Name;
    const sp = this.workspaceParts().find(p => p.ClassName === 'SpawnLocation' && p.p.Enabled);
    const base = sp ? sp.p.CFrame.pos.add(V3(0, sp.p.Size.Y / 2 + 3.01, 0)) : V3(0, 5, 0);
    const mk = (name, size, color, off) => {
      const p = this.new('Part');
      p.p.Name = name; p.p.Size = size; p.p.Color = color; p.p.CFrame = new CFrame(base.X + off[0], base.Y + off[1], base.Z + off[2]);
      p.p.CanCollide = false;
      p.limbOff = off;
      p.rawParent(m);
      return p;
    };
    const skin = Color3.rgb(245, 205, 48);
    const root = mk('HumanoidRootPart', V3(2, 2, 1), Color3.rgb(163, 162, 165), [0, 0, 0]);
    root.p.Transparency = 1;
    mk('Head', V3(2, 1, 1), skin, [0, 1.5, 0]).p.Shape = E('PartType', 'Block');
    mk('Torso', V3(2, 2, 1), Color3.rgb(13, 105, 172), [0, 0, 0]);
    mk('Left Arm', V3(1, 2, 1), skin, [-1.5, 0, 0]);
    mk('Right Arm', V3(1, 2, 1), skin, [1.5, 0, 0]);
    mk('Left Leg', V3(1, 2, 1), Color3.rgb(164, 189, 71), [-0.5, -2, 0]);
    mk('Right Leg', V3(1, 2, 1), Color3.rgb(164, 189, 71), [0.5, -2, 0]);
    const face = this.new('Decal'); face.p.Name = 'face'; face.rawParent(m.findChild('Head'));
    const hum = this.new('Humanoid');
    hum.p.Name = 'Humanoid';
    hum.p.DisplayName = pl.p.DisplayName;
    const st = this.game.findChild('StarterPlayer').p;
    hum.p.WalkSpeed = st.CharacterWalkSpeed; hum.p.JumpPower = st.CharacterJumpPower;
    hum.p.RootPart = root;
    hum.rawParent(m);
    m.p.PrimaryPart = root;
    m.isCharacter = true; m.humanoid = hum; m.player = pl;
    // StarterCharacterScripts
    const scs = this.game.findChild('StarterPlayer').findChild('StarterCharacterScripts');
    const clones = [];
    for (const s of scs.children) { const c = s.clone(); c.scriptId = s.scriptId; c.rawParent(m); clones.push(c); }
    m.rawParent(this.workspace);
    pl.set('Character', m);
    this.camera.p.CameraSubject = hum;
    this.char = m;
    // StarterGui → PlayerGui
    const pg = pl.findChild('PlayerGui');
    for (const g of pg.children.slice()) if (g.p.ResetOnSpawn !== false && g.fromStarter) g.destroy();
    for (const g of this.game.findChild('StarterGui').children) {
      if (pg.children.some(x => x.fromStarter && x.p.Name === g.p.Name && x.p.ResetOnSpawn === false)) continue;
      const c = g.clone();
      if (!c) continue;
      c.fromStarter = true;
      const copyIds = (a, b) => { b.scriptId = a.scriptId; a.children.forEach((x, i) => b.children[i] && copyIds(x, b.children[i])); };
      copyIds(g, c);
      c.rawParent(pg);
      for (const d of [c, ...c.descendants()]) if (d.ClassName === 'LocalScript' && d.source !== undefined) { d.ran = false; this.runScriptInst(d); }
    }
    for (const c of clones) if (c.source !== undefined) this.runScriptInst(c);
    pl.fire('CharacterAdded', [m]);
    this.cam.yaw = Math.atan2(-root.p.CFrame.m[2], -root.p.CFrame.m[8]) || 0;
    return m;
  }
  removeCharacter(pl) {
    const m = pl.p.Character;
    if (!m) return;
    pl.fire('CharacterRemoving', [m]);
    m.destroy();
    pl.p.Character = null;
    if (this.char === m) this.char = null;
  }
  killHumanoid(h) {
    if (h.ctl.dead) return;
    h.ctl.dead = true;
    h.fire('Died', []);
    const m = h.parent;
    if (m && m.isCharacter) {
      for (const p of this.modelParts(m)) {
        if (p.p.Name === 'HumanoidRootPart') continue;
        p.limbOff = null; p.p.CanCollide = true;
        p.p.AssemblyLinearVelocity = V3((Math.random() - 0.5) * 20, 10 + Math.random() * 10, (Math.random() - 0.5) * 20);
      }
      const pl = m.player;
      if (pl && this.players.p.CharacterAutoLoads) this.timer(this.players.p.RespawnTime, () => { if (pl.p.Character === m) this.spawnCharacter(pl); });
    }
  }
  characterStep(dt) {
    const m = this.char;
    if (!m || m.destroyed) return;
    const h = m.humanoid, root = m.findChild('HumanoidRootPart');
    if (!h || !root || h.destroyed || root.destroyed) return;
    const c = h.ctl;
    if (c.dead) return;
    const g = this.workspace.p.Gravity;
    let pos = root.p.CFrame.pos;
    // 輸入方向(以鏡頭為準)
    let mv = V3(0, 0, 0);
    const k = this.keysDown;
    if (!this.paused && this.inputEnabled !== false) {
      let f = (k.has('W') || k.has('Up') ? 1 : 0) - (k.has('S') || k.has('Down') ? 1 : 0);
      let r = (k.has('D') || k.has('Right') ? 1 : 0) - (k.has('A') || k.has('Left') ? 1 : 0);
      if (this.analog && (this.analog.x || this.analog.y)) { f = -this.analog.y; r = this.analog.x; }
      if (f || r) {
        const fw = V3(-Math.sin(this.cam.yaw), 0, -Math.cos(this.cam.yaw)), rt = V3(Math.cos(this.cam.yaw), 0, -Math.sin(this.cam.yaw));
        mv = fw.mul(f).add(rt.mul(r));
      }
    }
    if (c.scriptMove && c.scriptMove.mag > 0) mv = mv.add(V3(c.scriptMove.X, 0, c.scriptMove.Z));
    if (c.moveTo) {
      const d = V3(c.moveTo.X - pos.X, 0, c.moveTo.Z - pos.Z);
      if (d.mag < 1) { c.moveTo = null; h.fire('MoveToFinished', [true]); }
      else if (this.time - c.moveToStart > 8) { c.moveTo = null; h.fire('MoveToFinished', [false]); }
      else mv = d;
    }
    if (mv.mag > 1e-6) mv = mv.unit();
    if (!h.p.PlatformStand) {
      h.p.MoveDirection = mv;
    }
    const speed = h.p.WalkSpeed;
    let vx = mv.X * speed, vz = mv.Z * speed;
    if (c.knock) { vx += c.knock.X; vz += c.knock.Z; c.knock = c.knock.mul(Math.max(0, 1 - dt * 4)); if (c.knock.mag < 0.5) c.knock = null; }
    // 跳
    const wantJump = (k.has('Space') && this.inputEnabled !== false) || h.p.Jump || c.wantJump;
    if (wantJump && c.grounded && !h.p.Sit) {
      c.vy = h.p.UseJumpPower ? h.p.JumpPower : Math.sqrt(2 * g * h.p.JumpHeight);
      c.grounded = false;
      h.p.Jump = false; c.wantJump = false;
      h.fire('Jumping', [true]);
    }
    if (c.grounded && c.groundPart && !c.groundPart.destroyed) {
      // 站在移動平台上 → 跟著平台走
      const prev = this.prevCF.get(c.groundPart);
      if (prev) {
        const now = c.groundPart.p.CFrame;
        if (!now.luaEq(prev)) {
          const rel = prev.inv().point(pos.X, pos.Y, pos.Z);
          const np = now.point(rel.X, rel.Y, rel.Z);
          pos = np;
          const yawD = Math.atan2(now.m[2], now.m[8]) - Math.atan2(prev.m[2], prev.m[8]);
          if (yawD) c.yawCarry = (c.yawCarry || 0) + yawD;
        }
      }
    }
    c.vy -= g * dt;
    if (c.vy < -300) c.vy = -300;
    const he = V3(1, 2.5, 0.75);
    const center = (p) => V3(p.X, p.Y - 0.5, p.Z);
    const obstacles = this.collidables(m);
    // 依軸向移動 + 碰撞
    const steps = Math.max(1, Math.ceil(Math.max(Math.abs(vx), Math.abs(vz), Math.abs(c.vy)) * dt / 0.8));
    const sdt = dt / steps;
    let grounded = false, groundPart = null;
    for (let s = 0; s < steps; s++) {
      for (const axis of [0, 2]) {
        const d = (axis === 0 ? vx : vz) * sdt;
        if (!d) continue;
        const np = axis === 0 ? V3(pos.X + d, pos.Y, pos.Z) : V3(pos.X, pos.Y, pos.Z + d);
        const hit = this.boxHit(center(np), he, obstacles);
        if (!hit) { pos = np; continue; }
        // 小台階自動爬上去
        const top = hit.b[4];
        const feet = np.Y - 3;
        if (top - feet > 0 && top - feet <= 1.25 && !this.boxHit(center(V3(np.X, top + 3.01, np.Z)), he, obstacles)) { pos = V3(np.X, top + 3.01, np.Z); continue; }
      }
      const dy = c.vy * sdt;
      const np = V3(pos.X, pos.Y + dy, pos.Z);
      const hit = this.boxHit(center(np), he, obstacles);
      if (!hit) pos = np;
      else {
        if (dy <= 0) { pos = V3(pos.X, hit.b[4] + 3, pos.Z); grounded = true; groundPart = hit.part; c.vy = 0; }
        else { pos = V3(pos.X, hit.b[1] - 2.0 - 0.001, pos.Z); c.vy = 0; }
      }
    }
    if (!grounded && c.vy <= 0) {
      const probe = this.boxHit(center(V3(pos.X, pos.Y - 0.08, pos.Z)), he, obstacles);
      if (probe) { grounded = true; groundPart = probe.part; }
    }
    if (grounded && !c.grounded) h.fire('Running', [Math.hypot(vx, vz)]);
    if (!grounded && c.grounded && c.vy < 0) h.fire('FreeFalling', [true]);
    c.grounded = grounded; c.groundPart = groundPart;
    h.p.FloorMaterial = groundPart ? groundPart.p.Material : E('Material', 'Air');
    // 面向
    let yaw = c.yaw === undefined ? Math.atan2(-root.p.CFrame.m[2], -root.p.CFrame.m[8]) : c.yaw;
    if (c.yawCarry) { yaw += c.yawCarry; c.yawCarry = 0; }
    if (mv.mag > 0.01 && h.p.AutoRotate) {
      const target = Math.atan2(-mv.X, -mv.Z);
      let dd = target - yaw;
      while (dd > Math.PI) dd -= Math.PI * 2;
      while (dd < -Math.PI) dd += Math.PI * 2;
      yaw += dd * Math.min(1, dt * 12);
    }
    c.yaw = yaw;
    const rot = CFrame.anglesYXZ(0, yaw, 0);
    const cf = new CFrame(pos.X, pos.Y, pos.Z, rot.m);
    root.p.CFrame = cf;
    for (const p of m.children) if (p.limbOff && p !== root) p.p.CFrame = cf.mul(new CFrame(p.limbOff[0], p.limbOff[1], p.limbOff[2]));
    if (pos.Y < this.workspace.p.FallenPartsDestroyHeight) h.set('Health', 0);
  }
  collidables(exclude) {
    const out = [];
    for (const p of this.workspaceParts()) {
      if (!p.p.CanCollide || p.p.Transparency >= 1 && p.p.Name === 'HumanoidRootPart') continue;
      if (exclude && p.isDescendantOf(exclude)) continue;
      out.push(p);
    }
    return out;
  }
  boxHit(c, he, parts) {
    const mn = [c.X - he.X, c.Y - he.Y, c.Z - he.Z], mx = [c.X + he.X, c.Y + he.Y, c.Z + he.Z];
    let best = null;
    for (const p of parts) {
      const b = p._bb || aabb(p);
      if (b[0] < mx[0] && b[3] > mn[0] && b[1] < mx[1] && b[4] > mn[1] && b[2] < mx[2] && b[5] > mn[2]) {
        if (!best || b[4] > best.b[4]) best = { part: p, b };
      }
    }
    return best;
  }

  // ---------- 物理 ----------
  physics(dt) {
    const parts = this.workspaceParts();
    for (const p of parts) p._bb = aabb(p);
    const g = this.workspace.p.Gravity;
    const statics = parts.filter(p => p.p.CanCollide && !(p.limbOff));
    // 自由落體零件
    for (const p of parts) {
      if (p.p.Anchored || p.limbOff || (p.parent && p.parent.isCharacter && p.p.Name === 'HumanoidRootPart')) continue;
      if (this.isWelded(p)) continue;
      let v = p.p.AssemblyLinearVelocity;
      let ctl = false;
      for (const c of p.children) {
        if (c.ClassName === 'BodyVelocity') { v = c.p.Velocity; ctl = true; }
        else if (c.ClassName === 'LinearVelocity' && c.p.Enabled) { v = c.p.VectorVelocity; ctl = true; }
        else if (c.ClassName === 'BodyPosition' || (c.ClassName === 'AlignPosition' && c.p.Enabled)) { const d = c.p.Position.sub(p.p.CFrame.pos); v = d.mul(Math.min(10, d.mag) / Math.max(d.mag, 1e-6) * 3); ctl = true; }
        else if (c.ClassName === 'BodyForce' || c.ClassName === 'VectorForce') { const m = partVolume(p) * 0.7 || 1; v = v.add(c.p.Force.mul(dt / m)); }
      }
      if (!ctl) v = V3(v.X, v.Y - g * dt, v.Z);
      let pos = p.p.CFrame.pos.add(v.mul(dt));
      const he = halfExt(p);
      let onGround = false;
      if (p.p.CanCollide) {
        for (const o of statics) {
          if (o === p) continue;
          const b = o._bb;
          const mn = [pos.X - he[0], pos.Y - he[1], pos.Z - he[2]], mx = [pos.X + he[0], pos.Y + he[1], pos.Z + he[2]];
          if (!(b[0] < mx[0] && b[3] > mn[0] && b[1] < mx[1] && b[4] > mn[1] && b[2] < mx[2] && b[5] > mn[2])) continue;
          const pen = [mx[0] - b[0], b[3] - mn[0], mx[1] - b[1], b[4] - mn[1], mx[2] - b[2], b[5] - mn[2]];
          let mi = 0;
          for (let i = 1; i < 6; i++) if (pen[i] < pen[mi]) mi = i;
          const ax = mi >> 1, sg = mi & 1 ? 1 : -1, amt = pen[mi];
          const arr = [pos.X, pos.Y, pos.Z];
          arr[ax] += sg * amt;
          pos = V3(arr[0], arr[1], arr[2]);
          const va = [v.X, v.Y, v.Z];
          if (va[ax] * sg < 0) va[ax] = ax === 1 && Math.abs(va[1]) > 30 ? -va[1] * 0.25 : 0;
          v = V3(va[0], va[1], va[2]);
          if (ax === 1 && sg > 0) onGround = true;
        }
      }
      if (onGround) { const fr = Math.max(0, 1 - dt * 6); v = V3(v.X * fr, v.Y, v.Z * fr); }
      p.p.AssemblyLinearVelocity = v;
      if (!pos.luaEq(p.p.CFrame.pos)) { p.p.CFrame = p.p.CFrame.withPos(pos); p._bb = aabb(p); }
      if (pos.Y < this.workspace.p.FallenPartsDestroyHeight) p.destroy();
    }
    // 焊接零件跟著走
    this.applyWelds();
    this.characterStep(dt);
    for (const p of parts) if (p.limbOff || (p.parent && p.parent.isCharacter)) p._bb = aabb(p);
    this.touchStep(parts);
    // 記錄這格位置(給移動平台用)
    this.prevCF = new Map();
    for (const p of parts) if (p.p.Anchored) this.prevCF.set(p, p.p.CFrame);
  }
  isWelded(p) {
    const ws = this.weldsOf(p);
    for (const w of ws) { const o = w.p.Part0 === p ? w.p.Part1 : w.p.Part0; if (o && o !== p) return true; }
    return false;
  }
  weldsOf(p) {
    if (!this.weldCache || this.weldCacheFrame !== this.frame) {
      this.weldCacheFrame = this.frame;
      this.weldCache = new Map();
      for (const w of this.workspace.descendants()) {
        if ((w.ClassName === 'WeldConstraint' || w.ClassName === 'Weld' || w.ClassName === 'ManualWeld' || w.ClassName === 'Motor6D') && w.p.Enabled !== false && w.p.Part0 && w.p.Part1) {
          for (const x of [w.p.Part0, w.p.Part1]) { if (!this.weldCache.has(x)) this.weldCache.set(x, []); this.weldCache.get(x).push(w); }
        }
      }
    }
    return this.weldCache.get(p) || [];
  }
  applyWelds() {
    if (!this.weldCache || !this.weldCache.size) { this.weldsOf(null); if (!this.weldCache.size) return; }
    for (const [p, ws] of this.weldCache) {
      for (const w of ws) {
        if (w.p.Part0 !== p) continue;
        const a = w.p.Part0, b = w.p.Part1;
        if (!w.rel) w.rel = w.ClassName === 'WeldConstraint' ? a.p.CFrame.inv().mul(b.p.CFrame) : w.p.C0.mul(w.p.C1.inv());
        if (!b.p.Anchored && !b.limbOff) { b.p.CFrame = a.p.CFrame.mul(w.rel); b._bb = aabb(b); }
      }
    }
  }
  touchStep(parts) {
    const movers = parts.filter(p => p.p.CanTouch && (!p.p.Anchored || p.limbOff));
    const now = new Map();
    for (const a of movers) {
      const ab = a._bb;
      for (const b of parts) {
        if (b === a || !b.p.CanTouch) continue;
        if (a.parent && a.parent.isCharacter && b.parent === a.parent) continue;
        const bb = b._bb, e = 0.06;
        if (ab[0] - e < bb[3] && ab[3] + e > bb[0] && ab[1] - e < bb[4] && ab[4] + e > bb[1] && ab[2] - e < bb[5] && ab[5] + e > bb[2]) {
          const key = a.id < b.id ? a.id + ':' + b.id : b.id + ':' + a.id;
          if (!now.has(key)) now.set(key, [a, b]);
        }
      }
    }
    for (const [key, [a, b]] of now) {
      if (!this.touching.has(key)) {
        if (a.p.Name !== 'HumanoidRootPart') b.fire('Touched', [a]);
        if (b.p.Name !== 'HumanoidRootPart') a.fire('Touched', [b]);
        for (const [x, y] of [[a, b], [b, a]]) if (x.parent && x.parent.isCharacter && x.parent.humanoid) x.parent.humanoid.fire('Touched', [y, x]);
      }
    }
    for (const [key, [a, b]] of this.touching) {
      if (!now.has(key)) { if (!b.destroyed) b.fire('TouchEnded', [a]); if (!a.destroyed) a.fire('TouchEnded', [b]); }
    }
    this.touching = now;
  }
  touchingParts(p) {
    const b = aabb(p), out = [];
    for (const o of this.workspaceParts()) {
      if (o === p) continue;
      const c = aabb(o);
      if (b[0] < c[3] && b[3] > c[0] && b[1] < c[4] && b[4] > c[1] && b[2] < c[5] && b[5] > c[2]) out.push(o);
    }
    return out;
  }
  partsInRadius(c, r) { return this.workspaceParts().filter(p => { const b = aabb(p); const dx = Math.max(b[0] - c.X, 0, c.X - b[3]), dy = Math.max(b[1] - c.Y, 0, c.Y - b[4]), dz = Math.max(b[2] - c.Z, 0, c.Z - b[5]); return dx * dx + dy * dy + dz * dz <= r * r; }); }
  partsInBox(c, he) { return this.workspaceParts().filter(p => { const b = aabb(p); return b[0] < c.X + he.X && b[3] > c.X - he.X && b[1] < c.Y + he.Y && b[4] > c.Y - he.Y && b[2] < c.Z + he.Z && b[5] > c.Z - he.Z; }); }
  explode(ex) {
    const c = ex.p.Position, r = ex.p.BlastRadius;
    this.emitEffect({ k: 'explosion', pos: c, radius: r });
    const hitModels = new Set();
    for (const p of this.partsInRadius(c, r)) {
      const d = p.p.CFrame.pos.sub(c);
      ex.fire('Hit', [p, d.mag]);
      const m = p.parent;
      if (m && m.isCharacter && m.humanoid && !hitModels.has(m)) {
        hitModels.add(m);
        if (ex.p.DestroyJointRadiusPercent > 0 && !m.humanoid.findForceField()) m.humanoid.set('Health', 0);
      }
      if (!p.p.Anchored || (m && m.isCharacter)) {
        const push = d.mag > 0.01 ? d.unit() : V3(0, 1, 0);
        p.p.AssemblyLinearVelocity = p.p.AssemblyLinearVelocity.add(push.mul(Math.min(150, ex.p.BlastPressure / 5000)).add(V3(0, 30, 0)));
      }
    }
  }

  // ---------- 射線 ----------
  rayFilter(prm) {
    if (!prm) return (p) => p.p.CanQuery !== false;
    const list = prm.FilterDescendantsInstances instanceof LuaTable ? prm.FilterDescendantsInstances.arr.filter(x => x instanceof Instance) : [];
    const include = prm.FilterType && (prm.FilterType.Name === 'Include' || prm.FilterType.Name === 'Whitelist');
    return (p) => {
      if (p.p.CanQuery === false) return false;
      if (prm.RespectCanCollide && !p.p.CanCollide) return false;
      const inList = list.some(x => x === p || p.isDescendantOf(x));
      return include ? inList : !inList;
    };
  }
  raycast(o, d, filter) {
    const len = d.mag;
    if (len < 1e-9) return null;
    let best = null;
    for (const p of this.workspaceParts()) {
      if (filter && !filter(p)) continue;
      const r = rayPart(o, d, p);
      if (r && (!best || r.t < best.t)) best = { ...r, part: p };
    }
    if (!best) return null;
    return { part: best.part, pos: o.add(d.mul(best.t)), normal: best.n, dist: best.t * len };
  }
  mouseRay() { const r = this.mouse.ray; if (r) return new Ray(r.o, r.d); return new Ray(V3(0, 10, 20), V3(0, -0.5, -1).unit()); }
  mouseHit() {
    const r = this.mouse.ray;
    if (!r) return { cf: new CFrame(), part: null };
    const tf = this.mouseFilter;
    const hit = this.raycast(r.o, r.d.mul(1000), (p) => !(tf && (p === tf || p.isDescendantOf(tf))) && !(p.p.Name === 'HumanoidRootPart'));
    const pos = hit ? hit.pos : r.o.add(r.d.mul(1000));
    return { cf: new CFrame(pos.X, pos.Y, pos.Z, CFrame.lookAt(r.o, pos).m), part: hit ? hit.part : null };
  }
  getMouse() {
    if (!this.mouseObj) { this.mouseObj = this.new('Mouse'); this.mouseObj.p.Name = 'Mouse'; }
    return this.mouseObj;
  }
  screenRay(x, y) { if (this.opts.screenRay) { const r = this.opts.screenRay(x, y); return new Ray(r.o, r.d); } return this.mouseRay(); }
  worldToScreen(v) { if (this.opts.worldToScreen) { const r = this.opts.worldToScreen(v); return [V3(r.x, r.y, r.z), r.on]; } return [V3(0, 0, 0), false]; }
  guiAbs(g) { if (this.opts.guiAbs) return this.opts.guiAbs(g); return { size: new Vector2(0, 0), pos: new Vector2(0, 0) }; }

  // ---------- 輸入(app.js 呼叫) ----------
  inputObject(keyName, type, state) {
    const io = this.new('InputObject');
    io.p.Name = 'InputObject';
    io.p.KeyCode = E('KeyCode', keyName) || E('KeyCode', 'Unknown');
    io.p.UserInputType = E('UserInputType', type);
    io.p.UserInputState = E('UserInputState', state);
    io.p.Position = V3(this.mouse.x, this.mouse.y, 0);
    return io;
  }
  keyInput(name, down) {
    if (!this.started || this.stopped) return;
    if (down) { if (this.keysDown.has(name)) return; this.keysDown.add(name); } else this.keysDown.delete(name);
    const uis = this.game.findChild('UserInputService');
    const io = this.inputObject(name, 'Keyboard', down ? 'Begin' : 'End');
    if (uis) uis.fire(down ? 'InputBegan' : 'InputEnded', [io, false]);
    if (down && name === 'Space' && uis) uis.fire('JumpRequest', []);
    for (const [an, a] of this.actions) if (a.keys.includes(name)) this.queue.push(this.newThread(a.fn, [an, E('UserInputState', down ? 'Begin' : 'End'), io], 'action'));
    if (this.mouseObj) {
      const ch = name.length === 1 ? name.toLowerCase() : name === 'Space' ? ' ' : '';
      if (ch) this.mouseObj.fire(down ? 'KeyDown' : 'KeyUp', [ch]);
    }
  }
  mouseInput(button, down) {
    if (!this.started || this.stopped) return;
    const t = button === 0 ? 'MouseButton1' : button === 2 ? 'MouseButton2' : 'MouseButton3';
    if (down) this.mouseDown.add(t); else this.mouseDown.delete(t);
    const uis = this.game.findChild('UserInputService');
    if (uis) uis.fire(down ? 'InputBegan' : 'InputEnded', [this.inputObject('Unknown', t, down ? 'Begin' : 'End'), false]);
    for (const [an, a] of this.actions) if (a.keys.includes(t)) this.queue.push(this.newThread(a.fn, [an, E('UserInputState', down ? 'Begin' : 'End'), this.inputObject('Unknown', t, down ? 'Begin' : 'End')], 'action'));
    if (this.mouseObj) this.mouseObj.fire((button === 0 ? 'Button1' : 'Button2') + (down ? 'Down' : 'Up'), []);
    if (down && button === 0 && this.mouse.ray) {
      const hit = this.raycast(this.mouse.ray.o, this.mouse.ray.d.mul(1000), (p) => p.p.Name !== 'HumanoidRootPart' && !(this.char && p.isDescendantOf(this.char)));
      if (hit) {
        let cd = null;
        for (let x = hit.part; x && !cd; x = x.parent) cd = x.children.find(c => c.ClassName === 'ClickDetector');
        if (cd && hit.dist <= cd.p.MaxActivationDistance + 30) cd.fire('MouseClick', [this.localPlayer]);
      }
    }
  }
  mouseMove(x, y, ray) {
    this.mouse.x = x; this.mouse.y = y; this.mouse.ray = ray;
    if (!this.started || this.stopped) return;
    if (this.mouseObj) this.mouseObj.fire('Move', []);
    const uis = this.game.findChild('UserInputService');
    if (uis && uis.sig && uis.sig.InputChanged) uis.fire('InputChanged', [this.inputObject('Unknown', 'MouseMovement', 'Change'), false]);
  }
  guiEvent(inst, name, args) { if (inst && !inst.destroyed) inst.fire(name, args || []); }
  promptTrigger(pp) { pp.fire('Triggered', [this.localPlayer]); const svc = this.game.findChild('ProximityPromptService'); if (svc) svc.fire('PromptTriggered', [pp, this.localPlayer]); }
}

class Ray {
  constructor(o, d) { this.o = o; this.d = d; }
  get luaType() { return 'Ray'; }
  luaIndex(k, I) {
    if (k === 'Origin') return this.o;
    if (k === 'Direction') return this.d;
    if (k === 'Unit') return new Ray(this.o, this.d.unit());
    if (k === 'ClosestPoint') return nat('ClosestPoint', (a) => { const p = a[1]; const t = Math.max(0, p.sub(this.o).dot(this.d.unit())); return this.o.add(this.d.unit().mul(t)); });
    if (k === 'Distance') return nat('Distance', (a) => { const p = a[1]; const u = this.d.unit(); const t = Math.max(0, p.sub(this.o).dot(u)); return this.o.add(u.mul(t)).sub(p).mag; });
    throw memberErr(I, k, 'Ray');
  }
  luaToString() { return `{${this.o.luaToString()}}, {${this.d.luaToString()}}`; }
}

function halfExt(p) {
  const s = p.p.Size, m = p.p.CFrame.m, hx = s.X / 2, hy = s.Y / 2, hz = s.Z / 2;
  return [Math.abs(m[0]) * hx + Math.abs(m[1]) * hy + Math.abs(m[2]) * hz, Math.abs(m[3]) * hx + Math.abs(m[4]) * hy + Math.abs(m[5]) * hz, Math.abs(m[6]) * hx + Math.abs(m[7]) * hy + Math.abs(m[8]) * hz];
}
function aabb(p) {
  const c = p.p.CFrame, e = halfExt(p);
  return [c.x - e[0], c.y - e[1], c.z - e[2], c.x + e[0], c.y + e[1], c.z + e[2]];
}
function rayPart(o, d, p) {
  const cf = p.p.CFrame, s = p.p.Size;
  const iv = cf.inv();
  const lo = iv.point(o.X, o.Y, o.Z), ld = iv.vec(d.X, d.Y, d.Z);
  const shape = p.p.Shape && p.p.Shape.Name;
  if (shape === 'Ball') {
    const r = s.X / 2;
    const a = ld.dot(ld), b = 2 * lo.dot(ld), c = lo.dot(lo) - r * r;
    const disc = b * b - 4 * a * c;
    if (disc < 0) return null;
    const t = (-b - Math.sqrt(disc)) / (2 * a);
    if (t < 0 || t > 1) return null;
    const hp = lo.add(ld.mul(t));
    const n = cf.vec(hp.X, hp.Y, hp.Z).unit();
    return { t, n };
  }
  const he = [s.X / 2, s.Y / 2, s.Z / 2], O = [lo.X, lo.Y, lo.Z], D = [ld.X, ld.Y, ld.Z];
  let t0 = 0, t1 = 1, na = -1, ns = 0;
  for (let i = 0; i < 3; i++) {
    if (Math.abs(D[i]) < 1e-12) { if (O[i] < -he[i] || O[i] > he[i]) return null; continue; }
    let a = (-he[i] - O[i]) / D[i], b = (he[i] - O[i]) / D[i];
    let sg = -1;
    if (a > b) { const t = a; a = b; b = t; sg = 1; }
    if (a > t0) { t0 = a; na = i; ns = sg; }
    if (b < t1) t1 = b;
    if (t0 > t1) return null;
  }
  if (na < 0) return null;
  const ln = [0, 0, 0];
  ln[na] = ns;
  return { t: t0, n: cf.vec(ln[0], ln[1], ln[2]) };
}

// ===================================================================
// 全域
// ===================================================================
function installGlobals(rt) {
  const I = rt.I, G = I.G;
  const g = (n, f) => G.set(n, nat(n, f));
  G.set('game', rt.game); G.set('Game', rt.game);
  G.set('workspace', rt.workspace); G.set('Workspace', rt.workspace);
  G.set('Enum', ENUM_ROOT);
  G.set('shared', rt.I.shared);

  const ctor = (name, fns) => { const t = new LuaTable(); for (const k in fns) { const v = fns[k]; t.set(k, typeof v === 'function' ? nat(k, v) : v); } t.frozen = true; G.set(name, t); return t; };
  const num = (a, i, n, d) => checkNum(I, a, i, n, d);
  ctor('Vector3', {
    new: (a) => V3(num(a, 0, 'new', 0), num(a, 1, 'new', 0), num(a, 2, 'new', 0)),
    zero: V3(0, 0, 0), one: V3(1, 1, 1), xAxis: V3(1, 0, 0), yAxis: V3(0, 1, 0), zAxis: V3(0, 0, 1),
    FromNormalId: (a) => { const n = a[0] && a[0].Name; return { Right: V3(1, 0, 0), Left: V3(-1, 0, 0), Top: V3(0, 1, 0), Bottom: V3(0, -1, 0), Back: V3(0, 0, 1), Front: V3(0, 0, -1) }[n] || V3(); },
    FromAxis: (a) => { const n = a[0] && a[0].Name; return { X: V3(1, 0, 0), Y: V3(0, 1, 0), Z: V3(0, 0, 1) }[n] || V3(); },
  });
  ctor('Vector2', { new: (a) => new Vector2(num(a, 0, 'new', 0), num(a, 1, 'new', 0)), zero: new Vector2(0, 0), one: new Vector2(1, 1), xAxis: new Vector2(1, 0), yAxis: new Vector2(0, 1) });
  ctor('Vector3int16', { new: (a) => V3(Math.trunc(num(a, 0, 'new', 0)), Math.trunc(num(a, 1, 'new', 0)), Math.trunc(num(a, 2, 'new', 0))) });
  ctor('Color3', {
    new: (a) => new Color3(num(a, 0, 'new', 0), num(a, 1, 'new', 0), num(a, 2, 'new', 0)),
    fromRGB: (a) => Color3.rgb(num(a, 0, 'fromRGB', 0), num(a, 1, 'fromRGB', 0), num(a, 2, 'fromRGB', 0)),
    fromHSV: (a) => Color3.hsv(num(a, 0, 'fromHSV'), num(a, 1, 'fromHSV'), num(a, 2, 'fromHSV')),
    fromHex: (a) => { const h = checkStr(I, a, 0, 'fromHex').replace('#', ''); if (!/^[0-9a-fA-F]{6}$|^[0-9a-fA-F]{3}$/.test(h)) throw I.rtErr('Unable to convert characters to hex value'); const f = h.length === 3 ? h.split('').map(c => c + c).join('') : h; return Color3.rgb(parseInt(f.slice(0, 2), 16), parseInt(f.slice(2, 4), 16), parseInt(f.slice(4, 6), 16)); },
    toHSV: (a) => C3M.ToHSV([a[0]], I),
  });
  ctor('BrickColor', {
    new: (a) => {
      const v = a[0];
      if (typeof v === 'string') return BrickColor.byName(v);
      if (v instanceof Color3) return BrickColor.closest(v);
      if (typeof v === 'number' && a.length >= 3) return BrickColor.closest(Color3.rgb(v * 255, a[1] * 255, a[2] * 255));
      if (typeof v === 'number') return BrickColor.byNumber(v);
      return BrickColor.byNumber(194);
    },
    random: () => new BrickColor(BRICK_COLORS[Math.floor(Math.random() * BRICK_COLORS.length)]),
    palette: (a) => new BrickColor(BRICK_COLORS[(a[0] || 0) % BRICK_COLORS.length]),
    White: () => BrickColor.byName('White'), Gray: () => BrickColor.byName('Medium stone grey'), DarkGray: () => BrickColor.byName('Dark stone grey'),
    Black: () => BrickColor.byName('Black'), Red: () => BrickColor.byName('Bright red'), Yellow: () => BrickColor.byName('Bright yellow'),
    Green: () => BrickColor.byName('Dark green'), Blue: () => BrickColor.byName('Bright blue'),
  });
  ctor('CFrame', {
    new: (a) => {
      const n = a.length;
      if (n === 0) return new CFrame();
      if (a[0] instanceof Vector3) {
        if (a[1] instanceof Vector3) return CFrame.lookAt(a[0], a[1]);
        return new CFrame(a[0].X, a[0].Y, a[0].Z);
      }
      if (n >= 12) return new CFrame(num(a, 0, 'new'), num(a, 1, 'new'), num(a, 2, 'new'), a.slice(3, 12).map((x, i) => num(a, i + 3, 'new')));
      if (n === 7) return CFrame.fromQuat(num(a, 0, 'new'), num(a, 1, 'new'), num(a, 2, 'new'), num(a, 3, 'new'), num(a, 4, 'new'), num(a, 5, 'new'), num(a, 6, 'new'));
      return new CFrame(num(a, 0, 'new', 0), num(a, 1, 'new', 0), num(a, 2, 'new', 0));
    },
    Angles: (a) => CFrame.anglesXYZ(num(a, 0, 'Angles', 0), num(a, 1, 'Angles', 0), num(a, 2, 'Angles', 0)),
    fromEulerAnglesXYZ: (a) => CFrame.anglesXYZ(num(a, 0, 'fromEulerAnglesXYZ', 0), num(a, 1, 'fromEulerAnglesXYZ', 0), num(a, 2, 'fromEulerAnglesXYZ', 0)),
    fromEulerAnglesYXZ: (a) => CFrame.anglesYXZ(num(a, 0, 'fromEulerAnglesYXZ', 0), num(a, 1, 'fromEulerAnglesYXZ', 0), num(a, 2, 'fromEulerAnglesYXZ', 0)),
    fromOrientation: (a) => CFrame.anglesYXZ(num(a, 0, 'fromOrientation', 0), num(a, 1, 'fromOrientation', 0), num(a, 2, 'fromOrientation', 0)),
    fromAxisAngle: (a) => { const ax = argV3(I, a, 0, 'fromAxisAngle').unit(), t = num(a, 1, 'fromAxisAngle'); const s = Math.sin(t / 2); return CFrame.fromQuat(0, 0, 0, ax.X * s, ax.Y * s, ax.Z * s, Math.cos(t / 2)); },
    lookAt: (a) => CFrame.lookAt(argV3(I, a, 0, 'lookAt'), argV3(I, a, 1, 'lookAt'), a[2] instanceof Vector3 ? a[2] : undefined),
    lookAlong: (a) => { const p = argV3(I, a, 0, 'lookAlong'); return CFrame.lookAt(p, p.add(argV3(I, a, 1, 'lookAlong'))); },
    fromMatrix: (a) => { const p = a[0], x = a[1], y = a[2], z = a[3] || x.cross(y); return new CFrame(p.X, p.Y, p.Z, [x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z]); },
    identity: new CFrame(),
  });
  ctor('UDim', { new: (a) => new UDim(num(a, 0, 'new', 0), num(a, 1, 'new', 0)) });
  ctor('UDim2', {
    new: (a) => a[0] instanceof UDim ? new UDim2(a[0].Scale, a[0].Offset, a[1].Scale, a[1].Offset) : new UDim2(num(a, 0, 'new', 0), num(a, 1, 'new', 0), num(a, 2, 'new', 0), num(a, 3, 'new', 0)),
    fromScale: (a) => new UDim2(num(a, 0, 'fromScale', 0), 0, num(a, 1, 'fromScale', 0), 0),
    fromOffset: (a) => new UDim2(0, num(a, 0, 'fromOffset', 0), 0, num(a, 1, 'fromOffset', 0)),
  });
  ctor('NumberRange', { new: (a) => new NumberRange(num(a, 0, 'new'), a[1] === undefined ? undefined : num(a, 1, 'new')) });
  ctor('NumberSequence', { new: (a) => a[0] });
  ctor('ColorSequence', { new: (a) => a[0] });
  ctor('NumberSequenceKeypoint', { new: (a) => a[1] });
  ctor('ColorSequenceKeypoint', { new: (a) => a[1] });
  ctor('PhysicalProperties', { new: () => undefined });
  ctor('Ray', { new: (a) => new Ray(argV3(I, a, 0, 'new'), argV3(I, a, 1, 'new')) });
  ctor('TweenInfo', {
    new: (a) => new TweenInfo(num(a, 0, 'new', 1), a[1] instanceof EnumItem ? a[1] : E('EasingStyle', 'Quad'), a[2] instanceof EnumItem ? a[2] : E('EasingDirection', 'Out'), num(a, 3, 'new', 0), truthy(a[4]), num(a, 5, 'new', 0)),
  });
  ctor('RaycastParams', { new: () => new RaycastParams() });
  ctor('OverlapParams', { new: () => new RaycastParams() });
  ctor('Random', {
    new: (a) => {
      let seed = a[0] === undefined ? Math.floor(Math.random() * 2 ** 31) : num(a, 0, 'new');
      const st = { s: seed >>> 0 };
      const r = () => { st.s |= 0; st.s = st.s + 0x6D2B79F5 | 0; let t = Math.imul(st.s ^ st.s >>> 15, 1 | st.s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
      const obj = new LuaTable();
      obj.set('NextNumber', nat('NextNumber', (b) => { const lo = b[1] === undefined ? 0 : b[1], hi = b[2] === undefined ? 1 : b[2]; return lo + r() * (hi - lo); }));
      obj.set('NextInteger', nat('NextInteger', (b) => { const lo = num(b, 1, 'NextInteger'), hi = num(b, 2, 'NextInteger'); return lo + Math.floor(r() * (hi - lo + 1)); }));
      obj.set('NextUnitVector', nat('NextUnitVector', () => { const t = r() * Math.PI * 2, z = r() * 2 - 1, s = Math.sqrt(1 - z * z); return V3(s * Math.cos(t), s * Math.sin(t), z); }));
      obj.set('Shuffle', nat('Shuffle', (b) => { const t = b[1]; for (let i = t.arr.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [t.arr[i], t.arr[j]] = [t.arr[j], t.arr[i]]; } }));
      obj.set('Clone', nat('Clone', () => obj));
      return obj;
    },
  });
  ctor('Instance', {
    new: (a) => {
      const cn = checkStr(I, a, 0, 'new');
      const cls = CLASSES[cn];
      if (!cls) throw I.rtErr(`Unable to create an Instance of type "${cn}"`);
      if (cls.notCreatable || cls.service) throw I.rtErr(`Unable to create an Instance of type "${cn}"`);
      const inst = rt.new(cn);
      if (a[1] !== undefined) inst.setParent(argInst(I, a, 1, 'new'), I);
      return inst;
    },
    fromExisting: (a) => argInst(I, a, 0, 'fromExisting').clone(),
  });
  ctor('DateTime', { now: () => { const t = new LuaTable(); t.set('UnixTimestamp', Math.floor(Date.now() / 1000)); t.set('UnixTimestampMillis', Date.now()); return t; } });

  // ---- 排程 ----
  const waitG = function* (a) {
    const t = a[0] === undefined ? 0 : checkNum(I, a, 0, 'wait');
    const r = yield { k: 'wait', t };
    return r || [0, rt.time];
  };
  const fnOrThread = (a, n) => { const f = a[0]; if (luaType(f) === 'function' || f instanceof Coroutine) return f; throw I.argErr(0, n, `function or thread expected, got ${luauTypeof(f)}`); };
  const spawnNow = function* (f, args) {
    if (f instanceof Coroutine) {
      if (f.rthread) { const th = f.rthread; if (th.state === 'dead') return f; th.resume = args; th.state = 'ready'; rt.queue.unshift(th); return f; }
      const co = G.get('coroutine').get('resume');
      yield* co([f, ...args], I);
      return f;
    }
    const th = rt.newThread(f, args, 'task.spawn');
    for (;;) {
      const sig = rt.runThread(th);
      if (!sig) break;
      if (sig.k === 'pause') { yield sig; continue; }
      rt.handle(th, sig);
      break;
    }
    return th.handle;
  };
  const task = new LuaTable();
  const T = (n, f) => task.set(n, nat(n, f));
  T('wait', function* (a) { const t = a[0] === undefined ? 0 : checkNum(I, a, 0, 'wait'); const r = yield { k: 'wait', t }; return [r ? r[0] : 0]; });
  T('spawn', function* (a) { return yield* spawnNow(fnOrThread(a, 'spawn'), a.slice(1)); });
  T('defer', (a) => { const f = fnOrThread(a, 'defer'); if (f instanceof Coroutine && f.rthread) { f.rthread.state = 'ready'; f.rthread.resume = a.slice(1); rt.queue.push(f.rthread); return f; } const th = rt.newThread(f, a.slice(1), 'task.defer'); rt.queue.push(th); return th.handle; });
  T('delay', (a) => { const t = checkNum(I, a, 0, 'delay', 0); const f = a[1]; if (luaType(f) !== 'function') throw I.argErr(1, 'delay', `function expected, got ${luauTypeof(f)}`); return rt.callLater(f, a.slice(2), t).handle; });
  T('cancel', (a) => { const h = a[0]; if (h instanceof Coroutine) { if (h.rthread) h.rthread.state = 'dead'; h.status = 'dead'; } });
  T('synchronize', () => {}); T('desynchronize', () => {});
  G.set('task', task);
  g('wait', waitG);
  g('delay', (a) => { rt.callLater(a[1], [], checkNum(I, a, 0, 'delay', 0)); });
  g('spawn', (a) => { const th = rt.newThread(fnOrThread(a, 'spawn'), [], 'spawn'); th.state = 'wait'; th.waitStart = rt.time; th.wakeAt = rt.time; th.delayed = false; rt.sleepers.push(th); });
  g('tick', () => Date.now() / 1000);
  g('time', () => rt.time);
  g('elapsedTime', () => rt.time);
  g('settings', () => new LuaTable());
  g('UserSettings', () => new LuaTable());
  g('require', function* (a) {
    const m = a[0];
    if (typeof m === 'number') throw I.rtErr('require(資源ID) 需要連到 Roblox 伺服器，這個網頁版不支援；請改成 require(某個 ModuleScript)');
    if (!(m instanceof Instance) || m.ClassName !== 'ModuleScript') throw I.rtErr('Attempted to call require with invalid argument(s).');
    if (m.modState === 'done') return [m.modValue];
    if (m.modState === 'loading') throw I.rtErr('Requested module was required recursively');
    if (m.modState === 'error') throw I.rtErr('Requested module experienced an error while loading');
    m.modState = 'loading';
    const fn = rt.compileInst(m);
    if (!fn) { m.modState = 'error'; throw I.rtErr('Requested module experienced an error while loading'); }
    let r;
    try { r = yield* I.call(fn, []); }
    catch (e) { m.modState = 'error'; throw e; }
    if (r.length !== 1) { m.modState = 'error'; throw I.rtErr('Module code did not return exactly one value'); }
    m.modState = 'done'; m.modValue = r[0];
    return [r[0]];
  });
  g('printidentity', () => { rt.emit('print', 'Current identity is 2'); });
  g('version', () => '0.700.0.0');
  g('gcinfo', () => 1024);
  G.set('PluginManager', undefined);
  // 讓 debug.traceback 等常見呼叫不會出錯
  const dbg = new LuaTable();
  dbg.set('traceback', nat('traceback', (a) => { const msg = a[0] === undefined ? '' : I.tostr(a[0]) + '\n'; return msg + I.traceback().map(f => `${f.chunk}:${f.line}${f.name !== 'main chunk' ? ' function ' + f.name : ''}`).join('\n'); }));
  dbg.set('info', nat('info', () => [I.frame() ? I.frame().chunk : '', I.frame() ? I.frame().line : 0]));
  dbg.set('profilebegin', nat('profilebegin', () => {})); dbg.set('profileend', nat('profileend', () => {}));
  dbg.set('setmemorycategory', nat('setmemorycategory', () => {})); dbg.set('resetmemorycategory', nat('resetmemorycategory', () => {}));
  G.set('debug', dbg);
  G.set('buffer', new LuaTable());
}

function classMembers(name) {
  const c = CLASSES[name];
  if (!c) return null;
  const a = flat(c);
  return {
    props: [...new Set(['Name', 'Parent', 'ClassName', ...Object.keys(a.virt), ...Object.keys(a.props)])],
    methods: Object.keys(a.methods).filter(k => /^[A-Z]/.test(k)),
    events: [...a.events].filter(e => !e.includes(':')),
  };
}

return { Runtime, Instance, CLASSES, classMembers, Vector3, Vector2, Color3, CFrame, UDim, UDim2, BrickColor, EnumItem, ENUMS, Signal, aabb, halfExt, ease, lerpVal };
});
