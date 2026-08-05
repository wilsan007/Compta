import { inflateSync } from 'node:zlib'

export const BRAND_PALETTE = {
  terracotta: '#C44536',
  indigo: '#1E2A4A',
  sand: '#F5F0E8',
  emerald: '#2D7D6F',
  amber: '#E8A838',
  brick: '#A6342E',
}

export function hexToRgb(hex) {
  const h = hex.replace('#', '')
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
  ]
}

export function rgbToHex(r, g, b) {
  const c = (v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')
  return `#${c(r)}${c(g)}${c(b)}`.toUpperCase()
}

function srgbToLinear(c) {
  const v = c / 255
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

export function rgbToLab(r, g, b) {
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

export function hexToLab(hex) {
  return rgbToLab(...hexToRgb(hex))
}

export function deltaE2000(lab1, lab2) {
  const [L1, a1, b1] = lab1
  const [L2, a2, b2] = lab2
  const kL = 1
  const kC = 1
  const kH = 1

  const C1 = Math.hypot(a1, b1)
  const C2 = Math.hypot(a2, b2)
  const Cbar = (C1 + C2) / 2

  const Cbar7 = Math.pow(Cbar, 7)
  const G = 0.5 * (1 - Math.sqrt(Cbar7 / (Cbar7 + Math.pow(25, 7))))

  const a1p = a1 * (1 + G)
  const a2p = a2 * (1 + G)

  const C1p = Math.hypot(a1p, b1)
  const C2p = Math.hypot(a2p, b2)

  const toDeg = (rad) => ((rad * 180) / Math.PI + 360) % 360
  const h1p = C1p === 0 ? 0 : toDeg(Math.atan2(b1, a1p))
  const h2p = C2p === 0 ? 0 : toDeg(Math.atan2(b2, a2p))

  const dLp = L2 - L1
  const dCp = C2p - C1p

  let dhp
  if (C1p * C2p === 0) dhp = 0
  else if (Math.abs(h2p - h1p) <= 180) dhp = h2p - h1p
  else if (h2p - h1p > 180) dhp = h2p - h1p - 360
  else dhp = h2p - h1p + 360

  const dHp = 2 * Math.sqrt(C1p * C2p) * Math.sin(((dhp / 2) * Math.PI) / 180)

  const Lbarp = (L1 + L2) / 2
  const Cbarp = (C1p + C2p) / 2

  let hbarp
  if (C1p * C2p === 0) hbarp = h1p + h2p
  else if (Math.abs(h1p - h2p) <= 180) hbarp = (h1p + h2p) / 2
  else if (h1p + h2p < 360) hbarp = (h1p + h2p + 360) / 2
  else hbarp = (h1p + h2p - 360) / 2

  const T =
    1 -
    0.17 * Math.cos((((hbarp - 30) * Math.PI) / 180)) +
    0.24 * Math.cos(((2 * hbarp * Math.PI) / 180)) +
    0.32 * Math.cos((((3 * hbarp + 6) * Math.PI) / 180)) -
    0.2 * Math.cos((((4 * hbarp - 63) * Math.PI) / 180))

  const dTheta = 30 * Math.exp(-Math.pow((hbarp - 275) / 25, 2))
  const Cbarp7 = Math.pow(Cbarp, 7)
  const Rc = 2 * Math.sqrt(Cbarp7 / (Cbarp7 + Math.pow(25, 7)))
  const Sl =
    1 + (0.015 * Math.pow(Lbarp - 50, 2)) / Math.sqrt(20 + Math.pow(Lbarp - 50, 2))
  const Sc = 1 + 0.045 * Cbarp
  const Sh = 1 + 0.015 * Cbarp * T
  const Rt = -Math.sin(((2 * dTheta * Math.PI) / 180)) * Rc

  return Math.sqrt(
    Math.pow(dLp / (kL * Sl), 2) +
      Math.pow(dCp / (kC * Sc), 2) +
      Math.pow(dHp / (kH * Sh), 2) +
      Rt * (dCp / (kC * Sc)) * (dHp / (kH * Sh))
  )
}

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

function paeth(a, b, c) {
  const p = a + b - c
  const pa = Math.abs(p - a)
  const pb = Math.abs(p - b)
  const pc = Math.abs(p - c)
  if (pa <= pb && pa <= pc) return a
  if (pb <= pc) return b
  return c
}

/**
 * Minimal PNG decoder for 8-bit truecolour images (colour type 2 and 6),
 * non-interlaced. Enough for FLUX API output requested with output_format=png.
 * Returns { width, height, channels, data } where data is raw RGB(A) bytes.
 */
export function decodePng(buffer) {
  if (!buffer.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error('Not a PNG file (bad signature)')
  }

  let offset = 8
  let header = null
  const idatChunks = []

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset)
    const type = buffer.toString('ascii', offset + 4, offset + 8)
    const data = buffer.subarray(offset + 8, offset + 8 + length)

    if (type === 'IHDR') {
      header = {
        width: data.readUInt32BE(0),
        height: data.readUInt32BE(4),
        bitDepth: data[8],
        colorType: data[9],
        compression: data[10],
        filter: data[11],
        interlace: data[12],
      }
    } else if (type === 'IDAT') {
      idatChunks.push(data)
    } else if (type === 'IEND') {
      break
    }

    offset += 12 + length
  }

  if (!header) throw new Error('PNG has no IHDR chunk')
  if (header.bitDepth !== 8) {
    throw new Error(`Unsupported PNG bit depth ${header.bitDepth} (expected 8)`)
  }
  if (header.colorType !== 2 && header.colorType !== 6) {
    throw new Error(
      `Unsupported PNG colour type ${header.colorType} (expected 2=RGB or 6=RGBA)`
    )
  }
  if (header.interlace !== 0) {
    throw new Error('Interlaced PNG is not supported')
  }

  const channels = header.colorType === 6 ? 4 : 3
  const { width, height } = header
  const stride = width * channels
  const raw = inflateSync(Buffer.concat(idatChunks))
  const out = Buffer.alloc(stride * height)

  let pos = 0
  for (let y = 0; y < height; y++) {
    const filterType = raw[pos++]
    const rowStart = y * stride
    const prevStart = (y - 1) * stride

    for (let x = 0; x < stride; x++) {
      const value = raw[pos + x]
      const left = x >= channels ? out[rowStart + x - channels] : 0
      const up = y > 0 ? out[prevStart + x] : 0
      const upLeft = y > 0 && x >= channels ? out[prevStart + x - channels] : 0

      let recon
      switch (filterType) {
        case 0:
          recon = value
          break
        case 1:
          recon = value + left
          break
        case 2:
          recon = value + up
          break
        case 3:
          recon = value + Math.floor((left + up) / 2)
          break
        case 4:
          recon = value + paeth(left, up, upLeft)
          break
        default:
          throw new Error(`Unknown PNG filter type ${filterType} on row ${y}`)
      }
      out[rowStart + x] = recon & 0xff
    }
    pos += stride
  }

  return { width, height, channels, data: out }
}

/**
 * Extract dominant colours by quantising into a 16x16x16 grid and averaging
 * the true colours inside each populated bucket.
 */
export function dominantColors(png, topN = 8) {
  const { width, height, channels, data } = png
  const buckets = new Map()
  let sampled = 0

  // Cap the work at roughly 250k samples for large images.
  const totalPixels = width * height
  const step = Math.max(1, Math.floor(Math.sqrt(totalPixels / 250_000)))

  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const i = (y * width + x) * channels
      if (channels === 4 && data[i + 3] < 128) continue

      const r = data[i]
      const g = data[i + 1]
      const b = data[i + 2]
      const key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)

      let bucket = buckets.get(key)
      if (!bucket) {
        bucket = { r: 0, g: 0, b: 0, count: 0 }
        buckets.set(key, bucket)
      }
      bucket.r += r
      bucket.g += g
      bucket.b += b
      bucket.count++
      sampled++
    }
  }

  if (sampled === 0) return []

  return [...buckets.values()]
    .sort((a, b) => b.count - a.count)
    .slice(0, topN)
    .map((bucket) => {
      const r = bucket.r / bucket.count
      const g = bucket.g / bucket.count
      const b = bucket.b / bucket.count
      return {
        hex: rgbToHex(r, g, b),
        lab: rgbToLab(r, g, b),
        share: bucket.count / sampled,
      }
    })
}

/**
 * Compare an image's dominant colours against the brand palette.
 *
 * mode 'strict'  -> brand colours must be present AND large off-palette areas fail
 * mode 'loose'   -> brand colours must be present, off-palette areas tolerated
 *                   (photographs legitimately contain skin, wood, sky tones)
 * mode 'off'     -> report only, never fail
 */
export function validatePalette(png, options = {}) {
  const {
    mode = 'strict',
    expect = ['terracotta', 'indigo', 'sand'],
    tolerance = mode === 'strict' ? 8 : 16,
    minShare = 0.03,
    palette = BRAND_PALETTE,
  } = options

  const paletteLabs = Object.entries(palette).map(([name, hex]) => ({
    name,
    hex,
    lab: hexToLab(hex),
  }))

  const dominants = dominantColors(png, 10).map((colour) => {
    let nearest = null
    for (const entry of paletteLabs) {
      const delta = deltaE2000(colour.lab, entry.lab)
      if (!nearest || delta < nearest.deltaE) {
        nearest = { name: entry.name, hex: entry.hex, deltaE: delta }
      }
    }
    return { hex: colour.hex, share: colour.share, nearest }
  })

  const significant = dominants.filter((d) => d.share >= minShare)

  const coverage = expect.map((name) => {
    const target = hexToLab(palette[name])
    let best = Infinity
    let bestHex = null
    for (const colour of dominantColors(png, 24)) {
      const delta = deltaE2000(colour.lab, target)
      if (delta < best) {
        best = delta
        bestHex = colour.hex
      }
    }
    return { name, expected: palette[name], closest: bestHex, deltaE: best, ok: best <= tolerance }
  })

  const missing = coverage.filter((c) => !c.ok)
  const offPalette = significant.filter((d) => d.nearest.deltaE > tolerance * 2)

  let ok = true
  const problems = []

  if (mode !== 'off') {
    if (missing.length > 0) {
      ok = false
      problems.push(
        `brand colours absent or drifted: ${missing
          .map((m) => `${m.name} (closest ${m.closest}, ΔE ${m.deltaE.toFixed(1)})`)
          .join(', ')}`
      )
    }
  }

  if (mode === 'strict' && offPalette.length > 0) {
    ok = false
    problems.push(
      `significant off-palette areas: ${offPalette
        .map((d) => `${d.hex} (${(d.share * 100).toFixed(0)}%, ΔE ${d.nearest.deltaE.toFixed(1)})`)
        .join(', ')}`
    )
  }

  return { ok, mode, tolerance, problems, coverage, dominants: significant }
}
