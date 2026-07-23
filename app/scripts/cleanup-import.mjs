import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://ndtaedcgwnaopopugiql.supabase.co'
const supabaseKey = 'sb_publishable_6WZDE3wBMwc5ildtfy19Nw_pxdPnAZK'
const supabase = createClient(supabaseUrl, supabaseKey)

async function cleanup() {
  // 1. Delete journal_lines for entries with numbers matching rest111.txt pattern
  const { data: entries, error: entryErr } = await supabase
    .from('journal_entries')
    .select('id, number, journal_code')
    .or('number.like.ACH%,number.like.BQ3%,number.like.CAIS%,number.like.JSA%')
  
  if (entryErr) {
    console.error('Error fetching entries:', entryErr.message)
    return
  }

  console.log(`Found ${entries?.length || 0} entries to delete`)
  
  if (entries && entries.length > 0) {
    const entryIds = entries.map(e => e.id)
    
    // Delete journal_lines first (foreign key)
    const { error: linesErr } = await supabase
      .from('journal_lines')
      .delete()
      .in('journal_id', entryIds)
    
    if (linesErr) console.error('Error deleting lines:', linesErr.message)
    else console.log(`Deleted journal_lines for ${entryIds.length} entries`)
    
    // Delete journal_entries
    const { error: jeErr } = await supabase
      .from('journal_entries')
      .delete()
      .in('id', entryIds)
    
    if (jeErr) console.error('Error deleting entries:', jeErr.message)
    else console.log(`Deleted ${entryIds.length} journal_entries`)
  }

  // 2. Delete third_party_accounts with codes starting with 4010xx
  const { data: deletedTiers, error: tiersErr } = await supabase
    .from('third_party_accounts')
    .delete()
    .like('code', '4010%')
    .select('code')
  
  if (tiersErr) console.error('Error deleting tiers:', tiersErr.message)
  else console.log(`Deleted ${deletedTiers?.length || 0} third_party_accounts`)

  // 3. Delete chart_accounts that were imported (codes from rest111.txt)
  const codes = [
    '401000', '421000', '425000', '431000', '442000', '443000',
    '512120', '531100', '580000',
    '602100', '604000', '605000', '605100', '606100', '606310',
    '608520', '615400', '615510', '623000', '624100', '625000',
    '625200', '627000', '628000', '641100', '641300', '645100',
  ]
  
  const { data: deletedAccounts, error: accErr } = await supabase
    .from('chart_accounts')
    .delete()
    .in('code', codes)
    .select('code')
  
  if (accErr) console.error('Error deleting accounts:', accErr.message)
  else console.log(`Deleted ${deletedAccounts?.length || 0} chart_accounts`)

  console.log('\nCleanup complete! You can now reimport rest111.txt')
}

cleanup().catch(console.error)
