import { readFileSync, writeFileSync, readdirSync } from 'fs'
import { join } from 'path'

const pagesDir = join(process.cwd(), 'src', 'pages')
const files = readdirSync(pagesDir).filter(f => f.endsWith('.tsx'))

let totalFixed = 0

for (const file of files) {
  const filepath = join(pagesDir, file)
  let content = readFileSync(filepath, 'utf-8')
  let lines = content.split('\n')
  let modified = false
  
  // Find all function component definitions (top-level, starting at column 0)
  // A component function starts with `function Name(` or `export function Name(`
  const components = []
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (/^(export\s+)?(async\s+)?function\s+[A-Z]\w*\s*\(/.test(line)) {
      components.push({ name: line.match(/function\s+(\w+)/)[1], lineIdx: i })
    }
  }
  
  if (components.length === 0) continue
  
  for (const comp of components) {
    // Find the end of this component (next top-level function or end of file)
    const compEnd = components.find(c => c.lineIdx > comp.lineIdx)?.lineIdx ?? lines.length
    
    // Check if this component has useToast() already
    let hasUseToast = false
    for (let i = comp.lineIdx; i < compEnd; i++) {
      if (lines[i].includes('const { toast } = useToast()')) {
        hasUseToast = true
        break
      }
    }
    
    // Check if this component uses `toast(` 
    let usesToast = false
    for (let i = comp.lineIdx; i < compEnd; i++) {
      if (/\btoast\s*\(/.test(lines[i]) && !lines[i].includes('const { toast } = useToast()')) {
        usesToast = true
        break
      }
    }
    
    if (usesToast && !hasUseToast) {
      // Need to add `const { toast } = useToast()` to this component
      // Find the first line after the function opening brace
      let insertIdx = comp.lineIdx
      // Find the opening brace
      while (insertIdx < compEnd && !lines[insertIdx].includes('{')) {
        insertIdx++
      }
      insertIdx++ // Move past the opening brace line
      
      // Find a good insertion point (after first useState or at the start)
      let firstUseState = -1
      for (let i = insertIdx; i < compEnd; i++) {
        if (lines[i].includes('useState')) {
          firstUseState = i
          break
        }
      }
      
      if (firstUseState >= 0) {
        // Insert after the first useState line (or its continuation)
        insertIdx = firstUseState + 1
      }
      
      // Check if useToast is imported
      const hasImport = content.includes("import { useToast } from '@/lib/toast'") || 
                        content.includes('import { useToast } from "@/lib/toast"')
      
      if (!hasImport) {
        // Add import at the top (after last import line)
        let lastImport = -1
        for (let i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('import ')) {
            lastImport = i
          }
        }
        lines.splice(lastImport + 1, 0, "import { useToast } from '@/lib/toast'")
        modified = true
        // Adjust component positions
        comp.lineIdx++
      }
      
      // Re-find compEnd after potential import insertion
      const newCompEnd = components.find(c => c.lineIdx > comp.lineIdx)?.lineIdx ?? lines.length
      
      // Re-find insert position
      insertIdx = comp.lineIdx
      while (insertIdx < newCompEnd && !lines[insertIdx].includes('{')) {
        insertIdx++
      }
      insertIdx++
      
      firstUseState = -1
      for (let i = insertIdx; i < newCompEnd; i++) {
        if (lines[i].includes('useState')) {
          firstUseState = i
          break
        }
      }
      if (firstUseState >= 0) {
        insertIdx = firstUseState + 1
      }
      
      // Get indentation from the line above
      const indentMatch = lines[insertIdx - 1]?.match(/^(\s*)/)
      const indent = indentMatch ? indentMatch[1] : '  '
      
      lines.splice(insertIdx, 0, `${indent}const { toast } = useToast()`)
      modified = true
      console.log(`  ${file}: added useToast() to ${comp.name}`)
    }
    
    if (!usesToast && hasUseToast) {
      // Remove unused toast declaration
      for (let i = comp.lineIdx; i < compEnd; i++) {
        if (lines[i].includes('const { toast } = useToast()')) {
          // Check if toast is truly unused in this component
          let used = false
          for (let j = comp.lineIdx; j < compEnd; j++) {
            if (j !== i && /\btoast\s*\(/.test(lines[j])) {
              used = true
              break
            }
          }
          if (!used) {
            lines.splice(i, 1)
            modified = true
            console.log(`  ${file}: removed unused toast from ${comp.name}`)
          }
          break
        }
      }
    }
  }
  
  // Check for unused useToast import
  if (modified) {
    content = lines.join('\n')
    // Check if useToast is still used anywhere
    if (!content.includes('useToast()')) {
      // Remove the import
      content = content.replace(/import \{ useToast \} from ['"]@\/lib\/toast['"]\n?/, '')
      lines = content.split('\n')
      console.log(`  ${file}: removed unused useToast import`)
    }
  }
  
  if (modified) {
    writeFileSync(filepath, lines.join('\n'))
    totalFixed++
  }
}

console.log(`\nTotal: ${totalFixed} files fixed`)
