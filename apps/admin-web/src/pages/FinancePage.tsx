import { useMemo, useState } from 'react';
import { API } from '../lib/config';
import { http } from '../lib/api';
import { useAsync } from '../lib/useAsync';
import { money, date } from '../lib/format';
import type { Subscription } from '../lib/types';
import { Card } from '../components/ui/Card';
import { StatusBadge, type Tone } from '../components/ui/StatusBadge';

const ESTADOS = ['todos', 'active', 'past_due', 'cancelled', 'trialing'] as const;
type Estado = (typeof ESTADOS)[number];

const toneOf: Record<string, Tone> = {
  active: 'green', past_due: 'amber', cancelled: 'red', trialing: 'sky',
};
const estadoLabel: Record<Estado, string> = {
  todos: 'Todos', active: 'Activas', past_due: 'En mora', cancelled: 'Canceladas', trialing: 'Prueba',
};

const th = 'text-left px-5 py-3 text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500';
const td = 'px-5 py-4 text-sm text-gray-700 dark:text-gray-300';

export function FinancePage() {
  const [estado, setEstado] = useState<Estado>('active');

  // GET /admin/subscriptions?estado= (payment-service) — ver README.
  const { data, loading, error, reload } = useAsync<Subscription[]>(
    () => http.get<Subscription[]>(
      `${API.payment}/admin/subscriptions${estado === 'todos' ? '' : `?estado=${estado}`}`,
    ),
    [estado],
  );

  // Ingreso recurrente visible en el listado actual (MRR aproximado del filtro).
  const total = useMemo(
    () => (data ?? []).filter((s) => s.estado === 'active').reduce((a, s) => a + (s.monto || 0), 0),
    [data],
  );

  async function cancel(s: Subscription) {
    if (!confirm(`¿Cancelar la suscripción de ${s.usuario_email ?? s.usuario_id}?`)) return;
    // POST /admin/subscriptions/:id/cancel (payment-service).
    try { await http.post(`${API.payment}/admin/subscriptions/${s.id}/cancel`); reload(); }
    catch { /* estado real al recargar */ }
  }

  async function extend(s: Subscription) {
    const dias = Number(prompt('¿Cuántos días de cortesía otorgar?', '30'));
    if (!Number.isFinite(dias) || dias <= 0) return;
    // POST /admin/subscriptions/:id/extend { dias } (payment-service).
    try { await http.post(`${API.payment}/admin/subscriptions/${s.id}/extend`, { dias }); reload(); }
    catch { /* estado real al recargar */ }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Suscripciones</h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Cobros, cancelaciones y cortesías.</p>
        </div>
        <Card padding="px-5 py-3">
          <div className="text-xs text-gray-500 dark:text-gray-400">MRR (activas visibles)</div>
          <div className="text-xl font-bold text-emerald-600">{money(total)}</div>
        </Card>
      </div>

      {/* Filtros pill */}
      <div className="inline-flex flex-wrap items-center gap-1 p-1 rounded-lg bg-gray-100 dark:bg-gray-800">
        {ESTADOS.map((e) => (
          <button
            key={e} onClick={() => setEstado(e)}
            className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
              estado === e
                ? 'bg-white dark:bg-gray-700 text-indigo-600 dark:text-indigo-400 shadow-sm'
                : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200'
            }`}
          >
            {estadoLabel[e]}
          </button>
        ))}
      </div>

      {loading && <div className="text-gray-500 dark:text-gray-400">Cargando…</div>}
      {error && <div className="text-amber-600 dark:text-amber-400 text-sm">Endpoint no disponible ({error}).</div>}

      {data && (
        <Card padding="p-0" className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="border-b border-gray-100 dark:border-gray-700">
                <tr>
                  <th className={th}>Socio</th>
                  <th className={th}>Plan</th>
                  <th className={th}>Monto</th>
                  <th className={th}>Método</th>
                  <th className={th}>Vence</th>
                  <th className={th}>Estado</th>
                  <th className={th}></th>
                </tr>
              </thead>
              <tbody>
                {data.map((s) => (
                  <tr key={s.id} className="border-b border-gray-100 dark:border-gray-700/60 last:border-0 hover:bg-gray-50 dark:hover:bg-gray-700/30">
                    <td className={`${td} font-medium text-gray-900 dark:text-white`}>{s.usuario_email ?? s.usuario_id}</td>
                    <td className={td}>{s.plan_nombre}</td>
                    <td className={`${td} font-semibold text-gray-900 dark:text-white tabular-nums`}>{money(s.monto, s.moneda)}</td>
                    <td className={`${td} capitalize`}>{s.metodo_pago}</td>
                    <td className={td}>{date(s.valido_hasta)}</td>
                    <td className={td}>
                      <StatusBadge tone={toneOf[s.estado] ?? 'gray'}>{s.estado}</StatusBadge>
                    </td>
                    <td className={`${td} text-right whitespace-nowrap`}>
                      <button onClick={() => void extend(s)} className="text-indigo-600 dark:text-indigo-400 font-medium hover:underline mr-4">Cortesía</button>
                      {s.estado !== 'cancelled' && (
                        <button onClick={() => void cancel(s)} className="text-red-500 font-medium hover:underline">Cancelar</button>
                      )}
                    </td>
                  </tr>
                ))}
                {data.length === 0 && (
                  <tr><td colSpan={7} className="px-5 py-8 text-center text-gray-400">Sin suscripciones.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}
