import Link from "next/link";

export default function DocsPage() {
  return (
    <main className="min-h-screen bg-void-950 text-white">
      <header className="mx-auto flex max-w-5xl items-center justify-between px-6 py-8">
        <div>
          <p className="text-xs uppercase tracking-[0.3em] text-neon-400">Zero Echelon</p>
          <h1 className="text-2xl font-display">Outpost API Docs</h1>
        </div>
        <Link
          href="/outpost"
          className="rounded-full border border-slate-700 px-4 py-2 text-xs uppercase tracking-[0.3em] text-slate-300"
        >
          Back to Outpost
        </Link>
      </header>

      <section className="mx-auto max-w-5xl px-6 pb-20">
        <div className="glass-panel rounded-3xl p-8 space-y-8">
          <div>
            <h2 className="font-display text-xl mb-2">Authentication</h2>
            <p className="text-sm text-slate-300">
              Outpost uses API key authentication only. Include your key in the
              <span className="text-neon-400"> x-api-key</span> header. OAuth is
              not supported.
            </p>
          </div>

          <div className="space-y-3">
            <h3 className="font-display text-lg">Create a job</h3>
            <p className="text-sm text-slate-300">
              Submit a new agent job with an objective and priority.
            </p>
            <pre className="rounded-2xl bg-void-900/80 p-4 text-xs text-slate-200 overflow-x-auto">
{`curl -X POST https://outpost.zeroechelon.io/api/jobs \\
  -H "Content-Type: application/json" \\
  -H "x-api-key: $OUTPOST_API_KEY" \\
  -d '{"objective":"Secure signal relays","priority":"high"}'`}
            </pre>
          </div>

          <div className="space-y-3">
            <h3 className="font-display text-lg">List audit events</h3>
            <p className="text-sm text-slate-300">
              Retrieve transaction logs for finance reconciliation.
            </p>
            <pre className="rounded-2xl bg-void-900/80 p-4 text-xs text-slate-200 overflow-x-auto">
{`curl https://outpost.zeroechelon.io/api/audit \\
  -H "x-api-key: $OUTPOST_API_KEY"`}
            </pre>
          </div>

          <div className="space-y-3">
            <h3 className="font-display text-lg">Stripe webhook</h3>
            <p className="text-sm text-slate-300">
              Configure Stripe to send checkout events to the Outpost webhook.
            </p>
            <pre className="rounded-2xl bg-void-900/80 p-4 text-xs text-slate-200 overflow-x-auto">
{`POST https://outpost.zeroechelon.io/api/webhook`}
            </pre>
          </div>
        </div>
      </section>
    </main>
  );
}
