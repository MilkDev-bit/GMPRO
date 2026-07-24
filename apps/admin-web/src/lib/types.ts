// Contratos de datos del panel. Reflejan lo que los endpoints ADMIN del backend
// deben devolver (ver README → "Endpoints backend a crear").

export interface Member {
  id: string;
  nombre: string;
  apellido_paterno?: string;
  email: string;
  rol: 'miembro' | 'staff' | 'admin';
  activo: boolean;
  creado_en: string;
  ultimo_login?: string | null;
}

export interface Subscription {
  id: string;
  usuario_id: string;
  usuario_email?: string;
  plan_nombre: string;
  estado: 'active' | 'past_due' | 'cancelled' | 'trialing';
  monto: number;
  moneda: string;
  metodo_pago: 'stripe' | 'efectivo' | string;
  valido_hasta: string;
  proximo_pago_en?: string | null;
}

export interface FinanceSummary {
  ingresosMes: number;
  moneda: string;
  suscripcionesActivas: number;
  suscripcionesPastDue: number;
  altasMes: number;
  bajasMes: number;
}

export interface Offer {
  id: string;
  nombre: string;
  tipo: 'porcentaje' | 'monto_fijo' | 'meses_gratis';
  valor: number; // % , importe, o nº de meses
  codigo: string;
  activa: boolean;
  valido_desde: string;
  valido_hasta: string;
  usos: number;
  max_usos?: number | null;
}
