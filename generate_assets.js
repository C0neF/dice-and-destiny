const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const LEGACY_LINUX_BASE = '/home/conef/.openclaw/workspace/dice-and-destiny/assets/sprites';
const REPO_BASE = path.join(__dirname, 'assets', 'sprites');
const BASE = process.env.DICE_SPRITES_BASE
  ? path.resolve(process.env.DICE_SPRITES_BASE)
  : (process.platform === 'linux' ? LEGACY_LINUX_BASE : REPO_BASE);

function mkdirp(p) {
  fs.mkdirSync(p, { recursive: true });
}

function buf(w, h) {
  return Buffer.alloc(w * h * 4, 0);
}

function sp(b, w, x, y, r, g, bb, a = 255) {
  if (x < 0 || y < 0) return;
  const h = b.length / 4 / w;
  if (x >= w || y >= h) return;
  const i = (y * w + x) * 4;
  b[i] = Math.min(255, Math.max(0, r));
  b[i + 1] = Math.min(255, Math.max(0, g));
  b[i + 2] = Math.min(255, Math.max(0, bb));
  b[i + 3] = a;
}

function rect(b, w, x1, y1, x2, y2, r, g, bb, a = 255) {
  for (let y = y1; y <= y2; y++) {
    for (let x = x1; x <= x2; x++) {
      sp(b, w, x, y, r, g, bb, a);
    }
  }
}

function circle(b, w, cx, cy, rad, r, g, bb, a = 255) {
  for (let dy = -rad; dy <= rad; dy++) {
    for (let dx = -rad; dx <= rad; dx++) {
      if (dx * dx + dy * dy <= rad * rad) {
        sp(b, w, cx + dx, cy + dy, r, g, bb, a);
      }
    }
  }
}

function outline(b, w, x1, y1, x2, y2, r, g, bb, a = 255) {
  for (let x = x1; x <= x2; x++) {
    sp(b, w, x, y1, r, g, bb, a);
    sp(b, w, x, y2, r, g, bb, a);
  }
  for (let y = y1; y <= y2; y++) {
    sp(b, w, x1, y, r, g, bb, a);
    sp(b, w, x2, y, r, g, bb, a);
  }
}

async function save(b, w, h, f) {
  mkdirp(path.dirname(f));
  await sharp(b, { raw: { width: w, height: h, channels: 4 } }).toFile(f);
}

function countFiles(dir) {
  const files = [];
  function walk(d) {
    fs.readdirSync(d).forEach((f) => {
      const p = path.join(d, f);
      if (fs.statSync(p).isDirectory()) {
        walk(p);
      } else {
        files.push(p);
      }
    });
  }
  walk(dir);
  return files.length;
}

async function main() {
  // PLAYER
  for (const [nm, off] of [['player_idle', 0], ['player_walk1', -1], ['player_walk2', 1]]) {
    const w = 16;
    const h = 16;
    const b = buf(w, h);
    rect(b, w, 5, 5, 10, 11, 180, 180, 200);
    rect(b, w, 6, 6, 9, 10, 200, 200, 220);
    rect(b, w, 6, 2, 9, 5, 220, 190, 160);
    rect(b, w, 5, 1, 10, 3, 120, 120, 140);
    sp(b, w, 7, 4, 40, 40, 60);
    sp(b, w, 9, 4, 40, 40, 60);
    rect(b, w, 4, 6, 5, Math.max(6, 11 + off), 60, 80, 180);
    rect(b, w, 10, 6, 11, Math.max(6, 11 + off), 60, 80, 180);
    rect(b, w, 6, 12, 7, Math.min(15, 14 + off), 140, 140, 160);
    rect(b, w, 8, 12, 9, Math.min(15, 14 + off), 140, 140, 160);
    rect(b, w, 5, 14, 7, 15, 100, 70, 40);
    rect(b, w, 8, 14, 10, 15, 100, 70, 40);
    sp(b, w, 12, 5, 200, 200, 220);
    sp(b, w, 12, 6, 200, 200, 220);
    sp(b, w, 12, 7, 180, 180, 200);
    sp(b, w, 12, 8, 120, 80, 40);
    await save(b, w, h, `${BASE}/player/${nm}.png`);
  }
  console.log('✓ Player');

  // BASE ENEMIES
  let w = 16;
  let h = 16;
  let b;

  b = buf(w, h);
  circle(b, w, 8, 10, 5, 60, 180, 80);
  circle(b, w, 8, 8, 3, 80, 200, 100);
  sp(b, w, 6, 6, 140, 240, 160);
  sp(b, w, 7, 6, 140, 240, 160);
  sp(b, w, 6, 9, 20, 20, 20);
  sp(b, w, 9, 9, 20, 20, 20);
  sp(b, w, 6, 8, 255, 255, 255);
  sp(b, w, 9, 8, 255, 255, 255);
  await save(b, w, h, `${BASE}/enemies/slime.png`);

  b = buf(w, h);
  rect(b, w, 6, 2, 9, 5, 230, 230, 220);
  sp(b, w, 7, 3, 40, 10, 10);
  sp(b, w, 9, 3, 40, 10, 10);
  sp(b, w, 7, 5, 40, 30, 30);
  sp(b, w, 8, 5, 40, 30, 30);
  for (let y = 6; y <= 10; y++) sp(b, w, 8, y, 220, 220, 210);
  rect(b, w, 6, 7, 10, 7, 210, 210, 200);
  rect(b, w, 6, 9, 10, 9, 210, 210, 200);
  sp(b, w, 5, 7, 220, 220, 210);
  sp(b, w, 4, 8, 220, 220, 210);
  sp(b, w, 11, 7, 220, 220, 210);
  sp(b, w, 12, 8, 220, 220, 210);
  sp(b, w, 7, 11, 220, 220, 210);
  sp(b, w, 7, 12, 220, 220, 210);
  sp(b, w, 7, 13, 220, 220, 210);
  sp(b, w, 9, 11, 220, 220, 210);
  sp(b, w, 9, 12, 220, 220, 210);
  sp(b, w, 9, 13, 220, 220, 210);
  sp(b, w, 13, 6, 180, 180, 200);
  sp(b, w, 13, 7, 180, 180, 200);
  await save(b, w, h, `${BASE}/enemies/skeleton.png`);

  b = buf(w, h);
  rect(b, w, 7, 6, 9, 9, 120, 60, 160);
  for (const [bx, d] of [[3, -1], [12, 1]]) {
    sp(b, w, bx, 5, 100, 50, 140);
    sp(b, w, bx + d, 4, 100, 50, 140);
    sp(b, w, bx, 6, 110, 55, 150);
    sp(b, w, bx + d, 6, 110, 55, 150);
    sp(b, w, bx, 7, 100, 50, 140);
  }
  sp(b, w, 7, 7, 255, 50, 50);
  sp(b, w, 9, 7, 255, 50, 50);
  sp(b, w, 7, 5, 130, 70, 170);
  sp(b, w, 9, 5, 130, 70, 170);
  await save(b, w, h, `${BASE}/enemies/bat.png`);

  b = buf(32, 32);
  rect(b, 32, 10, 10, 21, 24, 180, 40, 40);
  rect(b, 32, 12, 12, 19, 22, 200, 60, 50);
  rect(b, 32, 11, 4, 20, 10, 200, 50, 40);
  sp(b, 32, 10, 3, 80, 20, 20);
  sp(b, 32, 9, 2, 80, 20, 20);
  sp(b, 32, 21, 3, 80, 20, 20);
  sp(b, 32, 22, 2, 80, 20, 20);
  rect(b, 32, 13, 6, 14, 7, 255, 200, 0);
  rect(b, 32, 17, 6, 18, 7, 255, 200, 0);
  rect(b, 32, 13, 9, 18, 9, 40, 10, 10);
  for (let i = 0; i < 5; i++) {
    sp(b, 32, 6 - i, 10 + i, 150, 30, 30);
    sp(b, 32, 7 - i, 10 + i, 150, 30, 30);
    sp(b, 32, 25 + i, 10 + i, 150, 30, 30);
    sp(b, 32, 24 + i, 10 + i, 150, 30, 30);
  }
  rect(b, 32, 12, 25, 14, 29, 160, 35, 35);
  rect(b, 32, 17, 25, 19, 29, 160, 35, 35);
  await save(b, 32, 32, `${BASE}/enemies/demon.png`);

  b = buf(w, h);
  rect(b, w, 6, 3, 10, 6, 80, 160, 60);
  sp(b, w, 5, 3, 80, 160, 60);
  sp(b, w, 11, 3, 80, 160, 60);
  sp(b, w, 7, 4, 255, 50, 50);
  sp(b, w, 9, 4, 255, 50, 50);
  rect(b, w, 6, 7, 10, 12, 100, 80, 40);
  rect(b, w, 7, 13, 8, 15, 80, 160, 60);
  rect(b, w, 9, 13, 10, 15, 80, 160, 60);
  sp(b, w, 12, 7, 180, 180, 200);
  sp(b, w, 12, 8, 180, 180, 200);
  await save(b, w, h, `${BASE}/enemies/goblin.png`);

  b = buf(w, h);
  for (let y = 3; y <= 13; y++) {
    for (let x = 4; x <= 11; x++) {
      const a = y > 11 ? (x % 2 === 0 ? 120 : 0) : 140;
      if (a > 0) sp(b, w, x, y, 220, 220, 240, a);
    }
  }
  sp(b, w, 6, 6, 40, 40, 80, 200);
  sp(b, w, 9, 6, 40, 40, 80, 200);
  sp(b, w, 7, 8, 60, 60, 100, 180);
  sp(b, w, 8, 8, 60, 60, 100, 180);
  await save(b, w, h, `${BASE}/enemies/ghost.png`);
  console.log('✓ Base enemies');

  // EXTRA ENEMIES
  const extraEnemies = [
    ['mimic', (bb, ww) => {
      rect(bb, ww, 3, 8, 12, 14, 140, 90, 40);
      rect(bb, ww, 4, 9, 11, 13, 160, 110, 50);
      rect(bb, ww, 3, 5, 12, 8, 140, 90, 40);
      sp(bb, ww, 5, 6, 255, 50, 50);
      sp(bb, ww, 10, 6, 255, 50, 50);
      for (let i = 0; i < 4; i++) {
        sp(bb, ww, 5 + i * 2, 8, 255, 255, 255);
        sp(bb, ww, 4 + i * 2, 8, 200, 200, 200);
      }
    }],
    ['mushroom', (bb, ww) => {
      rect(bb, ww, 7, 10, 9, 15, 180, 160, 140);
      circle(bb, ww, 8, 7, 4, 140, 50, 160);
      circle(bb, ww, 8, 6, 3, 160, 70, 180);
      sp(bb, ww, 6, 6, 255, 255, 255, 180);
      sp(bb, ww, 10, 7, 255, 255, 255, 150);
      sp(bb, ww, 7, 9, 20, 20, 40);
      sp(bb, ww, 9, 9, 20, 20, 40);
    }],
    ['fire_elemental', (bb, ww) => {
      for (let y = 4; y <= 14; y++) {
        const hw = Math.max(1, 4 - Math.abs(y - 9) / 2);
        for (let x = -hw; x <= hw; x++) sp(bb, ww, 8 + x, y, 255, 120 - y * 3, 20);
      }
      sp(bb, ww, 7, 7, 255, 255, 100);
      sp(bb, ww, 9, 7, 255, 255, 100);
      sp(bb, ww, 8, 2, 255, 200, 50);
      sp(bb, ww, 7, 3, 255, 150, 30);
    }],
    ['ice_golem', (bb, ww) => {
      rect(bb, ww, 5, 3, 10, 13, 140, 180, 220);
      rect(bb, ww, 6, 4, 9, 12, 170, 210, 240);
      sp(bb, ww, 6, 6, 40, 80, 180);
      sp(bb, ww, 9, 6, 40, 80, 180);
      rect(bb, ww, 3, 7, 5, 10, 120, 160, 200);
      rect(bb, ww, 10, 7, 12, 10, 120, 160, 200);
      sp(bb, ww, 7, 4, 255, 255, 255, 180);
      sp(bb, ww, 8, 3, 255, 255, 255, 150);
    }],
    ['dark_knight', (bb, ww) => {
      rect(bb, ww, 6, 2, 10, 5, 30, 25, 40);
      rect(bb, ww, 5, 5, 11, 12, 40, 35, 50);
      rect(bb, ww, 6, 6, 10, 11, 50, 45, 60);
      sp(bb, ww, 7, 3, 200, 30, 30);
      sp(bb, ww, 9, 3, 200, 30, 30);
      rect(bb, ww, 6, 13, 7, 15, 35, 30, 45);
      rect(bb, ww, 9, 13, 10, 15, 35, 30, 45);
      sp(bb, ww, 13, 5, 180, 180, 200);
      sp(bb, ww, 13, 6, 180, 180, 200);
      sp(bb, ww, 13, 7, 120, 80, 40);
    }],
  ];

  for (const [name, draw] of extraEnemies) {
    const ew = 16;
    const eh = 16;
    const eb = buf(ew, eh);
    draw(eb, ew);
    await save(eb, ew, eh, `${BASE}/enemies/${name}.png`);
  }
  console.log('✓ Extra enemies');

  // BASE TILES
  for (const [nm, base] of [['floor_1', [90, 85, 80]], ['floor_2', [85, 80, 75]]]) {
    b = buf(w, h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const v = ((x * 7 + y * 13) % 17) - 8;
        sp(b, w, x, y, base[0] + v, base[1] + v, base[2] + v);
      }
    }
    sp(b, w, 3, 5, base[0] - 20, base[1] - 20, base[2] - 20);
    sp(b, w, 4, 6, base[0] - 20, base[1] - 20, base[2] - 20);
    await save(b, w, h, `${BASE}/tiles/${nm}.png`);
  }

  b = buf(w, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const v = ((x * 3 + y * 7) % 11) - 5;
      sp(b, w, x, y, 60 + v, 55 + v, 65 + v);
    }
  }
  for (let y = 0; y < h; y += 4) {
    for (let x = 0; x < w; x++) sp(b, w, x, y, 45, 40, 50);
    const off = y % 8 === 0 ? 0 : 8;
    for (let bx = off; bx < w; bx += 8) sp(b, w, bx, y + 1, 45, 40, 50);
  }
  await save(b, w, h, `${BASE}/tiles/wall_top.png`);

  b = buf(w, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const v = ((x * 3 + y * 7) % 11) - 5;
      sp(b, w, x, y, 70 + v, 65 + v, 75 + v);
    }
  }
  for (let x = 0; x < w; x++) {
    sp(b, w, x, 0, 40, 35, 45);
    sp(b, w, x, 1, 50, 45, 55);
  }
  await save(b, w, h, `${BASE}/tiles/wall_front.png`);

  b = buf(w, h);
  rect(b, w, 3, 0, 4, 15, 80, 60, 40);
  rect(b, w, 11, 0, 12, 15, 80, 60, 40);
  rect(b, w, 3, 0, 12, 1, 80, 60, 40);
  rect(b, w, 5, 2, 10, 15, 120, 80, 40);
  rect(b, w, 6, 3, 9, 14, 140, 100, 50);
  sp(b, w, 9, 9, 200, 180, 60);
  await save(b, w, h, `${BASE}/tiles/door_closed.png`);

  b = buf(w, h);
  rect(b, w, 3, 0, 4, 15, 80, 60, 40);
  rect(b, w, 11, 0, 12, 15, 80, 60, 40);
  rect(b, w, 3, 0, 12, 1, 80, 60, 40);
  rect(b, w, 3, 2, 5, 15, 100, 70, 35);
  rect(b, w, 6, 2, 12, 15, 20, 15, 25);
  await save(b, w, h, `${BASE}/tiles/door_open.png`);

  b = buf(w, h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) sp(b, w, x, y, 50, 45, 55);
  for (let i = 0; i < 5; i++) {
    const y = 3 + i * 2;
    const x1 = 3 + i;
    const x2 = 12 - i;
    rect(b, w, x1, y, x2, y + 1, 80 + i * 10, 75 + i * 10, 85 + i * 10);
  }
  await save(b, w, h, `${BASE}/tiles/stairs_down.png`);

  b = buf(w, h);
  rect(b, w, 3, 8, 12, 14, 140, 90, 40);
  rect(b, w, 4, 9, 11, 13, 160, 110, 50);
  sp(b, w, 7, 10, 200, 180, 60);
  sp(b, w, 8, 10, 200, 180, 60);
  rect(b, w, 3, 5, 12, 8, 140, 90, 40);
  rect(b, w, 4, 6, 11, 7, 120, 80, 35);
  await save(b, w, h, `${BASE}/tiles/chest.png`);

  b = buf(w, h);
  rect(b, w, 3, 8, 12, 14, 140, 90, 40);
  rect(b, w, 4, 9, 11, 13, 160, 110, 50);
  rect(b, w, 2, 3, 13, 6, 140, 90, 40);
  sp(b, w, 5, 8, 255, 220, 50);
  sp(b, w, 7, 8, 255, 230, 70);
  sp(b, w, 9, 8, 255, 220, 50);
  await save(b, w, h, `${BASE}/tiles/chest_open.png`);
  console.log('✓ Base tiles');

  // EXTRA TILES
  const extraTiles = [
    ['floor_3', (bb, ww) => {
      for (let y = 0; y < 16; y++) {
        for (let x = 0; x < 16; x++) {
          const v = ((x * 7 + y * 13) % 17) - 8;
          sp(bb, ww, x, y, 75 + v, 90 + v, 70 + v);
        }
      }
    }],
    ['floor_4', (bb, ww) => {
      for (let y = 0; y < 16; y++) {
        for (let x = 0; x < 16; x++) {
          const v = ((x * 7 + y * 13) % 17) - 8;
          sp(bb, ww, x, y, 95 + v, 75 + v, 75 + v);
        }
      }
      sp(bb, ww, 5, 8, 120, 40, 40);
      sp(bb, ww, 6, 9, 110, 35, 35);
    }],
    ['wall_mossy', (bb, ww) => {
      for (let y = 0; y < 16; y++) {
        for (let x = 0; x < 16; x++) {
          const v = ((x * 3 + y * 7) % 11) - 5;
          sp(bb, ww, x, y, 60 + v, 55 + v, 65 + v);
        }
      }
      sp(bb, ww, 3, 10, 50, 100, 50);
      sp(bb, ww, 4, 11, 40, 90, 40);
      sp(bb, ww, 12, 8, 50, 100, 50);
      sp(bb, ww, 7, 13, 45, 95, 45);
    }],
    ['wall_cracked', (bb, ww) => {
      for (let y = 0; y < 16; y++) {
        for (let x = 0; x < 16; x++) {
          const v = ((x * 3 + y * 7) % 11) - 5;
          sp(bb, ww, x, y, 60 + v, 55 + v, 65 + v);
        }
      }
      for (let i = 0; i < 6; i++) sp(bb, ww, 5 + i, 4 + (i % 3), 35, 30, 40);
      for (let i = 0; i < 4; i++) sp(bb, ww, 8 + i, 10 - i, 35, 30, 40);
    }],
    ['trap_spikes', (bb, ww) => {
      for (let y = 0; y < 16; y++) {
        for (let x = 0; x < 16; x++) {
          const v = ((x * 7 + y * 13) % 17) - 8;
          sp(bb, ww, x, y, 90 + v, 85 + v, 80 + v);
        }
      }
      for (let i = 0; i < 4; i++) {
        sp(bb, ww, 3 + i * 3, 6, 160, 160, 170);
        sp(bb, ww, 3 + i * 3, 7, 180, 180, 190);
        sp(bb, ww, 3 + i * 3, 5, 140, 140, 150);
      }
    }],
    ['lava', (bb, ww) => {
      for (let y = 0; y < 16; y++) {
        for (let x = 0; x < 16; x++) {
          const v = ((x * 5 + y * 11) % 13) - 6;
          sp(bb, ww, x, y, 200 + v, 80 + v, 20);
        }
      }
      sp(bb, ww, 5, 7, 255, 200, 50);
      sp(bb, ww, 10, 4, 255, 220, 80);
      sp(bb, ww, 3, 12, 255, 180, 40);
    }],
    ['ice_floor', (bb, ww) => {
      for (let y = 0; y < 16; y++) {
        for (let x = 0; x < 16; x++) {
          const v = ((x * 7 + y * 13) % 17) - 8;
          sp(bb, ww, x, y, 170 + v, 200 + v, 230 + v);
        }
      }
      sp(bb, ww, 4, 5, 255, 255, 255, 150);
      sp(bb, ww, 10, 10, 255, 255, 255, 120);
    }],
    ['portal', (bb, ww) => {
      circle(bb, ww, 8, 8, 6, 80, 30, 140);
      circle(bb, ww, 8, 8, 4, 120, 50, 200);
      circle(bb, ww, 8, 8, 2, 180, 100, 255);
      sp(bb, ww, 8, 8, 255, 200, 255);
    }],
  ];

  for (const [name, draw] of extraTiles) {
    const tw = 16;
    const th = 16;
    const tb = buf(tw, th);
    draw(tb, tw);
    await save(tb, tw, th, `${BASE}/tiles/${name}.png`);
  }
  console.log('✓ Extra tiles');

  // BASE CARDS
  const cards = [
    ['card_attack', [180, 50, 50]],
    ['card_defend', [50, 80, 180]],
    ['card_magic', [140, 50, 180]],
    ['card_heal', [50, 160, 70]],
    ['card_dice', [200, 180, 50]],
    ['card_back', [80, 60, 120]],
  ];

  for (const [nm, c] of cards) {
    const cw = 48;
    const ch = 64;
    b = buf(cw, ch);
    rect(b, cw, 0, 0, cw - 1, ch - 1, 40, 35, 50);
    rect(b, cw, 1, 1, cw - 2, ch - 2, 230, 220, 200);
    rect(b, cw, 2, 2, cw - 3, ch - 3, 245, 240, 230);
    rect(b, cw, 3, 3, cw - 4, 18, c[0], c[1], c[2]);
    const cx = 24;
    const cy = 38;
    circle(b, cw, cx, cy, 6, c[0], c[1], c[2]);
    circle(
      b,
      cw,
      cx,
      cy,
      4,
      Math.min(255, c[0] + 40),
      Math.min(255, c[1] + 40),
      Math.min(255, c[2] + 40)
    );
    await save(b, cw, ch, `${BASE}/cards/${nm}.png`);
  }
  console.log('✓ Base cards');

  // EXTRA CARDS
  const extraCards = [
    ['card_combo', [220, 150, 40]],
    ['card_curse', [100, 30, 120]],
    ['card_summon', [40, 180, 200]],
  ];

  for (const [nm, c] of extraCards) {
    const cw = 48;
    const ch = 64;
    const cb = buf(cw, ch);
    rect(cb, cw, 0, 0, cw - 1, ch - 1, 40, 35, 50);
    rect(cb, cw, 1, 1, cw - 2, ch - 2, 230, 220, 200);
    rect(cb, cw, 2, 2, cw - 3, ch - 3, 245, 240, 230);
    rect(cb, cw, 3, 3, cw - 4, 18, c[0], c[1], c[2]);
    circle(cb, cw, 24, 38, 6, c[0], c[1], c[2]);
    circle(
      cb,
      cw,
      24,
      38,
      4,
      Math.min(255, c[0] + 40),
      Math.min(255, c[1] + 40),
      Math.min(255, c[2] + 40)
    );
    await save(cb, cw, ch, `${BASE}/cards/${nm}.png`);
  }
  console.log('✓ Extra cards');

  // DICE
  const dotPos = {
    1: [[12, 12]],
    2: [[8, 8], [16, 16]],
    3: [[8, 8], [12, 12], [16, 16]],
    4: [[8, 8], [16, 8], [8, 16], [16, 16]],
    5: [[8, 8], [16, 8], [12, 12], [8, 16], [16, 16]],
    6: [[8, 8], [16, 8], [8, 12], [16, 12], [8, 16], [16, 16]],
  };

  for (let f = 1; f <= 6; f++) {
    b = buf(24, 24);
    rect(b, 24, 2, 2, 21, 21, 240, 240, 240);
    outline(b, 24, 2, 2, 21, 21, 60, 60, 60);
    for (const [dx, dy] of dotPos[f]) circle(b, 24, dx, dy, 2, 40, 40, 40);
    await save(b, 24, 24, `${BASE}/dice/dice_${f}.png`);
  }

  for (const [nm, c] of [['dice_fire', [220, 60, 40]], ['dice_ice', [60, 140, 220]], ['dice_poison', [60, 180, 60]]]) {
    b = buf(24, 24);
    rect(b, 24, 2, 2, 21, 21, c[0], c[1], c[2]);
    outline(b, 24, 2, 2, 21, 21, 40, 40, 40);
    circle(b, 24, 12, 12, 4, Math.min(255, c[0] + 60), Math.min(255, c[1] + 60), Math.min(255, c[2] + 60));
    await save(b, 24, 24, `${BASE}/dice/${nm}.png`);
  }
  console.log('✓ Dice');

  // UI
  const hp = [
    [2, 1], [3, 1], [4, 1], [7, 1], [8, 1], [9, 1], [1, 2], [2, 2], [3, 2], [4, 2],
    [5, 2], [6, 2], [7, 2], [8, 2], [9, 2], [10, 2], [1, 3], [2, 3], [3, 3], [4, 3],
    [5, 3], [6, 3], [7, 3], [8, 3], [9, 3], [10, 3], [2, 4], [3, 4], [4, 4], [5, 4],
    [6, 4], [7, 4], [8, 4], [9, 4], [3, 5], [4, 5], [5, 5], [6, 5], [7, 5], [8, 5],
    [4, 6], [5, 6], [6, 6], [7, 6], [5, 7], [6, 7],
  ];

  b = buf(12, 12);
  for (const [x, y] of hp) sp(b, 12, x, y, 220, 40, 50);
  await save(b, 12, 12, `${BASE}/ui/heart_full.png`);

  b = buf(12, 12);
  for (const [x, y] of hp) sp(b, 12, x, y, 100, 80, 80);
  await save(b, 12, 12, `${BASE}/ui/heart_empty.png`);

  const ep = [[6, 0], [5, 1], [4, 2], [3, 3], [2, 4], [3, 4], [4, 4], [5, 4], [6, 4], [7, 4], [6, 5], [5, 6], [4, 7], [3, 8], [5, 8], [4, 9], [3, 10]];

  b = buf(12, 12);
  for (const [x, y] of ep) sp(b, 12, x, y, 240, 200, 50);
  await save(b, 12, 12, `${BASE}/ui/energy_full.png`);

  b = buf(12, 12);
  for (const [x, y] of ep) sp(b, 12, x, y, 100, 90, 60);
  await save(b, 12, 12, `${BASE}/ui/energy_empty.png`);

  b = buf(64, 20);
  rect(b, 64, 0, 0, 63, 19, 60, 60, 80);
  rect(b, 64, 1, 1, 62, 18, 80, 80, 110);
  rect(b, 64, 2, 2, 61, 17, 100, 100, 140);
  await save(b, 64, 20, `${BASE}/ui/button_normal.png`);

  b = buf(64, 20);
  rect(b, 64, 0, 0, 63, 19, 80, 80, 110);
  rect(b, 64, 1, 1, 62, 18, 100, 100, 140);
  rect(b, 64, 2, 2, 61, 17, 120, 120, 170);
  await save(b, 64, 20, `${BASE}/ui/button_hover.png`);

  b = buf(32, 32);
  rect(b, 32, 0, 0, 31, 31, 40, 35, 50);
  rect(b, 32, 1, 1, 30, 30, 60, 55, 70);
  rect(b, 32, 2, 2, 29, 29, 45, 40, 55);
  await save(b, 32, 32, `${BASE}/ui/panel.png`);

  b = buf(80, 80);
  outline(b, 80, 0, 0, 79, 79, 200, 180, 120);
  outline(b, 80, 1, 1, 78, 78, 160, 140, 80);
  rect(b, 80, 2, 2, 77, 77, 20, 18, 30);
  await save(b, 80, 80, `${BASE}/ui/minimap_frame.png`);
  console.log('✓ UI');

  // EFFECTS
  for (let i = 1; i <= 3; i++) {
    b = buf(24, 24);
    for (let j = 0; j < 8 + i * 3; j++) {
      const x = 4 + j;
      const y = 4 + j - i + 2;
      sp(b, 24, x, y, 255, 255, 255, 200);
      sp(b, 24, x + 1, y, 200, 200, 220, 150);
    }
    await save(b, 24, 24, `${BASE}/effects/slash_${i}.png`);

    b = buf(24, 24);
    circle(b, 24, 12, 12, 3 + i * 2, 255, 200 - i * 40, 50, 220 - i * 30);
    circle(b, 24, 12, 12, 1 + i, 255, 255, 200, 200);
    await save(b, 24, 24, `${BASE}/effects/explosion_${i}.png`);

    b = buf(24, 24);
    for (let j = 0; j < 4 + i * 2; j++) {
      const ang = (j * Math.PI * 2) / (4 + i * 2);
      sp(b, 24, 12 + Math.round(Math.cos(ang) * (2 + i * 2)), 12 + Math.round(Math.sin(ang) * (2 + i * 2)), 100, 255, 100, 200);
    }
    circle(b, 24, 12, 12, i, 150, 255, 150, 180);
    await save(b, 24, 24, `${BASE}/effects/heal_${i}.png`);

    b = buf(24, 24);
    rect(b, 24, 8 - i, 8 - i, 16 + i, 16 + i, 240, 240, 240, 180);
    outline(b, 24, 8 - i, 8 - i, 16 + i, 16 + i, 60, 60, 60, 180);
    circle(b, 24, 12, 12, 2, 40, 40, 40);
    await save(b, 24, 24, `${BASE}/effects/dice_roll_${i}.png`);
  }
  console.log('✓ Effects');

  // RELICS
  const relics = [
    ['relic_lucky_coin', (bb, ww) => { circle(bb, ww, 10, 10, 7, 200, 180, 50); circle(bb, ww, 10, 10, 5, 230, 210, 80); sp(bb, ww, 10, 10, 255, 255, 150); sp(bb, ww, 8, 7, 255, 255, 200); }],
    ['relic_blood_vial', (bb, ww) => { rect(bb, ww, 7, 4, 12, 6, 180, 40, 40); rect(bb, ww, 8, 6, 11, 15, 200, 30, 30); rect(bb, ww, 9, 7, 10, 14, 230, 50, 50); sp(bb, ww, 9, 8, 255, 100, 100); }],
    ['relic_iron_crown', (bb, ww) => { rect(bb, ww, 4, 10, 15, 14, 160, 160, 170); rect(bb, ww, 5, 11, 14, 13, 190, 190, 200); sp(bb, ww, 5, 8, 160, 160, 170); sp(bb, ww, 10, 7, 160, 160, 170); sp(bb, ww, 15, 8, 160, 160, 170); sp(bb, ww, 10, 6, 200, 200, 220); }],
    ['relic_flame_ring', (bb, ww) => { circle(bb, ww, 10, 10, 7, 200, 100, 30); circle(bb, ww, 10, 10, 4, 40, 30, 20, 0); sp(bb, ww, 8, 5, 255, 150, 30); sp(bb, ww, 12, 5, 255, 150, 30); sp(bb, ww, 10, 3, 255, 200, 50); }],
    ['relic_frost_amulet', (bb, ww) => { rect(bb, ww, 8, 2, 11, 4, 100, 100, 120); rect(bb, ww, 6, 5, 13, 12, 60, 140, 220); rect(bb, ww, 7, 6, 12, 11, 80, 170, 240); sp(bb, ww, 10, 8, 200, 230, 255); rect(bb, ww, 9, 13, 10, 16, 100, 100, 120); }],
    ['relic_poison_fang', (bb, ww) => { sp(bb, ww, 10, 3, 230, 230, 220); for (let i = 0; i < 8; i++) { sp(bb, ww, 10 - i / 3, 3 + i, 220, 220, 210); sp(bb, ww, 10 + i / 3, 3 + i, 220, 220, 210); } sp(bb, ww, 10, 14, 60, 200, 60); sp(bb, ww, 9, 13, 60, 200, 60); }],
    ['relic_war_drum', (bb, ww) => { rect(bb, ww, 5, 6, 14, 14, 140, 90, 40); rect(bb, ww, 6, 7, 13, 13, 160, 110, 50); rect(bb, ww, 5, 6, 14, 7, 120, 70, 30); rect(bb, ww, 5, 13, 14, 14, 120, 70, 30); sp(bb, ww, 3, 9, 80, 60, 30); sp(bb, ww, 3, 10, 80, 60, 30); sp(bb, ww, 2, 8, 100, 80, 40); }],
    ['relic_crystal_ball', (bb, ww) => { circle(bb, ww, 10, 10, 6, 120, 60, 180); circle(bb, ww, 10, 10, 4, 160, 80, 220); circle(bb, ww, 10, 10, 2, 200, 120, 255); sp(bb, ww, 8, 7, 230, 180, 255, 180); rect(bb, ww, 8, 15, 12, 17, 100, 90, 80); }],
    ['relic_broken_mirror', (bb, ww) => { rect(bb, ww, 4, 3, 15, 16, 180, 190, 200); rect(bb, ww, 5, 4, 14, 15, 200, 210, 220); for (let i = 0; i < 12; i++) sp(bb, ww, 5 + i, 4 + (i % 10), 100, 100, 120); sp(bb, ww, 8, 8, 255, 255, 255, 150); sp(bb, ww, 12, 6, 255, 255, 255, 100); }],
    ['relic_golden_dice', (bb, ww) => { rect(bb, ww, 5, 5, 15, 15, 220, 190, 50); outline(bb, ww, 5, 5, 15, 15, 180, 150, 30); rect(bb, ww, 6, 6, 14, 14, 240, 210, 70); circle(bb, ww, 8, 8, 1, 40, 30, 10); circle(bb, ww, 12, 12, 1, 40, 30, 10); circle(bb, ww, 10, 10, 1, 40, 30, 10); }],
  ];

  for (const [name, draw] of relics) {
    const rw = 20;
    const rh = 20;
    const rb = buf(rw, rh);
    draw(rb, rw);
    await save(rb, rw, rh, `${BASE}/relics/${name}.png`);
  }
  console.log('✓ Relics');

  // STATUS
  const statuses = [
    ['status_burn', (bb, ww) => { sp(bb, ww, 5, 2, 255, 200, 50); sp(bb, ww, 6, 2, 255, 200, 50); for (let y = 3; y <= 9; y++) { const hw = Math.max(0, 3 - Math.abs(y - 6)); for (let x = -hw; x <= hw; x++) sp(bb, ww, 6 + x, y, 255, 120 + y * 10, 20); } }],
    ['status_freeze', (bb, ww) => { for (let i = 0; i < 6; i++) { const a = (i * Math.PI) / 3; sp(bb, ww, 6 + Math.round(Math.cos(a) * 4), 6 + Math.round(Math.sin(a) * 4), 150, 200, 255); sp(bb, ww, 6 + Math.round(Math.cos(a) * 2), 6 + Math.round(Math.sin(a) * 2), 200, 230, 255); } sp(bb, ww, 6, 6, 255, 255, 255); }],
    ['status_poison', (bb, ww) => { circle(bb, ww, 6, 5, 3, 60, 180, 60); sp(bb, ww, 5, 4, 30, 30, 30); sp(bb, ww, 7, 4, 30, 30, 30); sp(bb, ww, 6, 6, 30, 30, 30); sp(bb, ww, 6, 9, 40, 160, 40); sp(bb, ww, 6, 10, 30, 140, 30); }],
    ['status_weak', (bb, ww) => { sp(bb, ww, 6, 2, 200, 50, 50); sp(bb, ww, 5, 3, 200, 50, 50); sp(bb, ww, 7, 3, 200, 50, 50); for (let i = 0; i < 5; i++) sp(bb, ww, 4 + i, 4 + i, 200, 50, 50); rect(bb, ww, 4, 9, 8, 9, 200, 50, 50); }],
    ['status_strength', (bb, ww) => { sp(bb, ww, 6, 9, 240, 200, 50); sp(bb, ww, 5, 8, 240, 200, 50); sp(bb, ww, 7, 8, 240, 200, 50); for (let i = 0; i < 5; i++) sp(bb, ww, 4 + i, 7 - i, 240, 200, 50); rect(bb, ww, 4, 2, 8, 2, 240, 200, 50); }],
    ['status_shield', (bb, ww) => { for (let y = -4; y <= 4; y++) { const hw = Math.max(0, 4 - Math.abs(y)); for (let x = -hw; x <= hw; x++) sp(bb, ww, 6 + x, 6 + y, 60, 120, 220); } outline(bb, ww, 3, 2, 9, 10, 40, 80, 180); }],
    ['status_regen', (bb, ww) => { rect(bb, ww, 5, 2, 7, 10, 50, 200, 80); rect(bb, ww, 2, 5, 10, 7, 50, 200, 80); }],
    ['status_vulnerable', (bb, ww) => { circle(bb, ww, 6, 6, 4, 140, 50, 180); circle(bb, ww, 6, 6, 2, 80, 20, 120, 0); sp(bb, ww, 4, 4, 160, 60, 200); sp(bb, ww, 8, 8, 160, 60, 200); }],
    ['status_combo', (bb, ww) => { sp(bb, ww, 3, 3, 255, 180, 50); sp(bb, ww, 4, 4, 255, 180, 50); sp(bb, ww, 5, 5, 255, 200, 80); sp(bb, ww, 6, 4, 255, 200, 80); sp(bb, ww, 7, 3, 255, 180, 50); sp(bb, ww, 8, 5, 255, 200, 80); sp(bb, ww, 9, 4, 255, 180, 50); }],
    ['status_dodge', (bb, ww) => { for (let i = 0; i < 8; i++) sp(bb, ww, 2 + i, 6 - Math.abs(i - 4) / 2, 220, 220, 240); sp(bb, ww, 10, 5, 220, 220, 240); }],
  ];

  for (const [name, draw] of statuses) {
    const sw = 12;
    const sh = 12;
    const sb = buf(sw, sh);
    draw(sb, sw);
    await save(sb, sw, sh, `${BASE}/status/${name}.png`);
  }
  console.log('✓ Status');

  // BG
  for (let f = 1; f <= 2; f++) {
    const bw = 8;
    const bh = 16;
    const bb = buf(bw, bh);
    rect(bb, bw, 3, 8, 4, 15, 100, 70, 40);
    rect(bb, bw, 2, 6, 5, 8, 120, 80, 40);
    const flicker = f === 1 ? 0 : 1;
    sp(bb, bw, 3, 3 + flicker, 255, 200, 50);
    sp(bb, bw, 4, 3 + flicker, 255, 200, 50);
    sp(bb, bw, 3, 4 + flicker, 255, 150, 30);
    sp(bb, bw, 4, 4 + flicker, 255, 150, 30);
    sp(bb, bw, 3, 5, 255, 100, 20);
    sp(bb, bw, 4, 5, 255, 100, 20);
    await save(bb, bw, bh, `${BASE}/bg/torch_${f}.png`);
  }

  {
    const bw = 16;
    const bh = 16;
    const bb = buf(bw, bh);
    for (let i = 0; i < 8; i++) {
      sp(bb, bw, i, 0, 200, 200, 200, 120);
      sp(bb, bw, 0, i, 200, 200, 200, 120);
      sp(bb, bw, i, i, 220, 220, 220, 100);
    }
    await save(bb, bw, bh, `${BASE}/bg/cobweb.png`);
  }

  {
    const bw = 16;
    const bh = 16;
    const bb = buf(bw, bh);
    circle(bb, bw, 5, 11, 3, 220, 210, 190);
    circle(bb, bw, 10, 11, 3, 210, 200, 180);
    circle(bb, bw, 8, 9, 3, 230, 220, 200);
    sp(bb, bw, 4, 10, 30, 20, 20);
    sp(bb, bw, 6, 10, 30, 20, 20);
    sp(bb, bw, 9, 10, 30, 20, 20);
    sp(bb, bw, 11, 10, 30, 20, 20);
    sp(bb, bw, 7, 8, 30, 20, 20);
    sp(bb, bw, 9, 8, 30, 20, 20);
    await save(bb, bw, bh, `${BASE}/bg/skull_pile.png`);
  }

  {
    const bw = 16;
    const bh = 16;
    const bb = buf(bw, bh);
    rect(bb, bw, 4, 4, 11, 14, 140, 90, 40);
    rect(bb, bw, 5, 5, 10, 13, 160, 110, 50);
    rect(bb, bw, 4, 6, 11, 7, 120, 70, 30);
    rect(bb, bw, 4, 11, 11, 12, 120, 70, 30);
    await save(bb, bw, bh, `${BASE}/bg/barrel.png`);
  }

  {
    const bw = 16;
    const bh = 32;
    const bb = buf(bw, bh);
    rect(bb, bw, 1, 0, 14, 31, 100, 70, 40);
    for (let row = 0; row < 4; row++) {
      const y = 2 + row * 8;
      rect(bb, bw, 2, y, 13, y + 5, 40 + row * 15, 30 + row * 10, 80 + row * 20);
      rect(bb, bw, 1, y + 6, 14, y + 7, 80, 55, 30);
    }
    await save(bb, bw, bh, `${BASE}/bg/bookshelf.png`);
  }

  for (const [name, c] of [['banner_red', [180, 40, 40]], ['banner_blue', [40, 60, 180]]]) {
    const bw = 8;
    const bh = 24;
    const bb = buf(bw, bh);
    rect(bb, bw, 1, 0, 6, 2, 120, 80, 40);
    rect(bb, bw, 2, 2, 5, 20, c[0], c[1], c[2]);
    rect(bb, bw, 3, 3, 4, 19, c[0] + 30, c[1] + 20, c[2] + 20);
    sp(bb, bw, 3, 21, c[0], c[1], c[2]);
    sp(bb, bw, 4, 22, c[0], c[1], c[2]);
    await save(bb, bw, bh, `${BASE}/bg/${name}.png`);
  }
  console.log('✓ BG');

  // ICON SVG
  const iconPath = path.join(__dirname, 'icon.svg');
  fs.writeFileSync(
    iconPath,
    '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><rect width="128" height="128" rx="16" fill="#2a1f3d"/><text x="64" y="52" font-size="40" text-anchor="middle" fill="#ffd700">🎲</text><text x="64" y="95" font-size="16" text-anchor="middle" fill="#eee" font-family="monospace">D&amp;D</text></svg>'
  );
  console.log('✓ Icon');

  const total = countFiles(BASE);
  console.log('\nAll assets generated!');
  console.log(`Total: ${total} files`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
