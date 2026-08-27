export type Rol = 'staff' | 'admin' | string;

export interface RoleAware {
  rol?: Rol;
}

export const isAdmin = (u?: RoleAware | null): boolean => u?.rol === 'admin';

export const isReception = (u?: RoleAware | null): boolean => !!u && u.rol !== 'admin';