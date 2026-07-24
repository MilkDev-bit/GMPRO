import { useState } from 'react';
import { API } from '../lib/config';
import { http } from '../lib/api';
import { useAsync } from '../lib/useAsync';
import { date } from '../lib/format';
import type { Offer } from '../lib/types';
import { Card } from '../components/ui/Card';
import { StatusBadge, type Tone } from '../components/ui/StatusBadge';

const TIPOS: { value: Offer['tipo']; label: string }[] = [
  { value: 'porcentaje', label: 'Porcentaje (%)' },
  { value: 'monto_fijo', label: 'Monto fijo' },
  { value: 'meses_gratis', label: 'Meses gratis' },
];

// Debe reflejar el regex del servidor: /^[A-Za-z0-9_-]{3,40}$/
const CODE_RE = /^[A-Za-z0-9_-]{3,40}$/;

const input =
  'border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-200 rounded-lg px-3 py-2 w-full text-sm placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-200 dark:focus:ring-indigo-500/30';
const th = 'text-left px-5 py-3 text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500';
const td = 'px-5 py-4 text-sm text-gray-700 dark:text-gray-300';

/** Muestra el valor según el tipo de oferta. */
function formatValor(o: Pick<Offer, 'tipo' | 'valor'>): string {
  if (o.tipo === 'porcentaje') return `${o.valor}%`;
  if (o.tipo === 'monto_fijo') return `$${o.valor}`;
  return `${o.valor} ${o.valor === 1 ? 'mes' : 'meses'}`;
}

/** Estado REAL derivado de activa + vigencia + cupo. */
function deriveStatus(o: Offer): { label: string; tone: Tone } {
  const now = Date.now();
  if (!o.activa) return { label: 'Inactiva', tone: 'gray' };
  if (new Date(o.valido_desde).getTime() > now) return { label: 'Programada', tone: 'indigo' };
  if (new Date(o.valido_hasta).getTime() < now) return { label: 'Expirada', tone: 'red' };
  if (o.max_usos != null && o.usos >= o.max_usos) return { label: 'Agotada', tone: 'amber' };
  return { label: 'Vigente', tone: 'green' };
}

/** Barra de uso: canjes registrados por el webhook (usos) vs. cupo (max_usos). */
function UsageCell({ o }: { o: Offer }) {
  if (o.max_usos == null) {
    return <span className="text-gray-600 dark:text-gray-300">{o.usos} · <span className="text-gray-400">sin límite</span></span>;
  }
  const pct = Math.min(100, Math.round((o.usos / o.max_usos) * 100));
  const full = o.usos >= o.max_usos;
  return (
    <div className="min-w-[7rem]">
      <div className="text-xs text-gray-600 dark:text-gray-300 mb-1">{o.usos} / {o.max_usos}</div>
      <div className="h-1.5 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
        <div className={`h-full rounded-full ${full ? 'bg-amber-500' : 'bg-brand'}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

export function OffersPage() {
  // GET /admin/offers (payment-service) — ver README.
  const { data, loading, error, reload } = useAsync<Offer[]>(
    () => http.get<Offer[]>(`${API.payment}/admin/offers`),
  );

  const [form, setForm] = useState({
    nombre: '', codigo: '', tipo: 'porcentaje' as Offer['tipo'],
    valor: 10, valido_desde: '', valido_hasta: '', max_usos: '' as string,
  });
  const [saving, setSaving] = useState(false);
  const [saveErr, setSaveErr] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  /** Validación cliente que refleja las reglas del backend (falla antes de la red). */
  function validateForm(): string | null {
    if (!CODE_RE.test(form.codigo))
      return 'El código debe tener 3-40 caracteres: letras, números, guion o guion bajo.';
    if (!form.valido_desde || !form.valido_hasta)
      return 'Indica el rango de vigencia (desde y hasta).';
    if (new Date(form.valido_hasta) <= new Date(form.valido_desde))
      return 'La fecha de fin debe ser posterior a la de inicio.';
    if (form.valor < 0) return 'El valor no puede ser negativo.';
    if (form.tipo === 'porcentaje' && (form.valor <= 0 || form.valor > 100))
      return 'El porcentaje debe estar entre 1 y 100.';
    if (form.tipo === 'meses_gratis' && form.valor < 1)
      return 'Los meses gratis deben ser al menos 1.';
    if (form.max_usos && Number(form.max_usos) < 1)
      return 'El máximo de usos debe ser al menos 1.';
    return null;
  }

  async function create(e: React.FormEvent) {
    e.preventDefault();
    const invalid = validateForm();
    if (invalid) { setSaveErr(invalid); return; }

    setSaving(true); setSaveErr(null);
    try {
      // POST /admin/offers (payment-service).
      await http.post(`${API.payment}/admin/offers`, {
        ...form,
        valor: Number(form.valor),
        max_usos: form.max_usos ? Number(form.max_usos) : null,
      });
      setForm({ ...form, nombre: '', codigo: '' });
      reload();
    } catch (err) {
      // El backend responde 409 si el código ya existe.
      const msg = err instanceof Error ? err.message : 'No se pudo crear la oferta.';
      setSaveErr(/exist|409|código/i.test(msg) ? 'Ya existe una oferta con ese código.' : msg);
    } finally { setSaving(false); }
  }

  async function toggle(o: Offer) {
    setBusyId(o.id);
    try { await http.patch(`${API.payment}/admin/offers/${o.id}`, { activa: !o.activa }); reload(); }
    catch { /* estado real al recargar */ }
    finally { setBusyId(null); }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Ofertas especiales</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Cupones de descuento y su canje.</p>
      </div>

      {/* Crear oferta */}
      <Card>
        <form onSubmit={create} className="grid md:grid-cols-3 gap-3">
          <input className={input} placeholder="Nombre (ej. Verano 2026)"
            value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })} required />
          <input className={input} placeholder="Código (ej. VERANO26)"
            value={form.codigo} onChange={(e) => setForm({ ...form, codigo: e.target.value.toUpperCase() })} required />
          <select className={input} value={form.tipo}
            onChange={(e) => setForm({ ...form, tipo: e.target.value as Offer['tipo'] })}>
            {TIPOS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
          </select>
          <input className={input} type="number" placeholder="Valor (%, importe o meses)"
            value={form.valor} onChange={(e) => setForm({ ...form, valor: Number(e.target.value) })} required />
          <label className="text-xs text-gray-500 dark:text-gray-400">
            Vigente desde
            <input className={input} type="date"
              value={form.valido_desde} onChange={(e) => setForm({ ...form, valido_desde: e.target.value })} required />
          </label>
          <label className="text-xs text-gray-500 dark:text-gray-400">
            Vigente hasta
            <input className={input} type="date"
              value={form.valido_hasta} onChange={(e) => setForm({ ...form, valido_hasta: e.target.value })} required />
          </label>
          <input className={input} type="number" placeholder="Máx. usos (opcional)"
            value={form.max_usos} onChange={(e) => setForm({ ...form, max_usos: e.target.value })} />
          <button type="submit" disabled={saving}
            className="bg-brand hover:bg-brand-700 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-60 transition-colors">
            {saving ? 'Creando…' : 'Crear oferta'}
          </button>
          {saveErr && <div className="text-red-500 text-sm md:col-span-3">{saveErr}</div>}
        </form>
      </Card>

      {loading && <div className="text-gray-500 dark:text-gray-400">Cargando…</div>}
      {error && <div className="text-amber-600 dark:text-amber-400 text-sm">Endpoint no disponible ({error}).</div>}

      {data && (
        <Card padding="p-0" className="overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="border-b border-gray-100 dark:border-gray-700">
                <tr>
                  <th className={th}>Oferta</th>
                  <th className={th}>Código</th>
                  <th className={th}>Tipo / Valor</th>
                  <th className={th}>Vigencia</th>
                  <th className={th}>Canjes</th>
                  <th className={th}>Estado</th>
                  <th className={th}></th>
                </tr>
              </thead>
              <tbody>
                {data.map((o) => {
                  const st = deriveStatus(o);
                  return (
                    <tr key={o.id} className="border-b border-gray-100 dark:border-gray-700/60 last:border-0 hover:bg-gray-50 dark:hover:bg-gray-700/30">
                      <td className={`${td} font-medium text-gray-900 dark:text-white`}>{o.nombre}</td>
                      <td className={`${td} font-mono`}>{o.codigo}</td>
                      <td className={td}>{formatValor(o)}</td>
                      <td className={td}>{date(o.valido_desde)} – {date(o.valido_hasta)}</td>
                      <td className={td}><UsageCell o={o} /></td>
                      <td className={td}><StatusBadge tone={st.tone}>{st.label}</StatusBadge></td>
                      <td className={`${td} text-right`}>
                        <button onClick={() => void toggle(o)} disabled={busyId === o.id}
                          className="text-indigo-600 dark:text-indigo-400 font-medium hover:underline disabled:opacity-50">
                          {busyId === o.id ? '…' : o.activa ? 'Desactivar' : 'Activar'}
                        </button>
                      </td>
                    </tr>
                  );
                })}
                {data.length === 0 && (
                  <tr><td colSpan={7} className="px-5 py-8 text-center text-gray-400">Aún no hay ofertas.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}
