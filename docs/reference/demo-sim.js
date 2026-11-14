/* プロンプトバトル デモ：戦闘シミュレーション（描画に依存しない） */
(function (root) {
  'use strict';

  /* 端末やブラウザが違っても計算結果が一致するよう、四則演算と平方根だけで作った関数 */
  var PI = Math.PI, TAU = Math.PI * 2;
  function hyp(a, b) { return Math.sqrt(a * a + b * b); }
  function dsin(x) {
    x = x - TAU * Math.floor(x / TAU + 0.5);
    if (x > PI / 2) x = PI - x; else if (x < -PI / 2) x = -PI - x;
    var x2 = x * x;
    return x * (1 + x2 * (-1 / 6 + x2 * (1 / 120 + x2 * (-1 / 5040 + x2 * (1 / 362880 + x2 * (-1 / 39916800))))));
  }
  function dcos(x) { return dsin(x + PI / 2); }
  function datanUnit(z) {
    var z2 = z * z;
    return z * (0.99997726 + z2 * (-0.33262347 + z2 * (0.19354346 + z2 * (-0.11643287 + z2 * (0.05265332 + z2 * -0.0117212)))));
  }
  function datan2(y, x) {
    if (x === 0 && y === 0) return 0;
    var ax = x < 0 ? -x : x, ay = y < 0 ? -y : y;
    var a = ax >= ay ? datanUnit(ay / ax) : PI / 2 - datanUnit(ax / ay);
    if (x < 0) a = PI - a;
    return y < 0 ? -a : a;
  }
  function makeRng(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  var PARTS = {
    // 車体
    light:   { slot: 'body', name: '軽量フレーム', hp: 90,  mass: 0.8, speedMul: 1.2, desc: '軽くて速い。押されやすく、もろい' },
    standard:{ slot: 'body', name: '標準ボディ',   hp: 120, mass: 1.0, speedMul: 1.0, desc: 'くせのない標準型' },
    heavy:   { slot: 'body', name: '重装甲ボディ', hp: 160, mass: 1.5, speedMul: 0.8, desc: '硬くて重い。遅いが押し負けない' },
    // 足回り
    small:   { slot: 'wheels', name: '小径タイヤ', speed: 9.0, turn: 3.2, grip: 0.8, desc: '最速で小回りがきく。踏ん張りは弱い' },
    big:     { slot: 'wheels', name: '大径タイヤ', speed: 7.5, turn: 2.4, grip: 1.0, desc: '速さと踏ん張りのバランス型' },
    tracks:  { slot: 'wheels', name: 'キャタピラ', speed: 5.5, turn: 1.8, grip: 1.6, desc: '遅くて曲がりにくい。押し合いに強い' },
    // 前面パーツ
    drill:   { slot: 'front', name: 'ドリル',   desc: '前で触れている間ずっと削る（毎秒13）' },
    hammer:  { slot: 'front', name: 'ハンマー', desc: '前の相手を1.5秒ごとに叩く（20ダメージ＋吹き飛ばし）' },
    lifter:  { slot: 'front', name: 'リフター', desc: '前の相手をひっくり返して1.6秒動けなくする' },
    bumper:  { slot: 'front', name: 'バンパー', desc: '体当たりの威力と吹き飛ばしが大きい。穴落とし向き' },
    // 上部パーツ
    mg:      { slot: 'top', name: '機関銃',     desc: '正面にしか撃てない。射程15、弾150発' },
    rocket:  { slot: 'top', name: 'ロケット',   desc: '正面に発射。17ダメージ＋吹き飛ばし、弾は6発だけ' },
    booster: { slot: 'top', name: 'ブースター', desc: '1秒間だけ2倍速。5秒ごとに使える' },
    shield:  { slot: 'top', name: 'シールド',   desc: '正面から受けるダメージを半分にする' }
  };
  var SLOTS = ['body', 'wheels', 'front', 'top'];
  var SLOT_NAMES = { body: '車体', wheels: '足回り', front: '前面パーツ', top: '上部パーツ' };

  var ARENA = {
    half: 15,
    pits: [{ x: -4, z: -7, r: 2.4 }, { x: 4, z: 7, r: 2.4 }],
    pads: [{ x: -11.5, z: 10.5, r: 2.0 }, { x: 11.5, z: -10.5, r: 2.0 }],
    time: 75
  };

  var ACTIONS = {
    charge: '突撃', flank: '回り込み', keep_distance: '距離を取る', retreat: '逃げる',
    push_to_pit: '穴へ押し込む', go_repair: '修理に向かう', circle: '周りを回る', hold: 'その場で待つ'
  };
  var CONDS = {
    always: function () { return 'いつでも'; },
    enemy_dist_lt: function (v) { return '相手との距離が' + v + 'より近い'; },
    enemy_dist_gt: function (v) { return '相手との距離が' + v + 'より遠い'; },
    my_hp_lt: function (v) { return '自分のHPが' + v + '%未満'; },
    my_hp_gt: function (v) { return '自分のHPが' + v + '%以上'; },
    enemy_hp_lt: function (v) { return '相手のHPが' + v + '%未満'; },
    time_left_lt: function (v) { return '残り時間が' + v + '秒未満'; },
    ammo_empty: function () { return '弾が切れた'; },
    enemy_near_pit: function (v) { return '相手が穴の近く（' + v + '以内）にいる'; },
    enemy_stunned: function () { return '相手がひっくり返っている'; },
    behind_enemy: function () { return '自分が相手の後ろ側にいる'; }
  };
  var COND_DEFAULT = { enemy_dist_lt: 6, enemy_dist_gt: 8, my_hp_lt: 40, my_hp_gt: 60, enemy_hp_lt: 40, time_left_lt: 20, enemy_near_pit: 5 };
  var BOOST_MODES = { never: '使わない', always: '使えるときは常に使う', on_charge: '突撃・押し込みのとき使う', on_retreat: '逃げるとき使う' };

  /* ---------- 作戦（プラン）の検証 ---------- */
  function sanitizePlan(raw) {
    var plan = { avoid_pits: false, use_boost: 'never', rules: [], pilot_comment: '' };
    if (!raw || typeof raw !== 'object') return plan;
    plan.avoid_pits = raw.avoid_pits === true;
    if (BOOST_MODES[raw.use_boost]) plan.use_boost = raw.use_boost;
    if (typeof raw.pilot_comment === 'string') plan.pilot_comment = raw.pilot_comment.slice(0, 80);
    var rules = Array.isArray(raw.rules) ? raw.rules : [];
    for (var i = 0; i < rules.length && plan.rules.length < 5; i++) {
      var r = rules[i];
      if (!r || !ACTIONS[r['do']]) continue;
      var conds = r['if'];
      if (!Array.isArray(conds)) conds = conds ? [conds] : [];
      var out = [];
      for (var j = 0; j < conds.length && out.length < 3; j++) {
        var c = conds[j];
        if (typeof c === 'string') c = { type: c };
        if (!c || !CONDS[c.type] || c.type === 'always') continue;
        var v = Number(c.value);
        if (!isFinite(v)) v = COND_DEFAULT[c.type];
        if (v !== undefined) v = Math.max(1, Math.min(100, Math.round(v)));
        out.push({ type: c.type, value: v });
      }
      var rule = { 'if': out, 'do': r['do'] };
      var d = Number(r.distance);
      if (isFinite(d)) rule.distance = Math.max(3, Math.min(14, d));
      plan.rules.push(rule);
    }
    return plan;
  }

  function describeRule(rule) {
    var cs = rule['if'].length
      ? rule['if'].map(function (c) { return CONDS[c.type](c.value); }).join(' かつ ')
      : 'いつでも';
    var act = ACTIONS[rule['do']];
    if ((rule['do'] === 'keep_distance' || rule['do'] === 'circle') && rule.distance) act += '（距離' + rule.distance + '）';
    return { when: cs, act: act };
  }

  /* ---------- 機体 ---------- */
  function makeBot(id, name, build, plan, x, z, th) {
    var b = PARTS[build.body], w = PARTS[build.wheels];
    return {
      id: id, name: name, build: build, plan: sanitizePlan(plan),
      x: x, z: z, th: th, vx: 0, vz: 0,
      hp: b.hp, maxHp: b.hp, mass: b.mass, eff: b.mass * w.grip,
      maxSpeed: w.speed * b.speedMul, turn: w.turn, radius: 1.25,
      ammo: build.top === 'mg' ? 150 : build.top === 'rocket' ? 6 : 0,
      cdFront: 0.5, cdTop: 0.5, cdBoost: 1, boostT: 0, stun: 0, ramCd: 0,
      repairLeft: 40, alive: true, falling: 0,
      action: 'hold', ruleIndex: -1, swing: 0, thinkT: 0, side: id === 0 ? 1 : -1, dealt: 0
    };
  }

  function createMatch(buildA, planA, buildB, planB, names, seed) {
    names = names || ['あなた', 'CPU'];
    return {
      t: 0, timeLeft: ARENA.time, over: null, steps: 0,
      rng: makeRng(seed === undefined ? Math.floor(Math.random() * 4294967296) : seed),
      bots: [
        makeBot(0, names[0], buildA, planA, -11, 0, 0),
        makeBot(1, names[1], buildB, planB, 11, 0, Math.PI)
      ],
      shots: [], events: []
    };
  }

  function angDiff(a, b) {
    var d = a - b;
    while (d > Math.PI) d -= 2 * Math.PI;
    while (d < -Math.PI) d += 2 * Math.PI;
    return d;
  }
  function dist(a, b) { return hyp(a.x - b.x, a.z - b.z); }
  function inFront(me, target, arc) {
    return Math.abs(angDiff(datan2(target.z - me.z, target.x - me.x), me.th)) <= arc;
  }
  function nearestPit(p) {
    var best = null, bd = 1e9;
    ARENA.pits.forEach(function (pit) {
      var d = hyp(p.x - pit.x, p.z - pit.z);
      if (d < bd) { bd = d; best = pit; }
    });
    return { pit: best, d: bd };
  }

  /* ---------- 条件判定 ---------- */
  function test(c, me, en, m) {
    var v = c.value;
    switch (c.type) {
      case 'enemy_dist_lt': return dist(me, en) < v;
      case 'enemy_dist_gt': return dist(me, en) > v;
      case 'my_hp_lt': return me.hp / me.maxHp * 100 < v;
      case 'my_hp_gt': return me.hp / me.maxHp * 100 >= v;
      case 'enemy_hp_lt': return en.hp / en.maxHp * 100 < v;
      case 'time_left_lt': return m.timeLeft < v;
      case 'ammo_empty': return (me.build.top === 'mg' || me.build.top === 'rocket') && me.ammo <= 0;
      case 'enemy_near_pit': return nearestPit(en).d < v;
      case 'enemy_stunned': return en.stun > 0;
      case 'behind_enemy': return Math.abs(angDiff(datan2(me.z - en.z, me.x - en.x), en.th)) > 1.75;
    }
    return false;
  }

  function think(me, en, m) {
    var rules = me.plan.rules, idx = -1;
    for (var i = 0; i < rules.length; i++) {
      var ok = true;
      for (var j = 0; j < rules[i]['if'].length; j++) {
        if (!test(rules[i]['if'][j], me, en, m)) { ok = false; break; }
      }
      if (ok) { idx = i; break; }
    }
    var act = idx >= 0 ? rules[idx]['do'] : 'idle';
    if (act !== me.action || idx !== me.ruleIndex) {
      m.events.push({ type: 'action', bot: me.id, action: act, fallback: idx < 0 });
    }
    me.action = act; me.ruleIndex = idx;
  }

  /* ---------- 行動 → 目標地点 ---------- */
  function decide(me, en, m) {
    var rule = me.ruleIndex >= 0 ? me.plan.rules[me.ruleIndex] : null;
    var d = dist(me, en);
    var ux = (en.x - me.x) / (d || 1), uz = (en.z - me.z) / (d || 1);
    var out = { tx: en.x, tz: en.z, throttle: 1, reverse: false, face: null };
    var want;
    switch (me.action) {
      case 'charge':
        break;
      case 'idle': // 当てはまる指示がないときは、その場でうろうろする
        out.face = me.th + 1; out.throttle = 0.3;
        break;
      case 'flank': {
        var rel = Math.abs(angDiff(datan2(me.z - en.z, me.x - en.x), en.th));
        if (rel < 1.9) { // まだ相手の正面〜横にいる → 後ろへ回る
          var hx = dcos(en.th), hz = dsin(en.th);
          var px = -hz * me.side, pz = hx * me.side;
          var off = rel < 1.0 ? 4.5 : 3.0;
          out.tx = en.x + px * off - hx * (rel < 1.0 ? 0 : 3);
          out.tz = en.z + pz * off - hz * (rel < 1.0 ? 0 : 3);
        }
        break;
      }
      case 'keep_distance':
        want = (rule && rule.distance) || 9;
        out.face = datan2(uz, ux);
        if (d < want - 1.5) { out.reverse = true; out.throttle = 1; }
        else if (d > want + 1.5) { out.throttle = 0.8; }
        else out.throttle = 0;
        break;
      case 'retreat':
        out.tx = me.x - ux * 8; out.tz = me.z - uz * 8;
        // 壁際では横へ流れる
        if (Math.abs(out.tx) > ARENA.half - 2 || Math.abs(out.tz) > ARENA.half - 2) {
          out.tx = me.x - uz * 8 * me.side; out.tz = me.z + ux * 8 * me.side;
        }
        break;
      case 'push_to_pit': {
        var np = nearestPit(en).pit;
        var ex = en.x - np.x, ez = en.z - np.z, el = hyp(ex, ez) || 1;
        ex /= el; ez /= el;
        // 相手をはさんで穴の反対側に立つ
        var sx = en.x + ex * 3.2, sz = en.z + ez * 3.2;
        var lined = (ux * -ex + uz * -ez) > 0.8;
        if (!lined && hyp(sx - me.x, sz - me.z) > 1.2) { out.tx = sx; out.tz = sz; }
        break;
      }
      case 'go_repair': {
        var pad = ARENA.pads[0], pd = 1e9;
        ARENA.pads.forEach(function (p) {
          var q = hyp(p.x - me.x, p.z - me.z);
          if (q < pd) { pd = q; pad = p; }
        });
        out.tx = pad.x; out.tz = pad.z;
        if (pd < 0.8) out.throttle = 0;
        break;
      }
      case 'circle':
        want = (rule && rule.distance) || 7;
        out.tx = en.x - ux * want - uz * 4 * me.side;
        out.tz = en.z - uz * want + ux * 4 * me.side;
        break;
      case 'hold':
        out.face = datan2(uz, ux); out.throttle = 0;
        break;
    }
    return out;
  }

  function damage(m, victim, amount, fx, fz, kind, attacker) {
    if (!victim.alive || amount <= 0) return 0;
    var a = Math.abs(angDiff(datan2(fz - victim.z, fx - victim.x), victim.th));
    var mod = 1, tag = '';
    if (victim.build.top === 'shield' && a < 1.22) { mod = 0.5; tag = 'shield'; }
    else if (a > 2.1) { mod = 1.5; tag = 'back'; }
    var dmg = amount * mod;
    victim.hp = Math.max(0, victim.hp - dmg);
    if (attacker) attacker.dealt += dmg;
    if (kind !== 'drill' && kind !== 'mg') {
      m.events.push({ type: 'hit', bot: victim.id, kind: kind, dmg: dmg, tag: tag, x: victim.x, z: victim.z });
    } else if (m.rng() < 0.25) {
      m.events.push({ type: 'spark', bot: victim.id, kind: kind, tag: tag, x: victim.x, z: victim.z });
    }
    return dmg;
  }
  function knock(victim, nx, nz, power) {
    victim.vx += nx * power / victim.eff;
    victim.vz += nz * power / victim.eff;
  }

  /* ---------- 1ステップ ---------- */
  function step(m, dt) {
    if (m.over) {
      m.bots.forEach(function (b) { if (b.falling > 0) b.falling += dt; });
      return;
    }
    m.steps++; m.t += dt; m.timeLeft = Math.max(0, ARENA.time - m.t);
    var bots = m.bots, i;

    for (i = 0; i < 2; i++) {
      var me = bots[i], en = bots[1 - i];
      me.cdFront -= dt; me.cdTop -= dt; me.cdBoost -= dt; me.ramCd -= dt;
      me.boostT -= dt; me.swing = Math.max(0, me.swing - dt);
      me.thinkT -= dt;
      if (me.stun > 0) {
        me.stun -= dt;
        me.vx -= me.vx * Math.min(1, 3 * dt); me.vz -= me.vz * Math.min(1, 3 * dt);
        continue;
      }
      if (me.thinkT <= 0) { think(me, en, m); me.thinkT = 0.25; }
      var cmd = decide(me, en, m);

      // 進みたい向き
      var dx = cmd.tx - me.x, dz = cmd.tz - me.z, dl = hyp(dx, dz) || 1;
      dx /= dl; dz /= dl;
      if (me.plan.avoid_pits && !cmd.reverse) {
        var ox = dx, oz = dz;
        ARENA.pits.forEach(function (pit) {
          var ax = me.x - pit.x, az = me.z - pit.z, ad = hyp(ax, az) || 1;
          var reach = pit.r + 3.2;
          if (ad < reach) {
            ax /= ad; az /= ad;
            var w = (reach - ad) / 3.2;
            var tx = -az, tz = ax;
            if (tx * ox + tz * oz < 0) { tx = -tx; tz = -tz; }
            dx += ax * w * 1.8 + tx * w * 1.0;
            dz += az * w * 1.8 + tz * w * 1.0;
          }
        });
      }
      var wantTh = cmd.face !== null ? cmd.face : datan2(dz, dx);
      var diff = angDiff(wantTh, me.th);
      var maxTurn = me.turn * dt;
      me.th += Math.max(-maxTurn, Math.min(maxTurn, diff));

      var thr = cmd.throttle;
      if (!cmd.reverse && cmd.face === null && Math.abs(diff) > 1.2) thr *= 0.25;
      if (dl < 0.6 && cmd.face === null && me.action !== 'charge') thr = 0;

      // ブースター
      if (me.build.top === 'booster' && me.cdBoost <= 0 && thr > 0.5 && Math.abs(diff) < 0.5) {
        var mode = me.plan.use_boost;
        var go = mode === 'always'
          || (mode === 'on_charge' && (me.action === 'charge' || me.action === 'push_to_pit') && dist(me, en) < 9)
          || (mode === 'on_retreat' && me.action === 'retreat');
        if (go) { me.boostT = 1.0; me.cdBoost = 5; m.events.push({ type: 'boost', bot: me.id }); }
      }
      var sp = me.maxSpeed * (me.boostT > 0 ? 2.0 : 1) * thr * (cmd.reverse ? -0.6 : 1);
      var tvx = dcos(me.th) * sp, tvz = dsin(me.th) * sp;
      var k = Math.min(1, 5 * dt);
      me.vx += (tvx - me.vx) * k; me.vz += (tvz - me.vz) * k;

      // 武器
      var d = dist(me, en);
      var contact = d < me.radius + en.radius + 0.7 && inFront(me, en, 0.7);
      var nx = (en.x - me.x) / (d || 1), nz = (en.z - me.z) / (d || 1);
      if (contact && en.alive) {
        if (me.build.front === 'drill') damage(m, en, 13 * dt, me.x, me.z, 'drill', me);
        else if (me.build.front === 'hammer' && me.cdFront <= 0) {
          me.cdFront = 1.5; me.swing = 0.35;
          damage(m, en, 20, me.x, me.z, 'hammer', me); knock(en, nx, nz, 6);
        } else if (me.build.front === 'lifter' && me.cdFront <= 0 && en.stun <= 0) {
          me.cdFront = 4.5; me.swing = 0.5;
          damage(m, en, 6, me.x, me.z, 'lifter', me); knock(en, nx, nz, 3);
          en.stun = 1.6;
          m.events.push({ type: 'flip', bot: en.id });
        }
      }
      if (me.build.top === 'mg' && me.ammo > 0 && me.cdTop <= 0 && d < 15 && inFront(me, en, 0.17)) {
        me.cdTop = 0.18; me.ammo--;
        var sa = me.th + (m.rng() - 0.5) * 0.08;
        m.shots.push({ x: me.x + dcos(me.th) * 1.3, z: me.z + dsin(me.th) * 1.3, vx: dcos(sa) * 32, vz: dsin(sa) * 32, owner: me.id, dmg: 1.5, knock: 0, life: 0.6, kind: 'mg' });
        if (me.ammo === 0) m.events.push({ type: 'ammo_out', bot: me.id });
      }
      if (me.build.top === 'rocket' && me.ammo > 0 && me.cdTop <= 0 && d < 18 && inFront(me, en, 0.14)) {
        me.cdTop = 2.6; me.ammo--;
        m.shots.push({ x: me.x + dcos(me.th) * 1.3, z: me.z + dsin(me.th) * 1.3, vx: dcos(me.th) * 16, vz: dsin(me.th) * 16, owner: me.id, dmg: 17, knock: 7, life: 1.4, kind: 'rocket' });
        m.events.push({ type: 'launch', bot: me.id });
        if (me.ammo === 0) m.events.push({ type: 'ammo_out', bot: me.id });
      }
    }

    // 移動
    for (i = 0; i < 2; i++) {
      var b = bots[i];
      b.x += b.vx * dt; b.z += b.vz * dt;
      var lim = ARENA.half - b.radius;
      if (b.x > lim) { b.x = lim; if (b.vx > 0) b.vx = 0; }
      if (b.x < -lim) { b.x = -lim; if (b.vx < 0) b.vx = 0; }
      if (b.z > lim) { b.z = lim; if (b.vz > 0) b.vz = 0; }
      if (b.z < -lim) { b.z = -lim; if (b.vz < 0) b.vz = 0; }
    }

    // 機体どうしの衝突
    var A = bots[0], B = bots[1];
    var dd = dist(A, B), minD = A.radius + B.radius;
    if (dd < minD) {
      var cx = (B.x - A.x) / (dd || 1), cz = (B.z - A.z) / (dd || 1);
      if (!dd) { cx = 1; cz = 0; }
      var over = minD - dd, tot = A.eff + B.eff;
      A.x -= cx * over * (B.eff / tot); A.z -= cz * over * (B.eff / tot);
      B.x += cx * over * (A.eff / tot); B.z += cz * over * (A.eff / tot);
      var vrel = (A.vx - B.vx) * cx + (A.vz - B.vz) * cz;
      if (vrel > 0) {
        var red = A.eff * B.eff / tot;
        var aB = A.build.front === 'bumper' && inFront(A, B, 0.9);
        var bB = B.build.front === 'bumper' && inFront(B, A, 0.9);
        var j = vrel * 1.3 * red;
        A.vx -= cx * j / A.eff * (bB ? 2 : 1); A.vz -= cz * j / A.eff * (bB ? 2 : 1);
        B.vx += cx * j / B.eff * (aB ? 2 : 1); B.vz += cz * j / B.eff * (aB ? 2 : 1);
        if (vrel > 5 && A.ramCd <= 0 && B.ramCd <= 0) {
          A.ramCd = B.ramCd = 0.7;
          var base = (vrel - 5) * 2.2;
          damage(m, B, base * (A.eff / tot) * 2 * (aB ? 2.5 : 1) * (bB ? 0.3 : 1), A.x, A.z, 'ram', A);
          damage(m, A, base * (B.eff / tot) * 2 * (bB ? 2.5 : 1) * (aB ? 0.3 : 1), B.x, B.z, 'ram', B);
        }
      }
    }

    // 弾
    for (i = m.shots.length - 1; i >= 0; i--) {
      var s = m.shots[i];
      s.x += s.vx * dt; s.z += s.vz * dt; s.life -= dt;
      var tgt = bots[1 - s.owner], gone = s.life <= 0 || Math.abs(s.x) > ARENA.half || Math.abs(s.z) > ARENA.half;
      if (!gone && tgt.alive && hyp(s.x - tgt.x, s.z - tgt.z) < tgt.radius) {
        var sl = hyp(s.vx, s.vz);
        damage(m, tgt, s.dmg, s.x - s.vx / sl, s.z - s.vz / sl, s.kind, bots[s.owner]);
        if (s.knock) knock(tgt, s.vx / sl, s.vz / sl, s.knock);
        gone = true;
      }
      if (gone) m.shots.splice(i, 1);
    }

    // 修理と穴
    for (i = 0; i < 2; i++) {
      var r = bots[i];
      ARENA.pads.forEach(function (p) {
        if (r.repairLeft > 0 && r.hp < r.maxHp && r.stun <= 0 &&
            hyp(r.x - p.x, r.z - p.z) < p.r && hyp(r.vx, r.vz) < 1.5) {
          var h = Math.min(10 * dt, r.repairLeft, r.maxHp - r.hp);
          r.hp += h; r.repairLeft -= h; r.repairing = true;
        }
      });
      if (r.repairing && !r.wasRepairing) m.events.push({ type: 'repair', bot: r.id });
      r.wasRepairing = r.repairing; r.repairing = false;
      var np = nearestPit(r);
      if (r.alive && np.d < np.pit.r - 0.35) {
        r.alive = false; r.falling = 0.001; r.vx = r.vz = 0;
        r.x += (np.pit.x - r.x) * 0.5; r.z += (np.pit.z - r.z) * 0.5;
        m.events.push({ type: 'fall', bot: r.id });
      }
    }

    // 決着
    var a0 = bots[0], b0 = bots[1];
    if (!a0.alive || !b0.alive) {
      m.over = { winner: a0.alive ? 0 : b0.alive ? 1 : -1, reason: 'pit' };
    } else if (a0.hp <= 0 || b0.hp <= 0) {
      m.over = { winner: a0.hp > 0 ? 0 : b0.hp > 0 ? 1 : -1, reason: 'ko' };
    } else if (m.timeLeft <= 0) {
      var ra = a0.hp / a0.maxHp, rb = b0.hp / b0.maxHp;
      m.over = { winner: Math.abs(ra - rb) < 0.01 ? -1 : ra > rb ? 0 : 1, reason: 'time' };
    }
    if (m.over) m.events.push({ type: 'over', winner: m.over.winner, reason: m.over.reason });
  }

  /* ---------- パーツ配布とCPU ---------- */
  function shuffle(a) {
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1)), t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }
  function deal() {
    var out = {};
    SLOTS.forEach(function (slot) {
      var ids = Object.keys(PARTS).filter(function (k) { return PARTS[k].slot === slot; });
      out[slot] = shuffle(ids).slice(0, 2);
    });
    return out;
  }
  function validHand(h) {
    if (!h || typeof h !== 'object') return false;
    return SLOTS.every(function (slot) {
      var a = h[slot];
      return Array.isArray(a) && a.length === 2 && a[0] !== a[1] &&
        a.every(function (id) { return typeof id === 'string' && PARTS.hasOwnProperty(id) && PARTS[id].slot === slot; });
    });
  }
  function validBuild(b, hand) {
    if (!b || typeof b !== 'object') return false;
    return SLOTS.every(function (slot) { return hand[slot].indexOf(b[slot]) >= 0; });
  }
  function cpuSetup(hand) {
    function pick(slot) { return hand[slot][Math.floor(Math.random() * 2)]; }
    var build = { body: pick('body'), wheels: pick('wheels'), front: pick('front'), top: pick('top') };
    var ranged = build.top === 'mg' || build.top === 'rocket';
    var styles = ['brawler', 'pusher'];
    if (ranged) styles.push('gunner', 'gunner');
    if (build.front === 'bumper') styles.push('pusher');
    var style = styles[Math.floor(Math.random() * styles.length)];
    var plan, label;
    if (style === 'gunner') {
      label = '射撃型';
      plan = { avoid_pits: true, use_boost: 'never', rules: [
        { 'if': [{ type: 'ammo_empty' }], 'do': 'charge' },
        { 'if': [{ type: 'my_hp_lt', value: 35 }, { type: 'enemy_dist_gt', value: 9 }], 'do': 'go_repair' },
        { 'if': [], 'do': 'keep_distance', distance: 9 }
      ] };
    } else if (style === 'pusher') {
      label = '穴落とし型';
      plan = { avoid_pits: true, use_boost: 'on_charge', rules: [
        { 'if': [{ type: 'enemy_near_pit', value: 7 }], 'do': 'push_to_pit' },
        { 'if': [], 'do': 'flank' }
      ] };
    } else {
      label = '突撃型';
      plan = { avoid_pits: Math.random() < 0.7, use_boost: 'on_charge', rules: [
        { 'if': [{ type: 'my_hp_lt', value: 30 }, { type: 'enemy_dist_gt', value: 8 }], 'do': 'go_repair' },
        { 'if': [], 'do': 'charge' }
      ] };
    }
    return { build: build, plan: plan, label: label };
  }

  /* ---------- AIが使えないときの簡易解釈 ---------- */
  function localParse(text) {
    var plan = { avoid_pits: false, use_boost: 'never', rules: [], pilot_comment: 'キーワードだけ拾って動くっす！' };
    if (/穴.{0,6}(避|よけ|気をつけ|注意|落ちるな|近づくな|近寄るな)/.test(text)) plan.avoid_pits = true;
    if (/ブースト|ブースター|加速/.test(text)) plan.use_boost = /逃|退/.test(text) ? 'on_retreat' : 'on_charge';
    var segs = text.split(/[。\n、,．.!！]/);
    segs.forEach(function (s) {
      if (!s.trim() || /ブースト|ブースター/.test(s)) return;
      var conds = [], mm;
      if ((mm = s.match(/(?:HP|体力).{0,4}?(\d+)\s*[%％]/i)) && !/相手|敵/.test(s)) conds.push({ type: 'my_hp_lt', value: +mm[1] });
      else if (/(HP|体力).{0,6}(半分|減|少な|やば|ピンチ)/i.test(s)) conds.push({ type: /相手|敵/.test(s) ? 'enemy_hp_lt' : 'my_hp_lt', value: 50 });
      if (/弾.{0,6}(切れ|なくな|尽き)/.test(s)) conds.push({ type: 'ammo_empty' });
      if (/(相手|敵).{0,8}穴.{0,4}(近|そば)/.test(s)) conds.push({ type: 'enemy_near_pit', value: 6 });
      if (/近(づかれ|い|寄られ)/.test(s) && /たら|とき|時|なら/.test(s)) conds.push({ type: 'enemy_dist_lt', value: 6 });
      if (/ひっくり返|動けな/.test(s)) conds.push({ type: 'enemy_stunned' });
      var act = null;
      if (/穴.{0,8}(落と|押し|突き)/.test(s)) act = 'push_to_pit';
      else if (/突撃|突っ込|体当たり/.test(s)) act = 'charge';
      else if (/修理|回復|直し/.test(s)) act = 'go_repair';
      else if (/回り込|背後|後ろから|横から|側面/.test(s)) act = 'flank';
      else if (/逃げ|下がれ|退|離れろ/.test(s)) act = 'retreat';
      else if (/距離|離れて|遠くから|撃|射/.test(s)) act = 'keep_distance';
      else if (/回(れ|って)|ぐるぐる|周り/.test(s)) act = 'circle';
      else if (/待|止ま|動くな/.test(s)) act = 'hold';
      else if (/突撃|突っ込|体当たり|攻め|近づ|殴|叩|削|ぶつか|押せ/.test(s)) act = 'charge';
      if (act) plan.rules.push({ 'if': conds, 'do': act });
    });
    // 条件つきの指示を先に調べる
    plan.rules = plan.rules.filter(function (r) { return r['if'].length; })
      .concat(plan.rules.filter(function (r) { return !r['if'].length; }));
    return sanitizePlan(plan);
  }

  var api = {
    PARTS: PARTS, SLOTS: SLOTS, SLOT_NAMES: SLOT_NAMES, ARENA: ARENA, ACTIONS: ACTIONS,
    BOOST_MODES: BOOST_MODES, CONDS: CONDS,
    actionLabel: function (a) { return a === 'idle' ? '指示待ちでうろうろ' : ACTIONS[a]; },
    sanitizePlan: sanitizePlan, describeRule: describeRule, createMatch: createMatch, step: step,
    deal: deal, cpuSetup: cpuSetup, localParse: localParse,
    validHand: validHand, validBuild: validBuild
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.PBSim = api;
})(typeof window !== 'undefined' ? window : this);
