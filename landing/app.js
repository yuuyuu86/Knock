/* ============================================================
   Knock — landing page interactions
   ============================================================ */
(() => {
  'use strict';

  const $  = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const svg = (d, extra = '') =>
    `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;

  /* ---------- icon set ---------- */
  const ICON = {
    camera:   '<rect x="3" y="6" width="18" height="14" rx="2.4"/><circle cx="12" cy="13" r="3.4"/><path d="M8.5 6l1.3-2h4.4L15.5 6"/>',
    clipboard:'<rect x="7" y="4" width="10" height="17" rx="2"/><path d="M9.5 4V3h5v1"/><path d="M4 8v11a2 2 0 002 2"/>',
    play:     '<path d="M7 4.8v14.4L19 12z"/>',
    next:     '<path d="M6 5l10 7-10 7z"/><path d="M18 5v14"/>',
    speaker:  '<path d="M5 9.5h3.2L13 5.5v13l-4.8-4H5z"/><path d="M16.5 9.5a4 4 0 010 5"/>',
    wifi:     '<path d="M3 9.5a14 14 0 0118 0"/><path d="M6.5 13a9 9 0 0111 0"/><path d="M10 16.4a4 4 0 014 0"/><circle cx="12" cy="19.6" r=".9" fill="currentColor"/>',
    window:   '<rect x="3" y="4.5" width="18" height="15" rx="2.2"/><path d="M3 9h18"/>',
    bolt:     '<path d="M13.2 2.5L4.8 13.4h6L10 21.5l9.2-11.2h-6.6z"/>',
    lock:     '<rect x="4.8" y="10.5" width="14.4" height="10" rx="2.2"/><path d="M8.5 10.5V7.8a3.5 3.5 0 017 0v2.7"/>',
    sun:      '<circle cx="12" cy="12" r="4"/><path d="M12 2.6v2M12 19.4v2M2.6 12h2M19.4 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M18.7 5.3l-1.4 1.4M6.7 17.3l-1.4 1.4"/>',
    mic:      '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0013 0"/><path d="M12 18v3"/>',
    grid:     '<rect x="3.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.6"/>',
    trash:    '<path d="M4.5 7h15"/><path d="M9 7V5h6v2"/><path d="M6.5 7l.9 12.2A2 2 0 009.4 21h5.2a2 2 0 002-1.8L17.5 7"/>',
    battery:  '<rect x="2.5" y="8" width="16" height="8" rx="2.2"/><path d="M21 11v2"/><rect x="5" y="10.5" width="7" height="3" rx="1" fill="currentColor" stroke="none"/>',
    link:     '<path d="M10.5 13.5a4 4 0 006 .5l2-2a4 4 0 00-5.7-5.7l-1.1 1.1"/><path d="M13.5 10.5a4 4 0 00-6-.5l-2 2a4 4 0 005.7 5.7l1.1-1.1"/>',
    keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2.4"/><path d="M6.5 10h.01M10 10h.01M13.5 10h.01M17 10h.01M8 14h8"/>',
    moon:     '<path d="M20 14.5A8.5 8.5 0 019.5 4a8.5 8.5 0 1010.5 10.5z"/>',
  };

  /* ---------- action catalogue ---------- */
  const CATEGORIES = [
    { name: 'スクリーンショットとクリップボード', icon: ICON.camera, items: [
      'スクリーンショット → クリップボード', 'スクリーンショット → デスクトップ', 'スクリーンショット（範囲選択）',
      'コピー（⌘C）', 'ペースト（⌘V）', '書式なしでペースト', '取り消す（⌘Z）', 'やり直す（⇧⌘Z）' ] },
    { name: 'メディアと音量', icon: ICON.play, items: [
      'ミュート / 解除', '音量を上げる', '音量を下げる', '再生 / 一時停止', '次の曲へ', '前の曲へ' ] },
    { name: '入力・ディスプレイ・集中モード', icon: ICON.mic, items: [
      'マイクのミュート / 解除', '画面の明るさを上げる', '画面の明るさを下げる',
      'キーボードバックライトを上げる', 'キーボードバックライトを下げる', '集中モードを切り替える…' ] },
    { name: 'カスタムショートカット', icon: ICON.bolt, items: [
      'キーボードショートカットを送る…', 'アプリケーションを開く…', 'URL を開く…', 'Apple ショートカットを実行…' ] },
    { name: 'ウインドウとスペース', icon: ICON.window, items: [
      'Mission Control', 'Spotlight 検索', 'クイックメモ', '最前面のウインドウを最小化', '最前面のウインドウを閉じる',
      'ウインドウを左半分へ', 'ウインドウを右半分へ', 'ウインドウを最大化', 'フルスクリーン切り替え',
      '最前面のアプリを隠す', 'ほかのアプリを隠す', '前のスペースへ', '次のスペースへ',
      '直前のアプリに切り替え', 'アプリスイッチャー（叩いて送る）', '最前面のアプリを終了' ] },
    { name: 'ロック・スリープ・スクリーンセーバ', icon: ICON.lock, items: [
      '画面をロック', 'スクリーンセーバを開始', 'ディスプレイをスリープ' ] },
    { name: '接続', icon: ICON.wifi, items: [
      'Wi‑Fi のオン / オフ', 'Bluetooth のオン / オフ', '外部ディスクを取り出す' ] },
    { name: 'システムとユーティリティ', icon: ICON.grid, items: [
      'ゴミ箱を空にする', 'バッテリー残量を表示', '新規メールを作成', '現在の天気を表示' ] },
  ];

  /* flat list for the picker */
  const PICKER_GROUPS = CATEGORIES.map(c => ({ name: c.name, items: c.items }));

  /* ---------- 1. theme ---------- */
  const root = document.documentElement;
  try {
    const saved = localStorage.getItem('knock-theme');
    if (saved) root.dataset.theme = saved;
  } catch (_) {}
  $('#themeBtn').addEventListener('click', () => {
    const isDark = root.dataset.theme
      ? root.dataset.theme === 'dark'
      : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = isDark ? 'light' : 'dark';
    try { localStorage.setItem('knock-theme', root.dataset.theme); } catch (_) {}
  });

  /* ---------- 2. nav ---------- */
  const nav = $('#nav');
  addEventListener('scroll', () => nav.classList.toggle('scrolled', scrollY > 10), { passive: true });
  const toggle = $('#navToggle');
  toggle.addEventListener('click', () => {
    const open = nav.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(open));
  });
  $$('#navLinks a').forEach(a => a.addEventListener('click', () => nav.classList.remove('open')));

  /* ---------- 3. hero rotator ---------- */
  const ROT = [
    ['スクショ',       ICON.camera],
    ['音楽を操作',     ICON.play],
    ['ウインドウ整列', ICON.window],
    ['Wi‑Fi 切替',     ICON.wifi],
    ['ショートカット', ICON.bolt],
    ['画面をロック',   ICON.lock],
  ];
  const rotEl = $('#rotator'), rotWord = $('#rotWord'), rotIco = $('#rotIco');
  let rotI = 0;
  setInterval(() => {
    rotI = (rotI + 1) % ROT.length;
    const [word, icon] = ROT[rotI];
    rotEl.classList.remove('swap');
    void rotEl.offsetWidth;
    rotWord.textContent = word;
    rotIco.innerHTML = icon;
    rotEl.classList.add('swap');
  }, 2600);
  rotIco.innerHTML = ICON.camera;

  /* ---------- 4. tap ripple + chip highlight loop ---------- */
  const zones = { L: $('#zoneL'), R: $('#zoneR') };
  const chips = Object.fromEntries($$('.chip').map(c => [c.dataset.chip, c]));
  const SEQ = ['L1', 'R1', 'L2', 'R3', 'L3', 'R2'];
  let seqI = 0;

  function pulse(key) {
    const side = key[0], count = +key[1];
    const zone = zones[side];
    Object.values(chips).forEach(c => c.classList.remove('on'));
    chips[key]?.classList.add('on');
    if (!zone) return;
    let n = 0;
    const tick = () => {
      zone.classList.remove('hit');
      void zone.offsetWidth;
      zone.classList.add('hit');
      if (++n < count) setTimeout(tick, 170);
    };
    tick();
  }
  setInterval(() => { pulse(SEQ[seqI]); seqI = (seqI + 1) % SEQ.length; }, 2200);
  setTimeout(() => pulse(SEQ[0]), 800);

  /* ---------- 5. marquee band ---------- */
  const BAND = [
    ['スクリーンショット', ICON.camera], ['再生 / 一時停止', ICON.play], ['ウインドウを左半分へ', ICON.window],
    ['Wi‑Fi 切り替え', ICON.wifi], ['Apple ショートカット', ICON.bolt], ['画面をロック', ICON.lock],
    ['マイクのミュート', ICON.mic], ['Mission Control', ICON.grid], ['明るさを上げる', ICON.sun],
    ['ゴミ箱を空にする', ICON.trash], ['URL を開く', ICON.link], ['キー入力を送る', ICON.keyboard],
  ];
  const bandHTML = BAND.map(([t, i]) => `<span>${svg(i)}${t}</span>`).join('');
  $('#marquee').innerHTML = bandHTML + bandHTML;

  /* ---------- 6. knock map ---------- */
  const DEFAULTS = {
    L: ['ミュート / 解除', 'スクリーンショット → クリップボード', 'Apple ショートカットを実行…'],
    R: ['再生 / 一時停止', '次の曲へ', 'Wi‑Fi のオン / オフ'],
  };
  const state = { L: [...DEFAULTS.L], R: [...DEFAULTS.R] };
  const LABEL = ['1 回タップ', '2 回タップ', '3 回タップ'];

  function renderSlots(side) {
    const host = $(side === 'L' ? '#slotsL' : '#slotsR');
    host.innerHTML = state[side].map((v, i) => `
      <button class="slot" data-side="${side}" data-i="${i}">
        <span class="slot-dots">${'<i></i>'.repeat(i + 1)}</span>
        <span class="slot-body">
          <span class="k">${LABEL[i]}</span>
          <span class="v">${v}</span>
        </span>
        <span class="slot-edit">変更${svg('<path d="M4 20h4L19 9a2.8 2.8 0 10-4-4L4 16z"/>')}</span>
      </button>`).join('');
  }
  renderSlots('L'); renderSlots('R');

  /* picker popover */
  let picker = null;
  function closePicker() { picker?.remove(); picker = null; }
  addEventListener('click', e => { if (picker && !picker.contains(e.target) && !e.target.closest('.slot')) closePicker(); });
  addEventListener('keydown', e => { if (e.key === 'Escape') closePicker(); });
  addEventListener('scroll', closePicker, { passive: true });

  document.addEventListener('click', e => {
    const slot = e.target.closest('.slot');
    if (!slot) return;
    const { side, i } = slot.dataset;
    closePicker();

    picker = document.createElement('div');
    picker.className = 'picker';
    picker.innerHTML = PICKER_GROUPS.map(g =>
      `<div class="grp">${g.name}</div>` +
      g.items.map(it => `<button data-v="${it}" class="${it === state[side][i] ? 'sel' : ''}">${it}</button>`).join('')
    ).join('');
    document.body.appendChild(picker);

    const r = slot.getBoundingClientRect();
    const w = picker.offsetWidth, h = picker.offsetHeight;
    let left = Math.min(r.left, innerWidth - w - 16);
    let top  = r.bottom + 8;
    if (top + h > innerHeight - 12) top = Math.max(12, r.top - h - 8);
    picker.style.left = Math.max(16, left) + 'px';
    picker.style.top  = top + 'px';

    picker.addEventListener('click', ev => {
      const b = ev.target.closest('button[data-v]');
      if (!b) return;
      state[side][+i] = b.dataset.v;
      renderSlots(side);
      closePicker();
      const fresh = $(`.slot[data-side="${side}"][data-i="${i}"]`);
      fresh.classList.add('firing');
      setTimeout(() => fresh.classList.remove('firing'), 650);
    });
  });

  /* ---------- 7. actions catalogue ---------- */
  $('#catGrid').innerHTML = CATEGORIES.map(c => `
    <div class="cat rv">
      <h3><span class="ico">${svg(c.icon)}</span>${c.name}</h3>
      <ul>${c.items.map(i => `<li>${i}</li>`).join('')}</ul>
    </div>`).join('');

  /* ---------- 8. demo player ---------- */
  const STEPS = [
    { t: '側面をノック',       h: '左側を 2 回',            s: '本体の内蔵センサーが振動のパターンを読み取ります。', i: ICON.speaker },
    { t: 'ジェスチャーを判定', h: 'ダブルタップとして認識', s: 'タイピングやトラックパッド操作とは区別されます。',   i: ICON.grid },
    { t: 'アクションを実行',   h: 'スクリーンショット',     s: '割り当てたアクションがその場で走ります。',           i: ICON.camera },
    { t: '結果を受け取る',     h: 'クリップボードへ保存',   s: '⌘V ですぐに貼り付けられます。',                      i: ICON.clipboard },
  ];
  const stepsHost = $('#demoSteps'), visual = $('#demoVisual');
  stepsHost.innerHTML = STEPS.map((s, i) =>
    `<div class="demo-step" data-i="${i}"><span class="n">${i + 1}</span>${s.t}</div>`).join('');

  let demoI = -1, demoTimer = null;
  function showStep(i) {
    demoI = i;
    $$('.demo-step').forEach((el, k) => el.classList.toggle('on', k === i));
    const s = STEPS[i];
    visual.innerHTML = `
      <div class="big">${svg(s.i)}</div>
      <h4>${s.h}</h4>
      <p>${s.s}</p>`;
  }
  function startDemo() {
    clearInterval(demoTimer);
    showStep(0);
    demoTimer = setInterval(() => showStep((demoI + 1) % STEPS.length), 2400);
  }
  stepsHost.addEventListener('click', e => {
    const el = e.target.closest('.demo-step');
    if (!el) return;
    clearInterval(demoTimer);
    showStep(+el.dataset.i);
    demoTimer = setInterval(() => showStep((demoI + 1) % STEPS.length), 2400);
  });
  showStep(0);

  const demoObs = new IntersectionObserver(es => {
    es.forEach(e => e.isIntersecting ? startDemo() : clearInterval(demoTimer));
  }, { threshold: .3 });
  demoObs.observe($('#demo'));

  /* ---------- 9. pricing ---------- */
  const TIERS = [
    { now: '$5',  was: '$12', note: '1 台の Mac で利用可能' },
    { now: '$9',  was: '$20', note: '2 台の Mac で利用可能' },
    { now: '$12', was: '$28', note: '3 台の Mac で利用可能' },
  ];
  const seg = $('#seg'), thumb = $('#segThumb');
  function moveThumb(btn) {
    thumb.style.left  = btn.offsetLeft + 'px';
    thumb.style.width = btn.offsetWidth + 'px';
  }
  seg.addEventListener('click', e => {
    const b = e.target.closest('button[data-tier]');
    if (!b) return;
    $$('#seg button').forEach(x => x.classList.toggle('on', x === b));
    const t = TIERS[+b.dataset.tier];
    $('#priceNow').textContent = t.now;
    $('#priceWas').textContent = t.was;
    $('#tierNote').textContent = t.note;
    moveThumb(b);
  });
  const initBtn = $('#seg button.on');
  requestAnimationFrame(() => moveThumb(initBtn));
  addEventListener('resize', () => moveThumb($('#seg button.on')));

  $('#buyBtn').addEventListener('click', e => {
    e.preventDefault();
    const label = $('#buyBtn').textContent;
    $('#buyBtn').textContent = 'チェックアウトは準備中です';
    setTimeout(() => { $('#buyBtn').textContent = label; }, 1800);
  });

  /* ---------- 10. FAQ ---------- */
  const FAQ = [
    { q: 'Knock とは何ですか？',
      a: 'MacBook 本体の左右側面への物理的なタップを、macOS の操作や Apple ショートカットの実行に変換するネイティブアプリです。メニューバーに常駐し、設定した回数のノックを検出すると対応するアクションを実行します。' },
    { q: '対応している MacBook は？',
      a: '本体の内蔵モーションセンサーを利用するため、対応するハードウェアを備えた Apple シリコン搭載の MacBook が必要です。Intel Mac には対応していません。',
      chips: ['MacBook Air M2 / M3 / M4', 'MacBook Pro M1 Pro / M1 Max', 'MacBook Pro M2 以降の各世代'] },
    { q: 'いくつジェスチャーを設定できますか？',
      a: '左側の 1回・2回・3回タップ、右側の 1回・2回・3回タップで、合計 6 つのジェスチャーを自由に割り当てられます。' },
    { q: 'Apple ショートカットは使えますか？',
      a: 'はい。ショートカット App で作成した処理はすべて、50 種類以上の内蔵アクションと並べてノックに割り当てられます。' },
    { q: 'サブスクリプションですか？',
      a: 'いいえ。買い切りです。一度購入すれば、アプリ本体とその後のアップデートをずっと使えます。' },
    { q: '感度は調整できますか？',
      a: 'はい。タイピングやトラックパッドの操作で誤検出しないよう、ノックの検出しきい値を細かく調整できます。' },
    { q: '閉じた状態でも動きますか？',
      a: '動きません。本体のセンサーからデータを読み取る仕組みのため、MacBook を開いて使用している間のみタップを検出します。' },
    { q: 'データはどう扱われますか？',
      a: 'すべての処理は Mac 内で完結します。ジェスチャーの設定内容やアクションの実行履歴がサーバーへ送信されることはありません。' },
    { q: '何台の Mac で使えますか？',
      a: 'ライセンスは 1 台・2 台・3 台から選べます。購入時に台数を選択してください。いずれも個人利用の範囲でご利用いただけます。' },
    { q: '返金はできますか？',
      a: 'ワークフローに合わなかった場合は、購入から 14 日以内にご連絡ください。理由を問わず全額返金します。' },
  ];
  $('#faqList').innerHTML = FAQ.map((f, i) => `
    <div class="qa rv" data-i="${i}">
      <button aria-expanded="false">
        ${f.q}
        <span class="chev">${svg('<path d="M6 9.5l6 6 6-6"/>', 'stroke-width="2.4"')}</span>
      </button>
      <div class="ans"><div>
        <p>${f.a}</p>
        ${f.chips ? `<div class="chip-row">${f.chips.map(c => `<span>${c}</span>`).join('')}</div>` : ''}
      </div></div>
    </div>`).join('');

  $('#faqList').addEventListener('click', e => {
    const btn = e.target.closest('.qa > button');
    if (!btn) return;
    const qa = btn.parentElement;
    const open = qa.classList.toggle('open');
    btn.setAttribute('aria-expanded', String(open));
  });

  /* ---------- 11. scroll reveal ---------- */
  const rvTargets = ['.section .center', '.map-grid', '.demo-frame', '.price-card', '.pay-note', '.cta-box', '.hero-stage'];
  rvTargets.forEach(sel => $$(sel).forEach(el => el.classList.add('rv')));
  const io = new IntersectionObserver((entries, obs) => {
    entries.forEach(en => {
      if (!en.isIntersecting) return;
      en.target.classList.add('in');
      obs.unobserve(en.target);
    });
  }, { threshold: .12, rootMargin: '0px 0px -40px 0px' });
  $$('.rv').forEach((el, i) => { el.style.transitionDelay = `${Math.min(i % 6, 5) * 55}ms`; io.observe(el); });

  /* ---------- 12. misc ---------- */
  $('#year').textContent = new Date().getFullYear();
})();
