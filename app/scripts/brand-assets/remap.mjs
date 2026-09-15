/**
 * Post-process: remap generated PNG pixels to the nearest brand palette colour.
 *
 * Used for assets in 'strict' palette mode where FLUX drifts the hex codes.
 * The skill `brand-consistency` calls this "K-means remap in LAB space" —
 * the fallback that always works.
 *
 * For 'loose' mode (photographs), remap is skipped: skin, wood, sky tones
 * are legitimately off-palette.
 */

import { deflateSync } from 'node:zlib'
import { readFileSync, writeFileSync } from 'node:fs'

import {
  BRAND_PALETTE,
  decodePng,
  hexToLab,
  deltaE2000,
} from './palette.mjs'

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

function crc32(buf) {
  let table = crc32.table
  if (!table) {
    table = new Uint32Array(256)
    for (let n = 0; n < 256; n++) {
      let c = n
      for (let k = 0; k < 8; k++) {
        c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
      }
      table[n] = c
    }
    crc32.table = table
  }
  let crc = 0xffffffff
  for (const byte of buf) {
    crc = table[(crc ^ byte) & 0xff] ^ (crc >>> 8)
  }
  return (crc ^ 0xffffffff) >>> 0
}

function encodeChunk(type, data) {
  const typeBuf = Buffer.from(type, 'ascii')
  const lenBuf = Buffer.alloc(4)
  lenBuf.writeUInt32BE(data.length, 0)
  const crcBuf = Buffer.alloc(4)
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0)
  return Buffer.concat([lenBuf, typeBuf, data, crcBuf])
}

function encodePng(png) {
  const { width, height, channels, data } = png
  const colorType = channels === 4 ? 6 : 2

  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0)
  ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8 // bit depth
  ihdr[9] = colorType
  ihdr[10] = 0 // compression
  ihdr[11] = 0 // filter
  ihdr[12] = 0 // interlace

  // Build raw scanlines with filter byte 0 (none) per row
  const stride = width * channels
  const raw = Buffer.alloc((stride + 1) * height)
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0 // filter: none
    data.subarray(y * stride, (y + 1) * stride).copy(raw, y * (stride + 1) + 1)
  }

  const idat = deflateSync(raw, { level: 9 })

  return Buffer.concat([
    PNG_SIGNATURE,
    encodeChunk('IHDR', ihdr),
    encodeChunk('IDAT', idat),
    encodeChunk('IEND', Buffer.alloc(0)),
  ])
}

/**
 * Remap every pixel to the nearest brand palette colour in CIE LAB space.
 *
 * @param {string} inputPath   Path to the source PNG.
 * @param {string} outputPath  Path for the remapped PNG.
 * @param {string[]} paletteNames  Which brand palette entries to snap to.
 * @param {object} options
 * @param {number} options.threshold  Max ΔE for remap. Pixels farther than this
 *   from every palette entry are left unchanged (avoids destroying detail in
 *   photographic regions that happen to be in strict-mode assets).
 */
export function remapToPalette(inputPath, outputPath, paletteNames, options = {}) {
  const { threshold = 25 } = options

  const paletteLabs = paletteNames.map((name) => ({
    name,
    hex: BRAND_PALETTE[name],
    lab: hexToLab(BRAND_PALETTE[name]),
    rgb: [
      parseInt(BRAND_PALETTE[name].slice(1, 3), 16),
      parseInt(BRAND_PALETTE[name].slice(3, 5), 16),
      parseInt(BRAND_PALETTE[name].slice(5, 7), 16),
    ],
  }))

  const png = decodePng(readFileSync(inputPath))
  const { width, height, channels, data } = png

  let remapped = 0
  const total = width * height

  for (let i = 0; i < total; i++) {
    const offset = i * channels
    const r = data[offset]
    const g = data[offset + 1]
    const b = data[offset + 2]
    const alpha = channels === 4 ? data[offset + 3] : 255
    if (alpha < 128) continue

    // Find nearest palette entry in LAB
    let nearest = null
    let bestDelta = Infinity
    for (const entry of paletteLabs) {
      const pixelLab = labFromRgb(r, g, b)
      const delta = deltaE2000(pixelLab, entry.lab)
      if (delta < bestDelta) {
        bestDelta = delta
        nearest = entry
      }
    }

    if (nearest && bestDelta <= threshold) {
      data[offset] = nearest.rgb[0]
      data[offset + 1] = nearest.rgb[1]
      data[offset + 2] = nearest.rgb[2]
      remapped++
    }
  }

  writeFileSync(outputPath, encodePng(png))

  return {
    totalPixels: total,
    remappedPixels: remapped,
    coverage: remapped / total,
  }
}

// Inline to avoid circular import — palette.mjs exports rgbToLab but we
// need a version that doesn't create closures in a hot loop.
function labFromRgb(r, g, b) {
  const rl = srgbToLinear(r)
  const gl = srgbToLinear(g)
  const bl = srgbToLinear(b)

  const x = (rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375) / 0.95047
  const y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.072175
  const z = (rl * 0.0193339 + gl * 0.119192 + bl * 0.9503041) / 1.08883

  const f = (t) => (t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116)
  const fx = f(x)
  const fy = f(y)
  const fz = f(z)

  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
}

function srgbToLinear(c) {
  const v = c / 255
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}
