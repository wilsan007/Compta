/**
 * Asset definitions for Onusuite brand imagery.
 *
 * Derived from .agents/brand-book.md sections 16 (visual strategy),
 * 18 (palette), 20 (imagery) and 22 (design principles).
 *
 * Prompt rules applied, per the installed flux-best-practices skill:
 *  - every hex code is paired with a plain colour name
 *  - 3 to 5 colours maximum per prompt
 *  - FLUX has no negative prompts, so every "avoid" from the brand book is
 *    expressed as a positive anchor describing what should be there instead
 *  - subject is front-loaded; photographic assets carry camera and lens specs
 *  - fixed seeds keep runs reproducible
 */

const TERRACOTTA = '#C44536 (deep terracotta)'
const INDIGO = '#1E2A4A (deep indigo)'
const SAND = '#F5F0E8 (light sand)'
const EMERALD = '#2D7D6F (emerald green)'
const AMBER = '#E8A838 (warm amber)'

export const ASSETS = [
  {
    id: 'hero-geometric',
    file: 'hero-geometric.png',
    model: 'flux-2-pro',
    width: 1536,
    height: 864,
    seed: 1801,
    paletteMode: 'strict',
    expect: ['terracotta', 'indigo', 'sand'],
    description: 'Motif géométrique principal pour le hero des pages d\'accueil',
    prompt: [
      'A precise flat geometric composition built on a strict modular grid,',
      `interlocking rectangles and squares filled with solid ${TERRACOTTA},`,
      `maintaining exact color #C44536 for all terracotta shapes,`,
      `and solid ${INDIGO}, maintaining exact color #1E2A4A for all indigo shapes,`,
      `arranged over a calm ${SAND} background, maintaining exact color #F5F0E8,`,
      'thin crisp dividing lines, generous mathematical spacing, perfect right angles,',
      'the visual language of engineering drawings and Swiss print design,',
      'flat two-dimensional matte surfaces with printed-poster flatness,',
      'even diffuse studio light, sharp edges, no depth illusion,',
      `colour palette strictly limited to #C44536, #1E2A4A and #F5F0E8, no other colours,`,
      'restrained and architectural, evoking accounting precision and modular software structure.',
    ].join(' '),
  },

  {
    id: 'hero-dataviz',
    file: 'hero-dataviz.png',
    model: 'flux-2-pro',
    width: 1536,
    height: 1152,
    seed: 2204,
    paletteMode: 'strict',
    expect: ['terracotta', 'indigo', 'sand'],
    description: 'Données visualisées abstraites (brand book §20: "données visualisées")',
    prompt: [
      'A clean flat data visualisation poster showing abstract business figures,',
      `vertical bar columns filled with solid ${TERRACOTTA}, maintaining exact color #C44536,`,
      `a single rising line chart drawn in ${INDIGO}, maintaining exact color #1E2A4A,`,
      `small square legend blocks in ${EMERALD}, all on a ${SAND} background,`,
      'maintaining exact color #F5F0E8 for the background,',
      'thin axis rules, evenly spaced gridlines aligned to an 8 pixel grid,',
      'flat two-dimensional vector shapes with matte printed surfaces,',
      'editorial infographic style from a financial annual report,',
      'even diffuse lighting, tack-sharp geometric edges,',
      `colour palette strictly limited to #C44536, #1E2A4A, #2D7D6F and #F5F0E8,`,
      'calm, factual and precise, information-dense yet orderly.',
    ].join(' '),
  },

  {
    id: 'og-background',
    file: 'og-background.png',
    model: 'flux-2-pro',
    width: 1216,
    height: 640,
    seed: 3310,
    paletteMode: 'strict',
    expect: ['terracotta', 'indigo', 'sand'],
    description:
      'Fond de l\'image Open Graph. Volontairement sans texte: la typographie est composée ensuite avec de vraies polices.',
    prompt: [
      'A wide minimal geometric background panel,',
      `a broad calm expanse of ${SAND} occupying the left two thirds, maintaining exact color #F5F0E8,`,
      `a modular block pattern of ${TERRACOTTA} squares, maintaining exact color #C44536,`,
      `and ${INDIGO} squares, maintaining exact color #1E2A4A, gathered along the right edge,`,
      'large areas of quiet uninterrupted flat colour reserved for later typography,',
      'thin precise separating lines, strict grid alignment,',
      'flat two-dimensional matte poster surfaces, even diffuse light,',
      `colour palette strictly limited to #F5F0E8, #C44536 and #1E2A4A,`,
      'clean unmarked surfaces throughout, restrained architectural composition.',
    ].join(' '),
  },

  {
    id: 'founder-office',
    file: 'founder-office.png',
    model: 'flux-2-max',
    width: 1536,
    height: 1152,
    seed: 4417,
    paletteMode: 'loose',
    expect: ['sand', 'amber'],
    description:
      'Dirigeant de PME dans son bureau (brand book §20: "dirigeants réels dans leur bureau")',
    prompt: [
      'A West African business owner in her forties working alone at her own desk',
      'in a small company office in Abidjan, reviewing printed accounting ledgers',
      'beside an open laptop, absorbed in concentration, a candid unposed documentary moment,',
      'she wears a simple well-tailored blouse, natural bare face with a healthy glow,',
      `warm afternoon daylight entering through a tall window on the left, ${AMBER} light spilling`,
      `across ${SAND} plaster walls, weathered wooden desk with visible grain,`,
      'shot on Hasselblad X2D with 65mm lens at f/2.8, shallow depth of field,',
      'Kodak Portra 400 colour science, warm earth tones, natural film grain,',
      'authentic reportage photography, tack-sharp on her hands and face.',
    ].join(' '),
  },

  {
    id: 'sme-workspace',
    file: 'sme-workspace.png',
    model: 'flux-2-max',
    width: 1536,
    height: 1152,
    seed: 5523,
    paletteMode: 'loose',
    expect: ['sand', 'amber'],
    description: 'Espace de travail PME, plan large documentaire',
    prompt: [
      'The interior of a small North African accounting office in Casablanca, mid-morning,',
      'two colleagues at separate desks each focused on their own screen,',
      'stacked paper files and a wall calendar, a single potted plant by the window,',
      'lived-in and genuinely used rather than staged,',
      `soft natural daylight through wooden shutters casting ${AMBER} bands across`,
      `${SAND} walls and a tiled floor,`,
      'shot on Leica SL2 with 35mm lens at f/4, deep focus, wide environmental frame,',
      'muted warm earth tones, natural film grain, honest documentary interior photography.',
    ].join(' '),
  },
]

export function getAsset(id) {
  return ASSETS.find((asset) => asset.id === id)
}
