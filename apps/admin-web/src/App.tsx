import { Navigate, Route, Routes } from 'react-router-dom';
import { useAuth } from './auth/AuthContext';
import { isAdmin } from './lib/roles';
import { Layout } from './components/Layout';
import { LoginPage } from './pages/LoginPage';
import { PaymentReturnPage } from './pages/PaymentReturnPage';
import { DashboardPage } from './pages/DashboardPage';
import { MembersPage } from './pages/MembersPage';
import { FinancePage } from './pages/FinancePage';
import { OffersPage } from './pages/OffersPage';

function Protected({ children, adminOnly }: { children: JSX.Element; adminOnly?: boolean }) {
  const { user, loading } = useAuth();
  if (loading) return <div className="p-8 text-gray-500">Cargando…</div>;
  if (!user) return <Navigate to="/login" replace />;
  if (adminOnly && !isAdmin(user)) return <Navigate to="/members" replace />;
  return <Layout>{children}</Layout>;
}

export default function App() {
  const { user } = useAuth();
  return (
    <Routes>
      <Route path="/login" element={user ? <Navigate to="/" replace /> : <LoginPage />} />
      <Route path="/payment/success" element={<PaymentReturnPage kind="success" />} />
      <Route path="/payment/cancel" element={<PaymentReturnPage kind="cancel" />} />
      <Route path="/" element={<Protected adminOnly><DashboardPage /></Protected>} />
      <Route path="/members" element={<Protected><MembersPage /></Protected>} />
      <Route path="/finance" element={<Protected adminOnly><FinancePage /></Protected>} />
      <Route path="/offers" element={<Protected adminOnly><OffersPage /></Protected>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
