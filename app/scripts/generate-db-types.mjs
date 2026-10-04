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
    // Récupérer toutes les tables avec leurs colonnes.
    //
    // ⚠️ LES PARTITIONS SONT EXCLUES — et ce n'est pas un détail de confort.
    // Le socle des chaînages partitionne `chain_traces` et `domain_events` par
    // mois, et la 252 crée les partitions du mois + 3. Leurs NOMS portent la date
    // (`chain_traces_2026_09`…). Les inclure rendait ce fichier **dépendant du
    // jour où on le génère** : le 30/09 il portait `…_2026_09` à `…_2026_12`, et
    // le 1ᵉʳ octobre il aurait porté `…_2026_10` à `…_2027_01` — la CI
    // « Vérifier que les types sont à jour » **échouait donc le 1ᵉʳ de chaque
    // mois**, pour n'importe quel commit, sans qu'aucun code ait changé. Mesuré
    // le 01/10/2026 (run `36829228592`) : la CI a refusé un commit qui ne touchait
    // ni le schéma ni les types, alors que les vérifications locales de la veille
    // étaient vertes.
    //
    // Rien n'utilise ces partitions : le code interroge les PARENTS
    // (`chain_traces`, `domain_events`), et PostgreSQL route tout seul. Elles sont
    // un détail d'implémentation, et `relispartition` le dit.
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
        -- Les tables d audit des suites SQL (_audit_expected, _audit_results)
        -- sont des ARTEFACTS D EXECUTION : elles naissent quand les tests SQL
        -- tournent, et disparaissent sur une base neuve. Les inclure rendrait le
        -- fichier genere dependant du fait que les tests ont tourne en local :
        -- la CI regenere sur base neuve et refuserait alors tout ecart, sans
        -- qu aucun code ait change. Meme famille que le piege des partitions
        -- ci-dessus, meme cause : une table qui n est pas du schema.
        -- Le predicat NOT LIKE avec un joker ne convient PAS : le tiret bas
        -- matche n importe quel caractere, donc il est VRAI pour toutes les
        -- tables (mesure le 2026-10-02) et la generation renvoyait 0 table.
        -- D ou le left(...,1) different du tiret bas : ni joker, ni
        -- dependance au reglage standard_conforming_strings.
        AND left(t.table_name, 1) <> '_'
        AND NOT EXISTS (
          SELECT 1
            FROM pg_class k
            JOIN pg_namespace n ON n.oid = k.relnamespace
           WHERE n.nspname = 'public'
             AND k.relname = t.table_name
             AND k.relispartition
        )
      ORDER BY t.table_name, c.ordinal_position
    `

    const { rows } = await pool.query(tablesQuery)

    // Les relations : chaque clé étrangère, avec ses colonnes RÉSOLUES PAR
    // `attnum` (et non par position dans le tableau — l'ordre de `conkey` suit
    // l'ordre de déclaration de la contrainte, pas celui des colonnes).
    //
    // `unnest(...) WITH ORDINALITY` sert à garder l'association colonne ↔ colonne
    // référencée quand la clé est COMPOSITE (427 des 692 le sont : le
    // cloisonnement de tenant, `(tenant_id, employee_id)`).
    //
    // On ne garde que les relations que PostgREST sait RÉSOUDRE : il exige que
    // les colonnes référencées soient couvertes par une clé unique ou primaire
    // côté cible. Sans cette condition on déclarerait des jointures que PostgREST
    // refuse à l'exécution — un type qui promet l'impossible. Mesuré le
    // 2026-10-02 : **692/692** relations sont résolvables, donc ce filtre ne
    // retire rien aujourd'hui ; il rend le générateur exact si une clé cible
    // non unique apparaît plus tard.
    const relationsQuery = `
      SELECT
        c.conname AS foreign_key_name,
        src.relname AS source_table,
        tgt.relname AS target_table,
        src_att.attname AS source_column,
        tgt_att.attname AS target_column,
        cardinality(c.conkey) AS column_count,
        (src_att.attnotnull AND cardinality(c.confkey) = 1) AS is_one_to_one
      FROM pg_constraint c
      JOIN pg_class src ON src.oid = c.conrelid
      JOIN pg_class tgt ON tgt.oid = c.confrelid
      JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS src_key(attnum, ordinality)
        ON TRUE
      JOIN LATERAL unnest(c.confkey) WITH ORDINALITY AS tgt_key(attnum, ordinality)
        ON tgt_key.ordinality = src_key.ordinality
      JOIN pg_attribute src_att
        ON src_att.attrelid = c.conrelid AND src_att.attnum = src_key.attnum
      JOIN pg_attribute tgt_att
        ON tgt_att.attrelid = c.confrelid AND tgt_att.attnum = tgt_key.attnum
      WHERE c.contype = 'f'
        AND c.connamespace = 'public'::regnamespace
        AND EXISTS (
          SELECT 1 FROM pg_constraint uc
          WHERE uc.contype IN ('u', 'p')
            AND uc.conrelid = c.confrelid
            AND uc.conkey @> c.confkey
        )
      ORDER BY c.conname, src_key.ordinality
    `
    const { rows: relationRows } = await pool.query(relationsQuery)

    // Regrouper les colonnes par clé étrangère : `conkey` et `confkey` sont
    // parallèles, d'où le regroupement sur (conname, ordre).
    const relations = {}
    for (const row of relationRows) {
      const cle = row.source_table + '\u0000' + row.foreign_key_name
      if (!relations[cle]) {
        relations[cle] = {
          foreignKeyName: row.foreign_key_name,
          columns: [],
          isOneToOne: row.is_one_to_one,
          referencedRelation: row.target_table,
          referencedColumns: []
        }
      }
      relations[cle].columns.push(row.source_column)
      relations[cle].referencedColumns.push(row.target_column)
    }
    // `source_table` -> liste de relations, dans un ordre DÉTERMINÉ (le nom de la
    // contrainte) : le fichier généré ne doit pas dépendre de l'ordre du planner.
    const relationsParTable = {}
    for (const [cle, rel] of Object.entries(relations)) {
      const table = cle.split('\u0000')[0]
      if (!relationsParTable[table]) relationsParTable[table] = []
      relationsParTable[table].push(rel)
    }
    for (const list of Object.values(relationsParTable)) {
      list.sort((a, b) => (a.foreignKeyName < b.foreignKeyName ? -1 : a.foreignKeyName > b.foreignKeyName ? 1 : 0))
    }

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
        // LOT7-04 : une colonne nullable se lit `T | null`, PAS `col?: T`. PostgREST
        // renvoie toujours la propriété — avec la valeur null quand la colonne est
        // vide, jamais absente. La marquer optionnelle laissait croire qu'il suffisait
        // de tester sa présence, et masquait les `null` que le code doit traiter.
        // (`Insert` et `Update` gardent `?` : là, une colonne PEUT être omise.)
        const type = col.nullable ? `${col.type} | null` : col.type
        tsContent += `        ${tsKey(col.name)}: ${type}\n`
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
      // Relations : chaque clé étrangère devient une entrée `Relationships`.
    //
    // LOT7-04 (corrigé le 2026-10-02) : ce bloc était écrit `Relationships: []`
    // en dur, et le commentaire affirmait que « les jointures imbriquées ne sont pas
    // décrites ici ». C'était vrai du générateur, et c'est ce qui rendait
    // `Joined<>` INUTILISABLE : les 363 tables déclaraient zéro relation, donc
    // aucune relation n'était une clé de `Row<T>` et le type ne pouvait nommer
    // aucune jointure (0 usage). Mesuré : **692** clés étrangères existent, dont
    // **427 composites** `(tenant_id, …)` — le cloisonnement de tenant.
    //
    // `Relationships` est la forme attendue par supabase-js :
    // `{ foreignKeyName, columns, isOneToOne, referencedRelation, referencedColumns }`.
    // C'est ce que `Joined<>` lit pour résoudre une ressource jointe.
    //
    // Une relation n'est PAS toujours clé de `Row` : `employees` n'est pas une
    // colonne de `salary_advances`, c'est une clé étrangère. `Joined<>` ne doit
    // donc pas contraindre `K` à `keyof Row<T>` (ce qui le rendait faux même
    // lorsque les relations étaient là) mais à `RelationshipsNames<T>` — voir
    // `src/types/dbRow.ts`.
    tsContent += `      }\n      Relationships: [\n`
    for (const rel of relationsParTable[tableName] || []) {
      tsContent += `        {\n`
      tsContent += `          foreignKeyName: ${JSON.stringify(rel.foreignKeyName)},\n`
      tsContent += `          columns: [${rel.columns.map((c) => JSON.stringify(c)).join(', ')}],\n`
      tsContent += `          isOneToOne: ${rel.isOneToOne},\n`
      tsContent += `          referencedRelation: ${JSON.stringify(rel.referencedRelation)},\n`
      tsContent += `          referencedColumns: [${rel.referencedColumns.map((c) => JSON.stringify(c)).join(', ')}]\n`
      tsContent += `        },\n`
    }
    tsContent += `      ]\n    }\n`
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
