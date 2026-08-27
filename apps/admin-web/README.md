# GymPro · Panel de Administración

Stack: **React 18 + Vite + TypeScript + TailwindCSS + React Router**.
Cliente web para staff/admin

## Arranque
```bash
cd apps/admin-web
cp .env.example .env      
npm install
npm run dev               
npm run build            
```

Piezas reutilizables:
- `components/ui/` → `Card`/`CardHeader`, `KPIStat`, `StatusBadge`, `PillFilter`.
- `components/charts/` → `RevenueAreaChart` (área MRR con gradiente), `AltasBajasBarChart` (barras radio superior), `RetentionDonut` (gauge). Usan **Recharts**.
- `components/icons.tsx` → iconos outline inline (sin dependencia de librería de iconos).