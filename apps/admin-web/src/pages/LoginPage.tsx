import { useState } from 'react';
import { useAuth } from '../auth/AuthContext';

const input =
  'w-full border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 text-gray-800 dark:text-gray-100 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-200 dark:focus:ring-indigo-500/30';

export function LoginPage() {
  const { login } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login(email.trim(), password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo iniciar sesión.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="min-h-screen grid place-items-center bg-gray-50 dark:bg-gray-900 p-4">
      <form onSubmit={onSubmit} className="w-full max-w-sm bg-white dark:bg-gray-800 border border-gray-100 dark:border-gray-700 rounded-2xl p-8 shadow-card">
        <div className="flex items-center gap-2 mb-6">
          <span className="w-9 h-9 rounded-lg bg-brand text-white grid place-items-center font-bold">G</span>
          <span className="text-lg font-bold text-gray-900 dark:text-white">Gym<span className="text-brand">Pro</span></span>
          <span className="text-xs text-gray-400 self-end mb-0.5">admin</span>
        </div>

        <h1 className="text-xl font-bold text-gray-900 dark:text-white mb-1">Iniciar sesión</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-6">Acceso solo para personal (staff/admin).</p>

        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Correo</label>
        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
          className={`${input} mb-4`} autoComplete="username" required />

        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Contraseña</label>
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
          className={`${input} mb-4`} autoComplete="current-password" required />

        {error && (
          <div className="text-sm text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-500/10 rounded-lg px-3 py-2 mb-4">
            {error}
          </div>
        )}

        <button type="submit" disabled={busy}
          className="w-full bg-brand hover:bg-brand-700 text-white rounded-lg py-2.5 text-sm font-medium disabled:opacity-60 transition-colors">
          {busy ? 'Entrando…' : 'Iniciar sesión'}
        </button>
      </form>
    </div>
  );
}
