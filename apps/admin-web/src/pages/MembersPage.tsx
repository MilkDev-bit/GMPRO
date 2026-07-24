import { useState } from 'react';
import { API } from '../lib/config';
import { http } from '../lib/api';
import { useAsync } from '../lib/useAsync';
import { date } from '../lib/format';
import type { Member } from '../lib/types';
import { Card } from '../components/ui/Card';
import { StatusBadge } from '../components/ui/StatusBadge';
import { SearchIcon } from '../components/icons';

const th = 'text-left px-5 py-3 text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500';
const td = 'px-5 py-4 text-sm text-gray-700 dark:text-gray-300';

export function MembersPage() {
  const [q, setQ] = useState('');
  // GET /admin/members?search= (auth-service) — ver README.
  const { data, loading, error, reload } = useAsync<Member[]>(
    () => http.get<Member[]>(`${API.auth}/admin/members?search=${encodeURIComponent(q)}`),
    [q],
  );

  async function toggleActive(m: Member) {
    // PATCH /admin/members/:id { activo } (auth-service).
    try {
      await http.patch(`${API.auth}/admin/members/${m.id}`, { activo: !m.activo });
      reload();
    } catch { /* el listado mostrará el estado real al recargar */ }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Miembros</h1>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Gestión de socios y estado de acceso.</p>
        </div>
        <div className="relative w-full sm:w-80">
          <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input
            value={q} onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por nombre o email…"
            className="w-full pl-10 pr-3 py-2 rounded-lg text-sm bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-200 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-200 dark:focus:ring-indigo-500/30"
          />
        </div>
      </div>

      {loading && <div className="text-gray-500 dark:text-gray-400">Cargando…</div>}
      {error && <div className="text-amber-600 dark:text-amber-400 text-sm">Endpoint no disponible ({error}).</div>}

      {data && (
        <Card padding="p-0" className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="border-b border-gray-100 dark:border-gray-700">
                <tr>
                  <th className={th}>Nombre</th>
                  <th className={th}>Email</th>
                  <th className={th}>Rol</th>
                  <th className={th}>Alta</th>
                  <th className={th}>Estado</th>
                  <th className={th}></th>
                </tr>
              </thead>
              <tbody>
                {data.map((m) => (
                  <tr key={m.id} className="border-b border-gray-100 dark:border-gray-700/60 last:border-0 hover:bg-gray-50 dark:hover:bg-gray-700/30">
                    <td className={`${td} font-medium text-gray-900 dark:text-white`}>
                      {m.nombre} {m.apellido_paterno ?? ''}
                    </td>
                    <td className={`${td} text-gray-500 dark:text-gray-400`}>{m.email}</td>
                    <td className={`${td} capitalize`}>{m.rol}</td>
                    <td className={td}>{date(m.creado_en)}</td>
                    <td className={td}>
                      <StatusBadge tone={m.activo ? 'green' : 'red'}>
                        {m.activo ? 'Activo' : 'Suspendido'}
                      </StatusBadge>
                    </td>
                    <td className={`${td} text-right`}>
                      <button onClick={() => void toggleActive(m)}
                        className="text-indigo-600 dark:text-indigo-400 font-medium hover:underline">
                        {m.activo ? 'Suspender' : 'Reactivar'}
                      </button>
                    </td>
                  </tr>
                ))}
                {data.length === 0 && (
                  <tr><td colSpan={6} className="px-5 py-8 text-center text-gray-400">Sin resultados.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}
