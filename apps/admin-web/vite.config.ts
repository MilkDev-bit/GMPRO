import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Dev server en :5173. Las URLs del backend se leen de VITE_* (ver src/lib/config.ts).
export default defineConfig({
  plugins: [react()],
  server: { port: 5173 },
});
