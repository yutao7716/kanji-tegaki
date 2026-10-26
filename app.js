/* かんじ てがき じしょ（Web版）
 * 手書き認識：書いた線を KanjiVG の書き順データと比べる（すべてブラウザの中で動く・通信しない）
 */
'use strict';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const S = {
  dict: {}, ordered: [], raw: {}, norm: {}, info: {}, antonyms: {}, idiomMap: {},
  selected: null, candidates: [],
};

/* ---------------- 保存（りれき・おきにいり） ---------------- */
const Store = {
  get(key) { try { return JSON.parse(localStorage.getItem(key) || '[]'); } catch { return []; } },
  set(key, v) { try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* 保存できない環境 */ } },
  record(k) { const h = this.get('history').filter((x) => x !== k); h.unshift(k); this.set('history', h.slice(0, 100)); },
  isFav(k) { return this.get('favorites').includes(k); },
  toggleFav(k) {
    let f = this.get('favorites');
    f = f.includes(k) ? f.filter((x) => x !== k) : [k, ...f];
    this.set('favorites', f);
  },
};

/* ---------------- 設定（かんたん／ふつう） ---------------- */
const Settings = {
  get standard() { try { return localStorage.getItem('standardExplanation') === '1'; } catch { return false; } },
  set standard(v) { try { localStorage.setItem('standardExplanation', v ? '1' : '0'); } catch { /* 保存できない環境 */ } },
};
const meaningOf = (x) => (Settings.standard ? (x.meaningStd || x.meaning) : x.meaning);

/* ---------------- 学年 ---------------- */
const GRADES = [1, 2, 3, 4, 5, 6, 7];
const gradeLabel = (g) => (g >= 7 ? '中学・高校' : `${g}ねんせい`);
const gradeShort = (g) => (g >= 7 ? '中・高' : `${g}年`);

/* ---------------- 認識 ---------------- */
const N = 16;
const dist2 = (p, q) => Math.hypot(p[0] - q[0], p[1] - q[1]);

function normalize(strokes) {
  const all = strokes.flat();
  const xs = all.map((p) => p[0]), ys = all.map((p) => p[1]);
  const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
  const sc = Math.max(maxX - minX, maxY - minY, 0.001);
  const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  return strokes.map((s) => s.map((p) => [(p[0] - cx) / sc, (p[1] - cy) / sc]));
}

function resample(s) {
  if (s.length < 2) return Array(N).fill(s[0] || [0, 0]);
  const cum = [0];
  for (let i = 1; i < s.length; i++) cum.push(cum[i - 1] + dist2(s[i], s[i - 1]));
  const total = cum[cum.length - 1];
  if (total === 0) return Array(N).fill(s[0]);
  const out = [];
  let j = 0;
  for (let i = 0; i < N; i++) {
    const t = (total * i) / (N - 1);
    while (j < s.length - 2 && cum[j + 1] < t) j++;
    const seg = cum[j + 1] - cum[j];
    const r = seg === 0 ? 0 : (t - cum[j]) / seg;
    out.push([s[j][0] + (s[j + 1][0] - s[j][0]) * r, s[j][1] + (s[j + 1][1] - s[j][1]) * r]);
  }
  return out;
}

function strokeDist(a, b) {
  const n = Math.min(a.length, b.length);
  let sum = 0;
  for (let i = 0; i < n; i++) sum += dist2(a[i], b[i]);
  return sum / n;
}

function hungarian(c) {
  const n = c.length, INF = 1e9;
  const u = new Array(n + 1).fill(0), v = new Array(n + 1).fill(0);
  const p = new Array(n + 1).fill(0), way = new Array(n + 1).fill(0);
  for (let i = 1; i <= n; i++) {
    p[0] = i;
    let j0 = 0;
    const minv = new Array(n + 1).fill(INF), used = new Array(n + 1).fill(false);
    do {
      used[j0] = true;
      const i0 = p[j0];
      let delta = INF, j1 = 0;
      for (let j = 1; j <= n; j++) {
        if (used[j]) continue;
        const cur = c[i0 - 1][j - 1] - u[i0] - v[j];
        if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
        if (minv[j] < delta) { delta = minv[j]; j1 = j; }
      }
      for (let j = 0; j <= n; j++) {
        if (used[j]) { u[p[j]] += delta; v[j] -= delta; } else minv[j] -= delta;
      }
      j0 = j1;
    } while (p[j0] !== 0);
    do { const j1 = way[j0]; p[j0] = p[j1]; j0 = j1; } while (j0);
  }
  let total = 0;
  for (let j = 1; j <= n; j++) total += c[p[j] - 1][j - 1];
  return total;
}

function score(input, tmpl) {
  const n = input.length, m = tmpl.length, k = Math.max(n, m);
  const c = Array.from({ length: k }, () => new Array(k).fill(0.5));
  for (let i = 0; i < n; i++) {
    const rev = input[i].slice().reverse();
    for (let j = 0; j < m; j++) {
      c[i][j] = Math.min(strokeDist(input[i], tmpl[j]), strokeDist(rev, tmpl[j]) + 0.08) + Math.abs(i - j) * 0.02;
    }
  }
  return hungarian(c) / k + 0.12 * Math.abs(n - m);
}

function recognize(strokes, limit = 8) {
  if (!strokes.length) return [];
  const input = normalize(strokes.map(resample));
  const n = input.length, range = Math.max(3, Math.floor(n / 3));
  let pool = Object.keys(S.norm).filter((k) => Math.abs(S.norm[k].length - n) <= range);
  if (!pool.length) pool = Object.keys(S.norm);
  return pool.map((k) => [k, score(input, S.norm[k])]).sort((a, b) => a[1] - b[1]).slice(0, limit).map((x) => x[0]);
}

/* ---------------- 手書きキャンバス ---------------- */
class HandCanvas {
  constructor(canvas, { onStrokeEnd, onChange } = {}) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.strokes = [];      // 0〜1 の点列
    this.current = null;
    this.onStrokeEnd = onStrokeEnd;   // (points) => true なら のこす
    this.onChange = onChange;
    new ResizeObserver(() => this.resize()).observe(canvas);
    canvas.addEventListener('pointerdown', (e) => this.down(e));
    canvas.addEventListener('pointermove', (e) => this.move(e));
    canvas.addEventListener('pointerup', (e) => this.up(e));
    canvas.addEventListener('pointercancel', (e) => this.up(e));
    canvas.addEventListener('touchstart', (e) => e.preventDefault(), { passive: false });
  }
  resize() {
    const r = this.canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.round(r.width * dpr);
    this.canvas.height = Math.round(r.height * dpr);
    this.redraw();
  }
  pos(e) {
    const r = this.canvas.getBoundingClientRect();
    return [(e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height];
  }
  down(e) {
    if (this.disabled) return;
    e.preventDefault();
    this.canvas.setPointerCapture(e.pointerId);
    this.current = [this.pos(e)];
    this.redraw();
  }
  move(e) {
    if (!this.current) return;
    e.preventDefault();
    const evs = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
    for (const ev of evs) this.current.push(this.pos(ev));
    this.redraw();
  }
  up() {
    if (!this.current) return;
    const s = this.current;
    this.current = null;
    if (s.length === 1) s.push([s[0][0] + 0.001, s[0][1] + 0.001]);
    const keep = this.onStrokeEnd ? this.onStrokeEnd(s) : true;
    if (keep !== false) this.strokes.push(s);
    this.redraw();
    this.onChange && this.onChange(this.strokes);
  }
  clear() { this.strokes = []; this.current = null; this.redraw(); this.onChange && this.onChange(this.strokes); }
  undo() { this.strokes.pop(); this.redraw(); this.onChange && this.onChange(this.strokes); }
  redraw() {
    const { ctx, canvas } = this;
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.strokeStyle = '#111';
    ctx.lineWidth = Math.max(4, w * 0.035);
    const all = this.current ? [...this.strokes, this.current] : this.strokes;
    for (const s of all) {
      ctx.beginPath();
      ctx.moveTo(s[0][0] * w, s[0][1] * h);
      for (let i = 1; i < s.length - 1; i++) {
        const mx = (s[i][0] + s[i + 1][0]) / 2, my = (s[i][1] + s[i + 1][1]) / 2;
        ctx.quadraticCurveTo(s[i][0] * w, s[i][1] * h, mx * w, my * h);
      }
      const last = s[s.length - 1];
      ctx.lineTo(last[0] * w, last[1] * h);
      ctx.stroke();
    }
  }
}

/* ---------------- SVG（お手本の線） ---------------- */
function pathD(pts) {
  if (!pts.length) return '';
  let d = `M${pts[0][0]} ${pts[0][1]}`;
  for (let i = 1; i < pts.length - 1; i++) {
    const mx = (pts[i][0] + pts[i + 1][0]) / 2, my = (pts[i][1] + pts[i + 1][1]) / 2;
    d += ` Q${pts[i][0]} ${pts[i][1]} ${mx} ${my}`;
  }
  const l = pts[pts.length - 1];
  return d + ` L${l[0]} ${l[1]}`;
}
const SVGNS = 'http://www.w3.org/2000/svg';
function svgEl(tag, attrs) {
  const el = document.createElementNS(SVGNS, tag);
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v);
  return el;
}
function animateStroke(path, duration) {
  const len = path.getTotalLength();
  path.style.strokeDasharray = `${len}`;
  path.style.strokeDashoffset = `${len}`;
  return path.animate([{ strokeDashoffset: len }, { strokeDashoffset: 0 }], { duration, fill: 'forwards', easing: 'linear' }).finished;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/* ---------------- 読み上げ ---------------- */
function speak(text) {
  if (!('speechSynthesis' in window)) return;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  u.lang = 'ja-JP';
  u.rate = 0.85;
  speechSynthesis.speak(u);
}
function speechText(e) {
  const parts = [];
  if (e.onyomi.length) parts.push('おんよみは、' + e.onyomi.join('、'));
  if (e.kunyomi.length) parts.push('くんよみは、' + e.kunyomi.map((k) => k.replace(/[()]/g, '')).join('、'));
  parts.push('いみは、' + meaningOf(e));
  return parts.join('。');
}

/* ---------------- メイン画面 ---------------- */
let mainPad, recogTimer;
const START_MSG = 'マスの なかに かんじを 1もじ かいてね';

function onMainChange(strokes) {
  $('#undoBtn').disabled = !strokes.length;
  $('#searchBtn').disabled = !strokes.length;
  clearTimeout(recogTimer);
  if (!strokes.length) {
    S.candidates = [];
    renderCandidates();
    $('#message').textContent = START_MSG;
    return;
  }
  recogTimer = setTimeout(runRecognition, 800);
}

function runRecognition() {
  clearTimeout(recogTimer);
  const strokes = mainPad.strokes;
  if (!strokes.length) return;
  S.candidates = recognize(strokes);
  renderCandidates();
  if (S.candidates.length) {
    select(S.candidates[0]);
    $('#message').textContent = 'ちがう ときは「これかな？」から えらんでね';
  }
}

function renderCandidates() {
  $('#candidatesBox').hidden = !S.candidates.length;
  $('#candidates').innerHTML = S.candidates
    .map((k) => `<button class="cand${k === S.selected ? ' selected' : ''}" data-k="${esc(k)}">${esc(k)}</button>`).join('');
}

function select(k) {
  S.selected = k;
  Store.record(k);
  renderCandidates();
  renderCard();
}

function row(title, color, inner) {
  return `<div class="row"><span class="label bg-${color}">${title}</span><div>${inner}</div></div>`;
}
function chips(items, empty = 'なし') {
  if (!items.length) return `<span class="none">${empty}</span>`;
  return `<div class="chips">${items.map((x) => `<span class="chip">${esc(x)}</span>`).join('')}</div>`;
}

function renderCard() {
  const k = S.selected;
  const e = S.dict[k];
  const box = $('#card');
  if (!k) { box.innerHTML = ''; return; }
  if (!e) { box.innerHTML = `<div class="card empty-card">この かんじは まだ じしょに のっていないよ。</div>`; return; }
  const info = S.info[k];
  const fav = Store.isFav(k);
  const anto = S.antonyms[k] || [];
  const idioms = S.idiomMap[k] || [];
  const yoji = idioms.filter((i) => i.kind === 'yoji').slice(0, 3);
  const koto = idioms.filter((i) => i.kind !== 'yoji').slice(0, 2);
  const idiomChips = (list) => `<div class="chips">${list.map((i) => `<button class="chip" data-idiom="${esc(i.text)}">${esc(i.text)} ⓘ</button>`).join('')}</div>`;

  box.innerHTML = `
  <article class="card">
    <div class="card-head">
      <div class="kanji-box">${esc(k)}</div>
      <div class="head-right">
        <div class="meaning-head">
          <div class="meaning"><span class="label bg-orange">いみ</span><span>${esc(meaningOf(e))}</span></div>
          <div class="tabs mini" role="group" aria-label="せつめいの むずかしさ">
            <button class="tab${Settings.standard ? '' : ' active'}" data-level="easy">かんたん</button>
            <button class="tab${Settings.standard ? ' active' : ''}" data-level="std">ふつう</button>
          </div>
        </div>
        <div class="badges">
          <span class="badge" style="background:rgba(246,196,69,.55)">${gradeLabel(e.grade)}</span>
          ${info ? `<span class="badge" style="background:rgba(47,124,246,.12)">${info.strokes}かく</span>
          <span class="badge" style="background:rgba(52,168,83,.14)">ぶしゅ ${esc(info.radical)}${info.radicalName ? `（${esc(info.radicalName)}）` : ''}</span>` : ''}
        </div>
      </div>
    </div>
    <div class="actions">
      <button class="action blue" data-act="speak"><span class="ico">🔊</span>よみあげ</button>
      <button class="action orange" data-act="order"><span class="ico">▶️</span>かきじゅん</button>
      <button class="action green" data-act="practice"><span class="ico">✏️</span>れんしゅう</button>
      <button class="action yellow" data-act="fav"><span class="ico">${fav ? '★' : '☆'}</span>おきにいり</button>
    </div>
    <hr>
    ${row('おんよみ', 'blue', chips(e.onyomi))}
    ${row('くんよみ', 'green', chips(e.kunyomi))}
    ${e.examples.length ? row('つかいかた', 'purple', chips(e.examples)) : ''}
    ${e.synonyms.length ? row('にた ことば', 'pink', chips(e.synonyms)) : ''}
    ${anto.length ? row('はんたい', 'red', `<div class="chips">${anto.map((a) => `<button class="chip anto" data-k="${esc(a)}">${esc(a)}</button>`).join('')}</div>`) : ''}
    ${yoji.length ? row('四字じゅくご', 'teal', idiomChips(yoji)) : ''}
    ${koto.length ? row('ことわざ', 'indigo', idiomChips(koto)) : ''}
  </article>`;
}

function onCardClick(ev) {
  const btn = ev.target.closest('button');
  if (!btn) return;
  const k = S.selected;
  if (btn.dataset.k) { select(btn.dataset.k); return; }
  if (btn.dataset.level) { Settings.standard = btn.dataset.level === 'std'; renderCard(); return; }
  if (btn.dataset.idiom) { openIdiom(btn.dataset.idiom); return; }
  switch (btn.dataset.act) {
    case 'speak': speak(speechText(S.dict[k])); break;
    case 'order': openOrder(k); break;
    case 'practice': openPractice(k, 'trace'); break;
    case 'fav': Store.toggleFav(k); renderCard(); break;
  }
}

/* ---------------- ダイアログ共通 ---------------- */
function openDialog(id) { const d = $(id); if (!d.open) d.showModal(); return d; }
document.addEventListener('click', (ev) => {
  if (ev.target.matches('[data-close]')) ev.target.closest('dialog').close();
});

/* ---------------- 四字熟語・ことわざ ---------------- */
let currentIdiom = null;
function openIdiom(text) {
  const all = Object.values(S.idiomMap).flat();
  const i = all.find((x) => x.text === text);
  if (!i) return;
  currentIdiom = i;
  $('#idiomText').textContent = i.text;
  $('#idiomReading').textContent = i.reading;
  $('#idiomMeaning').textContent = meaningOf(i);
  openDialog('#dlgIdiom');
}

/* ---------------- さがす ---------------- */
let searchGrade = 1;
const toHira = (s) => s.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));
function renderSearch() {
  const q = toHira($('#readingInput').value.trim());
  let list;
  if (q) {
    list = S.ordered.filter((e) => [...e.onyomi, ...e.kunyomi.map((r) => r.replace(/[()]/g, ''))].some((r) => toHira(r).startsWith(q)));
    $('#searchInfo').textContent = `「${$('#readingInput').value.trim()}」と よむ かんじ（${list.length}じ）`;
    $('#gradeTabs').hidden = true;
  } else {
    list = S.ordered.filter((e) => e.grade === searchGrade);
    $('#searchInfo').textContent = `${gradeLabel(searchGrade)}で ならう かんじ（${list.length}じ）`;
    $('#gradeTabs').hidden = false;
  }
  $('#gradeTabs').innerHTML = GRADES.map((g) => `<button class="tab${g === searchGrade ? ' active' : ''}" data-g="${g}">${gradeShort(g)}</button>`).join('');
  fillGrid('#searchGrid', list.map((e) => e.kanji), 'みつからなかったよ');
}
function fillGrid(sel, list, emptyText) {
  $(sel).innerHTML = list.length
    ? list.map((k) => `<button data-k="${esc(k)}">${esc(k)}</button>`).join('')
    : `<p class="nothing">${emptyText}</p>`;
}

/* ---------------- りれき ---------------- */
let historyTab = 'history';
function renderHistory() {
  document.querySelectorAll('#historyTabs .tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === historyTab));
  const list = Store.get(historyTab);
  fillGrid('#historyGrid', list, historyTab === 'history' ? 'まだ しらべた かんじは ないよ' : 'カードの ☆ を おすと ここに あつまるよ');
  $('#clearHistory').hidden = !(historyTab === 'history' && list.length);
}

/* ---------------- 書き順アニメーション ---------------- */
let orderRun = 0, orderProgress = 0;
function buildOrderSvg(k) {
  const svg = $('#orderSvg');
  svg.innerHTML = '';
  const strokes = S.raw[k] || [];
  const style = { fill: 'none', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '0.055' };
  const grid = svgEl('g', { stroke: 'rgba(220,80,80,.32)', 'stroke-width': '0.004', 'stroke-dasharray': '0.02 0.016' });
  grid.append(svgEl('line', { x1: 0.5, y1: 0, x2: 0.5, y2: 1 }), svgEl('line', { x1: 0, y1: 0.5, x2: 1, y2: 0.5 }));
  svg.append(grid);
  strokes.forEach((s) => svg.append(svgEl('path', { d: pathD(s), stroke: 'rgba(0,0,0,.12)', ...style })));
  const ink = strokes.map((s) => {
    const p = svgEl('path', { d: pathD(s), stroke: '#111', ...style });
    p.style.visibility = 'hidden';
    svg.append(p);
    return p;
  });
  const nums = strokes.map((s, i) => {
    const g = svgEl('g', { visibility: 'hidden' });
    g.append(svgEl('circle', { cx: s[0][0], cy: s[0][1], r: 0.036, fill: '#f08a24' }));
    const t = svgEl('text', { x: s[0][0], y: s[0][1] + 0.016, 'text-anchor': 'middle', 'font-size': 0.045, 'font-weight': 700, fill: '#fff' });
    t.textContent = i + 1;
    g.append(t);
    svg.append(g);
    return g;
  });
  return { ink, nums };
}
let orderParts = null, orderKanji = null;
function openOrder(k) {
  orderKanji = k;
  $('#orderTitle').textContent = `「${k}」の かきじゅん`;
  $('#orderCount').textContent = `${(S.raw[k] || []).length}かく`;
  openDialog('#dlgOrder');
  playOrder();
}
async function drawOrderStroke(i, run) {
  const p = orderParts.ink[i];
  p.style.visibility = 'visible';
  p.setAttribute('stroke', '#e5484d');
  orderParts.nums[i].setAttribute('visibility', 'visible');
  const dur = $('#orderSlow').checked ? 1200 : 600;
  await animateStroke(p, dur);
  if (run === orderRun) p.setAttribute('stroke', '#111');
}
async function playOrder() {
  const run = ++orderRun;
  orderParts = buildOrderSvg(orderKanji);
  orderProgress = 0;
  await sleep(300);
  for (let i = 0; i < orderParts.ink.length; i++) {
    if (run !== orderRun || !$('#dlgOrder').open) return;
    await drawOrderStroke(i, run);
    orderProgress = i + 1;
    await sleep(250);
  }
}
async function stepOrder() {
  const run = ++orderRun;
  if (!orderParts || orderProgress >= orderParts.ink.length) {
    orderParts = buildOrderSvg(orderKanji);
    orderProgress = 0;
  }
  const i = orderProgress;
  orderProgress++;
  await drawOrderStroke(i, run);
}

/* ---------------- 練習・テスト ---------------- */
const P = { kanji: null, mode: 'trace', done: 0, mistakes: 0, strokeMistakes: 0, pad: null, onNext: null, hintPath: null };

function openPractice(k, mode, opts = {}) {
  P.kanji = k; P.mode = mode; P.onNext = opts.onNext || null;
  $('#practiceTabs').hidden = !!P.onNext;
  $('#practicePrompt').hidden = !opts.prompt;
  $('#practicePrompt').textContent = opts.prompt || '';
  $('#practiceNext').hidden = !P.onNext;
  openDialog('#dlgPractice');
  restartPractice();
}
function practiceStrokes() { return S.raw[P.kanji] || []; }
function restartPractice() {
  P.done = 0; P.mistakes = 0; P.strokeMistakes = 0;
  setFeedback('', true);
  $('#practiceTitle').textContent = P.onNext ? 'かきとり テスト' : (P.mode === 'trace' ? 'なぞって れんしゅう' : '見ないで かいてみよう');
  document.querySelectorAll('#practiceTabs .tab').forEach((t) => t.classList.toggle('active', t.dataset.mode === P.mode));
  $('#practiceDone').hidden = true;
  $('#practiceNext').textContent = 'わからない →';
  P.pad.disabled = false;
  P.pad.strokes = [];
  requestAnimationFrame(() => P.pad.resize());
  renderGuide();
}
function setFeedback(text, good) {
  const f = $('#practiceFeedback');
  f.textContent = text || ' ';
  f.className = 'feedback ' + (good ? 'good' : 'bad');
}
function renderGuide() {
  const svg = $('#practiceGuide');
  svg.innerHTML = '';
  const strokes = practiceStrokes();
  const style = { fill: 'none', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '0.06' };
  if (P.mode === 'trace') {
    strokes.forEach((s, i) => svg.append(svgEl('path', { d: pathD(s), stroke: `rgba(0,0,0,${i < P.done ? 0.06 : 0.18})`, ...style })));
    if (P.done < strokes.length) {
      const s = strokes[P.done];
      svg.append(svgEl('circle', { cx: s[0][0], cy: s[0][1], r: 0.035, fill: '#34a853' }));
      const t = svgEl('text', { x: s[0][0], y: s[0][1] + 0.015, 'text-anchor': 'middle', 'font-size': 0.04, 'font-weight': 700, fill: '#fff' });
      t.textContent = P.done + 1;
      svg.append(t);
    }
  }
  P.hintPath = svgEl('path', { d: '', stroke: 'rgba(229,72,77,.7)', ...style });
  svg.append(P.hintPath);
  $('#practiceCount').textContent = `${Math.min(P.done, strokes.length)} / ${strokes.length} かく`;
}
function showHint() {
  const strokes = practiceStrokes();
  if (P.done >= strokes.length || !P.hintPath) return;
  P.hintPath.setAttribute('d', pathD(strokes[P.done]));
  animateStroke(P.hintPath, 800);
}
function judge(points) {
  const strokes = practiceStrokes();
  if (P.done >= strokes.length) return false;
  const user = resample(points);
  let len = 0;
  for (let i = 1; i < user.length; i++) len += dist2(user[i], user[i - 1]);
  if (len < 0.03) return false;
  const th = P.mode === 'trace' ? 0.15 : 0.2;
  const target = strokes[P.done];
  if (strokeDist(user, target) < th) {
    P.done++; P.strokeMistakes = 0;
    const msgs = ['いいね！', 'そのちょうし！', 'じょうず！'];
    setFeedback(P.done >= strokes.length ? 'できた！' : msgs[Math.floor(Math.random() * msgs.length)], true);
    renderGuide();
    if (P.done >= strokes.length) finishPractice();
    return true;
  }
  P.mistakes++; P.strokeMistakes++;
  if (strokeDist(user.slice().reverse(), target) < th) setFeedback('かく むきが ぎゃくだよ', false);
  else if (strokes.some((s, j) => j > P.done && strokeDist(user, s) < th)) setFeedback('かきじゅんが ちがうよ', false);
  else setFeedback('もういちど かいてみよう', false);
  if (P.mode === 'trace' || P.strokeMistakes >= 2) showHint();
  return false;
}
function finishPractice() {
  P.pad.disabled = true;
  const o = $('#practiceDone');
  o.innerHTML = `<div class="mark">${P.mistakes === 0 ? '💮' : '⭕️'}</div><div>${P.mistakes === 0 ? 'かんぺき！' : `できたね！（まちがい ${P.mistakes}かい）`}</div>`;
  o.hidden = false;
  $('#practiceNext').textContent = 'つぎへ →';
}

/* ---------------- 書き取りテスト ---------------- */
const T = { grade: 1, questions: [], index: 0, results: [] };
function renderTestSetup() {
  $('#testBody').innerHTML = `
    <p class="sub">どの がくねんの かんじに する？</p>
    <div class="tabs" id="testGrades">${GRADES.map((g) => `<button class="tab${g === T.grade ? ' active' : ''}" data-g="${g}">${gradeShort(g)}</button>`).join('')}</div>
    <div class="btn-row" style="margin-top:24px"><button class="big blue" id="testStart">5もん スタート！</button></div>`;
}
function testPrompt(e) {
  if (e.examples.length) return `「${e.examples[0].split(e.kanji).join('□')}」の □ に 入る かんじを かこう`;
  return `「${(e.kunyomi[0] || e.onyomi[0] || '').replace(/[()]/g, '')}」と よむ かんじを かこう`;
}
function startTest() {
  const pool = S.ordered.filter((e) => e.grade === T.grade && S.raw[e.kanji]);
  T.questions = pool.sort(() => Math.random() - 0.5).slice(0, 5);
  T.index = 0; T.results = [];
  $('#dlgTest').close();
  nextQuestion();
}
function nextQuestion() {
  if (T.index >= T.questions.length) { showTestResult(); return; }
  const e = T.questions[T.index];
  openPractice(e.kanji, 'test', {
    prompt: testPrompt(e),
    onNext: () => { T.results.push([e.kanji, P.done >= practiceStrokes().length ? P.mistakes : -1]); T.index++; nextQuestion(); },
  });
}
function showTestResult() {
  $('#dlgPractice').close();
  const perfect = T.results.filter((r) => r[1] === 0).length;
  $('#testBody').innerHTML = `
    <p class="prompt">${T.results.length}もん中 ${perfect}もん かんぺき！</p>
    <div class="test-results">${T.results.map(([k, m]) => `<div><div class="k">${esc(k)}</div>${m === 0 ? '💮' : m > 0 ? '⭕️' : '🔺'}</div>`).join('')}</div>
    <div class="btn-row"><button class="big orange" id="testAgain">もういちど</button><button class="big blue" id="testSetup">ほかの 学年</button></div>`;
  openDialog('#dlgTest');
}

/* ---------------- 起動 ---------------- */
async function main() {
  const get = (u) => fetch(u).then((r) => { if (!r.ok) throw new Error(u); return r.json(); });
  const [kanji, strokes, extras] = await Promise.all([get('data/kanji.json'), get('data/strokes.json'), get('data/extras.json')]);
  kanji.forEach((e) => { S.dict[e.kanji] = e; });
  S.ordered = kanji.map((e, i) => [e, i]).sort((a, b) => a[0].grade - b[0].grade || a[1] - b[1]).map((x) => x[0]);
  S.raw = strokes;
  for (const [k, s] of Object.entries(strokes)) S.norm[k] = normalize(s);
  S.info = extras.info || {};
  S.antonyms = extras.antonyms || {};
  for (const i of extras.idioms || []) {
    for (const ch of new Set([...i.text])) (S.idiomMap[ch] = S.idiomMap[ch] || []).push(i);
  }

  $('#loading').hidden = true;
  $('#app').hidden = false;

  mainPad = new HandCanvas($('#mainCanvas'), { onChange: onMainChange });
  P.pad = new HandCanvas($('#practiceCanvas'), { onStrokeEnd: judge });

  $('#clearBtn').onclick = () => mainPad.clear();
  $('#undoBtn').onclick = () => mainPad.undo();
  $('#searchBtn').onclick = runRecognition;
  $('#candidates').onclick = (ev) => { const b = ev.target.closest('button'); if (b) select(b.dataset.k); };
  $('#card').onclick = onCardClick;

  // メニュー
  const menu = $('#menu');
  $('#menuBtn').onclick = (ev) => { ev.stopPropagation(); menu.hidden = !menu.hidden; };
  document.addEventListener('click', () => { menu.hidden = true; });
  menu.onclick = (ev) => {
    const b = ev.target.closest('button');
    if (!b) return;
    menu.hidden = true;
    if (b.dataset.open === 'search') { $('#readingInput').value = ''; renderSearch(); openDialog('#dlgSearch'); }
    if (b.dataset.open === 'history') { historyTab = 'history'; renderHistory(); openDialog('#dlgHistory'); }
    if (b.dataset.open === 'test') { renderTestSetup(); openDialog('#dlgTest'); }
    if (b.dataset.open === 'about') openDialog('#dlgAbout');
  };

  // さがす
  $('#readingInput').oninput = renderSearch;
  $('#gradeTabs').onclick = (ev) => { const b = ev.target.closest('button'); if (b) { searchGrade = +b.dataset.g; renderSearch(); } };
  $('#searchGrid').onclick = (ev) => { const b = ev.target.closest('button'); if (b) { $('#dlgSearch').close(); select(b.dataset.k); } };

  // りれき
  $('#historyTabs').onclick = (ev) => { const b = ev.target.closest('button'); if (b) { historyTab = b.dataset.tab; renderHistory(); } };
  $('#historyGrid').onclick = (ev) => { const b = ev.target.closest('button'); if (b) { $('#dlgHistory').close(); select(b.dataset.k); } };
  $('#clearHistory').onclick = () => { if (confirm('りれきを ぜんぶ けしますか？')) { Store.set('history', []); renderHistory(); } };

  // 書き順
  $('#orderReplay').onclick = playOrder;
  $('#orderStep').onclick = stepOrder;
  $('#dlgOrder').addEventListener('close', () => { orderRun++; });

  // 練習
  $('#practiceTabs').onclick = (ev) => { const b = ev.target.closest('button'); if (b) { P.mode = b.dataset.mode; restartPractice(); } };
  $('#practiceRestart').onclick = restartPractice;
  $('#practiceHint').onclick = showHint;
  $('#practiceNext').onclick = () => { if (P.onNext) P.onNext(); };
  $('#dlgPractice').addEventListener('close', () => { if (P.onNext && T.index < T.questions.length) { T.questions = []; } P.onNext = null; });

  // テスト
  $('#testBody').onclick = (ev) => {
    const b = ev.target.closest('button');
    if (!b) return;
    if (b.dataset.g) { T.grade = +b.dataset.g; renderTestSetup(); }
    if (b.id === 'testStart' || b.id === 'testAgain') startTest();
    if (b.id === 'testSetup') renderTestSetup();
  };

  $('#idiomSpeak').onclick = () => currentIdiom && speak(currentIdiom.reading + '。' + meaningOf(currentIdiom));

  if ('serviceWorker' in navigator && location.protocol === 'https:') {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
}

main().catch((err) => {
  console.error(err);
  $('#loading').textContent = 'データを よみこめませんでした。ページを よみなおしてください。';
});
