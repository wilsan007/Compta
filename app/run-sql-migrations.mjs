import pg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sqlDir = path.join(__dirname, 'sql');

// SEC-01: Never hardcode credentials. Read from DATABASE_URL or individual env vars.
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl && !process.env.PGHOST) {
  console.error('❌ ERREUR DE SÉCURITÉ: Aucune connexion configurée.');
  console.error('   Définissez DATABASE_URL ou PGHOST/PGUSER/PGPASSWORD/PGDATABASE dans votre environnement.');
  console.error('   Exemple: export DATABASE_URL="postgresql://user:pass@host:port/db"');
  process.exit(1);
}

// Détecter si on est en local (localhost/127.0.0.1) pour désactiver SSL
const isLocal = databaseUrl
  ? /localhost|127\.0\.0\.1/.test(databaseUrl)
  : /localhost|127\.0\.0\.1/.test(process.env.PGHOST || '');

// Base distante : certificat toujours vérifié. Le CA Supabase n'est pas dans le magasin
// système — le fournir via PGSSLROOTCERT (ex. prod-ca-2021.crt, Database → Settings → SSL).
const caPath = process.env.PGSSLROOTCERT;
const sslConfig = isLocal
  ? false
  : { rejectUnauthorized: true, ...(caPath ? { ca: fs.readFileSync(caPath, 'utf8') } : {}) };

const client = new pg.Client(
  databaseUrl
    ? { connectionString: databaseUrl, ssl: sslConfig }
    : {
        host: process.env.PGHOST,
        port: Number(process.env.PGPORT || 5432),
        user: process.env.PGUSER,
        password: process.env.PGPASSWORD,
        database: process.env.PGDATABASE,
        ssl: sslConfig,
      }
);

async function main() {
  
  try {
    console.log('🔗 Connexion à la base de données...');
    await client.connect();
    console.log('✅ Connecté!\n');

    // Check if migration tracking table exists
    const { rows: tableCheck } = await client.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_name = 'sql_migrations_tracker'
      );
    `);

    if (!tableCheck[0].exists) {
      console.log('📋 Création de la table de tracking des migrations...');
      await client.query(`
        CREATE TABLE IF NOT EXISTS sql_migrations_tracker (
          id SERIAL PRIMARY KEY,
          filename TEXT UNIQUE NOT NULL,
          executed_at TIMESTAMPTZ DEFAULT NOW(),
          status TEXT DEFAULT 'success',
          error_message TEXT
        );
      `);
      console.log('✅ Table sql_migrations_tracker créée\n');
    }

    // Get already executed migrations
    const { rows: executed } = await client.query(`
      SELECT filename, status, error_message, executed_at 
      FROM sql_migrations_tracker 
      ORDER BY filename;
    `);
    
    const executedMap = new Map(executed.map(r => [r.filename, r]));

    // DB-01: Inclure les fichiers de fondation non numérotés (multi_tenant_migration.sql,
    // legislation_packs_migration.sql, audit_schema.sql) en les exécutant en premier.
    // Ordre: fondations → migrations numérotées.
    const foundationFiles = [
      'multi_tenant_migration.sql',
      'legislation_packs_migration.sql',
      'audit_schema.sql',
    ].filter(f => fs.existsSync(path.join(sqlDir, f)));

    // 00_schema_dump.sql est l'instantané de base, chargé à part (psql) avant ce script :
    // le rejouer comme migration échoue (clés primaires en double).
    // Les fichiers *_tests.sql sont des tests d'intégration exécutés par la CI, jamais
    // des migrations : ils insèrent et suppriment des données de test.
    const numberedFiles = fs.readdirSync(sqlDir)
      .filter(f => /^\d{2,3}_.*\.sql$/.test(f) && f !== '00_schema_dump.sql' && !/_tests\.sql$/.test(f))
      .sort((a, b) => {
        const numA = parseInt(a.match(/^(\d+)/)?.[1] || '0', 10);
        const numB = parseInt(b.match(/^(\d+)/)?.[1] || '0', 10);
        return numA - numB || a.localeCompare(b);
      });

    // SOC-06: Détecter les doublons de numéros et ÉCHOUER (au lieu d'avertir)
    const numMap = new Map();
    for (const f of numberedFiles) {
      const num = f.match(/^(\d+)/)?.[1] || f.substring(0, 2);
      if (!numMap.has(num)) numMap.set(num, []);
      numMap.get(num).push(f);
    }
    let hasDuplicates = false;
    for (const [num, files] of numMap) {
      if (files.length > 1) {
        console.error(`❌ DOUBLON: migration ${num} existe ${files.length} fois: ${files.join(', ')}`);
        hasDuplicates = true;
      }
    }
    if (hasDuplicates) {
      console.error('\n❌ Des numéros de migration sont en doublon. Renumérotez-les avant de continuer.');
      process.exit(1);
    }

    const allFiles = [...foundationFiles, ...numberedFiles];

    console.log(`📂 ${allFiles.length} fichiers SQL trouvés dans /sql\n`);
    console.log('━'.repeat(80));

    // Show status of each file
    let toExecute = [];
    let alreadyDone = 0;
    let failed = [];

    for (const file of allFiles) {
      const record = executedMap.get(file);
      if (!record) {
        toExecute.push(file);
        console.log(`⬜ [À EXÉCUTER] ${file}`);
      } else if (record.status === 'success') {
        alreadyDone++;
        console.log(`✅ [DÉJÀ FAIT]  ${file}`);
      } else {
        failed.push(file);
        toExecute.push(file);
        console.log(`❌ [ÉCHOUÉ]     ${file} — ${record.error_message || 'erreur inconnue'}`);
      }
    }

    console.log('━'.repeat(80));
    console.log(`\n📊 Résumé: ${alreadyDone} déjà exécutés, ${toExecute.length} à exécuter, ${failed.length} échoués précédemment\n`);

    if (toExecute.length === 0) {
      console.log('🎉 Tous les fichiers SQL ont déjà été exécutés!');
      return;
    }

    // Execute pending migrations
    console.log(`🚀 Exécution de ${toExecute.length} migration(s)...\n`);
    let success = 0;
    let errors = 0;

    for (const file of toExecute) {
      const filePath = path.join(sqlDir, file);
      const sql = fs.readFileSync(filePath, 'utf8');
      
      console.log(`\n▶ Exécution de ${file}...`);
      
      try {
        // Execute each statement separately for better error tracking
        await client.query('BEGIN');
        
        // Use simple query execution - split on semicolons is unreliable, 
        // so we execute the whole file as one query
        await client.query(sql);
        
        await client.query('COMMIT');
        
        // Record success
        await client.query(`
          INSERT INTO sql_migrations_tracker (filename, status) 
          VALUES ($1, 'success')
          ON CONFLICT (filename) 
          DO UPDATE SET status = 'success', error_message = NULL, executed_at = NOW();
        `, [file]);
        
        success++;
        console.log(`  ✅ Succès`);
      } catch (err) {
        await client.query('ROLLBACK');
        
        // Record failure
        await client.query(`
          INSERT INTO sql_migrations_tracker (filename, status, error_message) 
          VALUES ($1, 'failed', $2)
          ON CONFLICT (filename) 
          DO UPDATE SET status = 'failed', error_message = $2, executed_at = NOW();
        `, [file, err.message.substring(0, 500)]);
        
        errors++;
        console.log(`  ❌ Erreur: ${err.message.substring(0, 200)}`);
        // DB-01: Arrêter à la première erreur — les migrations suivantes
        // s'appuient sur le schéma créé par les précédentes.
        console.log(`\n⛔ ARRÊT: une migration a échoué. Corrigez-la avant de continuer.`);
        break;
      }
    }

    console.log('\n' + '═'.repeat(80));
    console.log(`\n📊 RÉSULTAT FINAL: ${success} succès, ${errors} erreurs sur ${toExecute.length} migrations`);
    
    if (errors > 0) {
      console.log('\n⚠️  Certaines migrations ont échoué. Vérifiez les erreurs ci-dessus.');
      // LOT0-03 : sans code de sortie non nul, la CI passait au vert malgré l'échec
      process.exitCode = 1;
    }

  } catch (err) {
    console.error('❌ Erreur de connexion:', err.message);
    process.exit(1);
  } finally {
    await client.end();
    console.log('\n🔌 Déconnecté.');
  }
}

main();
