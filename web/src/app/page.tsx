'use client';
import { useEffect, useState } from 'react';

export default function Home() {
  const [status, setStatus] = useState<string>('...');

  useEffect(() => {
    fetch('/api/health', { cache: 'no-store' })
      .then(r => r.json())
      .then(d => setStatus(d?.status ?? 'fail'))
      .catch(() => setStatus('fail'));
  }, []);

  return (
    <main className="p-6">
      <h1 className="text-2xl font-bold">ERP Moderno — mig</h1>
      <p className="mt-2">API health: <b>{status}</b></p>
    </main>
  );
}
