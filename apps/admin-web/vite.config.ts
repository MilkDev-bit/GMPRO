import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// A08-2: Content-Security-Policy restrictiva inyectada SOLO en el build de
// producción (no en dev, donde el HMR de Vite necesita inline/eval/ws y una CSP
// estricta lo rompería). El header definitivo debería fijarlo TAMBIÉN el host
// estático (Railway/CDN) como cabecera HTTP; este <meta> es defensa en profundidad
// embebida en el HTML servido.
//
// Notas de política:
//   • script-src 'self'         → el bundle de Vite son módulos ES externos (sin inline).
//   • style-src 'unsafe-inline' → Recharts/estilos inyectados usan <style>/style="".
//   • connect-src …railway.app  → los microservicios backend (fetch). Ajustar si se
//                                 migra a dominio propio.
//   • font-src 'self'           → Inter self-hosted (@fontsource), sin CDN.
const CSP = [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "frame-src 'none'",
  "img-src 'self' data:",
  "font-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "script-src 'self'",
  "connect-src 'self' https://*.up.railway.app",
  "form-action 'self'",
].join('; ');

function cspMetaPlugin() {
  return {
    name: 'inject-csp-meta',
    transformIndexHtml(html: string) {
      const tag = `<meta http-equiv="Content-Security-Policy" content="${CSP}" />`;
      return html.replace('</title>', `</title>\n    ${tag}`);
    },
  };
}

// Dev server en :5173. Las URLs del backend se leen de VITE_* (ver src/lib/config.ts).
export default defineConfig(({ command }) => ({
  plugins: [react(), ...(command === 'build' ? [cspMetaPlugin()] : [])],
  server: { port: 5173 },
}));
