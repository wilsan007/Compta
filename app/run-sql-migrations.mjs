import pg from 'pg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sqlDir = path.join(__dirname, 'sql');

const client = new pg.Client({
  host: 'aws-1-eu-west-2.pooler.supabase.com',
  port: 6543,
  user: 'postgres.ndtaedcgwnaopopugiql',
  password: 'Aod@@1002@@',
  database: 'postgres',
  ssl: { rejectUnauthorized: false }
});

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

    // Get only numbered SQL files (01_xxx.sql through 66_xxx.sql)
    const allFiles = fs.readdirSync(sqlDir)
      .filter(f => /^\d{2}_.*\.sql$/.test(f))
      .sort();

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
      }
    }

    console.log('\n' + '═'.repeat(80));
    console.log(`\n📊 RÉSULTAT FINAL: ${success} succès, ${errors} erreurs sur ${toExecute.length} migrations`);
    
    if (errors > 0) {
      console.log('\n⚠️  Certaines migrations ont échoué. Vérifiez les erreurs ci-dessus.');
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
