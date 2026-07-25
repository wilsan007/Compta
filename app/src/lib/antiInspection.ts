// Anti-debugging / Anti-devtools detection utility
// Makes it harder for attackers to inspect the running application
// NOTE: These are deterrents, not absolute protections. Determined attackers can bypass them.

let devtoolsOpen = false
let intervalId: ReturnType<typeof setInterval> | null = null

/**
 * Detect if browser DevTools are open using multiple techniques.
 * Returns true if devtools are likely open.
 */
function detectDevTools(): boolean {
  // Technique 1: Window size threshold (devtools docked reduces visible area)
  const threshold = 200
  const widthDiff = window.outerWidth - window.innerWidth
  const heightDiff = window.outerHeight - window.innerHeight
  if (widthDiff > threshold || heightDiff > threshold) return true

  // Technique 2: Timing-based detection (debugger statement pauses execution)
  // This is handled separately by startDebuggerTrap()

  // Technique 3: Console output detection (only works in some browsers)
  // Creating a large object and checking if it was expanded in console
  return false
}

/**
 * Start a periodic check for devtools.
 * When detected, optionally clear console and show a warning.
 */
export function startDevToolsDetection(onDetect?: () => void): void {
  if (intervalId) return // Already running

  intervalId = setInterval(() => {
    const wasOpen = devtoolsOpen
    devtoolsOpen = detectDevTools()
    if (devtoolsOpen && !wasOpen) {
      // DevTools just opened
      if (onDetect) {
        onDetect()
      } else {
        // Default action: clear console to prevent inspection
        console.clear()
        console.warn('⚠️ Inspection du code détectée. Cette action est enregistrée.')
      }
    }
  }, 1000)
}

/**
 * Stop devtools detection.
 */
export function stopDevToolsDetection(): void {
  if (intervalId) {
    clearInterval(intervalId)
    intervalId = null
  }
}

/**
 * Set up a debugger trap that periodically triggers a debugger statement.
 * When devtools are open, this pauses execution and makes debugging harder.
 * When devtools are closed, the debugger statement is a no-op.
 */
export function startDebuggerTrap(): void {
  setInterval(() => {
    const start = performance.now()
    // eslint-disable-next-line no-debugger
    debugger
    const end = performance.now()
    // If debugger paused execution for > 100ms, devtools are likely open
    if (end - start > 100) {
      console.clear()
    }
  }, 5000)
}

/**
 * Disable right-click context menu (prevents "View Source" and "Inspect Element").
 * This is a deterrent, not a strong protection.
 */
export function disableContextMenu(): void {
  document.addEventListener('contextmenu', (e) => {
    e.preventDefault()
    return false
  })
}

/**
 * Disable common keyboard shortcuts for devtools and view source.
 * Ctrl+Shift+I, Ctrl+Shift+J, Ctrl+Shift+C, Ctrl+U, F12
 */
export function disableDevToolsShortcuts(): void {
  document.addEventListener('keydown', (e) => {
    // F12
    if (e.key === 'F12') {
      e.preventDefault()
      return false
    }
    // Ctrl+Shift+I / Ctrl+Shift+J / Ctrl+Shift+C (Chrome/Firefox devtools)
    if (e.ctrlKey && e.shiftKey && ['I', 'J', 'C'].includes(e.key.toUpperCase())) {
      e.preventDefault()
      return false
    }
    // Ctrl+U (View Source)
    if (e.ctrlKey && e.key.toUpperCase() === 'U') {
      e.preventDefault()
      return false
    }
    // Cmd+Opt+I / Cmd+Opt+J / Cmd+Opt+C (Safari/Chrome on Mac)
    if (e.metaKey && e.altKey && ['I', 'J', 'C'].includes(e.key.toUpperCase())) {
      e.preventDefault()
      return false
    }
  })
}

/**
 * Initialize all anti-inspection protections.
 * Call this once in main.tsx after the app mounts.
 */
export function initAntiInspection(): void {
  // Only activate in production
  if (import.meta.env.DEV) return

  startDevToolsDetection()
  disableContextMenu()
  disableDevToolsShortcuts()
}
