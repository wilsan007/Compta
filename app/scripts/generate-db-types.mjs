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
        type: mapPostgresTypeToTs(row.data_type),
        nullable: row.is_nullable === 'YES',
        default: row.column_default
      })
    }

    // Générer le fichier TypeScript
    let tsContent = `// ============================================
// Types générés automatiquement depuis PostgreSQL
// NE PAS ÉDITER MANUELLEMENT — utiliser scripts/generate-db-types.mjs
// ============================================

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
      tsContent += `      }\n    }\n`
    }

    tsContent += `    }\n  }\n}\n`

    // Écrire le fichier
    const outputPath = join(__dirname, '../src/types/database-generated.ts')
    writeFileSync(outputPath, tsContent, 'utf8')

    console.log(`✅ Types générés : ${outputPath}`)
    console.log(`📊 ${Object.keys(tables).length} tables traitées`)

  } finally {
    await pool.end()
  }
}

// Nom de propriété TypeScript valide (colonnes avec espaces, tirets…)
function tsKey(name) {
  return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name) ? name : JSON.stringify(name)
}

function mapPostgresTypeToTs(pgType) {
  const mapping = {
    'uuid': 'string',
    'text': 'string',
    'varchar': 'string',
    'character varying': 'string',
    'integer': 'number',
    'bigint': 'number',
    'smallint': 'number',
    'numeric': 'number',
    'decimal': 'number',
    'real': 'number',
    'double precision': 'number',
    'boolean': 'boolean',
    'date': 'string',
    'timestamp without time zone': 'string',
    'timestamp with time zone': 'string',
    'timestamptz': 'string',
    'json': 'any',
    'jsonb': 'any',
    'array': 'any[]',
    'bytea': 'string'
  }
  return mapping[pgType] || 'any'
}

generateTypes().catch(console.error)
