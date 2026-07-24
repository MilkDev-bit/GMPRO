// Cliente HTTP tipado para el panel admin.
//   • Adjunta el Bearer del staff en cada request a NUESTRO backend.
//   • Ante 401 intenta UN refresh (contra auth-service) y reintenta la petición.
//   • Envelope estándar del backend: { success, data, error }.
//
// Seguridad: el token vive en memoria (módulo), no en localStorage, para reducir
// la superficie de XSS/robo de token. Se rehidrata vía /refresh (cookie httpOnly)
// al recargar. React escapa el render por defecto → no usar dangerouslySetInnerHTML.

import { API } from './config';

export interface ApiEnvelope<T> {
  success: boolean;
  data: T | null;
  error: string | null;
}

let accessToken: string | null = null;
export const setAccessToken = (t: string | null) => { accessToken = t; };
export const getAccessToken = () => accessToken;

let refreshing: Promise<boolean> | null = null;

/** Intenta renovar el access token con la cookie de refresh (single-flight). */
async function tryRefresh(): Promise<boolean> {
  if (refreshing) return refreshing;
  refreshing = (async () => {
    try {
      const res = await fetch(`${API.auth}/refresh`, {
        method: 'POST',
        credentials: 'include', // envía la cookie httpOnly de refresh
      });
      if (!res.ok) return false;
      const json = (await res.json()) as ApiEnvelope<{ accessToken: string }>;
      if (json.data?.accessToken) {
        accessToken = json.data.accessToken;
        return true;
      }
      return false;
    } catch {
      return false;
    } finally {
      refreshing = null;
    }
  })();
  return refreshing;
}

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

async function request<T>(
  method: string,
  url: string,
  body?: unknown,
  _retried = false,
): Promise<T> {
  const res = await fetch(url, {
    method,
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  // 401 → un solo intento de refresh + retry (evita bucle con _retried).
  if (res.status === 401 && !_retried) {
    if (await tryRefresh()) return request<T>(method, url, body, true);
  }

  const text = await res.text();
  let json: ApiEnvelope<T> | null = null;
  try { json = text ? (JSON.parse(text) as ApiEnvelope<T>) : null; } catch { /* no-json */ }

  if (!res.ok || (json && json.success === false)) {
    throw new ApiError(res.status, json?.error ?? `HTTP ${res.status}`);
  }
  return (json?.data as T) ?? (null as T);
}

export const http = {
  get: <T>(url: string) => request<T>('GET', url),
  post: <T>(url: string, body?: unknown) => request<T>('POST', url, body),
  put: <T>(url: string, body?: unknown) => request<T>('PUT', url, body),
  patch: <T>(url: string, body?: unknown) => request<T>('PATCH', url, body),
  del: <T>(url: string) => request<T>('DELETE', url),
};
