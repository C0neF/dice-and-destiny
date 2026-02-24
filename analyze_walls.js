// Analyze the survivor arena background image to find wall-floor boundaries
// by scanning pixel brightness transitions on each edge.
const sharp = require('sharp');
const path = require('path');

const IMG = path.join(__dirname, 'assets/sprites/bg/survivor_arena_bg.png');

// BG placement in game coords
const BG_X = -40, BG_Y = -40;
const BG_W = 720, BG_H = 440;

async function main() {
  const img = sharp(IMG);
  const meta = await img.metadata();
  const W = meta.width, H = meta.height;
  console.log(`Image: ${W}x${H}`);
  
  const { data } = await img.raw().toBuffer({ resolveWithObject: true });
  const ch = meta.channels; // 3 or 4

  function brightness(x, y) {
    const i = (y * W + x) * ch;
    return (data[i] + data[i+1] + data[i+2]) / 3;
  }

  // Average brightness of a horizontal line segment
  function hLineBrightness(y, x0, x1) {
    let sum = 0, n = 0;
    for (let x = x0; x < x1; x += 2) {
      sum += brightness(x, y);
      n++;
    }
    return sum / n;
  }

  // Average brightness of a vertical line segment
  function vLineBrightness(x, y0, y1) {
    let sum = 0, n = 0;
    for (let y = y0; y < y1; y += 2) {
      sum += brightness(x, y);
      n++;
    }
    return sum / n;
  }

  // The floor tiles are brighter than the dark wall blocks.
  // Scan from each edge inward, find where brightness crosses a threshold.
  // Use the middle band to avoid corner artifacts.

  const midX0 = Math.floor(W * 0.3), midX1 = Math.floor(W * 0.7);
  const midY0 = Math.floor(H * 0.3), midY1 = Math.floor(H * 0.7);

  // --- TOP: scan downward from y=0, sampling middle horizontal band ---
  console.log('\n=== TOP (scan down) ===');
  for (let y = 0; y < Math.floor(H * 0.3); y += 4) {
    const b = hLineBrightness(y, midX0, midX1);
    const frac = y / H;
    const gameY = frac * BG_H + BG_Y;
    if (b > 45) { // floor tiles are brighter
      console.log(`  Floor starts at img y=${y} (${(frac*100).toFixed(1)}%) → game y=${gameY.toFixed(1)}, brightness=${b.toFixed(1)}`);
      break;
    }
    if (y % 20 === 0) console.log(`  y=${y} b=${b.toFixed(1)} → game y=${gameY.toFixed(1)}`);
  }

  // --- BOTTOM: scan upward from y=H-1 ---
  console.log('\n=== BOTTOM (scan up) ===');
  for (let y = H - 1; y > Math.floor(H * 0.7); y -= 4) {
    const b = hLineBrightness(y, midX0, midX1);
    const frac = y / H;
    const gameY = frac * BG_H + BG_Y;
    if (b > 45) {
      console.log(`  Floor ends at img y=${y} (${(frac*100).toFixed(1)}%) → game y=${gameY.toFixed(1)}, brightness=${b.toFixed(1)}`);
      break;
    }
    if ((H - 1 - y) % 20 === 0) console.log(`  y=${y} b=${b.toFixed(1)} → game y=${gameY.toFixed(1)}`);
  }

  // --- LEFT: scan rightward from x=0, sampling middle vertical band ---
  console.log('\n=== LEFT (scan right) ===');
  for (let x = 0; x < Math.floor(W * 0.3); x += 4) {
    const b = vLineBrightness(x, midY0, midY1);
    const frac = x / W;
    const gameX = frac * BG_W + BG_X;
    if (b > 45) {
      console.log(`  Floor starts at img x=${x} (${(frac*100).toFixed(1)}%) → game x=${gameX.toFixed(1)}, brightness=${b.toFixed(1)}`);
      break;
    }
    if (x % 20 === 0) console.log(`  x=${x} b=${b.toFixed(1)} → game x=${gameX.toFixed(1)}`);
  }

  // --- RIGHT: scan leftward from x=W-1 ---
  console.log('\n=== RIGHT (scan left) ===');
  for (let x = W - 1; x > Math.floor(W * 0.7); x -= 4) {
    const b = vLineBrightness(x, midY0, midY1);
    const frac = x / W;
    const gameX = frac * BG_W + BG_X;
    if (b > 45) {
      console.log(`  Floor ends at img x=${x} (${(frac*100).toFixed(1)}%) → game x=${gameX.toFixed(1)}, brightness=${b.toFixed(1)}`);
      break;
    }
    if ((W - 1 - x) % 20 === 0) console.log(`  x=${x} b=${b.toFixed(1)} → game x=${gameX.toFixed(1)}`);
  }

  // Also do a finer scan near the transitions
  console.log('\n=== FINE SCAN (brightness profile near edges) ===');
  
  console.log('\nTop edge (game y from -10 to 40):');
  for (let gameY = -10; gameY <= 40; gameY += 2) {
    const frac = (gameY - BG_Y) / BG_H;
    const imgY = Math.round(frac * H);
    if (imgY >= 0 && imgY < H) {
      const b = hLineBrightness(imgY, midX0, midX1);
      console.log(`  game y=${gameY.toString().padStart(4)} → img y=${imgY.toString().padStart(5)} brightness=${b.toFixed(1)}`);
    }
  }

  console.log('\nBottom edge (game y from 320 to 380):');
  for (let gameY = 320; gameY <= 380; gameY += 2) {
    const frac = (gameY - BG_Y) / BG_H;
    const imgY = Math.round(frac * H);
    if (imgY >= 0 && imgY < H) {
      const b = hLineBrightness(imgY, midX0, midX1);
      console.log(`  game y=${gameY.toString().padStart(4)} → img y=${imgY.toString().padStart(5)} brightness=${b.toFixed(1)}`);
    }
  }

  console.log('\nLeft edge (game x from -30 to 40):');
  for (let gameX = -30; gameX <= 40; gameX += 2) {
    const frac = (gameX - BG_X) / BG_W;
    const imgX = Math.round(frac * W);
    if (imgX >= 0 && imgX < W) {
      const b = vLineBrightness(imgX, midY0, midY1);
      console.log(`  game x=${gameX.toString().padStart(4)} → img x=${imgX.toString().padStart(5)} brightness=${b.toFixed(1)}`);
    }
  }

  console.log('\nRight edge (game x from 600 to 670):');
  for (let gameX = 600; gameX <= 670; gameX += 2) {
    const frac = (gameX - BG_X) / BG_W;
    const imgX = Math.round(frac * W);
    if (imgX >= 0 && imgX < W) {
      const b = vLineBrightness(imgX, midY0, midY1);
      console.log(`  game x=${gameX.toString().padStart(4)} → img x=${imgX.toString().padStart(5)} brightness=${b.toFixed(1)}`);
    }
  }

  console.log('\n=== CURRENT VALUES ===');
  console.log('ARENA_MIN = Vector2(24, 22)');
  console.log('ARENA_MAX = Vector2(616, 335)');
}

main().catch(console.error);
