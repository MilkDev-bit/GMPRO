// URLs de los microservicios. En dev se leen de .env (VITE_*); con fallback a
// Railway. Nunca metemos secretos aquí: solo endpoints públicos.
const env = import.meta.env;

export const API = {
  auth: env.VITE_AUTH_URL ?? 'https://auth-service.up.railway.app/api/v1/auth',
  payment: env.VITE_PAYMENT_URL ?? 'https://payment-service.up.railway.app/api/v1',
  access: env.VITE_ACCESS_URL ?? 'https://access-service.up.railway.app/api/v1/access',
  fitness: env.VITE_FITNESS_URL ?? 'https://fitness-service.up.railway.app/api/v1',
} as const;

// Roles internos autorizados a usar el panel (coincide con STAFF_ROLES del backend).
export const STAFF_ROLES = ['staff', 'admin'] as const;
