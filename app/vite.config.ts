import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { visualizer } from 'rollup-plugin-visualizer'
import path from 'path'

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    ...(process.env.ANALYZE ? [visualizer({ filename: 'dist/stats.html', template: 'treemap', gzipSize: true, brotliSize: false })] : []),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    hmr: {
      overlay: false,
      host: 'localhost',
    },
  },
  build: {
    // SECURITY: No source maps in production — prevents code reverse-engineering
    sourcemap: false,
    // SECURITY: Modern target — older browsers are more vulnerable
    target: 'es2020',
    // SECURITY: Chunk size warning limit (large chunks are easier to analyze)
    chunkSizeWarningLimit: 500,
    rollupOptions: {
      output: {
        // SECURITY: Split chunks to prevent easy code analysis
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (id.includes('react') || id.includes('react-dom') || id.includes('react-router')) return 'react-vendor'
            if (id.includes('@supabase')) return 'supabase'
            if (id.includes('i18next')) return 'i18n'
            if (id.includes('pdfjs')) return 'pdf'
            if (id.includes('xlsx')) return 'xlsx'
            if (id.includes('recharts') || id.includes('d3-')) return 'charts'
            if (id.includes('date-fns')) return 'date-fns'
            if (id.includes('lucide-react')) return 'icons'
            if (id.includes('zustand')) return 'zustand'
            if (id.includes('@radix-ui')) return 'radix'
            if (id.includes('framer-motion')) return 'animation'
            if (id.includes('clsx') || id.includes('tailwind-merge')) return 'utils'
            if (id.includes('zod')) return 'validation'
            if (id.includes('decimal.js') || id.includes('big.js')) return 'math'
          }
        },
      },
    },
    // SECURITY: Minify with oxc — Vite 8's built-in minifier
    minify: 'oxc',
  },
})
