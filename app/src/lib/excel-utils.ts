// PRF-02 : xlsx chargé dynamiquement pour réduire le bundle initial

export async function exportToExcel(data: any[], filename: string, sheetName = 'Sheet1') {
  const XLSX = await import('xlsx')
  const ws = XLSX.utils.json_to_sheet(data)
  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, sheetName)
  XLSX.writeFile(wb, filename)
}

export async function importFromExcel(file: File): Promise<any[]> {
  const XLSX = await import('xlsx')
  const buf = await file.arrayBuffer()
  const wb = XLSX.read(buf)
  const ws = wb.Sheets[wb.SheetNames[0]]
  return XLSX.utils.sheet_to_json(ws)
}
