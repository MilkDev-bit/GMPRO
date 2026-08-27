import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

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

export default defineConfig(({ command }) => ({
  plugins: [react(), ...(command === 'build' ? [cspMetaPlugin()] : [])],
  server: { port: 5173 },
}));
