import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";

const size = 1024;
const bytesPerPixel = 3;
const scanline = 1 + size * bytesPerPixel;
const raw = Buffer.alloc(scanline * size);

for (let y = 0; y < size; y += 1) {
  const row = y * scanline;
  raw[row] = 0;

  for (let x = 0; x < size; x += 1) {
    const offset = row + 1 + x * bytesPerPixel;
    const t = (x + y) / (size * 2);
    let red = Math.round(37 + 28 * t);
    let green = Math.round(54 + 30 * t);
    let blue = Math.round(96 + 55 * t);

    const dx = x - size / 2;
    const dy = y - size / 2;
    const radius = Math.hypot(dx, dy);
    const angle = Math.atan2(dy, dx);
    const isRing = radius > 245 && radius < 335;
    const isOpening = Math.abs(angle) < 0.72;

    if (isRing && !isOpening) {
      red = 248;
      green = 250;
      blue = 255;
    }

    raw[offset] = red;
    raw[offset + 1] = green;
    raw[offset + 2] = blue;
  }
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuffer = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])));
  return Buffer.concat([length, typeBuffer, data, checksum]);
}

const header = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(size, 0);
ihdr.writeUInt32BE(size, 4);
ihdr[8] = 8;
ihdr[9] = 2;

const png = Buffer.concat([
  header,
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

const output = resolve(
  "ios",
  "CrispAgent",
  "Resources",
  "Assets.xcassets",
  "AppIcon.appiconset",
  "AppIcon-1024.png",
);
writeFileSync(output, png);
console.log(`Generated ${output}`);
