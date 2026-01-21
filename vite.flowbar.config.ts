import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  root: resolve(__dirname, 'src/renderer'),
  base: './',
  build: {
    outDir: resolve(__dirname, 'out/renderer'),
    emptyOutDir: false,
    rollupOptions: {
      input: resolve(__dirname, 'src/renderer/flowBar.html'),
      output: {
        entryFileNames: 'assets/flowbar-[hash].js',
        chunkFileNames: 'assets/flowbar-[hash].js',
        assetFileNames: 'assets/flowbar-[hash].[ext]'
      }
    }
  },
  resolve: {
    alias: {
      '@shared': resolve(__dirname, 'src/shared')
    }
  }
})
