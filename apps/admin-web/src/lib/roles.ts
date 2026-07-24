// Distinción de roles del panel. `staff` = recepción (cobros en terminal,
// generación de tickets, gestión de miembros). `admin` = rol mayor con acceso a
// finanzas e ingresos. Los gráficos de ingresos y la gestión financiera se
// reservan a `admin`; recepción NO ve el dashboard financiero.

export type Rol = 'staff' | 'admin' | string;

export interface RoleAware {
  rol?: Rol;
}

export const isAdmin = (u?: RoleAware | null): boolean => u?.rol === 'admin';

/** Recepción y cualquier otro staff no-admin. */
export const isReception = (u?: RoleAware | null): boolean => !!u && u.rol !== 'admin';
