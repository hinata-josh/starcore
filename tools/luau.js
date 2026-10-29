/* luau.js — 瀏覽器/Node 共用的 Luau 直譯器
 * 原始碼 → 詞法 → 語法樹 → 用 generator 走訪執行。
 * 每個敘述前都可以停下來(中斷點/單步)；task.wait、coroutine.yield 等「讓出」
 * 也都是 generator 的 yield，一路往外傳給排程器處理。
 */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Luau = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
'use strict';

// ===================================================================
// 值
// ===================================================================
class LuaTable {
  constructor() { this.hash = new Map(); this.arr = []; this.mt = null; this.frozen = false; }
  get(k) {
    if (typeof k === 'number') {
      const i = k - 1;
      if (i >= 0 && i < this.arr.length && (i | 0) === i) return this.arr[i];
    }
    return this.hash.get(k);
  }
  set(k, v) {
    if (typeof k === 'number' && Number.isInteger(k) && k >= 1) {
      const n = this.arr.length;
      if (k <= n) {
        if (v === undefined && k === n) {
          this.arr.pop();
          while (this.arr.length && this.arr[this.arr.length - 1] === undefined) this.arr.pop();
        } else this.arr[k - 1] = v;
        return;
      }
      if (k === n + 1) {
        if (v === undefined) { this.hash.delete(k); return; }
        this.arr.push(v); this.hash.delete(k);
        let nk = k + 1;
        while (this.hash.has(nk)) { this.arr.push(this.hash.get(nk)); this.hash.delete(nk); nk++; }
        return;
      }
    }
    if (v === undefined) this.hash.delete(k); else this.hash.set(k, v);
  }
  length() { return this.arr.length; }
  keyList() {
    const ks = [];
    for (let i = 0; i < this.arr.length; i++) if (this.arr[i] !== undefined) ks.push(i + 1);
    for (const k of this.hash.keys()) ks.push(k);
    return ks;
  }
  static from(arr) { const t = new LuaTable(); for (const v of arr) t.arr.push(v); while (t.arr.length && t.arr[t.arr.length - 1] === undefined) t.arr.pop(); return t; }
  static fromObject(o) { const t = new LuaTable(); for (const k in o) t.set(k, o[k]); return t; }
}

class LuaFunction {
  constructor(node, scope, name) { this.node = node; this.scope = scope; this.name = name || node.name || 'anonymous'; }
}

class Coroutine {
  constructor(fn) { this.fn = fn; this.gen = null; this.status = 'suspended'; this.stack = []; this.stack.pcall = 0; }
}

class LuaError extends Error {
  constructor(value, traceback, line, chunk) {
    super(typeof value === 'string' ? value : 'error object');
    this.value = value; this.traceback = traceback || []; this.luaLine = line; this.chunk = chunk;
  }
}

const GenFn = Object.getPrototypeOf(function* () {}).constructor;
function nat(name, fn) { fn.luaName = name; fn.isGen = fn instanceof GenFn; return fn; }

function truthy(v) { return v !== undefined && v !== null && v !== false; }

function luaType(v) {
  if (v === undefined || v === null) return 'nil';
  switch (typeof v) {
    case 'boolean': return 'boolean';
    case 'number': return 'number';
    case 'string': return 'string';
    case 'function': return 'function';
  }
  if (v instanceof LuaTable) return 'table';
  if (v instanceof LuaFunction) return 'function';
  if (v instanceof Coroutine) return 'thread';
  return 'userdata';
}
function luauTypeof(v) {
  const t = luaType(v);
  if (t === 'userdata') return v.luaType || 'userdata';
  return t;
}

function numToStr(n) {
  if (n === Infinity) return 'inf';
  if (n === -Infinity) return '-inf';
  if (n !== n) return 'nan';
  if (Object.is(n, -0)) return '-0';
  if (Number.isInteger(n) && Math.abs(n) < 1e15) return String(n);
  let s = String(n);
  if (Number.isInteger(n) && !/e/.test(s)) s = n.toExponential().replace(/\.?0+e/, 'e');
  return s.replace(/e([+-])(\d)$/, 'e$10$2');
}

function str2num(s) {
  s = s.trim();
  let m = /^([+-]?)0[xX]([0-9a-fA-F]+)$/.exec(s);
  if (m) { const v = parseInt(m[2], 16); return m[1] === '-' ? -v : v; }
  if (/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s)) return parseFloat(s);
  return undefined;
}

// ===================================================================
// 詞法分析
// ===================================================================
const KEYWORDS = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in',
  'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);
const OPS3 = ['...', '..=', '//='];
const OPS2 = ['==', '~=', '<=', '>=', '//', '..', '+=', '-=', '*=', '/=', '%=', '^=', '::', '->'];
const OPS1 = '+-*/%^#&~|<>=(){}[];:,.?@';
const NUM_RE = /0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:[0-9][0-9_]*(?:\.[0-9_]*)?|\.[0-9][0-9_]*)(?:[eE][+-]?[0-9_]+)?/y;

function synErr(msg, line) { const e = new Error(msg); e.isSyntax = true; e.luaLine = line; return e; }

function longLevel(src, i) {
  let j = i + 1, lv = 0;
  while (src[j] === '=') { lv++; j++; }
  return src[j] === '[' ? lv : -1;
}
function readLong(src, i, lv, line, what) {
  let j = i + lv + 2;
  if (src[j] === '\r') j++;
  if (src[j] === '\n') { j++; line++; }
  const close = ']' + '='.repeat(lv) + ']';
  const k = src.indexOf(close, j);
  if (k < 0) throw synErr(`unfinished long ${what}`, line);
  const text = src.slice(j, k);
  for (let x = 0; x < text.length; x++) if (text[x] === '\n') line++;
  return { text, end: k + close.length, line };
}
function readEscape(src, j, line) {
  const d = src[j + 1];
  switch (d) {
    case 'n': return { s: '\n', end: j + 2, line };
    case 't': return { s: '\t', end: j + 2, line };
    case 'r': return { s: '\r', end: j + 2, line };
    case 'a': return { s: '\x07', end: j + 2, line };
    case 'b': return { s: '\b', end: j + 2, line };
    case 'f': return { s: '\f', end: j + 2, line };
    case 'v': return { s: '\v', end: j + 2, line };
    case '\\': case '"': case "'": case '`': case '{': case '}': return { s: d, end: j + 2, line };
    case '\n': return { s: '\n', end: j + 2, line: line + 1 };
    case '\r': return { s: '\n', end: src[j + 2] === '\n' ? j + 3 : j + 2, line: line + 1 };
    case 'z': {
      let k = j + 2;
      while (k < src.length && /\s/.test(src[k])) { if (src[k] === '\n') line++; k++; }
      return { s: '', end: k, line };
    }
    case 'x': {
      const h = src.substr(j + 2, 2);
      if (!/^[0-9a-fA-F]{2}$/.test(h)) throw synErr('invalid hexadecimal escape sequence', line);
      return { s: String.fromCharCode(parseInt(h, 16)), end: j + 4, line };
    }
    case 'u': {
      const m = /^\{([0-9a-fA-F]+)\}/.exec(src.slice(j + 2, j + 14));
      if (!m) throw synErr('invalid unicode escape sequence', line);
      return { s: String.fromCodePoint(parseInt(m[1], 16)), end: j + 2 + m[0].length, line };
    }
    default: {
      const m = /^[0-9]{1,3}/.exec(src.slice(j + 1, j + 4));
      if (m) {
        const v = parseInt(m[0], 10);
        if (v > 255) throw synErr('escape sequence too large', line);
        return { s: String.fromCharCode(v), end: j + 1 + m[0].length, line };
      }
      throw synErr(`invalid escape sequence '\\${d === undefined ? '' : d}'`, line);
    }
  }
}

function lex(src, line0) {
  src = src.replace(/\r\n?/g, '\n');
  const toks = [];
  let i = 0, line = line0 || 1;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === '\n') { line++; i++; continue; }
    if (c === ' ' || c === '\t' || c === '\r' || c === '\f' || c === '\v' || c === '﻿') { i++; continue; }
    if (c === '-' && src[i + 1] === '-') {
      i += 2;
      if (src[i] === '[') {
        const lv = longLevel(src, i);
        if (lv >= 0) { const r = readLong(src, i, lv, line, 'comment'); i = r.end; line = r.line; continue; }
      }
      while (i < n && src[i] !== '\n') i++;
      continue;
    }
    const L = line;
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_') {
      let j = i + 1;
      while (j < n && /[A-Za-z0-9_]/.test(src[j])) j++;
      const w = src.slice(i, j);
      toks.push({ t: KEYWORDS.has(w) ? 'kw' : 'name', v: w, line: L });
      i = j; continue;
    }
    if ((c >= '0' && c <= '9') || (c === '.' && src[i + 1] >= '0' && src[i + 1] <= '9')) {
      NUM_RE.lastIndex = i;
      const m = NUM_RE.exec(src);
      const text = m[0], clean = text.replace(/_/g, '');
      let v;
      if (/^0[xX]/.test(clean)) v = parseInt(clean.slice(2), 16);
      else if (/^0[bB]/.test(clean)) v = parseInt(clean.slice(2), 2);
      else v = parseFloat(clean);
      i += text.length;
      if (i < n && /[A-Za-z_.]/.test(src[i]) && !(src[i] === '.' && src[i + 1] === '.')) throw synErr(`malformed number near '${text}${src[i]}'`, L);
      toks.push({ t: 'num', v, line: L });
      continue;
    }
    if (c === '"' || c === "'") {
      let j = i + 1, out = '';
      for (;;) {
        if (j >= n) throw synErr('unfinished string', L);
        const ch = src[j];
        if (ch === c) { j++; break; }
        if (ch === '\n') throw synErr('unfinished string', L);
        if (ch === '\\') { const r = readEscape(src, j, line); out += r.s; j = r.end; line = r.line; continue; }
        out += ch; j++;
      }
      toks.push({ t: 'str', v: out, line: L });
      i = j; continue;
    }
    if (c === '[') {
      const lv = longLevel(src, i);
      if (lv >= 0) {
        const r = readLong(src, i, lv, line, 'string');
        toks.push({ t: 'str', v: r.text, line: L });
        i = r.end; line = r.line; continue;
      }
    }
    if (c === '`') {
      let j = i + 1, cur = '';
      const parts = [];
      for (;;) {
        if (j >= n) throw synErr('unfinished interpolated string', L);
        const ch = src[j];
        if (ch === '`') { j++; break; }
        if (ch === '\n') throw synErr('unfinished interpolated string', L);
        if (ch === '\\') { const r = readEscape(src, j, line); cur += r.s; j = r.end; line = r.line; continue; }
        if (ch === '{') {
          if (cur) parts.push(cur);
          cur = '';
          let depth = 1, k = j + 1;
          const exprLine = line;
          while (k < n) {
            const x = src[k];
            if (x === '{') depth++;
            else if (x === '}') { depth--; if (depth === 0) break; }
            else if (x === '"' || x === "'") { k++; while (k < n && src[k] !== x) { if (src[k] === '\\') k++; k++; } }
            else if (x === '\n') line++;
            k++;
          }
          if (depth > 0) throw synErr('unfinished interpolated string expression', exprLine);
          const exprSrc = src.slice(j + 1, k);
          if (!exprSrc.trim()) throw synErr('malformed interpolated string, expected expression inside {}', exprLine);
          parts.push({ src: exprSrc, line: exprLine });
          j = k + 1; continue;
        }
        cur += ch; j++;
      }
      if (cur || !parts.length) parts.push(cur);
      toks.push({ t: 'istr', v: parts, line: L });
      i = j; continue;
    }
    const s3 = src.substr(i, 3), s2 = src.substr(i, 2);
    if (OPS3.includes(s3)) { toks.push({ t: 'op', v: s3, line: L }); i += 3; continue; }
    if (OPS2.includes(s2)) { toks.push({ t: 'op', v: s2, line: L }); i += 2; continue; }
    if (OPS1.includes(c)) { toks.push({ t: 'op', v: c, line: L }); i++; continue; }
    throw synErr(`unexpected symbol '${c}'`, L);
  }
  toks.push({ t: 'eof', v: '<eof>', line });
  return toks;
}

// ===================================================================
// 語法分析
// ===================================================================
const BINPRI = {
  'or': [1, 1], 'and': [2, 2],
  '<': [3, 3], '>': [3, 3], '<=': [3, 3], '>=': [3, 3], '~=': [3, 3], '==': [3, 3],
  '..': [9, 8], '+': [10, 10], '-': [10, 10],
  '*': [11, 11], '/': [11, 11], '//': [11, 11], '%': [11, 11],
  '^': [14, 13],
};
const UNARY_PRI = 12;
const COMPOUND = { '+=': '+', '-=': '-', '*=': '*', '/=': '/', '//=': '//', '%=': '%', '^=': '^', '..=': '..' };

class Parser {
  constructor(toks, chunk) { this.toks = toks; this.p = 0; this.chunk = chunk; }
  get tok() { return this.toks[this.p]; }
  peek(o = 1) { return this.toks[Math.min(this.p + o, this.toks.length - 1)]; }
  next() { return this.toks[this.p++]; }
  is(v) { const t = this.tok; return (t.t === 'op' || t.t === 'kw') && t.v === v; }
  accept(v) { if (this.is(v)) { this.p++; return true; } return false; }
  near() { const t = this.tok; return t.t === 'eof' ? '<eof>' : t.t === 'str' ? `'"${t.v}"'` : t.t === 'istr' ? "'`string`'" : `'${t.v}'`; }
  err(msg, line) { throw synErr(msg, line === undefined ? this.tok.line : line); }
  expect(v, open) {
    if (this.accept(v)) return;
    if (open && open.line !== this.tok.line) this.err(`Expected '${v}' (to close '${open.v}' at line ${open.line}), got ${this.near()}`);
    this.err(`Expected '${v}'${open ? ` (to close '${open.v}')` : ''}, got ${this.near()}`);
  }
  name() {
    const t = this.tok;
    if (t.t !== 'name') this.err(`Expected identifier, got ${this.near()}`);
    this.p++; return t.v;
  }

  parseChunk() {
    const body = this.block();
    if (this.tok.t !== 'eof') this.err(`Expected <eof>, got ${this.near()}${this.is('end') ? ' — 多了一個 end？(或是上面少了 function/if/for/while/do)' : ''}`);
    return { k: 'Function', params: [], isVararg: true, body, name: 'main chunk', line: 0, chunk: this.chunk, main: true };
  }
  blockEnd() {
    const t = this.tok;
    return t.t === 'eof' || (t.t === 'kw' && (t.v === 'end' || t.v === 'else' || t.v === 'elseif' || t.v === 'until'));
  }
  block() {
    const body = [];
    while (!this.blockEnd()) {
      if (this.is('return')) {
        const line = this.next().line;
        let exprs = [];
        if (!this.blockEnd() && !this.is(';')) exprs = this.exprlist();
        this.accept(';');
        body.push({ k: 'Return', exprs, line });
        if (!this.blockEnd()) this.err(`Expected 'end' after 'return' (return must be the last statement), got ${this.near()}`);
        break;
      }
      const s = this.statement();
      if (s) body.push(s);
    }
    return body;
  }
  statement() {
    const t = this.tok, line = t.line;
    if (this.accept(';')) return null;
    if (t.t === 'op' && t.v === '@') { this.next(); this.name(); return null; }
    if (t.t === 'kw') {
      switch (t.v) {
        case 'if': return this.ifstat();
        case 'while': {
          this.next();
          const cond = this.expr();
          this.expect('do');
          const body = this.block();
          this.expect('end', t);
          return { k: 'While', cond, body, line };
        }
        case 'do': { this.next(); const body = this.block(); this.expect('end', t); return { k: 'Do', body, line }; }
        case 'for': return this.forstat();
        case 'repeat': {
          this.next();
          const body = this.block();
          this.expect('until', t);
          const cond = this.expr();
          return { k: 'Repeat', body, cond, line };
        }
        case 'function': {
          this.next();
          let target = { k: 'Name', name: this.name(), line };
          let fname = target.name, isMethod = false;
          while (this.is('.') || this.is(':')) {
            const sep = this.next().v;
            const key = this.name();
            fname += sep + key;
            target = { k: 'Index', obj: target, key: { k: 'Str', v: key }, line };
            if (sep === ':') { isMethod = true; break; }
          }
          const fn = this.funcbody(t, fname, isMethod);
          return { k: 'FuncStat', target, fn, line };
        }
        case 'local': {
          this.next();
          if (this.is('function')) {
            const ft = this.next();
            const name = this.name();
            const fn = this.funcbody(ft, name, false);
            return { k: 'LocalFunc', name, fn, line };
          }
          const names = [this.name()];
          this.attrib(); this.optType();
          while (this.accept(',')) { names.push(this.name()); this.attrib(); this.optType(); }
          let exprs = [];
          if (this.accept('=')) exprs = this.exprlist();
          return { k: 'Local', names, exprs, line };
        }
        case 'break': this.next(); return { k: 'Break', line };
      }
    }
    if (t.t === 'name') {
      if (t.v === 'continue' && this.isContinue()) { this.next(); return { k: 'Continue', line }; }
      if (t.v === 'type' && this.peek().t === 'name') { this.next(); this.typeAlias(); return null; }
      if (t.v === 'export' && this.peek().t === 'name' && this.peek().v === 'type') { this.next(); this.next(); this.typeAlias(); return null; }
    }
    return this.exprstat();
  }
  isContinue() {
    const nx = this.peek();
    return nx.t === 'kw' || nx.t === 'eof' || (nx.t === 'op' && nx.v === ';') || nx.line > this.tok.line;
  }
  attrib() { if (this.is('<') && this.peek().t === 'name' && this.peek(2).t === 'op' && this.peek(2).v === '>') { this.p += 3; } }
  ifstat() {
    const open = this.next();
    const clauses = [];
    let cond = this.expr();
    this.expect('then');
    clauses.push({ cond, body: this.block(), line: open.line });
    let orelse = null;
    for (;;) {
      if (this.is('elseif')) {
        const l = this.next().line;
        cond = this.expr(); this.expect('then');
        clauses.push({ cond, body: this.block(), line: l });
      } else if (this.accept('else')) { orelse = this.block(); this.expect('end', open); break; }
      else { this.expect('end', open); break; }
    }
    return { k: 'If', clauses, orelse, line: open.line };
  }
  forstat() {
    const open = this.next(), line = open.line;
    const n1 = this.name();
    this.optType();
    if (this.accept('=')) {
      const start = this.expr();
      this.expect(',');
      const limit = this.expr();
      const step = this.accept(',') ? this.expr() : null;
      this.expect('do');
      const body = this.block();
      this.expect('end', open);
      return { k: 'NumFor', name: n1, start, limit, step, body, line };
    }
    const names = [n1];
    while (this.accept(',')) { names.push(this.name()); this.optType(); }
    this.expect('in');
    const exprs = this.exprlist();
    this.expect('do');
    const body = this.block();
    this.expect('end', open);
    return { k: 'GenFor', names, exprs, body, line };
  }
  funcbody(open, name, isMethod) {
    if (this.is('<')) this.skipBalanced('<', '>');
    const params = isMethod ? ['self'] : [];
    let isVararg = false;
    this.expect('(');
    if (!this.is(')')) {
      do {
        if (this.accept('...')) { isVararg = true; this.optType(); break; }
        params.push(this.name());
        this.optType();
      } while (this.accept(','));
    }
    this.expect(')');
    if (this.accept(':')) this.parseType();
    const body = this.block();
    const endLine = this.tok.line;
    this.expect('end', open);
    return { k: 'Function', params, isVararg, body, name, line: open.line, endLine, chunk: this.chunk, hc: false };
  }
  exprstat() {
    const line = this.tok.line;
    const e = this.suffixedexp();
    if (this.is('=') || this.is(',')) {
      const targets = [e];
      while (this.accept(',')) targets.push(this.suffixedexp());
      this.expect('=');
      const exprs = this.exprlist();
      for (const t of targets) if (t.k !== 'Name' && t.k !== 'Index') this.err('Assigned expression must be a variable or a field', line);
      return { k: 'Assign', targets, exprs, line };
    }
    const t = this.tok;
    if (t.t === 'op' && COMPOUND[t.v]) {
      this.next();
      if (e.k !== 'Name' && e.k !== 'Index') this.err('Assigned expression must be a variable or a field', line);
      const expr = this.expr();
      return { k: 'Compound', target: e, op: COMPOUND[t.v], expr, line };
    }
    if (e.k !== 'Call' && e.k !== 'MethodCall') {
      if (t.t === 'op' && t.v === '==') this.err(`Expected '=' (assignment), got '==' — 比較要放在 if 裡，指定值用單一個 =`, line);
      this.err(`Incomplete statement: expected assignment or a function call`, line);
    }
    return { k: 'CallStat', call: e, line };
  }
  exprlist() { const l = [this.expr()]; while (this.accept(',')) l.push(this.expr()); return l; }
  expr(limit = 0) {
    let left;
    const t = this.tok;
    if ((t.t === 'kw' && t.v === 'not') || (t.t === 'op' && (t.v === '-' || t.v === '#'))) {
      this.next();
      const e = this.expr(UNARY_PRI);
      if (t.v === '-' && e.k === 'Num') left = { k: 'Num', v: -e.v, line: t.line };
      else left = { k: 'Unop', op: t.v, e, line: t.line, hc: e.hc };
    } else left = this.simpleexp();
    for (;;) {
      const op = this.tok;
      if (!((op.t === 'op' || op.t === 'kw') && BINPRI[op.v])) break;
      const pr = BINPRI[op.v];
      if (pr[0] <= limit) break;
      this.next();
      const right = this.expr(pr[1]);
      left = { k: 'Binop', op: op.v, l: left, r: right, line: op.line, hc: left.hc || right.hc };
    }
    return left;
  }
  simpleexp() {
    const t = this.tok;
    let e;
    switch (t.t) {
      case 'num': this.next(); e = { k: 'Num', v: t.v }; break;
      case 'str': this.next(); e = { k: 'Str', v: t.v }; break;
      case 'istr': {
        this.next();
        const parts = [];
        let hc = false;
        for (const p of t.v) {
          if (typeof p === 'string') { parts.push(p); continue; }
          const sub = new Parser(lex(p.src, p.line), this.chunk);
          const ex = sub.expr();
          if (sub.tok.t !== 'eof') sub.err(`Expected '}' in interpolated string, got ${sub.near()}`);
          parts.push(ex); hc = hc || ex.hc;
        }
        e = { k: 'Interp', parts, hc, line: t.line };
        break;
      }
      case 'kw':
        if (t.v === 'nil') { this.next(); e = { k: 'Nil' }; break; }
        if (t.v === 'true') { this.next(); e = { k: 'True' }; break; }
        if (t.v === 'false') { this.next(); e = { k: 'False' }; break; }
        if (t.v === 'function') { this.next(); e = this.funcbody(t, `<anonymous:${t.line}>`, false); break; }
        if (t.v === 'if') { e = this.ifexpr(); break; }
        e = this.suffixedexp(); break;
      case 'op':
        if (t.v === '...') { this.next(); e = { k: 'Vararg' }; break; }
        if (t.v === '{') { e = this.table(); break; }
        e = this.suffixedexp(); break;
      default: e = this.suffixedexp();
    }
    if (this.accept('::')) this.parseType();
    return e;
  }
  ifexpr() {
    const open = this.next();
    const clauses = [];
    let hc = false;
    const cond = this.expr(); this.expect('then');
    const val = this.expr();
    clauses.push({ cond, val }); hc = cond.hc || val.hc;
    while (this.accept('elseif')) {
      const c = this.expr(); this.expect('then'); const v = this.expr();
      clauses.push({ cond: c, val: v }); hc = hc || c.hc || v.hc;
    }
    if (!this.accept('else')) this.err(`Expected 'else' in if-expression (if-expression must have an else branch), got ${this.near()}`);
    const orelse = this.expr();
    return { k: 'IfExpr', clauses, orelse, hc: hc || orelse.hc, line: open.line };
  }
  primaryexp() {
    const t = this.tok;
    if (t.t === 'name') { this.next(); return { k: 'Name', name: t.v, line: t.line }; }
    if (this.is('(')) {
      this.next();
      const e = this.expr();
      this.expect(')', t);
      return { k: 'Paren', e, hc: e.hc, line: t.line };
    }
    if (t.t === 'kw' && t.v === 'end') this.err(`Unexpected 'end' — 可能多了一個 end，或少了 function/if/for/while 開頭`);
    this.err(`Expected identifier when parsing expression, got ${this.near()}`);
  }
  suffixedexp() {
    let e = this.primaryexp();
    for (;;) {
      const t = this.tok;
      if (t.t === 'op') {
        if (t.v === '.') {
          this.next();
          const key = this.name();
          e = { k: 'Index', obj: e, key: { k: 'Str', v: key }, line: t.line, hc: e.hc };
          continue;
        }
        if (t.v === '[') {
          this.next();
          const key = this.expr();
          this.expect(']', t);
          e = { k: 'Index', obj: e, key, line: t.line, hc: e.hc || key.hc };
          continue;
        }
        if (t.v === ':') {
          this.next();
          const name = this.name();
          const args = this.callargs();
          e = { k: 'MethodCall', obj: e, name, args, line: t.line, hc: true };
          continue;
        }
        if (t.v === '(' || t.v === '{') {
          const args = this.callargs();
          e = { k: 'Call', fn: e, args, line: t.line, hc: true };
          continue;
        }
      } else if (t.t === 'str' || t.t === 'istr') {
        const args = this.callargs();
        e = { k: 'Call', fn: e, args, line: t.line, hc: true };
        continue;
      }
      return e;
    }
  }
  callargs() {
    const t = this.tok;
    if (t.t === 'str') { this.next(); return [{ k: 'Str', v: t.v }]; }
    if (t.t === 'istr') return [this.simpleexp()];
    if (this.is('{')) return [this.table()];
    if (this.is('(')) {
      this.next();
      if (this.accept(')')) return [];
      const args = this.exprlist();
      this.expect(')', t);
      return args;
    }
    this.err(`Expected function arguments, got ${this.near()}`);
  }
  table() {
    const open = this.next();
    const items = [];
    let hc = false;
    while (!this.is('}')) {
      if (this.is('[')) {
        const b = this.next();
        const key = this.expr();
        this.expect(']', b);
        this.expect('=');
        const value = this.expr();
        items.push({ type: 'keyed', key, value }); hc = hc || key.hc || value.hc;
      } else if (this.tok.t === 'name' && this.peek().t === 'op' && this.peek().v === '=') {
        const key = this.name(); this.next();
        const value = this.expr();
        items.push({ type: 'named', key, value }); hc = hc || value.hc;
      } else {
        const value = this.expr();
        items.push({ type: 'pos', value }); hc = hc || value.hc;
      }
      if (!this.accept(',') && !this.accept(';')) break;
    }
    this.expect('}', open);
    return { k: 'Table', items, hc, line: open.line };
  }

  // ---- 型別註記：只解析、不檢查 ----
  optType() { if (this.accept(':')) this.parseType(); }
  typeAlias() {
    this.name();
    if (this.is('<')) this.skipBalanced('<', '>');
    this.expect('=');
    this.parseType();
  }
  skipBalanced(open, close) {
    let depth = 0;
    do {
      if (this.tok.t === 'eof') this.err(`Expected '${close}', got <eof>`);
      if (this.is(open)) depth++;
      else if (this.is(close)) depth--;
      this.next();
    } while (depth > 0);
  }
  parseType() {
    this.accept('|') || this.accept('&');
    this.typeSimple();
    for (;;) {
      if (this.accept('?')) continue;
      if (this.accept('|') || this.accept('&')) { this.typeSimple(); continue; }
      break;
    }
  }
  typeSimple() {
    const t = this.tok;
    if (this.is('(')) { this.skipBalanced('(', ')'); if (this.accept('->')) this.parseType(); return; }
    if (this.is('<')) { this.skipBalanced('<', '>'); this.typeSimple(); return; }
    if (this.is('{')) { this.skipBalanced('{', '}'); return; }
    if (this.accept('...')) { this.typeSimple(); return; }
    if (t.t === 'str' || (t.t === 'kw' && (t.v === 'nil' || t.v === 'true' || t.v === 'false'))) { this.next(); return; }
    if (t.t === 'name') {
      this.next();
      if (t.v === 'typeof' && this.is('(')) { this.skipBalanced('(', ')'); return; }
      while (this.accept('.')) this.name();
      if (this.is('<')) this.skipBalanced('<', '>');
      return;
    }
    this.err(`Expected type, got ${this.near()}`);
  }
}

function parse(src, chunk) { return new Parser(lex(src), chunk || 'chunk').parseChunk(); }
function parseExpr(src) {
  const p = new Parser(lex(src), 'watch');
  const e = p.expr();
  if (p.tok.t !== 'eof') p.err(`Expected <eof>, got ${p.near()}`);
  return e;
}

// ===================================================================
// Lua pattern → JS RegExp
// ===================================================================
const PCLASS = { a: 'A-Za-z', d: '0-9', l: 'a-z', s: ' \\t\\n\\r\\f\\v', u: 'A-Z', w: 'A-Za-z0-9', x: '0-9A-Fa-f', p: '!-\\/:-@\\[-`{-~', c: '\\x00-\\x1f\\x7f', g: '!-~' };
function reEsc(c) { return /[\\^$.*+?()[\]{}|\/-]/.test(c) ? '\\' + c : c; }
function setEsc(c) { return /[\\\]\[^-]/.test(c) ? '\\' + c : c; }
const patCache = new Map();
function compilePat(pat, I) {
  let P = patCache.get(pat);
  if (P) return P;
  let re = '', i = 0, anchored = false, caps = 0;
  const n = pat.length, posCaps = [];
  const bad = (m) => { throw I.rtErr(`malformed pattern (${m})`); };
  const readSet = (j) => {
    j++;
    let neg = false, out = '', first = true;
    if (pat[j] === '^') { neg = true; j++; }
    while (j < n && (pat[j] !== ']' || first)) {
      first = false;
      const c = pat[j];
      if (c === '%') {
        const d = pat[j + 1];
        if (d === undefined) bad("ends with '%'");
        const lo = d.toLowerCase();
        if (PCLASS[lo] && d === lo) out += PCLASS[d];
        else if (PCLASS[lo]) out += d === 'S' ? '\\S' : d === 'D' ? '\\D' : d === 'W' ? '\\W' : '';
        else out += setEsc(d);
        j += 2;
      } else if (pat[j + 1] === '-' && j + 2 < n && pat[j + 2] !== ']') {
        out += setEsc(c) + '-' + setEsc(pat[j + 2]); j += 3;
      } else { out += setEsc(c); j++; }
    }
    if (j >= n) bad("missing ']'");
    return [`[${neg ? '^' : ''}${out}]`, j + 1];
  };
  if (pat[0] === '^') { anchored = true; i = 1; }
  while (i < n) {
    const c = pat[i];
    let atom;
    if (c === '(') {
      caps++;
      if (pat[i + 1] === ')') { posCaps.push(caps); re += '()'; i += 2; continue; }
      re += '('; i++; continue;
    }
    if (c === ')') { re += ')'; i++; continue; }
    if (c === '$' && i === n - 1) { re += '$'; i++; continue; }
    if (c === '%') {
      const d = pat[i + 1];
      if (d === undefined) bad("ends with '%'");
      if (d === 'b') throw I.rtErr('pattern item %b is not supported in this editor');
      if (d === 'f') {
        if (pat[i + 2] !== '[') bad("missing '[' after '%f' in pattern");
        const [set, j] = readSet(i + 2);
        re += `(?<!${set})(?=${set})`; i = j; continue;
      }
      if (d >= '0' && d <= '9') atom = '\\' + d;
      else {
        const lo = d.toLowerCase();
        if (PCLASS[lo]) atom = d === lo ? `[${PCLASS[d]}]` : `[^${PCLASS[lo]}]`;
        else atom = reEsc(d);
      }
      i += 2;
    } else if (c === '[') { const r = readSet(i); atom = r[0]; i = r[1]; }
    else if (c === '.') { atom = '[\\s\\S]'; i++; }
    else { atom = reEsc(c); i++; }
    const q = pat[i];
    if (q === '*' || q === '+' || q === '?') { atom += q; i++; }
    else if (q === '-') { atom += '*?'; i++; }
    re += atom;
  }
  P = { re, anchored, posCaps };
  try { new RegExp(re); } catch (e) { bad(e.message); }
  if (patCache.size > 500) patCache.clear();
  patCache.set(pat, P);
  return P;
}
function patCaps(m, P) {
  const out = [];
  for (let g = 1; g < m.length; g++) out.push(P.posCaps.includes(g) ? m.indices[g][0] + 1 : m[g]);
  return out;
}

// ===================================================================
// 直譯器
// ===================================================================
const BREAK = { k: 'break' }, CONTINUE = { k: 'continue' }, YBUDGET = { k: 'budget' };
const ARITH_EVENT = { '+': '__add', '-': '__sub', '*': '__mul', '/': '__div', '%': '__mod', '^': '__pow', '//': '__idiv' };
const ARITH_NAME = { '+': 'add', '-': 'sub', '*': 'mul', '/': 'div', '%': 'mod', '^': 'pow', '//': 'idiv' };

class Scope {
  constructor(parent, fnRoot, env) {
    this.vars = new Map(); this.parent = parent; this.fnRoot = fnRoot;
    this.env = env || (parent && parent.env); this.varargs = null;
  }
}

class Interp {
  constructor(opts = {}) {
    this.G = new LuaTable();
    this.shared = new LuaTable();
    this.stack = []; this.stack.pcall = 0;
    this.dbg = { active: false, mode: 'run', bps: new Map(), breakOnError: false, depth: 0, stack: null, lastLine: -1, lastFrame: null };
    this.steps = 0; this.budget = 4000; this.noYield = 0;
    this.output = opts.output || ((kind, text) => console.log(text));
    this.curCo = null;
    this.ids = new WeakMap(); this.nextId = 0x5e1a0;
    this.maxDepth = opts.maxDepth || 8000;
    this.rand = mulberry(Date.now() >>> 0);
    installStdlib(this);
  }

  // ---------- 編譯 ----------
  newEnv() { return new LuaTable(); }
  compile(src, chunk, env, locals) {
    const node = parse(src, chunk);
    const root = new Scope(null, true, env || this.newEnv());
    root.isRoot = true;
    if (locals) for (const k in locals) root.vars.set(k, locals[k]);
    return new LuaFunction(node, root, 'main chunk');
  }

  // ---------- 錯誤 ----------
  frame() { return this.stack[this.stack.length - 1]; }
  where() { const f = this.frame(); return f ? `${f.chunk}:${f.line}: ` : ''; }
  rtErr(msg) {
    const f = this.frame();
    return new LuaError(this.where() + msg, this.traceback(), f && f.line, f && f.chunk);
  }
  argErr(i, fname, msg) { return this.rtErr(`invalid argument #${i + 1} to '${fname}' (${msg})`); }
  traceback() {
    const out = [];
    for (let i = this.stack.length - 1; i >= 0; i--) { const f = this.stack[i]; out.push({ chunk: f.chunk, line: f.line, name: f.name }); }
    return out;
  }
  wrapJsError(e) {
    if (e instanceof LuaError) return e;
    if (e instanceof RangeError) return this.rtErr('stack overflow (遞迴太深了？檢查函式是不是一直呼叫自己)');
    if (e && e.isSyntax) return new LuaError(this.where() + e.message, this.traceback());
    return this.rtErr('internal error: ' + (e && e.message || e));
  }

  // ---------- 值操作 ----------
  addr(v) {
    let id = this.ids.get(v);
    if (!id) { id = (this.nextId += 0x38); this.ids.set(v, id); }
    return '0x' + id.toString(16).padStart(16, '0');
  }
  tostr(v) {
    switch (typeof v) {
      case 'undefined': return 'nil';
      case 'boolean': return v ? 'true' : 'false';
      case 'number': return numToStr(v);
      case 'string': return v;
      case 'function': return 'function: ' + this.addr(v);
    }
    if (v === null) return 'nil';
    if (v instanceof LuaTable) {
      if (v.mt) {
        const h = v.mt.get('__tostring');
        if (h !== undefined) {
          const r = this.callSync(h, [v])[0];
          if (typeof r !== 'string') throw this.rtErr("'__tostring' must return a string");
          return r;
        }
      }
      return 'table: ' + this.addr(v);
    }
    if (v instanceof LuaFunction) return 'function: ' + this.addr(v);
    if (v instanceof Coroutine) return 'thread: ' + this.addr(v);
    if (v.luaToString) return v.luaToString(this);
    return 'userdata: ' + this.addr(v);
  }
  getMeta(v, ev) { return v instanceof LuaTable && v.mt ? v.mt.get(ev) : undefined; }
  index(o, k) {
    if (o instanceof LuaTable) {
      const v = o.get(k);
      if (v !== undefined || !o.mt) return v;
      const h = o.mt.get('__index');
      if (h === undefined) return undefined;
      if (h instanceof LuaTable) return this.index(h, k);
      return this.callSync(h, [o, k])[0];
    }
    if (typeof o === 'string') return this.stringLib.get(k);
    if (o !== undefined && o !== null && o.luaIndex) return o.luaIndex(k, this);
    throw this.rtErr(`attempt to index ${luaType(o)} with ${this.fmtKey(k)}`);
  }
  fmtKey(k) { return typeof k === 'string' ? `'${k}'` : luaType(k) === 'number' ? 'number' : luaType(k); }
  setIndex(o, k, v) {
    if (o instanceof LuaTable) {
      if (o.frozen) throw this.rtErr('attempt to modify a readonly table');
      if (o.mt && o.get(k) === undefined) {
        const h = o.mt.get('__newindex');
        if (h !== undefined) {
          if (h instanceof LuaTable) return this.setIndex(h, k, v);
          this.callSync(h, [o, k, v]); return;
        }
      }
      if (k === undefined || k === null) throw this.rtErr('table index is nil');
      if (k !== k) throw this.rtErr('table index is NaN');
      o.set(k, v); return;
    }
    if (o !== undefined && o !== null && o.luaNewIndex) return o.luaNewIndex(k, v, this);
    throw this.rtErr(`attempt to index ${luaType(o)} with ${this.fmtKey(k)}`);
  }
  tonum(v) { return typeof v === 'number' ? v : typeof v === 'string' ? str2num(v) : undefined; }
  arith(op, a, b) {
    if (typeof a === 'number' && typeof b === 'number') {
      switch (op) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        case '/': return a / b;
        case '%': return b === Infinity ? (a >= 0 ? a : Infinity) : b === -Infinity ? (a <= 0 ? a : -Infinity) : a - Math.floor(a / b) * b;
        case '^': return Math.pow(a, b);
        case '//': return Math.floor(a / b);
      }
    }
    if (typeof a === 'string' || typeof b === 'string') {
      const na = this.tonum(a), nb = this.tonum(b);
      if (na !== undefined && nb !== undefined) return this.arith(op, na, nb);
    }
    const ev = ARITH_EVENT[op];
    let h = this.getMeta(a, ev);
    if (h === undefined) h = this.getMeta(b, ev);
    if (h !== undefined) return this.callSync(h, [a, b])[0];
    if (a && a.luaArith) { const r = a.luaArith(op, b, false, this); if (r !== undefined) return r; }
    if (b && b.luaArith) { const r = b.luaArith(op, a, true, this); if (r !== undefined) return r; }
    throw this.rtErr(`attempt to perform arithmetic (${ARITH_NAME[op]}) on ${luauTypeof(a)} and ${luauTypeof(b)}`);
  }
  concat(a, b) {
    const ta = typeof a, tb = typeof b;
    if ((ta === 'string' || ta === 'number') && (tb === 'string' || tb === 'number'))
      return (ta === 'number' ? numToStr(a) : a) + (tb === 'number' ? numToStr(b) : b);
    let h = this.getMeta(a, '__concat');
    if (h === undefined) h = this.getMeta(b, '__concat');
    if (h !== undefined) return this.callSync(h, [a, b])[0];
    throw this.rtErr(`attempt to concatenate ${luauTypeof(a)} with ${luauTypeof(b)}`);
  }
  eq(a, b) {
    if (a === b) return true;
    if (a === undefined || b === undefined || a === null || b === null) return a == b;
    const ta = typeof a;
    if (ta !== 'object' || typeof b !== 'object') return false;
    if (a instanceof LuaTable && b instanceof LuaTable) {
      let h = this.getMeta(a, '__eq');
      if (h === undefined) h = this.getMeta(b, '__eq');
      if (h !== undefined) return truthy(this.callSync(h, [a, b])[0]);
      return false;
    }
    if (a.luaEq) return a.luaEq(b);
    return false;
  }
  compare(op, a, b) {
    const ta = typeof a;
    if ((ta === 'number' && typeof b === 'number') || (ta === 'string' && typeof b === 'string')) {
      switch (op) { case '<': return a < b; case '<=': return a <= b; case '>': return a > b; case '>=': return a >= b; }
    }
    const [x, y, ev] = op === '<' ? [a, b, '__lt'] : op === '>' ? [b, a, '__lt'] : op === '<=' ? [a, b, '__le'] : [b, a, '__le'];
    let h = this.getMeta(x, ev);
    if (h === undefined) h = this.getMeta(y, ev);
    if (h !== undefined) return truthy(this.callSync(h, [x, y])[0]);
    throw this.rtErr(`attempt to compare ${luauTypeof(a)} ${op} ${luauTypeof(b)}`);
  }
  binop(op, a, b) {
    switch (op) {
      case '==': return this.eq(a, b);
      case '~=': return !this.eq(a, b);
      case '<': case '<=': case '>': case '>=': return this.compare(op, a, b);
      case '..': return this.concat(a, b);
      default: return this.arith(op, a, b);
    }
  }
  unop(op, v) {
    switch (op) {
      case 'not': return !truthy(v);
      case '-': {
        if (typeof v === 'number') return -v;
        const n = typeof v === 'string' ? str2num(v) : undefined;
        if (n !== undefined) return -n;
        const h = this.getMeta(v, '__unm');
        if (h !== undefined) return this.callSync(h, [v, v])[0];
        if (v && v.luaArith) { const r = v.luaArith('unm', undefined, false, this); if (r !== undefined) return r; }
        throw this.rtErr(`attempt to perform arithmetic (unm) on ${luauTypeof(v)}`);
      }
      case '#': {
        if (typeof v === 'string') return v.length;
        if (v instanceof LuaTable) {
          const h = this.getMeta(v, '__len');
          if (h !== undefined) return this.callSync(h, [v])[0];
          return v.length();
        }
        throw this.rtErr(`attempt to get length of a ${luauTypeof(v)} value`);
      }
    }
  }
  len(v) { return this.unop('#', v); }

  // ---------- 呼叫 ----------
  *call(fn, args, node) {
    if (fn instanceof LuaFunction) return yield* this.callLua(fn, args);
    if (typeof fn === 'function') {
      let r;
      if (fn.isGen) r = yield* fn(args, this);
      else r = fn(args, this);
      return r === undefined ? [] : Array.isArray(r) ? r : [r];
    }
    const h = this.getMeta(fn, '__call');
    if (h !== undefined) return yield* this.call(h, [fn, ...args]);
    throw this.rtErr(`attempt to call a ${luauTypeof(fn)} value${node && node.fn ? this.nameHint(node.fn) : ''}`);
  }
  *callLua(f, args) {
    const node = f.node;
    if (this.stack.length >= this.maxDepth) throw this.rtErr('stack overflow (遞迴太深了？檢查函式是不是一直呼叫自己)');
    const sc = new Scope(f.scope, true);
    const ps = node.params;
    for (let i = 0; i < ps.length; i++) sc.vars.set(ps[i], args[i]);
    if (node.isVararg) sc.varargs = args.length > ps.length ? args.slice(ps.length) : [];
    const frame = { name: f.name, fn: f, line: node.line, scope: sc, chunk: node.chunk };
    this.stack.push(frame);
    try {
      // 每 40 層把剩下的呼叫交給 drive() 從淺層 JS 堆疊接著跑，避免 JS 自己 stack overflow
      const r = this.stack.length % 40 === 0 && this.noYield === 0
        ? yield { k: 'seg', gen: this.execBlock(node.body, sc) }
        : yield* this.execBlock(node.body, sc);
      if (r && r.k === 'return') return r.vals;
      return [];
    } finally { this.stack.pop(); }
  }
  // 分段堆疊的驅動器：收到 {k:'seg'} 就把子 generator 疊上來跑，其餘訊號往外傳
  *drive(g) {
    const segs = [g];
    let send, err, hasErr = false;
    for (;;) {
      const top = segs[segs.length - 1];
      let r;
      const doThrow = hasErr;
      hasErr = false;
      try { r = doThrow ? top.throw(err) : top.next(send); }
      catch (e) { segs.pop(); if (!segs.length) throw e; hasErr = true; err = e; send = undefined; continue; }
      if (r.done) { segs.pop(); if (!segs.length) return r.value; send = r.value; continue; }
      if (r.value.k === 'seg') { segs.push(r.value.gen); send = undefined; continue; }
      send = yield r.value;
    }
  }
  // 在不能讓出的地方(metamethod、排序比較函式…)直接跑完
  callSync(fn, args) {
    if (typeof fn === 'function' && !fn.isGen) { const r = fn(args, this); return r === undefined ? [] : Array.isArray(r) ? r : [r]; }
    const g = this.drive(this.call(fn, args));
    this.noYield++;
    try {
      let r = g.next();
      while (!r.done) {
        if (r.value.k === 'budget' || r.value.k === 'pause') { r = g.next(); continue; }
        throw this.rtErr('attempt to yield across metamethod/C-call boundary (這裡不能用 wait/task.wait)');
      }
      return r.value;
    } finally { this.noYield--; }
  }
  // 測試/工具用：整段跑完，wait 立即返回
  runSync(fn, args) {
    const g = this.drive(this.call(fn, args || []));
    let r = g.next(), send;
    while (!r.done) {
      const s = r.value;
      send = s.k === 'wait' ? [s.t || 0, 0] : undefined;
      if (s.k === 'coyield') throw this.rtErr('attempt to yield from outside a coroutine');
      r = g.next(send);
    }
    return r.value;
  }

  // ---------- 敘述 ----------
  *hook(s, frame) {
    const d = this.dbg;
    let stop = false, why = 'step';
    switch (d.mode) {
      case 'pause': case 'into': stop = true; break;
      case 'over': stop = this.stack === d.stack && this.stack.length <= d.depth; break;
      case 'out': stop = this.stack === d.stack && this.stack.length < d.depth; break;
    }
    if (d.mode === 'pause') why = 'pause';
    if (!stop) {
      // 同一行有好幾個敘述時只停第一個；同一個敘述再跑一次(迴圈)就要再停
      const set = d.bps.get(frame.chunk);
      if (set && set.has(s.line) && !(d.lastFrame === frame && d.lastLine === s.line && d.lastStmt !== s)) { stop = true; why = 'breakpoint'; }
    }
    d.lastFrame = frame; d.lastLine = s.line; d.lastStmt = s;
    if (stop) {
      d.mode = 'paused';
      yield { k: 'pause', why, line: s.line, chunk: frame.chunk, stack: this.stack };
    }
  }
  *execBlock(body, sc) {
    const frame = this.stack[this.stack.length - 1];
    for (let i = 0; i < body.length; i++) {
      const s = body[i];
      frame.line = s.line; frame.scope = sc;
      if (this.noYield === 0) {
        if (this.dbg.active) yield* this.hook(s, frame);
        if (++this.steps >= this.budget) { this.steps = 0; yield YBUDGET; }
      }
      let r;
      try {
        r = yield* this.exec(s, sc);
      } catch (e) {
        if (this.dbg.breakOnError && this.noYield === 0 && !this.stack.pcall && e && !e.dbgSeen && !(e instanceof RangeError)) {
          const err = this.wrapJsError(e);
          err.dbgSeen = true;
          frame.line = s.line; frame.scope = sc;
          this.dbg.mode = 'paused';
          yield { k: 'pause', why: 'error', error: err, line: s.line, chunk: frame.chunk, stack: this.stack };
          throw err;
        }
        throw e;
      }
      if (r !== undefined) return r;
    }
  }
  *tickLoop() {
    if (this.noYield === 0 && ++this.steps >= this.budget) { this.steps = 0; yield YBUDGET; }
  }
  lookup(sc, name) {
    for (let s = sc; s; s = s.parent) if (s.vars.has(name)) return s;
    return null;
  }
  getGlobal(sc, name) {
    const v = sc.env.get(name);
    return v !== undefined ? v : this.G.get(name);
  }
  assignName(sc, name, v) {
    const s = this.lookup(sc, name);
    if (s) s.vars.set(name, v); else sc.env.set(name, v);
  }
  *exec(s, sc) {
    switch (s.k) {
      case 'Local': {
        const vals = s.exprs.length ? yield* this.evList(s.exprs, sc) : [];
        const ns = s.names;
        for (let i = 0; i < ns.length; i++) sc.vars.set(ns[i], vals[i]);
        return;
      }
      case 'Assign': {
        const ts = s.targets;
        if (ts.length === 1) {
          const t = ts[0];
          if (t.k === 'Name') {
            const v = s.exprs.length === 1 ? (s.exprs[0].hc ? (yield* this.evFirst(s.exprs[0], sc)) : this.evS(s.exprs[0], sc)) : (yield* this.evList(s.exprs, sc))[0];
            this.assignName(sc, t.name, v);
          } else {
            const o = t.obj.hc ? (yield* this.ev(t.obj, sc)) : this.evS(t.obj, sc);
            const k = t.key.hc ? (yield* this.ev(t.key, sc)) : this.evS(t.key, sc);
            const v = s.exprs.length === 1 ? (s.exprs[0].hc ? (yield* this.evFirst(s.exprs[0], sc)) : this.evS(s.exprs[0], sc)) : (yield* this.evList(s.exprs, sc))[0];
            this.setIndex(o, k, v);
          }
          return;
        }
        const refs = [];
        for (const t of ts) {
          if (t.k === 'Name') refs.push(null);
          else refs.push([t.obj.hc ? (yield* this.ev(t.obj, sc)) : this.evS(t.obj, sc), t.key.hc ? (yield* this.ev(t.key, sc)) : this.evS(t.key, sc)]);
        }
        const vals = yield* this.evList(s.exprs, sc);
        for (let i = 0; i < ts.length; i++) {
          if (refs[i]) this.setIndex(refs[i][0], refs[i][1], vals[i]);
          else this.assignName(sc, ts[i].name, vals[i]);
        }
        return;
      }
      case 'Compound': {
        const t = s.target;
        if (t.k === 'Name') {
          const ls = this.lookup(sc, t.name);
          const cur = ls ? ls.vars.get(t.name) : this.getGlobal(sc, t.name);
          const rhs = s.expr.hc ? (yield* this.ev(s.expr, sc)) : this.evS(s.expr, sc);
          const v = s.op === '..' ? this.concat(cur, rhs) : this.arith(s.op, cur, rhs);
          if (ls) ls.vars.set(t.name, v); else sc.env.set(t.name, v);
        } else {
          const o = t.obj.hc ? (yield* this.ev(t.obj, sc)) : this.evS(t.obj, sc);
          const k = t.key.hc ? (yield* this.ev(t.key, sc)) : this.evS(t.key, sc);
          const cur = this.index(o, k);
          const rhs = s.expr.hc ? (yield* this.ev(s.expr, sc)) : this.evS(s.expr, sc);
          this.setIndex(o, k, s.op === '..' ? this.concat(cur, rhs) : this.arith(s.op, cur, rhs));
        }
        return;
      }
      case 'CallStat': yield* this.evCall(s.call, sc); return;
      case 'Do': return yield* this.execBlock(s.body, new Scope(sc));
      case 'While': {
        for (;;) {
          const c = s.cond.hc ? (yield* this.ev(s.cond, sc)) : this.evS(s.cond, sc);
          if (!truthy(c)) return;
          const r = yield* this.execBlock(s.body, new Scope(sc));
          if (r !== undefined) { if (r === BREAK) return; if (r !== CONTINUE) return r; }
          if (this.noYield === 0 && ++this.steps >= this.budget) { this.steps = 0; yield YBUDGET; }
        }
      }
      case 'Repeat': {
        for (;;) {
          const inner = new Scope(sc);
          const r = yield* this.execBlock(s.body, inner);
          if (r !== undefined) { if (r === BREAK) return; if (r !== CONTINUE) return r; }
          const c = s.cond.hc ? (yield* this.ev(s.cond, inner)) : this.evS(s.cond, inner);
          if (truthy(c)) return;
          if (this.noYield === 0 && ++this.steps >= this.budget) { this.steps = 0; yield YBUDGET; }
        }
      }
      case 'If': {
        for (const cl of s.clauses) {
          const c = cl.cond.hc ? (yield* this.ev(cl.cond, sc)) : this.evS(cl.cond, sc);
          if (truthy(c)) return yield* this.execBlock(cl.body, new Scope(sc));
        }
        if (s.orelse) return yield* this.execBlock(s.orelse, new Scope(sc));
        return;
      }
      case 'NumFor': {
        const a = this.tonum(s.start.hc ? (yield* this.ev(s.start, sc)) : this.evS(s.start, sc));
        const b = this.tonum(s.limit.hc ? (yield* this.ev(s.limit, sc)) : this.evS(s.limit, sc));
        const st = s.step ? this.tonum(s.step.hc ? (yield* this.ev(s.step, sc)) : this.evS(s.step, sc)) : 1;
        if (a === undefined) throw this.rtErr("invalid 'for' initial value (number expected)");
        if (b === undefined) throw this.rtErr("invalid 'for' limit (number expected)");
        if (st === undefined) throw this.rtErr("invalid 'for' step (number expected)");
        if (st === 0) throw this.rtErr("'for' step is zero");
        for (let i = a; st > 0 ? i <= b : i >= b; i += st) {
          const inner = new Scope(sc);
          inner.vars.set(s.name, i);
          const r = yield* this.execBlock(s.body, inner);
          if (r !== undefined) { if (r === BREAK) return; if (r !== CONTINUE) return r; }
          if (this.noYield === 0 && ++this.steps >= this.budget) { this.steps = 0; yield YBUDGET; }
        }
        return;
      }
      case 'GenFor': {
        const vals = yield* this.evList(s.exprs, sc);
        let f = vals[0], st = vals[1], ctl = vals[2];
        if (f instanceof LuaTable && this.getMeta(f, '__call') === undefined) {
          const it = this.getMeta(f, '__iter');
          if (it !== undefined) {
            const r = yield* this.call(it, [f]);
            f = r[0]; st = r[1]; ctl = r[2];
          } else {
            f = this.snapshotIter(f); st = undefined; ctl = undefined;
          }
        } else if (f === undefined || (typeof f !== 'function' && !(f instanceof LuaFunction) && this.getMeta(f, '__call') === undefined)) {
          throw this.rtErr(`attempt to iterate over a ${luauTypeof(f)} value`);
        }
        const ns = s.names;
        if (f.fastIter) {
          const it = f.fastIter(st, ctl);
          for (;;) {
            const rs = it();
            if (rs === null) return;
            const inner = new Scope(sc);
            for (let i = 0; i < ns.length; i++) inner.vars.set(ns[i], rs[i]);
            const r = yield* this.execBlock(s.body, inner);
            if (r !== undefined) { if (r === BREAK) return; if (r !== CONTINUE) return r; }
            if (this.noYield === 0 && ++this.steps >= this.budget) { this.steps = 0; yield YBUDGET; }
          }
        }
        for (;;) {
          const rs = yield* this.call(f, [st, ctl]);
          if (rs[0] === undefined || rs[0] === null) return;
          ctl = rs[0];
          const inner = new Scope(sc);
          for (let i = 0; i < ns.length; i++) inner.vars.set(ns[i], rs[i]);
          const r = yield* this.execBlock(s.body, inner);
          if (r !== undefined) { if (r === BREAK) return; if (r !== CONTINUE) return r; }
          if (this.noYield === 0 && ++this.steps >= this.budget) { this.steps = 0; yield YBUDGET; }
        }
      }
      case 'Return': {
        if (s.exprs.length === 1 && (s.exprs[0].k === 'Call' || s.exprs[0].k === 'MethodCall')) return { k: 'return', vals: yield* this.evCall(s.exprs[0], sc) };
        return { k: 'return', vals: yield* this.evList(s.exprs, sc) };
      }
      case 'Break': return BREAK;
      case 'Continue': return CONTINUE;
      case 'FuncStat': {
        const t = s.target;
        const fn = new LuaFunction(s.fn, sc, s.fn.name);
        if (t.k === 'Name') this.assignName(sc, t.name, fn);
        else this.setIndex(this.evS(t.obj, sc), t.key.v, fn);
        return;
      }
      case 'LocalFunc': {
        sc.vars.set(s.name, undefined);
        sc.vars.set(s.name, new LuaFunction(s.fn, sc, s.name));
        return;
      }
    }
    throw this.rtErr('unknown statement ' + s.k);
  }
  snapshotIter(t) {
    const keys = t.keyList();
    let idx = 0;
    const f = nat('next', () => {
      while (idx < keys.length) { const k = keys[idx++]; const v = t.get(k); if (v !== undefined) return [k, v]; }
      return [undefined];
    });
    f.fastIter = () => () => {
      while (idx < keys.length) { const k = keys[idx++]; const v = t.get(k); if (v !== undefined) return [k, v]; }
      return null;
    };
    return f;
  }

  // ---------- 運算式 ----------
  varargs(sc) { let s = sc; while (!s.fnRoot) s = s.parent; return s.varargs || []; }
  *evFirst(e, sc) {
    if (e.k === 'Call' || e.k === 'MethodCall') return (yield* this.evCall(e, sc))[0];
    return yield* this.ev(e, sc);
  }
  *evList(exprs, sc) {
    const out = [];
    const n = exprs.length;
    for (let i = 0; i < n; i++) {
      const e = exprs[i];
      if (i === n - 1 && (e.k === 'Call' || e.k === 'MethodCall')) { const r = yield* this.evCall(e, sc); for (let j = 0; j < r.length; j++) out.push(r[j]); }
      else if (i === n - 1 && e.k === 'Vararg') { const va = this.varargs(sc); for (let j = 0; j < va.length; j++) out.push(va[j]); }
      else out.push(e.hc ? (yield* this.ev(e, sc)) : this.evS(e, sc));
    }
    return out;
  }
  *evCall(e, sc) {
    let fn, args;
    if (e.k === 'MethodCall') {
      const obj = e.obj.hc ? (yield* this.ev(e.obj, sc)) : this.evS(e.obj, sc);
      if (obj === undefined || obj === null) throw this.rtErr(`attempt to index nil with '${e.name}'${this.nameHint(e.obj)}`);
      fn = this.index(obj, e.name);
      if (fn === undefined) throw this.rtErr(`attempt to call missing method '${e.name}' of ${luauTypeof(obj)}`);
      args = yield* this.evList(e.args, sc);
      args.unshift(obj);
    } else {
      fn = e.fn.hc ? (yield* this.ev(e.fn, sc)) : this.evS(e.fn, sc);
      args = yield* this.evList(e.args, sc);
      if (fn === undefined || fn === null) throw this.rtErr(`attempt to call a nil value${this.nameHint(e.fn)}`);
    }
    return yield* this.call(fn, args, e);
  }
  nameHint(e) {
    if (e.k === 'Name') return ` (${'variable'} '${e.name}')`;
    if (e.k === 'Index' && e.key.k === 'Str') return ` (field '${e.key.v}')`;
    if (e.k === 'MethodCall') return ` (method '${e.name}')`;
    return '';
  }
  indexNode(o, k, e) {
    if (o === undefined || o === null) throw this.rtErr(`attempt to index nil with ${this.fmtKey(k)}${this.nameHint(e.obj)}`);
    return this.index(o, k);
  }
  evS(e, sc) {
    switch (e.k) {
      case 'Num': return e.v;
      case 'Str': return e.v;
      case 'Name': {
        for (let s = sc; s; s = s.parent) { const m = s.vars; if (m.has(e.name)) return m.get(e.name); }
        return this.getGlobal(sc, e.name);
      }
      case 'Nil': return undefined;
      case 'True': return true;
      case 'False': return false;
      case 'Index': return this.indexNode(this.evS(e.obj, sc), this.evS(e.key, sc), e);
      case 'Binop': {
        if (e.op === 'and') { const l = this.evS(e.l, sc); return truthy(l) ? this.evS(e.r, sc) : l; }
        if (e.op === 'or') { const l = this.evS(e.l, sc); return truthy(l) ? l : this.evS(e.r, sc); }
        const l = this.evS(e.l, sc), r = this.evS(e.r, sc);
        if (typeof l === 'number' && typeof r === 'number') {
          switch (e.op) {
            case '+': return l + r; case '-': return l - r; case '*': return l * r; case '/': return l / r;
            case '<': return l < r; case '>': return l > r; case '<=': return l <= r; case '>=': return l >= r;
            case '==': return l === r; case '~=': return l !== r;
          }
        }
        return this.binop(e.op, l, r);
      }
      case 'Unop': return this.unop(e.op, this.evS(e.e, sc));
      case 'Paren': return this.evS(e.e, sc);
      case 'Vararg': return this.varargs(sc)[0];
      case 'Function': return new LuaFunction(e, sc, e.name);
      case 'Table': {
        const t = new LuaTable();
        let ai = 1;
        const its = e.items;
        for (let i = 0; i < its.length; i++) {
          const it = its[i];
          if (it.type === 'pos') {
            if (i === its.length - 1 && it.value.k === 'Vararg') { for (const v of this.varargs(sc)) t.set(ai++, v); }
            else t.set(ai++, this.evS(it.value, sc));
          } else if (it.type === 'named') t.set(it.key, this.evS(it.value, sc));
          else {
            const k = this.evS(it.key, sc);
            if (k === undefined) throw this.rtErr('table index is nil');
            t.set(k, this.evS(it.value, sc));
          }
        }
        return t;
      }
      case 'IfExpr': {
        for (const cl of e.clauses) if (truthy(this.evS(cl.cond, sc))) return this.evS(cl.val, sc);
        return this.evS(e.orelse, sc);
      }
      case 'Interp': {
        let s = '';
        for (const p of e.parts) s += typeof p === 'string' ? p : this.tostr(this.evS(p, sc));
        return s;
      }
    }
    throw this.rtErr('cannot evaluate ' + e.k);
  }
  *ev(e, sc) {
    switch (e.k) {
      case 'Call': case 'MethodCall': return (yield* this.evCall(e, sc))[0];
      case 'Paren': return e.e.hc ? (yield* this.ev(e.e, sc)) : this.evS(e.e, sc);
      case 'Index': {
        const o = e.obj.hc ? (yield* this.ev(e.obj, sc)) : this.evS(e.obj, sc);
        const k = e.key.hc ? (yield* this.ev(e.key, sc)) : this.evS(e.key, sc);
        return this.indexNode(o, k, e);
      }
      case 'Binop': {
        const l = e.l.hc ? (yield* this.ev(e.l, sc)) : this.evS(e.l, sc);
        if (e.op === 'and') return truthy(l) ? (e.r.hc ? (yield* this.ev(e.r, sc)) : this.evS(e.r, sc)) : l;
        if (e.op === 'or') return truthy(l) ? l : (e.r.hc ? (yield* this.ev(e.r, sc)) : this.evS(e.r, sc));
        const r = e.r.hc ? (yield* this.ev(e.r, sc)) : this.evS(e.r, sc);
        return this.binop(e.op, l, r);
      }
      case 'Unop': return this.unop(e.op, e.e.hc ? (yield* this.ev(e.e, sc)) : this.evS(e.e, sc));
      case 'Table': {
        const t = new LuaTable();
        let ai = 1;
        const its = e.items;
        for (let i = 0; i < its.length; i++) {
          const it = its[i];
          if (it.type === 'pos') {
            const last = i === its.length - 1;
            if (last && (it.value.k === 'Call' || it.value.k === 'MethodCall')) { for (const v of yield* this.evCall(it.value, sc)) t.set(ai++, v); }
            else if (last && it.value.k === 'Vararg') { for (const v of this.varargs(sc)) t.set(ai++, v); }
            else t.set(ai++, it.value.hc ? (yield* this.ev(it.value, sc)) : this.evS(it.value, sc));
          } else if (it.type === 'named') t.set(it.key, it.value.hc ? (yield* this.ev(it.value, sc)) : this.evS(it.value, sc));
          else {
            const k = it.key.hc ? (yield* this.ev(it.key, sc)) : this.evS(it.key, sc);
            if (k === undefined) throw this.rtErr('table index is nil');
            t.set(k, it.value.hc ? (yield* this.ev(it.value, sc)) : this.evS(it.value, sc));
          }
        }
        return t;
      }
      case 'IfExpr': {
        for (const cl of e.clauses) {
          const c = cl.cond.hc ? (yield* this.ev(cl.cond, sc)) : this.evS(cl.cond, sc);
          if (truthy(c)) return cl.val.hc ? (yield* this.ev(cl.val, sc)) : this.evS(cl.val, sc);
        }
        return e.orelse.hc ? (yield* this.ev(e.orelse, sc)) : this.evS(e.orelse, sc);
      }
      case 'Interp': {
        let s = '';
        for (const p of e.parts) s += typeof p === 'string' ? p : this.tostr(p.hc ? (yield* this.ev(p, sc)) : this.evS(p, sc));
        return s;
      }
    }
    return this.evS(e, sc);
  }

  // ---------- 除錯器：讀取變數 ----------
  frameVars(frame) {
    const locals = [], upvals = [];
    const seen = new Set();
    let inFn = true;
    for (let s = frame.scope; s; s = s.parent) {
      for (const [k, v] of [...s.vars].reverse()) {
        if (seen.has(k)) continue;
        seen.add(k);
        (inFn ? locals : upvals).push([k, v]);
      }
      if (s.fnRoot) inFn = false;
    }
    return { locals, upvals, env: frame.scope ? frame.scope.env : null };
  }
  setBreakpoints(chunk, lines) {
    if (lines && lines.length) this.dbg.bps.set(chunk, new Set(lines)); else this.dbg.bps.delete(chunk);
    this.refreshDbg();
  }
  refreshDbg() { const d = this.dbg; d.active = d.mode !== 'run' || d.bps.size > 0; }
  setMode(mode) {
    const d = this.dbg;
    d.mode = mode;
    if (mode === 'over' || mode === 'out') { d.stack = d.pauseStack; d.depth = d.pauseDepth; }
    this.refreshDbg();
  }
  // 讀值給除錯面板用(不觸發 metamethod)
  peekValue(v, depth = 1) {
    const t = luaType(v);
    if (t === 'string') return JSON.stringify(v);
    if (t !== 'table') {
      try { return t === 'userdata' && v.luaToString ? `${v.luaType || 'userdata'}(${v.luaToString(this)})` : this.rawToStr(v); } catch (e) { return t; }
    }
    if (depth <= 0) return '{…}';
    const parts = [];
    const keys = v.keyList();
    for (let i = 0; i < keys.length && i < 12; i++) {
      const k = keys[i];
      const ks = typeof k === 'number' && k === i + 1 && i < v.arr.length ? '' : (typeof k === 'string' && /^[A-Za-z_]\w*$/.test(k) ? k + ' = ' : `[${this.peekValue(k, 0)}] = `);
      parts.push(ks + this.peekValue(v.get(k), depth - 1));
    }
    if (keys.length > 12) parts.push(`…(共 ${keys.length} 項)`);
    return '{' + parts.join(', ') + '}';
  }
  rawToStr(v) {
    if (v instanceof LuaTable) return 'table: ' + this.addr(v);
    return this.tostr(v);
  }
}

function mulberry(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// ===================================================================
// 標準函式庫
// ===================================================================
function argName(args, i) { return i >= args.length ? 'no value' : luauTypeof(args[i]); }
function checkNum(I, args, i, fname, def) {
  const v = args[i];
  if (typeof v === 'number') return v;
  if (v === undefined && def !== undefined) return def;
  if (typeof v === 'string') { const n = str2num(v); if (n !== undefined) return n; }
  throw I.argErr(i, fname, `number expected, got ${argName(args, i)}`);
}
function checkInt(I, args, i, fname, def) {
  const n = checkNum(I, args, i, fname, def);
  return n < 0 ? Math.ceil(n) : Math.floor(n);
}
function checkStr(I, args, i, fname, def) {
  const v = args[i];
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return numToStr(v);
  if (v === undefined && def !== undefined) return def;
  throw I.argErr(i, fname, `string expected, got ${argName(args, i)}`);
}
function checkTab(I, args, i, fname) {
  const v = args[i];
  if (v instanceof LuaTable) return v;
  throw I.argErr(i, fname, `table expected, got ${argName(args, i)}`);
}
function lib(I, name, fns) {
  const t = new LuaTable();
  for (const k in fns) {
    const v = fns[k];
    t.set(k, typeof v === 'function' ? nat(k, v) : v);
  }
  if (name) I.G.set(name, t);
  return t;
}

function fmtNumber(conv, n, flags, width, prec) {
  let s;
  const neg = n < 0 || Object.is(n, -0);
  let a = Math.abs(n);
  switch (conv) {
    case 'd': case 'i': s = String(Math.trunc(a)); if (prec !== undefined) s = s.padStart(prec, '0'); break;
    case 'u': s = String(Math.trunc(a)); break;
    case 'f': case 'F': s = !isFinite(a) ? (a !== a ? 'nan' : 'inf') : a.toFixed(prec === undefined ? 6 : prec); break;
    case 'e': case 'E': {
      if (!isFinite(a)) { s = a !== a ? 'nan' : 'inf'; break; }
      s = a.toExponential(prec === undefined ? 6 : prec).replace(/e([+-])(\d)$/, 'e$10$2');
      if (conv === 'E') s = s.toUpperCase();
      break;
    }
    case 'g': case 'G': {
      if (!isFinite(a)) { s = a !== a ? 'nan' : 'inf'; break; }
      const p = prec === undefined ? 6 : prec === 0 ? 1 : prec;
      const exp = a === 0 ? 0 : Math.floor(Math.log10(a));
      if (exp < -4 || exp >= p) {
        s = a.toExponential(p - 1);
        if (!flags.includes('#')) s = s.replace(/\.?0+e/, 'e');
        s = s.replace(/e([+-])(\d)$/, 'e$10$2');
      } else {
        s = a.toFixed(Math.max(0, p - 1 - exp));
        if (!flags.includes('#') && s.includes('.')) s = s.replace(/\.?0+$/, '');
      }
      if (conv === 'G') s = s.toUpperCase();
      break;
    }
  }
  let sign = neg && !(s === '0' && (conv === 'd' || conv === 'i')) ? '-' : flags.includes('+') ? '+' : flags.includes(' ') ? ' ' : '';
  if (neg && /^[0.]+$/.test(s) && (conv === 'd' || conv === 'i')) sign = '';
  if (width && flags.includes('0') && !flags.includes('-')) s = s.padStart(width - sign.length, '0');
  return sign + s;
}
function luaFormat(I, args) {
  const f = checkStr(I, args, 0, 'format');
  let ai = 1;
  return f.replace(/%([-+ #0]*)(\d*)(?:\.(\d*))?([diuoxXeEfFgGqscaA%])?/g, (m, flags, width, prec, conv) => {
    if (conv === '%' ) return '%';
    if (!conv) throw I.rtErr(`invalid option '${m}' to 'format'`);
    width = width ? parseInt(width, 10) : 0;
    prec = prec === undefined ? undefined : prec === '' ? 0 : parseInt(prec, 10);
    const idx = ai++;
    if (idx >= args.length && conv !== 's') throw I.argErr(idx, 'format', `number expected, got no value`);
    let s;
    switch (conv) {
      case 'd': case 'i': case 'u': {
        const n = checkNum(I, args, idx, 'format');
        if (!Number.isInteger(n)) throw I.argErr(idx, 'format', 'number has no integer representation');
        s = fmtNumber(conv, n, flags, width, prec);
        break;
      }
      case 'x': case 'X': case 'o': {
        const n = checkNum(I, args, idx, 'format');
        if (!Number.isInteger(n)) throw I.argErr(idx, 'format', 'number has no integer representation');
        const v = n < 0 ? BigInt.asUintN(64, BigInt(n)) : BigInt(n);
        s = v.toString(conv === 'o' ? 8 : 16);
        if (conv === 'X') s = s.toUpperCase();
        if (prec !== undefined) s = s.padStart(prec, '0');
        if (flags.includes('#') && n !== 0) s = (conv === 'o' ? '0' : conv === 'x' ? '0x' : '0X') + s;
        if (width && flags.includes('0') && !flags.includes('-')) s = s.padStart(width, '0');
        break;
      }
      case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': case 'a': case 'A':
        s = fmtNumber(conv.replace(/[aA]/, 'g'), checkNum(I, args, idx, 'format'), flags, width, prec); break;
      case 'c': s = String.fromCharCode(checkNum(I, args, idx, 'format')); break;
      case 's': {
        s = I.tostr(args[idx]);
        if (prec !== undefined) s = s.slice(0, prec);
        break;
      }
      case 'q': {
        const v = args[idx];
        if (typeof v === 'number') s = numToStr(v);
        else s = '"' + checkStr(I, args, idx, 'format').replace(/[\\"\n\r\0]/g, c => c === '\n' ? '\\n' : c === '\r' ? '\\r' : c === '\0' ? '\\0' : '\\' + c) + '"';
        break;
      }
    }
    if (width && s.length < width) s = flags.includes('-') ? s.padEnd(width) : s.padStart(width);
    return s;
  });
}

function prettyValue(I, v, depth, seen, indent) {
  if (!(v instanceof LuaTable) || (v.mt && v.mt.get('__tostring') !== undefined)) return typeof v === 'string' && depth < 3 ? JSON.stringify(v) : I.tostr(v);
  if (seen.has(v)) return '*** cycle table reference detected ***';
  if (depth <= 0) return '{...}';
  const keys = v.keyList();
  if (!keys.length) return '{}';
  seen.add(v);
  const pad = '    '.repeat(indent + 1);
  const lines = [];
  const MAX = 60;
  for (let i = 0; i < keys.length && i < MAX; i++) {
    const k = keys[i];
    const ks = typeof k === 'string' ? `["${k}"]` : `[${I.tostr(k)}]`;
    lines.push(`${pad}${ks} = ${prettyValue(I, v.get(k), depth - 1, seen, indent + 1)}`);
  }
  if (keys.length > MAX) lines.push(`${pad}... (${keys.length - MAX} more)`);
  seen.delete(v);
  return '{\n' + lines.join(',\n') + '\n' + '    '.repeat(indent) + '}';
}

function installStdlib(I) {
  const G = I.G;
  const g = (name, fn) => G.set(name, nat(name, fn));

  g('print', (args) => {
    I.output('print', args.map(v => v instanceof LuaTable ? prettyValue(I, v, 4, new Set(), 0) : I.tostr(v)).join(' '));
  });
  g('warn', (args) => { I.output('warn', args.map(v => I.tostr(v)).join(' ')); });
  g('error', (args) => {
    let v = args[0];
    const level = args[1] === undefined ? 1 : checkNum(I, args, 1, 'error');
    if (typeof v === 'string' && level > 0) {
      let f = I.frame();
      if (level >= 2) f = I.stack[I.stack.length - level] || f;
      if (f) v = `${f.chunk}:${f.line}: ${v}`;
    }
    const f = I.frame();
    throw new LuaError(v, I.traceback(), f && f.line, f && f.chunk);
  });
  g('assert', (args) => {
    if (!truthy(args[0])) {
      if (args.length > 1 && args[1] !== undefined) {
        const f = I.frame();
        throw new LuaError(args[1], I.traceback(), f && f.line, f && f.chunk);
      }
      throw I.rtErr('assertion failed!');
    }
    return args;
  });
  g('pcall', function* (args) {
    if (!args.length) throw I.argErr(0, 'pcall', 'value expected');
    const st = I.stack;
    const depth = st.length;
    st.pcall = (st.pcall || 0) + 1;
    try {
      const r = yield* I.call(args[0], args.slice(1));
      return [true, ...r];
    } catch (e) {
      if (e && e.isKill) throw e;
      st.length = depth;
      const le = I.wrapJsError(e);
      return [false, le.value];
    } finally { st.pcall--; }
  });
  g('xpcall', function* (args) {
    const st = I.stack;
    const depth = st.length;
    st.pcall = (st.pcall || 0) + 1;
    try {
      const r = yield* I.call(args[0], args.slice(2));
      return [true, ...r];
    } catch (e) {
      if (e && e.isKill) throw e;
      st.length = depth;
      const le = I.wrapJsError(e);
      const h = yield* I.call(args[1], [le.value]);
      return [false, ...h];
    } finally { st.pcall--; }
  });
  g('type', (args) => { if (!args.length) throw I.argErr(0, 'type', 'value expected'); return luaType(args[0]); });
  g('typeof', (args) => { if (!args.length) throw I.argErr(0, 'typeof', 'value expected'); return luauTypeof(args[0]); });
  g('tostring', (args) => I.tostr(args[0]));
  g('tonumber', (args) => {
    const v = args[0], base = args[1];
    if (base === undefined) {
      if (typeof v === 'number') return v;
      if (typeof v === 'string') return str2num(v);
      return undefined;
    }
    const b = checkNum(I, args, 1, 'tonumber');
    if (b < 2 || b > 36) throw I.argErr(1, 'tonumber', 'base out of range');
    let s = (typeof v === 'number' ? numToStr(v) : checkStr(I, args, 0, 'tonumber')).trim().toLowerCase();
    let neg = false;
    if (s[0] === '-') { neg = true; s = s.slice(1); }
    if (!s) return undefined;
    let n = 0;
    for (const ch of s) {
      const d = parseInt(ch, 36);
      if (isNaN(d) || d >= b) return undefined;
      n = n * b + d;
    }
    return neg ? -n : n;
  });
  const ipairsAux = nat('ipairs_iter', (args) => {
    const i = args[1] + 1;
    const v = I.index(args[0], i);
    return v === undefined ? [undefined] : [i, v];
  });
  g('ipairs', (args) => {
    const t = args[0];
    if (!(t instanceof LuaTable)) throw I.argErr(0, 'ipairs', `table expected, got ${argName(args, 0)}`);
    const f = nat('ipairs_iter', (a) => ipairsAux(a, I));
    f.fastIter = () => {
      let i = 0;
      return () => { i++; const v = t.mt ? I.index(t, i) : t.get(i); return v === undefined ? null : [i, v]; };
    };
    return [f, t, 0];
  });
  g('pairs', (args) => {
    const t = args[0];
    if (!(t instanceof LuaTable)) throw I.argErr(0, 'pairs', `table expected, got ${argName(args, 0)}`);
    return [I.snapshotIter(t), t, undefined];
  });
  g('next', (args) => {
    const t = checkTab(I, args, 0, 'next');
    const k = args[1];
    const keys = t.keyList();
    let idx = 0;
    if (k !== undefined) {
      idx = keys.indexOf(k);
      if (idx < 0) throw I.rtErr("invalid key to 'next'");
      idx++;
    }
    for (; idx < keys.length; idx++) { const v = t.get(keys[idx]); if (v !== undefined) return [keys[idx], v]; }
    return [undefined];
  });
  g('select', (args) => {
    const n = args[0];
    if (n === '#') return args.length - 1;
    let i = checkInt(I, args, 0, 'select');
    if (i < 0) i = args.length + i;
    else if (i === 0) throw I.argErr(0, 'select', 'index out of range');
    if (i < 1) throw I.argErr(0, 'select', 'index out of range');
    return args.slice(i);
  });
  const unpack = (args) => {
    const t = checkTab(I, args, 0, 'unpack');
    const i = checkInt(I, args, 1, 'unpack', 1);
    const j = args[2] === undefined ? t.length() : checkInt(I, args, 2, 'unpack');
    if (j - i >= 8000) throw I.rtErr('too many results to unpack');
    const out = [];
    for (let k = i; k <= j; k++) out.push(t.get(k));
    return out;
  };
  g('unpack', unpack);
  g('rawget', (args) => checkTab(I, args, 0, 'rawget').get(args[1]));
  g('rawset', (args) => { const t = checkTab(I, args, 0, 'rawset'); if (args[1] === undefined) throw I.rtErr('table index is nil'); t.set(args[1], args[2]); return t; });
  g('rawequal', (args) => args[0] === args[1]);
  g('rawlen', (args) => { const v = args[0]; if (typeof v === 'string') return v.length; return checkTab(I, args, 0, 'rawlen').length(); });
  g('setmetatable', (args) => {
    const t = checkTab(I, args, 0, 'setmetatable');
    const mt = args[1];
    if (mt !== undefined && !(mt instanceof LuaTable)) throw I.argErr(1, 'setmetatable', 'nil or table expected');
    if (t.mt && t.mt.get('__metatable') !== undefined) throw I.rtErr('cannot change a protected metatable');
    t.mt = mt || null;
    return t;
  });
  g('getmetatable', (args) => {
    const t = args[0];
    if (typeof t === 'string') return I.stringMeta;
    if (!(t instanceof LuaTable) || !t.mt) return undefined;
    const p = t.mt.get('__metatable');
    return p !== undefined ? p : t.mt;
  });
  g('newproxy', () => new LuaTable());
  G.set('_VERSION', 'Luau');
  G.set('_G', I.shared);

  // ---- string ----
  const S = lib(I, 'string', {
    len: (a) => checkStr(I, a, 0, 'len').length,
    sub: (a) => {
      const s = checkStr(I, a, 0, 'sub'), n = s.length;
      let i = checkInt(I, a, 1, 'sub', 1), j = checkInt(I, a, 2, 'sub', -1);
      if (i < 0) i = Math.max(n + i + 1, 1); else if (i === 0) i = 1;
      if (j < 0) j = n + j + 1; else if (j > n) j = n;
      return i > j ? '' : s.slice(i - 1, j);
    },
    upper: (a) => checkStr(I, a, 0, 'upper').toUpperCase(),
    lower: (a) => checkStr(I, a, 0, 'lower').toLowerCase(),
    rep: (a) => {
      const s = checkStr(I, a, 0, 'rep'), n = checkInt(I, a, 1, 'rep'), sep = a[2] === undefined ? '' : checkStr(I, a, 2, 'rep');
      if (n <= 0) return '';
      if ((s.length + sep.length) * n > 2e7) throw I.rtErr('resulting string too large');
      return sep ? Array(n).fill(s).join(sep) : s.repeat(n);
    },
    reverse: (a) => [...checkStr(I, a, 0, 'reverse')].reverse().join(''),
    byte: (a) => {
      const s = checkStr(I, a, 0, 'byte'), n = s.length;
      let i = checkInt(I, a, 1, 'byte', 1);
      let j = a[2] === undefined ? i : checkInt(I, a, 2, 'byte');
      if (i < 0) i = n + i + 1; if (j < 0) j = n + j + 1;
      if (i < 1) i = 1; if (j > n) j = n;
      const out = [];
      for (let k = i; k <= j; k++) out.push(s.charCodeAt(k - 1));
      return out;
    },
    char: (a) => a.map((_, i) => String.fromCharCode(checkInt(I, a, i, 'char'))).join(''),
    format: (a) => luaFormat(I, a),
    split: (a) => {
      const s = checkStr(I, a, 0, 'split'), sep = a[1] === undefined ? ',' : checkStr(I, a, 1, 'split');
      return LuaTable.from(sep === '' ? [...s] : s.split(sep));
    },
    find: (a) => strFind(I, a, true, 'find'),
    match: (a) => strFind(I, a, false, 'match'),
    gmatch: (a) => {
      const s = checkStr(I, a, 0, 'gmatch'), pat = checkStr(I, a, 1, 'gmatch');
      const P = compilePat(pat, I);
      const re = new RegExp(P.re, (P.anchored ? 'y' : 'g') + 'd');
      let pos = 0, done = false;
      return nat('gmatch_iter', () => {
        if (done || pos > s.length) return [undefined];
        re.lastIndex = pos;
        const m = re.exec(s);
        if (!m) { done = true; return [undefined]; }
        pos = m[0].length ? m.index + m[0].length : m.index + 1;
        if (P.anchored) done = true;
        const caps = patCaps(m, P);
        return caps.length ? caps : [m[0]];
      });
    },
    gsub: (a) => {
      const s = checkStr(I, a, 0, 'gsub'), pat = checkStr(I, a, 1, 'gsub');
      const repl = a[2];
      const maxN = a[3] === undefined ? Infinity : checkInt(I, a, 3, 'gsub');
      const tr = luaType(repl);
      if (tr !== 'string' && tr !== 'number' && tr !== 'table' && tr !== 'function') throw I.argErr(2, 'gsub', `string/function/table expected, got ${argName(a, 2)}`);
      const P = compilePat(pat, I);
      const re = new RegExp(P.re, (P.anchored ? 'y' : 'g') + 'd');
      let out = '', pos = 0, count = 0;
      while (count < maxN && pos <= s.length) {
        if (P.anchored && pos > 0) break;
        re.lastIndex = pos;
        const m = re.exec(s);
        if (!m) break;
        out += s.slice(pos, m.index);
        const whole = m[0], caps = patCaps(m, P);
        let rep;
        if (tr === 'string' || tr === 'number') {
          const rs = tr === 'number' ? numToStr(repl) : repl;
          rep = '';
          for (let k = 0; k < rs.length; k++) {
            const ch = rs[k];
            if (ch !== '%') { rep += ch; continue; }
            const d = rs[++k];
            if (d === '%') rep += '%';
            else if (d >= '0' && d <= '9') {
              const ci = +d;
              if (ci === 0) rep += whole;
              else if (ci === 1 && !caps.length) rep += whole;
              else if (ci > caps.length) throw I.rtErr(`invalid capture index %${ci} in replacement string`);
              else rep += I.tostr(caps[ci - 1]);
            } else throw I.rtErr("invalid use of '%' in replacement string");
          }
        } else {
          const key = caps.length ? caps[0] : whole;
          rep = tr === 'table' ? I.index(repl, key) : I.callSync(repl, caps.length ? caps : [whole])[0];
          if (rep === undefined || rep === false) rep = whole;
          else if (typeof rep === 'number') rep = numToStr(rep);
          else if (typeof rep !== 'string') throw I.rtErr(`invalid replacement value (a ${luaType(rep)})`);
        }
        out += rep; count++;
        if (whole.length === 0) { if (m.index < s.length) out += s[m.index]; pos = m.index + 1; }
        else pos = m.index + whole.length;
      }
      if (pos < s.length) out += s.slice(pos);
      return [out, count];
    },
  });
  I.stringLib = S;
  I.stringMeta = LuaTable.fromObject({ __index: S });

  // ---- math ----
  const fn1 = (name, f) => (a) => f(checkNum(I, a, 0, name));
  const perm = [];
  { const r = mulberry(1337); const p = [...Array(256).keys()]; for (let i = 255; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [p[i], p[j]] = [p[j], p[i]]; } for (let i = 0; i < 512; i++) perm[i] = p[i & 255]; }
  const fade = t => t * t * t * (t * (t * 6 - 15) + 10);
  const grad = (h, x, y, z) => { h &= 15; const u = h < 8 ? x : y, v = h < 4 ? y : h === 12 || h === 14 ? x : z; return ((h & 1) ? -u : u) + ((h & 2) ? -v : v); };
  const lerp = (t, a, b) => a + t * (b - a);
  const noise = (x, y, z) => {
    const X = Math.floor(x) & 255, Y = Math.floor(y) & 255, Z = Math.floor(z) & 255;
    x -= Math.floor(x); y -= Math.floor(y); z -= Math.floor(z);
    const u = fade(x), v = fade(y), w = fade(z);
    const A = perm[X] + Y, AA = perm[A] + Z, AB = perm[A + 1] + Z, B = perm[X + 1] + Y, BA = perm[B] + Z, BB = perm[B + 1] + Z;
    return lerp(w, lerp(v, lerp(u, grad(perm[AA], x, y, z), grad(perm[BA], x - 1, y, z)), lerp(u, grad(perm[AB], x, y - 1, z), grad(perm[BB], x - 1, y - 1, z))),
      lerp(v, lerp(u, grad(perm[AA + 1], x, y, z - 1), grad(perm[BA + 1], x - 1, y, z - 1)), lerp(u, grad(perm[AB + 1], x, y - 1, z - 1), grad(perm[BB + 1], x - 1, y - 1, z - 1))));
  };
  lib(I, 'math', {
    abs: fn1('abs', Math.abs), ceil: fn1('ceil', Math.ceil), floor: fn1('floor', Math.floor), sqrt: fn1('sqrt', Math.sqrt),
    sin: fn1('sin', Math.sin), cos: fn1('cos', Math.cos), tan: fn1('tan', Math.tan), asin: fn1('asin', Math.asin), acos: fn1('acos', Math.acos),
    exp: fn1('exp', Math.exp), log10: fn1('log10', Math.log10), sinh: fn1('sinh', Math.sinh), cosh: fn1('cosh', Math.cosh), tanh: fn1('tanh', Math.tanh),
    deg: fn1('deg', x => x * 180 / Math.PI), rad: fn1('rad', x => x * Math.PI / 180),
    sign: fn1('sign', x => x > 0 ? 1 : x < 0 ? -1 : 0),
    round: fn1('round', x => x < 0 ? -Math.round(-x) : Math.round(x)),
    atan: (a) => a[1] === undefined ? Math.atan(checkNum(I, a, 0, 'atan')) : Math.atan2(checkNum(I, a, 0, 'atan'), checkNum(I, a, 1, 'atan')),
    atan2: (a) => Math.atan2(checkNum(I, a, 0, 'atan2'), checkNum(I, a, 1, 'atan2')),
    log: (a) => { const x = checkNum(I, a, 0, 'log'); if (a[1] === undefined) return Math.log(x); const b = checkNum(I, a, 1, 'log'); return b === 2 ? Math.log2(x) : b === 10 ? Math.log10(x) : Math.log(x) / Math.log(b); },
    pow: (a) => Math.pow(checkNum(I, a, 0, 'pow'), checkNum(I, a, 1, 'pow')),
    fmod: (a) => { const x = checkNum(I, a, 0, 'fmod'), y = checkNum(I, a, 1, 'fmod'); return x % y; },
    modf: (a) => { const x = checkNum(I, a, 0, 'modf'); const ip = x >= 0 ? Math.floor(x) : Math.ceil(x); return [ip, isFinite(x) ? x - ip : 0]; },
    frexp: (a) => { let x = checkNum(I, a, 0, 'frexp'); if (x === 0 || !isFinite(x)) return [x, 0]; const e = Math.floor(Math.log2(Math.abs(x))) + 1; return [x / Math.pow(2, e), e]; },
    ldexp: (a) => checkNum(I, a, 0, 'ldexp') * Math.pow(2, checkNum(I, a, 1, 'ldexp')),
    max: (a) => { let m = checkNum(I, a, 0, 'max'); for (let i = 1; i < a.length; i++) m = Math.max(m, checkNum(I, a, i, 'max')); return m; },
    min: (a) => { let m = checkNum(I, a, 0, 'min'); for (let i = 1; i < a.length; i++) m = Math.min(m, checkNum(I, a, i, 'min')); return m; },
    clamp: (a) => {
      const x = checkNum(I, a, 0, 'clamp'), lo = checkNum(I, a, 1, 'clamp'), hi = checkNum(I, a, 2, 'clamp');
      if (lo > hi) throw I.argErr(2, 'clamp', 'max must be greater than or equal to min');
      return Math.min(Math.max(x, lo), hi);
    },
    lerp: (a) => { const x = checkNum(I, a, 0, 'lerp'), y = checkNum(I, a, 1, 'lerp'), t = checkNum(I, a, 2, 'lerp'); return t === 1 ? y : x + (y - x) * t; },
    map: (a) => { const x = checkNum(I, a, 0, 'map'), i0 = checkNum(I, a, 1, 'map'), i1 = checkNum(I, a, 2, 'map'), o0 = checkNum(I, a, 3, 'map'), o1 = checkNum(I, a, 4, 'map'); return o0 + (x - i0) * (o1 - o0) / (i1 - i0); },
    random: (a) => {
      const r = I.rand();
      if (!a.length) return r;
      let lo = 1, hi;
      if (a.length === 1) hi = checkInt(I, a, 0, 'random');
      else { lo = checkInt(I, a, 0, 'random'); hi = checkInt(I, a, 1, 'random'); }
      if (lo > hi) throw I.argErr(a.length === 1 ? 0 : 1, 'random', 'interval is empty');
      return lo + Math.floor(r * (hi - lo + 1));
    },
    randomseed: (a) => { I.rand = mulberry(checkInt(I, a, 0, 'randomseed') >>> 0); },
    noise: (a) => noise(checkNum(I, a, 0, 'noise'), checkNum(I, a, 1, 'noise', 0), checkNum(I, a, 2, 'noise', 0)),
    pi: Math.PI, huge: Infinity,
  });

  // ---- table ----
  lib(I, 'table', {
    insert: (a) => {
      const t = checkTab(I, a, 0, 'insert');
      if (t.frozen) throw I.rtErr('attempt to modify a readonly table');
      const n = t.length();
      if (a.length === 2) { t.set(n + 1, a[1]); return; }
      if (a.length !== 3) throw I.rtErr("wrong number of arguments to 'insert'");
      const pos = checkInt(I, a, 1, 'insert');
      if (pos < 1 || pos > n + 1) throw I.argErr(1, 'insert', 'position out of bounds');
      if (pos <= t.arr.length && a[2] !== undefined && n === t.arr.length) { t.arr.splice(pos - 1, 0, a[2]); return; }
      for (let i = n; i >= pos; i--) t.set(i + 1, t.get(i));
      t.set(pos, a[2]);
    },
    remove: (a) => {
      const t = checkTab(I, a, 0, 'remove');
      if (t.frozen) throw I.rtErr('attempt to modify a readonly table');
      const n = t.length();
      if (a.length < 2) { if (n === 0) return undefined; const v = t.get(n); t.set(n, undefined); return [v]; }
      const pos = checkInt(I, a, 1, 'remove');
      if (n === 0 && (pos === 0 || pos === n)) return [t.get(pos)];
      if (n + 1 === pos) { const v = t.get(pos); t.set(pos, undefined); return [v]; }
      if (pos < 1 || pos > n + 1) throw I.argErr(1, 'remove', 'position out of bounds');
      const v = t.get(pos);
      if (n === t.arr.length) { t.arr.splice(pos - 1, 1); while (t.arr.length && t.arr[t.arr.length - 1] === undefined) t.arr.pop(); return [v]; }
      for (let i = pos; i < n; i++) t.set(i, t.get(i + 1));
      t.set(n, undefined);
      return [v];
    },
    concat: (a) => {
      const t = checkTab(I, a, 0, 'concat');
      const sep = a[1] === undefined ? '' : checkStr(I, a, 1, 'concat');
      const i = checkInt(I, a, 2, 'concat', 1);
      const j = a[3] === undefined ? t.length() : checkInt(I, a, 3, 'concat');
      const parts = [];
      for (let k = i; k <= j; k++) {
        const v = t.get(k);
        if (typeof v === 'string') parts.push(v);
        else if (typeof v === 'number') parts.push(numToStr(v));
        else throw I.rtErr(`invalid value (at index ${k}) in table for 'concat'`);
      }
      return parts.join(sep);
    },
    sort: (a) => {
      const t = checkTab(I, a, 0, 'sort');
      const cmp = a[1];
      const n = t.length();
      const arr = [];
      for (let i = 1; i <= n; i++) arr.push(t.get(i));
      const lt = cmp === undefined ? (x, y) => I.compare('<', x, y) : (x, y) => truthy(I.callSync(cmp, [x, y])[0]);
      arr.sort((x, y) => lt(x, y) ? -1 : lt(y, x) ? 1 : 0);
      for (let i = 0; i < n; i++) t.set(i + 1, arr[i]);
    },
    find: (a) => {
      const t = checkTab(I, a, 0, 'find');
      const init = checkInt(I, a, 2, 'find', 1);
      for (let i = init; ; i++) { const v = t.get(i); if (v === undefined) return undefined; if (v === a[1] || I.eq(v, a[1])) return i; }
    },
    clear: (a) => { const t = checkTab(I, a, 0, 'clear'); if (t.frozen) throw I.rtErr('attempt to modify a readonly table'); t.arr = []; t.hash.clear(); },
    clone: (a) => { const t = checkTab(I, a, 0, 'clone'); const c = new LuaTable(); c.arr = t.arr.slice(); c.hash = new Map(t.hash); c.mt = t.mt; return c; },
    create: (a) => { const n = checkInt(I, a, 0, 'create'); const t = new LuaTable(); if (a[1] !== undefined) for (let i = 0; i < n; i++) t.arr.push(a[1]); return t; },
    freeze: (a) => { const t = checkTab(I, a, 0, 'freeze'); t.frozen = true; return t; },
    isfrozen: (a) => checkTab(I, a, 0, 'isfrozen').frozen,
    unpack,
    pack: (a) => { const t = LuaTable.from(a); t.set('n', a.length); return t; },
    maxn: (a) => { const t = checkTab(I, a, 0, 'maxn'); let m = 0; for (const k of t.keyList()) if (typeof k === 'number' && k > m) m = k; return m; },
    move: (a) => {
      const a1 = checkTab(I, a, 0, 'move'), f = checkInt(I, a, 1, 'move'), e = checkInt(I, a, 2, 'move'), t = checkInt(I, a, 3, 'move');
      const a2 = a[4] === undefined ? a1 : checkTab(I, a, 4, 'move');
      if (e >= f) {
        if (t > f || t > e || a1 !== a2) for (let i = 0; i <= e - f; i++) a2.set(t + i, a1.get(f + i));
        else for (let i = e - f; i >= 0; i--) a2.set(t + i, a1.get(f + i));
      }
      return a2;
    },
    getn: (a) => checkTab(I, a, 0, 'getn').length(),
  });

  // ---- coroutine ----
  const resume = function* (co, args) {
    if (co.status === 'dead') return [false, 'cannot resume dead coroutine'];
    if (co.status !== 'suspended') return [false, `cannot resume ${co.status === 'running' ? 'non-suspended' : co.status} coroutine`];
    const prevStack = I.stack, prevCo = I.curCo;
    if (prevCo) prevCo.status = 'normal';
    co.status = 'running';
    let send;
    if (!co.gen) { co.gen = I.drive(I.call(co.fn, args)); send = undefined; } else send = args;
    try {
      for (;;) {
        I.stack = co.stack; I.curCo = co;
        let r;
        try { r = co.gen.next(send); } finally { I.stack = prevStack; I.curCo = prevCo; }
        if (r.done) { co.status = 'dead'; return [true, ...r.value]; }
        if (r.value.k === 'coyield') { co.status = 'suspended'; return [true, ...r.value.vals]; }
        send = yield r.value;
      }
    } catch (e) {
      co.status = 'dead';
      if (e && e.isKill) throw e;
      const le = (() => { const s = I.stack; I.stack = co.stack; try { return I.wrapJsError(e); } finally { I.stack = s; } })();
      return [false, le.value];
    } finally { if (prevCo) prevCo.status = 'running'; }
  };
  const checkCo = (a, i, name) => { if (!(a[i] instanceof Coroutine)) throw I.argErr(i, name, `thread expected, got ${argName(a, i)}`); return a[i]; };
  I.mainCo = new Coroutine(null); I.mainCo.status = 'running';
  lib(I, 'coroutine', {
    create: (a) => { const f = a[0]; if (luaType(f) !== 'function') throw I.argErr(0, 'create', `function expected, got ${argName(a, 0)}`); return new Coroutine(f); },
    resume: function* (a) { return yield* resume(checkCo(a, 0, 'resume'), a.slice(1)); },
    yield: function* (a) {
      if (!I.curCo) throw I.rtErr('attempt to yield from outside a coroutine (coroutine.yield 只能在 coroutine 裡用)');
      const v = yield { k: 'coyield', vals: a };
      return v || [];
    },
    status: (a) => checkCo(a, 0, 'status').status,
    running: () => [I.curCo || I.mainCo, !I.curCo],
    isyieldable: () => !!I.curCo,
    wrap: (a) => {
      const co = new Coroutine(a[0]);
      return nat('wrap', function* (args) {
        const r = yield* resume(co, args);
        if (r[0] === false) {
          const v = r[1];
          const f = I.frame();
          throw new LuaError(v, I.traceback(), f && f.line, f && f.chunk);
        }
        return r.slice(1);
      });
    },
    close: (a) => { const co = checkCo(a, 0, 'close'); if (co.status === 'suspended' || co.status === 'dead') { co.status = 'dead'; return true; } throw I.rtErr('cannot close a running coroutine'); },
  });

  // ---- os / utf8 / bit32 ----
  const t0 = Date.now();
  const nowMs = () => (typeof performance !== 'undefined' ? performance.now() : Date.now() - t0);
  lib(I, 'os', {
    time: (a) => {
      const t = a[0];
      if (t instanceof LuaTable) {
        const d = new Date(I.index(t, 'year'), (I.index(t, 'month') || 1) - 1, I.index(t, 'day') || 1, I.index(t, 'hour') ?? 12, I.index(t, 'min') || 0, I.index(t, 'sec') || 0);
        return Math.floor(d.getTime() / 1000);
      }
      return Math.floor(Date.now() / 1000);
    },
    clock: () => nowMs() / 1000,
    difftime: (a) => checkNum(I, a, 0, 'difftime') - checkNum(I, a, 1, 'difftime', 0),
    date: (a) => {
      let f = a[0] === undefined ? '%c' : checkStr(I, a, 0, 'date');
      const t = a[1] === undefined ? Date.now() / 1000 : checkNum(I, a, 1, 'date');
      let utc = false;
      if (f[0] === '!') { utc = true; f = f.slice(1); }
      const d = new Date(t * 1000);
      const get = (m) => utc ? d['getUTC' + m]() : d['get' + m]();
      if (f.startsWith('*t')) return LuaTable.fromObject({ year: get('FullYear'), month: get('Month') + 1, day: get('Date'), hour: get('Hours'), min: get('Minutes'), sec: get('Seconds'), wday: get('Day') + 1, yday: 1, isdst: false });
      const p2 = (n) => String(n).padStart(2, '0');
      const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
      const MONS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      return f.replace(/%(.)/g, (m, c) => {
        switch (c) {
          case 'Y': return get('FullYear'); case 'y': return p2(get('FullYear') % 100); case 'm': return p2(get('Month') + 1);
          case 'd': return p2(get('Date')); case 'H': return p2(get('Hours')); case 'M': return p2(get('Minutes')); case 'S': return p2(get('Seconds'));
          case 'p': return get('Hours') < 12 ? 'AM' : 'PM'; case 'A': return DAYS[get('Day')]; case 'a': return DAYS[get('Day')].slice(0, 3);
          case 'B': return MONS[get('Month')]; case 'b': return MONS[get('Month')].slice(0, 3);
          case 'c': return `${DAYS[get('Day')].slice(0, 3)} ${MONS[get('Month')].slice(0, 3)} ${p2(get('Date'))} ${p2(get('Hours'))}:${p2(get('Minutes'))}:${p2(get('Seconds'))} ${get('FullYear')}`;
          case 'x': return `${p2(get('Month') + 1)}/${p2(get('Date'))}/${p2(get('FullYear') % 100)}`;
          case 'X': return `${p2(get('Hours'))}:${p2(get('Minutes'))}:${p2(get('Seconds'))}`;
          case '%': return '%';
        }
        return m;
      });
    },
  });
  lib(I, 'utf8', {
    char: (a) => a.map((_, i) => String.fromCodePoint(checkInt(I, a, i, 'char'))).join(''),
    charpattern: '[\x00-\x7F\xC2-\xFD][\x80-\xBF]*',
    codepoint: (a) => { const s = checkStr(I, a, 0, 'codepoint'); const i = checkInt(I, a, 1, 'codepoint', 1); const j = a[2] === undefined ? i : checkInt(I, a, 2, 'codepoint'); const cps = [...s].map(c => c.codePointAt(0)); return cps.slice(i - 1, j); },
    len: (a) => [...checkStr(I, a, 0, 'len')].length,
    codes: (a) => {
      const cps = [...checkStr(I, a, 0, 'codes')];
      let k = 0;
      return [nat('codes_iter', () => k < cps.length ? [++k, cps[k - 1].codePointAt(0)] : [undefined]), a[0], 0];
    },
    offset: (a) => checkInt(I, a, 1, 'offset', 1),
  });
  const u32 = (a, i, n) => checkNum(I, a, i, n) >>> 0;
  lib(I, 'bit32', {
    band: (a) => a.reduce((x, _, i) => (x & u32(a, i, 'band')) >>> 0, 0xFFFFFFFF),
    bor: (a) => a.reduce((x, _, i) => (x | u32(a, i, 'bor')) >>> 0, 0),
    bxor: (a) => a.reduce((x, _, i) => (x ^ u32(a, i, 'bxor')) >>> 0, 0),
    bnot: (a) => (~u32(a, 0, 'bnot')) >>> 0,
    btest: (a) => a.reduce((x, _, i) => (x & u32(a, i, 'btest')) >>> 0, 0xFFFFFFFF) !== 0,
    lshift: (a) => { const n = checkNum(I, a, 1, 'lshift'); return n >= 32 ? 0 : (u32(a, 0, 'lshift') << n) >>> 0; },
    rshift: (a) => { const n = checkNum(I, a, 1, 'rshift'); return n >= 32 ? 0 : u32(a, 0, 'rshift') >>> n; },
    arshift: (a) => (u32(a, 0, 'arshift') | 0) >> checkNum(I, a, 1, 'arshift') >>> 0,
    extract: (a) => { const n = u32(a, 0, 'extract'), f = checkNum(I, a, 1, 'extract'), w = checkNum(I, a, 2, 'extract', 1); return (n >>> f) & ((w >= 32 ? 0xFFFFFFFF : (1 << w) - 1) >>> 0); },
    replace: (a) => { const n = u32(a, 0, 'replace'), v = u32(a, 1, 'replace'), f = checkNum(I, a, 2, 'replace'), w = checkNum(I, a, 3, 'replace', 1); const m = ((w >= 32 ? 0xFFFFFFFF : (1 << w) - 1) >>> 0) << f; return ((n & ~m) | ((v << f) & m)) >>> 0; },
  });
}

function strFind(I, a, isFind, fname) {
  const s = checkStr(I, a, 0, fname), pat = checkStr(I, a, 1, fname);
  let init = checkInt(I, a, 2, fname, 1);
  const n = s.length;
  if (init < 0) init = Math.max(n + init + 1, 1); else if (init === 0) init = 1;
  if (init > n + 1) return undefined;
  if (isFind && (truthy(a[3]) || !/[\^$*+?.()[\]%-]/.test(pat))) {
    const idx = s.indexOf(pat, init - 1);
    return idx < 0 ? undefined : [idx + 1, idx + pat.length];
  }
  const P = compilePat(pat, I);
  if (P.anchored && init > 1) {
    const re = new RegExp(P.re, 'yd');
    re.lastIndex = init - 1;
    const m = re.exec(s);
    if (!m) return undefined;
    const caps = patCaps(m, P);
    return isFind ? [m.index + 1, m.index + m[0].length, ...caps] : caps.length ? caps : [m[0]];
  }
  const re = new RegExp(P.re, (P.anchored ? 'y' : 'g') + 'd');
  re.lastIndex = init - 1;
  const m = re.exec(s);
  if (!m) return undefined;
  const caps = patCaps(m, P);
  return isFind ? [m.index + 1, m.index + m[0].length, ...caps] : caps.length ? caps : [m[0]];
}

return { lex, parse, parseExpr, Interp, LuaTable, LuaFunction, LuaError, Coroutine, Scope, nat, truthy, luaType, luauTypeof, numToStr, str2num, checkNum, checkStr, checkTab, checkInt };
});
