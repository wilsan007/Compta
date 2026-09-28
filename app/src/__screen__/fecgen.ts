function escapeFECField(value: any): string {
  if (value === null || value === undefined) return ''
  return String(value).replace(/"/g, '""')
}

export function generateFECText(entries: any[]): string {
  const lines: string[] = []
  const header = [
    'JournalCode', 'JournalLib', 'EcritureNum', 'EcritureDate', 'CompteNum',
    'CompteLib', 'CompAuxNum', 'CompAuxLib', 'PieceRef', 'PieceDate',
    'EcritureLib', 'Debit', 'Credit', 'EcritureLet', 'DateLet',
    'ValidDate', 'Montantdevise', 'Idevise',
  ]
  lines.push(header.join('|'))

  for (const entry of entries) {
    const je = entry
    for (const line of je.journal_lines || []) {
      const row = [
        escapeFECField(je.journal_code),
        escapeFECField('Journal'),
        // AUD-C11 : EcritureNum = numéro définitif, continu par journal et par exercice
        escapeFECField(je.posting_number || je.number),
        escapeFECField(je.date?.replace(/-/g, '')),
        escapeFECField(line.account_general || line.account_code),
        escapeFECField(line.account_name || ''),
        escapeFECField(line.account_tiers || ''),
        escapeFECField(''),
        escapeFECField(je.piece_number || je.number),
        escapeFECField(je.date?.replace(/-/g, '')),
        escapeFECField(line.description || je.description),
        escapeFECField(Number(line.debit).toFixed(2)),
        escapeFECField(Number(line.credit).toFixed(2)),
        escapeFECField(line.lettrage_code || ''),
        escapeFECField(''),
        escapeFECField((je.validated_at || je.date)?.slice(0, 10).replace(/-/g, '')),
        '',
        '',
      ]
      lines.push(row.join('|'))
    }
  }

  return lines.join('\n')
}

