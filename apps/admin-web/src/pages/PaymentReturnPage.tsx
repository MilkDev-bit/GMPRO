import { useEffect, useState } from 'react';

/**
 * Página de retorno tras Stripe Checkout. Stripe sólo acepta success/cancel_url
 * http(s), así que la app móvil usa https://gmpro.lat/payment/success|cancel.
 * Esta página REBOTA de vuelta a la app móvil vía su deep link (gympro://) y, al
 * reabrirse, la app refresca la suscripción y activa la membresía. Si el rebote
 * automático no ocurre (p.ej. no está instalada), se muestra un botón manual.
 */
export function PaymentReturnPage({ kind }: { kind: 'success' | 'cancel' }) {
  const deepLink = `gympro://payment/${kind}`;
  const [bounced, setBounced] = useState(false);

  useEffect(() => {
    // Intento de reapertura automática de la app.
    const t = setTimeout(() => {
      window.location.href = deepLink;
      setBounced(true);
    }, 400);
    return () => clearTimeout(t);
  }, [deepLink]);

  const ok = kind === 'success';

  return (
    <div className="min-h-screen grid place-items-center bg-gray-50 dark:bg-gray-900 p-4">
      <div className="w-full max-w-sm bg-white dark:bg-gray-800 border border-gray-100 dark:border-gray-700 rounded-2xl p-8 shadow-card text-center">
        <div
          className={`w-14 h-14 rounded-full grid place-items-center mx-auto mb-5 text-white text-2xl font-bold ${
            ok ? 'bg-emerald-500' : 'bg-gray-400'
          }`}
        >
          {ok ? '✓' : '×'}
        </div>
        <h1 className="text-xl font-bold text-gray-900 dark:text-white mb-2">
          {ok ? 'Pago recibido' : 'Pago cancelado'}
        </h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-6">
          {ok
            ? 'Tu membresía se activará en la app en unos segundos. Vuelve a la aplicación de GymPro para continuar.'
            : 'No se realizó ningún cargo. Puedes volver a la app e intentarlo de nuevo cuando quieras.'}
        </p>
        <a
          href={deepLink}
          className="inline-block w-full bg-brand hover:bg-brand-700 text-white rounded-lg py-2.5 text-sm font-medium transition-colors"
        >
          Volver a la app GymPro
        </a>
        {bounced && (
          <p className="text-xs text-gray-400 mt-4">
            Si la app no se abrió automáticamente, toca el botón de arriba.
          </p>
        )}
      </div>
    </div>
  );
}
