import { readFileSync, writeFileSync, readdirSync } from 'fs'
import { join } from 'path'

const pagesDir = join(process.cwd(), 'src', 'pages')
const files = readdirSync(pagesDir).filter(f => f.endsWith('.tsx'))

let totalFixed = 0
let totalRemoved = 0

for (const file of files) {
  const filepath = join(pagesDir, file)
  const lines = readFileSync(filepath, 'utf-8').split('\n')
  
  const toastLines = []
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes('const { toast } = useToast()')) {
      toastLines.push(i)
    }
  }
  
  if (toastLines.length <= 1) continue
  
  const linesToRemove = []
  
  for (const lineIdx of toastLines) {
    let prevIdx = lineIdx - 1
    while (prevIdx >= 0 && lines[prevIdx].trim() === '') {
      prevIdx--
    }
    
    if (prevIdx < 0) continue
    
    const prevLine = lines[prevIdx]
    const prevTrimmed = prevLine.trim()
    
    const isFuncDecl = /^(export\s+)?(async\s+)?function\s+\w+.*\{$/.test(prevTrimmed)
    
    if (!isFuncDecl) {
      linesToRemove.push(lineIdx)
      continue
    }
    
    // Function declaration is indented -> nested function -> invalid
    const hasLeadingWhitespace = /^\s/.test(prevLine)
    if (hasLeadingWhitespace) {
      linesToRemove.push(lineIdx)
    }
  }
  
  if (linesToRemove.length === 0) continue
  
  const removed = linesToRemove.length
  for (const lineIdx of linesToRemove.reverse()) {
    let removeCount = 1
    if (lineIdx > 0 && lines[lineIdx - 1].trim() === '') {
      const beforeBlank = lineIdx > 1 ? lines[lineIdx - 2] : null
      if (beforeBlank && (beforeBlank.trim() === '' || beforeBlank.trim().endsWith('{'))) {
        removeCount = 2
      }
    }
    lines.splice(lineIdx - (removeCount - 1), removeCount)
  }
  
  writeFileSync(filepath, lines.join('\n'))
  totalFixed++
  totalRemoved += removed
  console.log(`Fixed ${file}: removed ${removed} duplicate useToast() call(s)`)
}

console.log(`\nTotal: ${totalFixed} files fixed, ${totalRemoved} duplicate calls removed`)
