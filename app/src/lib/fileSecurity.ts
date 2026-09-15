// File upload security utility
// Validates file type, size, magic bytes, and sanitizes filenames
// to prevent malicious file uploads (malware, polyglot files, path traversal via filename)

export interface FileValidationOptions {
  /** Maximum file size in bytes (default: 10 MB) */
  maxSize?: number
  /** Allowed MIME types (e.g. ['text/csv', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']) */
  allowedMimeTypes?: readonly string[]
  /** Allowed file extensions (e.g. ['.csv', '.xlsx', '.txt']) */
  allowedExtensions?: readonly string[]
  /** Whether to check magic bytes (default: true) */
  checkMagicBytes?: boolean
}

export interface FileValidationResult {
  ok: boolean
  error?: string
  sanitizedFilename?: string
}

// Magic bytes signatures for common file types
const MAGIC_BYTES: Record<string, number[] | null> = {
  pdf: [0x25, 0x50, 0x44, 0x46], // %PDF
  xlsx: [0x50, 0x4B, 0x03, 0x04], // PK (ZIP-based, also matches .docx, .xlsx)
  xls: [0xD0, 0xCF, 0x11, 0xE0], // OLE2 compound document
  csv: null, // Text-based, no magic bytes
  txt: null, // Text-based, no magic bytes
}

/**
 * Validate an uploaded file for security.
 * Checks: file size, MIME type, extension, magic bytes, filename sanitization.
 */
export async function validateFileUpload(
  file: File,
  options: FileValidationOptions = {},
): Promise<FileValidationResult> {
  const {
    maxSize = 10 * 1024 * 1024, // 10 MB default
    allowedMimeTypes,
    allowedExtensions,
    checkMagicBytes = true,
  } = options

  // 1. Check file size
  if (file.size > maxSize) {
    const maxMB = (maxSize / (1024 * 1024)).toFixed(1)
    return { ok: false, error: `File too large (max ${maxMB} MB)` }
  }

  if (file.size === 0) {
    return { ok: false, error: 'File is empty' }
  }

  // 2. Check file extension
  const ext = file.name.toLowerCase().match(/\.[^.]+$/)?.[0] || ''
  if (allowedExtensions && allowedExtensions.length > 0) {
    if (!allowedExtensions.includes(ext)) {
      return { ok: false, error: `File type not allowed. Accepted: ${allowedExtensions.join(', ')}` }
    }
  }

  // 3. Check MIME type
  if (allowedMimeTypes && allowedMimeTypes.length > 0) {
    if (!allowedMimeTypes.includes(file.type) && file.type !== 'application/octet-stream') {
      return { ok: false, error: `MIME type not allowed: ${file.type}` }
    }
  }

  // 4. Check magic bytes (first 4-8 bytes of the file)
  if (checkMagicBytes && file.size >= 4) {
    const buffer = await file.slice(0, 8).arrayBuffer()
    const bytes = new Uint8Array(buffer)

    // Check for executable files (should never be uploaded)
    const exeMagic = [0x4D, 0x5A] // MZ (Windows PE)
    const elfMagic = [0x7F, 0x45, 0x4C, 0x46] // ELF (Linux)
    const machoMagic = [0xCF, 0xFA, 0xED, 0xFE] // Mach-O (macOS)

    if (bytesStartsWith(bytes, exeMagic) || bytesStartsWith(bytes, elfMagic) || bytesStartsWith(bytes, machoMagic)) {
      return { ok: false, error: 'Executable files are not allowed' }
    }

    // Check for script files with shebang
    if (bytes[0] === 0x23 && bytes[1] === 0x21) { // #!
      return { ok: false, error: 'Script files are not allowed' }
    }

    // Verify magic bytes match the claimed extension
    if (ext === '.pdf' && MAGIC_BYTES.pdf && !bytesStartsWith(bytes, MAGIC_BYTES.pdf)) {
      return { ok: false, error: 'File claims to be PDF but magic bytes do not match' }
    }
    if (ext === '.xlsx' && MAGIC_BYTES.xlsx && !bytesStartsWith(bytes, MAGIC_BYTES.xlsx)) {
      return { ok: false, error: 'File claims to be XLSX but magic bytes do not match' }
    }
  }

  // 5. Sanitize filename
  const sanitizedFilename = sanitizeFilename(file.name)

  return { ok: true, sanitizedFilename }
}

/**
 * Sanitize a filename to prevent path traversal and XSS via filename.
 * - Removes path separators (/ \ ..)
 * - Removes null bytes
 * - Limits length to 255 characters
 * - Removes control characters
 */
export function sanitizeFilename(filename: string): string {
  // Remove path components — keep only the basename
  let name = filename.replace(/.*[/\\]/, '')
  // Remove directory traversal
  name = name.replace(/\.\./g, '')
  // Remove null bytes and control characters
  name = Array.from(name).filter(c => { const code = c.charCodeAt(0); return code > 0x1f && code !== 0x7f }).join('')
  // Limit length
  if (name.length > 255) {
    const ext = name.match(/\.[^.]+$/)?.[0] || ''
    name = name.slice(0, 255 - ext.length) + ext
  }
  // If empty after sanitization, provide a default
  if (!name) name = 'unnamed_file'
  return name
}

/**
 * Check if a Uint8Array starts with the given magic bytes.
 */
function bytesStartsWith(bytes: Uint8Array, magic: number[]): boolean {
  if (bytes.length < magic.length) return false
  return magic.every((byte, i) => bytes[i] === byte)
}

/**
 * Pre-configured validation profiles for common upload scenarios.
 */
export const FILE_PROFILES = {
  /** CSV/Excel import files */
  spreadsheet: {
    maxSize: 10 * 1024 * 1024, // 10 MB
    allowedExtensions: ['.csv', '.xlsx', '.xls', '.txt'],
    allowedMimeTypes: [
      'text/csv',
      'text/plain',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/octet-stream',
    ],
    checkMagicBytes: true,
  },
  /** PDF bank statements */
  pdf: {
    maxSize: 5 * 1024 * 1024, // 5 MB
    allowedExtensions: ['.pdf'],
    allowedMimeTypes: ['application/pdf', 'application/octet-stream'],
    checkMagicBytes: true,
  },
  /** Sage/MAE accounting files */
  sage: {
    maxSize: 10 * 1024 * 1024, // 10 MB
    allowedExtensions: ['.txt', '.csv', '.mae'],
    allowedMimeTypes: ['text/plain', 'text/csv', 'application/octet-stream'],
    checkMagicBytes: false, // .mae is a proprietary binary format
  },
} as const
