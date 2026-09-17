#!/usr/bin/env node
/**
 * generate-db-types.mjs
 * Génère les types TypeScript depuis le schéma PostgreSQL
 * Détecte les colonnes fantômes (LOT1-06) via compilation TypeScript
 */

import pg from 'pg'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import { writeFileSync } from 'fs'

const { Pool } = pg
const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

const DATABASE_URL = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/compta'

async function generateTypes() {
  const pool = new Pool({ connectionString: DATABASE_URL })

  try {
    // Récupérer toutes les tables avec leurs colonnes
    const tablesQuery = `
      SELECT
        t.table_name,
        c.column_name,
        c.data_type,
        c.udt_name,
        c.is_nullable,
        c.column_default,
        c.ordinal_position
      FROM information_schema.tables t
      JOIN information_schema.columns c ON c.table_name = t.table_name AND c.table_schema = t.table_schema
      WHERE t.table_schema = 'public'
        AND t.table_type = 'BASE TABLE'
      ORDER BY t.table_name, c.ordinal_position
    `

    const { rows } = await pool.query(tablesQuery)

    // Grouper par table
    const tables = {}
    for (const row of rows) {
      if (!tables[row.table_name]) {
        tables[row.table_name] = []
      }
      tables[row.table_name].push({
        name: row.column_name,
        type: mapPostgresTypeToTs(row.data_type, row.udt_name, `${row.table_name}.${row.column_name}`),
        nullable: row.is_nullable === 'YES',
        default: row.column_default
      })
    }

    // Générer le fichier TypeScript
    let tsContent = `// ============================================
// Types générés automatiquement depuis PostgreSQL
// NE PAS ÉDITER MANUELLEMENT — utiliser scripts/generate-db-types.mjs
// ============================================

// LOT7-04 : les colonnes json/jsonb étaient typées \`any\`, ce qui désactivait
// tout contrôle sur leur contenu ET sur tout ce qu'on en dérivait. \`Json\` décrit
// la forme réelle d'une valeur JSON : le compilateur exige désormais un accès
// explicite (cast ou garde de type) au lieu de laisser passer n'importe quoi.
export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
`

    for (const [tableName, columns] of Object.entries(tables)) {
      tsContent += `    ${tableName}: {\n      Row: {\n`
      for (const col of columns) {
        const optional = col.nullable ? '?' : ''
        tsContent += `        ${tsKey(col.name)}${optional}: ${col.type}\n`
      }
      tsContent += `      }\n      Insert: {\n`
      for (const col of columns) {
        const optional = col.nullable || col.default ? '?' : ''
        tsContent += `        ${tsKey(col.name)}${optional}: ${col.type}\n`
      }
      tsContent += `      }\n      Update: {\n`
      for (const col of columns) {
        tsContent += `        ${tsKey(col.name)}?: ${col.type}\n`
      }
      // LOT7-04 : supabase-js exige `Relationships` sur chaque table. Sans cette clé,
      // `createClient<Database>` résout toutes les lignes sur `never` — les accès
      // deviennent des erreurs « Property 'id' does not exist ». Les jointures
      // imbriquées ne sont pas décrites ici : un tableau vide suffit à rendre la
      // forme conforme, les tables restant typées correctement.
      tsContent += `      }\n      Relationships: []\n    }\n`
    }

    // Idem pour les quatre sections de schéma attendues par supabase-js.
    tsContent += `    }
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
`

    // Écrire le fichier
    const outputPath = join(__dirname, '../src/types/database-generated.ts')
    writeFileSync(outputPath, tsContent, 'utf8')

    console.log(`✅ Types générés : ${outputPath}`)
    console.log(`📊 ${Object.keys(tables).length} tables traitées`)
    if (unmapped.size > 0) {
      console.warn(`\n⚠️  ${unmapped.size} type(s) PostgreSQL sans correspondance, typés \`unknown\` :`)
      for (const t of unmapped) console.warn(`   - ${t}`)
      console.warn(`   Ajouter la correspondance dans TYPE_MAP / UDT_MAP de ce script.`)
    }

  } finally {
    await pool.end()
  }
}

// Nom de propriété TypeScript valide (colonnes avec espaces, tirets…)
function tsKey(name) {
  return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name) ? name : JSON.stringify(name)
}

// LOT7-04 : plus aucun `any` ici. Un type PostgreSQL inconnu tombe sur `unknown`,
// qui oblige l'appelant à restreindre explicitement — et le script le signale
// bruyamment pour qu'on ajoute la correspondance.
const TYPE_MAP = {
  'uuid': 'string',
  'text': 'string',
  'varchar': 'string',
  'character varying': 'string',
  'character': 'string',
  'integer': 'number',
  'bigint': 'number',
  'smallint': 'number',
  'numeric': 'number',
  'decimal': 'number',
  'real': 'number',
  'double precision': 'number',
  'boolean': 'boolean',
  'date': 'string',
  'time without time zone': 'string',
  'time with time zone': 'string',
  'timestamp without time zone': 'string',
  'timestamp with time zone': 'string',
  'timestamptz': 'string',
  'interval': 'string',
  'inet': 'string',
  'cidr': 'string',
  'macaddr': 'string',
  'json': 'Json',
  'jsonb': 'Json',
  'bytea': 'string'
}

// Les colonnes tableau remontent avec data_type = 'ARRAY' ; le type de l'élément
// n'est lisible que dans udt_name, préfixé d'un underscore ('_text', '_uuid').
const UDT_MAP = {
  '_text': 'string', '_varchar': 'string', '_uuid': 'string', '_bpchar': 'string',
  '_int2': 'number', '_int4': 'number', '_int8': 'number', '_numeric': 'number',
  '_float4': 'number', '_float8': 'number', '_bool': 'boolean',
  '_date': 'string', '_timestamp': 'string', '_timestamptz': 'string',
  '_json': 'Json', '_jsonb': 'Json'
}

const unmapped = new Set()

function mapPostgresTypeToTs(pgType, udtName, where) {
  if (pgType === 'ARRAY') {
    const element = UDT_MAP[udtName]
    if (element) return `${element}[]`
    unmapped.add(`${pgType} (${udtName}) — ex. ${where}`)
    return 'unknown[]'
  }
  const mapped = TYPE_MAP[pgType]
  if (mapped) return mapped
  unmapped.add(`${pgType} — ex. ${where}`)
  return 'unknown'
}

generateTypes().catch(console.error)
