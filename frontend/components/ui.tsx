export function StatCard({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="inset-card rounded-3xl p-6">
      <div className="text-xs uppercase tracking-widest text-mist">{label}</div>
      <div className="mt-2 font-display text-2xl font-bold">{value}</div>
      {sub ? <div className="mt-1 text-xs text-mist">{sub}</div> : null}
    </div>
  );
}

export function Empty({ title, body }: { title: string; body: string }) {
  return (
    <div className="inset-card rounded-3xl p-10 text-center">
      <div className="font-display text-xl font-bold">{title}</div>
      <p className="mx-auto mt-2 max-w-md text-sm text-mist">{body}</p>
    </div>
  );
}

export function TxStatus({ state }: { state: string | null }) {
  if (!state) return null;
  return <p className="mt-3 text-sm text-fog">{state}</p>;
}
