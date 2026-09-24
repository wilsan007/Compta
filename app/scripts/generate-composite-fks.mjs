#!/usr/bin/env node
/**
 * generate-composite-fks.mjs — ISO-02 : clés étrangères composites (tenant_id, …)
 *
 * LE DÉFAUT QUE CE SCRIPT FERME. Une clé étrangère mono-colonne
 * (`invoice_lines.invoice_id → invoices.id`) ne regarde pas la société : la ligne
 * de la société A peut désigner la ligne de la société B, que A ne voit même pas
 * en lecture. Mesuré le 24/09/2026 sur base neuve : 411 clés étrangères de ce
 * type, sur 189 tables. Une politique RLS « par le parent » bloquerait le rôle
 * `authenticated`, mais ni `service_role` ni les déclencheurs `SECURITY DEFINER` :
 * seule la clé composite `(tenant_id, …)` referme la classe, parce qu'elle vit
 * dans les DONNÉES et non dans les droits.
 *
 * POURQUOI UN GÉNÉRATEUR, ET NON UNE LISTE ÉCRITE À LA MAIN. Le relevé du schéma
 * est la source ; l'écrire à la main donnerait 411 occasions de se tromper, et la
 * prochaine table ajoutée échapperait à la liste. Le SQL produit est commité
 * (`sql/237_composite_foreign_keys.sql`), donc relisible et exécutable sans
 * Node — la CI ne dépend pas de ce script.
 *
 * MODE `--check` : mesure, sans rien écrire, les lignes qui violent déjà la
 * future clé (références inter-sociétés). C'est la preuve d'entrée du correctif :
 * une migration qui refuse de passer doit dire combien de lignes la gênent.
 *
 * Usage :
 *   DATABASE_URL=… node scripts/generate-composite-fks.mjs > sql/237_composite_foreign_keys.sql
 *   DATABASE_URL=… node scripts/generate-composite-fks.mjs --check
 */
import pg from 'pg';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl && !process.env.PGHOST) {
  console.error('❌ DATABASE_URL (ou PGHOST/PGUSER/PGPASSWORD/PGDATABASE) requis.');
  process.exit(1);
}

const isLocal = databaseUrl
  ? /localhost|127\.0\.0\.1/.test(databaseUrl)
  : /localhost|127\.0\.0\.1/.test(process.env.PGHOST || '');

const checkOnly = process.argv.includes('--check');
/**
 * Une SECONDE PASSE est nécessaire : des migrations postérieures à la 237 créent
 * des clés étrangères (`241` ajoute `goods_receipts.warehouse_id`, `244` recrée
 * `stock_movements_product_id_fkey` pour préserver l'historique). Elles ne
 * peuvent pas être traitées par la 237, qui s'exécute avant elles : le relevé de
 * la 237 est donc pris à l'état où elle s'exécute (≤ 236), et cette passe-là est
 * générée sur l'état FINAL, où elle ne trouve plus que les retardataires.
 */
const passe2 = process.argv.includes('--passe2');


const client = new pg.Client({
  ...(databaseUrl
    ? { connectionString: databaseUrl }
    : {
        host: process.env.PGHOST,
        port: Number(process.env.PGPORT || 5432),
        user: process.env.PGUSER,
        password: process.env.PGPASSWORD,
        database: process.env.PGDATABASE,
      }),
  ssl: isLocal ? false : { rejectUnauthorized: true },
});

/**
 * Les clés candidates : une seule colonne, les deux tables portent `tenant_id`,
 * et la colonne ne porte PAS déjà la société (la clé `…_tenant_id_fkey` vers
 * `tenants` n'a rien à composer : elle EST le lien de société).
 */
const CANDIDATES = `
SELECT f.conname      AS fk_name,
       cc.relname     AS child,
       cp.relname     AS parent,
       a.attname      AS child_col,
       pa.attname     AS parent_col,
       f.confdeltype  AS on_delete,
       f.confupdtype  AS on_update,
       f.condeferrable AS deferrable,
       f.condeferred  AS deferred
FROM pg_constraint f
JOIN pg_class cc     ON cc.oid = f.conrelid
JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'
JOIN pg_class cp     ON cp.oid = f.confrelid
JOIN pg_namespace np ON np.oid = cp.relnamespace AND np.nspname = 'public'
JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]
JOIN pg_attribute pa ON pa.attrelid = f.confrelid AND pa.attnum = f.confkey[1]
WHERE f.contype = 'f'
  AND array_length(f.conkey, 1) = 1
  AND a.attname <> 'tenant_id'
  AND EXISTS (SELECT 1 FROM information_schema.columns x
              WHERE x.table_schema = 'public' AND x.table_name = cc.relname
                AND x.column_name = 'tenant_id')
  AND EXISTS (SELECT 1 FROM information_schema.columns y
              WHERE y.table_schema = 'public' AND y.table_name = cp.relname
                AND y.column_name = 'tenant_id')
ORDER BY cc.relname, f.conname`;

/** Les contraintes d'unicité existantes, pour ne pas recréer ce qui tient déjà. */
const UNIQUES = `
SELECT c.relname AS tbl, k.conname,
       (SELECT array_agg(a.attname::text ORDER BY u.ord)
          FROM unnest(k.conkey) WITH ORDINALITY AS u(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = u.attnum) AS cols
FROM pg_constraint k
JOIN pg_class c     ON c.oid = k.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE k.contype IN ('u', 'p')`;

const ACTION = { a: 'NO ACTION', r: 'RESTRICT', c: 'CASCADE', n: 'SET NULL', d: 'SET DEFAULT' };

/**
 * LE PIÈGE MESURÉ, et sa solution. Depuis PostgreSQL 15, `ON DELETE SET NULL` et
 * `SET DEFAULT` acceptent une **liste de colonnes**. Sans elle, une clé composite
 * annule TOUTES les colonnes de la clé — y compris `tenant_id`, qui est NOT NULL :
 * supprimer un client faisait alors échouer la suppression de la facture (mesuré,
 * scénario T07 vu rouge avant ce correctif). Avec `SET NULL (colonne)`, la clé
 * composite retrouve exactement le comportement de la clé d'origine.
 */
const actsOn = (c) => ['n', 'd'].includes(c.on_delete) ? ' ("' + c.child_col + '")' : '';


/** PostgreSQL limite les identifiants à 63 octets : tronquer sans perdre l'unicité. */
function ident(name) {
  if (name.length <= 63) return name;
  let hash = 0;
  for (const ch of name) hash = (hash * 31 + ch.charCodeAt(0)) % 0xffffff;
  return `${name.slice(0, 56)}_${hash.toString(16).padStart(6, '0')}`;
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

/** Le mode mesure : combien de lignes, aujourd'hui, violent la future clé. */
async function check(candidates) {
  let faults = 0;
  for (const c of candidates) {
    const { rows } = await client.query(`
      SELECT count(*)::int AS n FROM public.${c.child} ch
      WHERE ch."${c.child_col}" IS NOT NULL AND ch.tenant_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM public.${c.parent} pa
                        WHERE pa."${c.parent_col}" = ch."${c.child_col}"
                          AND pa.tenant_id = ch.tenant_id)`);
    if (rows[0].n > 0) {
      faults += 1;
      console.log(`🔴 ${c.child}.${c.child_col} → ${c.parent}.${c.parent_col} : ${rows[0].n} ligne(s) hors société`);
    }
  }
  console.log(`\n${candidates.length} clé(s) examinée(s), ${faults} en défaut sur la base interrogée.`);
}

async function main() {
  await client.connect();

  const { rows: candidates } = await client.query(CANDIDATES);
  const { rows: uniques } = await client.query(UNIQUES);

  if (checkOnly) {
    await check(candidates);
    await client.end();
    return;
  }

  // (table, colonne) → colonnes de la contrainte d'unicité qui peut servir de cible
  const target = new Map();
  for (const u of uniques) {
    if (u.cols.length !== 2 || !u.cols.includes('tenant_id')) continue;
    for (const col of u.cols) {
      if (col === 'tenant_id') continue;
      target.set(`${u.tbl}.${col}`, u.cols);
    }
  }

  // 1. Les contraintes d'unicité manquantes sur les parents
  const missing = new Map();
  for (const c of candidates) {
    const key = `${c.parent}.${c.parent_col}`;
    if (target.has(key) || missing.has(key)) continue;
    missing.set(key, {
      parent: c.parent,
      col: c.parent_col,
      name: ident(`${c.parent}_tenant_id_${c.parent_col}_key`),
    });
  }

  // 2. Les clés étrangères composites, dans l'ordre des tables enfants
  const fks = candidates.map((c) => {
    const refCols = target.get(`${c.parent}.${c.parent_col}`) || ['tenant_id', c.parent_col];
    return {
      ...c,
      refColsSql: refCols.map((x) => `"${x}"`).join(', '),
      actions: `${c.on_update !== 'a' ? ` ON UPDATE ${ACTION[c.on_update]}` : ''}` +
               `${c.on_delete !== 'a' ? ` ON DELETE ${ACTION[c.on_delete]}${actsOn(c)}` : ''}`,
      defer: c.deferrable ? ` DEFERRABLE INITIALLY ${c.deferred ? 'DEFERRED' : 'IMMEDIATE'}` : '',
    };
  });

  console.log(render(fks, missing));
  await client.end();
}

/** Le SQL produit, commenté par table, prêt à être commité tel quel. */
function render(fks, missing) {
  const L = [];
  L.push('-- ============================================================');
  L.push(passe2
    ? '-- 249_composite_fks_after.sql — ISO-02, seconde passe : les clés nées après la 237'
    : '-- 237_composite_foreign_keys.sql — ISO-02 : référencer chez le voisin');
  L.push('--');
  L.push('-- GÉNÉRÉ par scripts/generate-composite-fks.mjs — ne pas éditer à la main.');
  if (passe2) {
    L.push('--');
    L.push('-- POURQUOI UNE SECONDE PASSE. La 237 s\'exécute avant les migrations 240 à 248 :');
    L.push('-- les clés qu\'elles créent ne pouvaient pas figurer dans son relevé, et deux');
    L.push('-- d\'entre elles ont rouvert la porte — `goods_receipts_warehouse_id_fkey`');
    L.push('-- (créée par la 241 en même temps que sa colonne) et');
    L.push('-- `stock_movements_product_id_fkey` (recréée MONO-COLONNE par la 244, qui');
    L.push('-- change son `ON DELETE` pour préserver l\'historique : un correctif juste qui');
    L.push('-- défait, sans le savoir, la clé composite de la 237). Mesuré après la 237 sur');
    L.push('-- la chaîne complète : 408 clés composites, 2 mono-colonnes restantes.');
    L.push('-- Cette passe est générée sur l\'état FINAL, où son relevé ne trouve que celles-là.');
  }
  L.push(`-- Relevé du ${new Date().toISOString().slice(0, 10)} : ${fks.length} clé(s) mono-colonne(s)`);
  L.push(`-- reliant deux tables cloisonnées, sur ${new Set(fks.map((f) => f.child)).size} table(s)`);
  L.push(`-- enfant, et ${missing.size} contrainte(s) d'unicité à poser avant que la clé`);
  L.push('-- composite ne puisse exister (PostgreSQL exige que les colonnes référencées');
  L.push('-- portent une unicité).');
  L.push('--');
  L.push("-- LA FORME. La référence devient `(tenant_id, colonne)` : la société de l'enfant est");
  L.push('-- comparée à celle du parent, dans les DONNÉES. Un `UPDATE` de société ne peut plus');
  L.push('-- « emporter » la référence, et un `INSERT` inter-sociétés est refusé pour tout le');
  L.push('-- monde — `service_role` et déclencheurs `SECURITY DEFINER` compris, ce que la RLS ne');
  L.push("-- peut pas faire puisqu'elle ne les voit pas.");
  L.push('--');
  L.push('-- CE QUE LA MIGRATION NE FAIT PAS. Elle ne devine rien : si des lignes violent déjà la');
  L.push('-- clé, elle échoue et les nomme — jamais de `NOT VALID`, qui laisserait le défaut');
  L.push('-- derrière un nom de contrainte. Une ligne dont `tenant_id` est NULL (ligne système)');
  L.push('-- reste hors du contrôle : en `MATCH SIMPLE`, un NULL dispense de la vérification —');
  L.push("-- c'est voulu, ces lignes n'appartiennent à personne.");
  L.push('--');
  L.push('-- LES ACTIONS DE SUPPRESSION SONT RECOPIÉES, jamais réinventées, et avec leur');
  L.push('-- liste de colonnes : `ON DELETE SET NULL (colonne)` détache la seule colonne');
  L.push('-- concernée. Sans cette liste, une clé composite annulerait aussi `tenant_id` —');
  L.push('-- NOT NULL — et la suppression du parent échouerait au lieu de détacher.');
  L.push('-- ============================================================');
  L.push('');
  L.push('-- ── 1. Les unicité des parents : (tenant_id, colonne référencée) ──────────');
  L.push('');
  for (const m of missing.values()) {
    L.push(`DO $$ BEGIN`);
    L.push(`  IF NOT EXISTS (SELECT 1 FROM pg_constraint`);
    L.push(`                 WHERE conname = ${q(m.name)} AND conrelid = 'public.${m.parent}'::regclass) THEN`);
    L.push(`    ALTER TABLE public.${m.parent} ADD CONSTRAINT ${m.name} UNIQUE ("tenant_id", "${m.col}");`);
    L.push(`  END IF;`);
    L.push(`END $$;`);
  }
  L.push('');
  L.push('-- ── 2. Les clés étrangères composites ────────────────────────────────────');
  L.push('');
  let lastChild = null;
  for (const f of fks) {
    if (f.child !== lastChild) {
      L.push(`-- ${f.child}`);
      lastChild = f.child;
    }
    L.push(`ALTER TABLE public.${f.child} DROP CONSTRAINT IF EXISTS ${f.fk_name};`);
    L.push(`ALTER TABLE public.${f.child} ADD CONSTRAINT ${f.fk_name}`);
    L.push(`  FOREIGN KEY ("tenant_id", "${f.child_col}")`);
    L.push(`  REFERENCES public.${f.parent} (${f.refColsSql})${f.actions}${f.defer};`);
  }
  L.push('');
  L.push('-- ── 3. La preuve, dans la migration elle-même ────────────────────────────');
  L.push("-- Le contrôle permanent (`ci/check_composite_fks.sql`) relit ce relevé à chaque");
  L.push("-- exécution ; la migration, elle, refuse de passer s'il reste une clé. La mesure");
  L.push('-- emploie EXACTEMENT le filtre du générateur, schéma du parent compris :');
  L.push("-- `auth.users` n'est pas cloisonné — un même compte appartient légitimement à");
  L.push('-- plusieurs sociétés, une clé composite y serait fausse.');
  L.push('');
  L.push(...VERDICT);
  L.push('');
  return L.join('\n');
}


/**
 * Le verdict posé dans la migration : la même mesure que le contrôle permanent,
 * mais ici elle fait échouer la migration. Un correctif qui n'énonce pas sa
 * propriété ne la tient pas — la 236 l'a montré, dont la liste « des treize
 * fonctions » en cachait dix-huit.
 */
const VERDICT = [
  `DO $$`,
  `DECLARE v_reste text; v_n int;`,
  `BEGIN`,
  `  SELECT count(*), string_agg(cc.relname || '.' || a.attname || ' → ' || cp.relname, ', ' ORDER BY cc.relname)`,
  `    INTO v_n, v_reste`,
  `  FROM pg_constraint f`,
  `  JOIN pg_class cc     ON cc.oid = f.conrelid`,
  `  JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'`,
  `  JOIN pg_class cp     ON cp.oid = f.confrelid`,
  `  JOIN pg_namespace np ON np.oid = cp.relnamespace AND np.nspname = 'public'`,
  `  JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]`,
  `  WHERE f.contype = 'f' AND array_length(f.conkey, 1) = 1 AND a.attname <> 'tenant_id'`,
  `    AND EXISTS (SELECT 1 FROM information_schema.columns x`,
  `                WHERE x.table_schema = 'public' AND x.table_name = cc.relname AND x.column_name = 'tenant_id')`,
  `    AND EXISTS (SELECT 1 FROM information_schema.columns y`,
  `                WHERE y.table_schema = 'public' AND y.table_name = cp.relname AND y.column_name = 'tenant_id');`,
  `  IF v_n > 0 THEN`,
  `    RAISE EXCEPTION '[ISO-02] % clé(s) étrangère(s) mono-colonne(s) relient encore deux tables cloisonnées : %', v_n, v_reste;`,
  `  END IF;`,
  `  RAISE NOTICE '[ISO-02] aucune clé étrangère mono-colonne entre deux tables cloisonnées.';`,
  `END $$;`,
];

main().catch(async (err) => {
  console.error('❌', err.message);
  await client.end().catch(() => {});
  process.exit(1);
});

