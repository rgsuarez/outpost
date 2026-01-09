import Link from "next/link";
import PricingSection from "../../components/PricingSection";

const agents = [
  { name: "Claude", role: "Negotiator" },
  { name: "Codex", role: "Builder" },
  { name: "Gemini", role: "Navigator" },
  { name: "Grok", role: "Scout" },
  { name: "Aider", role: "Stitcher" },
];

export default function OutpostPage() {
  return (
    <main className="min-h-screen bg-void-950 text-white">
      <div className="hero-grid scanlines">
        <header className="mx-auto flex max-w-6xl items-center justify-between px-6 py-8">
          <div className="flex items-center gap-3">
            <div className="h-10 w-10 rounded-2xl border border-neon-500/40 bg-void-800 shadow-glow" />
            <div>
              <p className="text-xs uppercase tracking-[0.3em] text-neon-400">
                Zero Echelon
              </p>
              <p className="font-display text-lg">Outpost</p>
            </div>
          </div>
          <nav className="hidden items-center gap-8 text-sm text-slate-300 md:flex">
            <Link href="/outpost" className="hover:text-white">
              Overview
            </Link>
            <Link href="/outpost/docs" className="hover:text-white">
              API Docs
            </Link>
            <a href="#pricing" className="hover:text-white">
              Pricing
            </a>
          </nav>
          <Link
            href="/outpost/docs"
            className="rounded-full border border-neon-500/40 px-4 py-2 text-xs uppercase tracking-[0.3em] text-neon-400"
          >
            Docs
          </Link>
        </header>

        <section className="mx-auto grid max-w-6xl grid-cols-1 gap-12 px-6 pb-24 pt-10 md:grid-cols-[1.2fr_0.8fr]">
          <div className="space-y-8">
            <div className="inline-flex items-center gap-3 rounded-full border border-neon-500/30 bg-void-900/60 px-4 py-2 text-xs uppercase tracking-[0.3em] text-neon-400">
              Secure orchestration layer
            </div>
            <h1 className="text-4xl md:text-6xl font-display leading-tight">
              Command AI squads with Zero Echelon precision.
            </h1>
            <p className="text-base md:text-lg text-slate-300 max-w-xl">
              Outpost is the mission control for multi-agent fleets. Operate with
              API key authentication only, Stripe-verified billing, and audit
              trails that satisfy finance and compliance.
            </p>
            <div className="flex flex-wrap items-center gap-4">
              <a
                href="#pricing"
                className="rounded-full bg-neon-500 px-6 py-3 text-sm font-semibold text-void-950 shadow-glow"
              >
                Deploy Outpost
              </a>
              <Link
                href="/outpost/docs"
                className="rounded-full border border-slate-700 px-6 py-3 text-sm text-white"
              >
                Explore API Docs
              </Link>
            </div>
            <div className="flex flex-wrap gap-4 text-xs uppercase tracking-[0.2em] text-slate-400">
              <span>API key only</span>
              <span>Stripe checkout</span>
              <span>Audit logs</span>
            </div>
          </div>
          <div className="glass-panel rounded-3xl p-8 shadow-pulse">
            <p className="text-xs uppercase tracking-[0.3em] text-pulse-500">
              Active Agents
            </p>
            <div className="mt-6 space-y-4">
              {agents.map((agent, index) => (
                <div
                  key={agent.name}
                  className="flex items-center justify-between rounded-2xl border border-slate-800 bg-void-900/60 px-4 py-3"
                >
                  <div>
                    <p className="font-display text-lg">{agent.name}</p>
                    <p className="text-xs text-slate-400">{agent.role}</p>
                  </div>
                  <span
                    className={`text-xs uppercase tracking-[0.2em] text-neon-400 ${
                      index % 2 === 0 ? "floaty" : ""
                    }`}
                  >
                    Online
                  </span>
                </div>
              ))}
            </div>
          </div>
        </section>
      </div>

      <section className="mx-auto max-w-6xl px-6 py-16">
        <div className="grid gap-6 md:grid-cols-3">
          {[
            {
              title: "Mission-grade telemetry",
              description:
                "Track every agent action with immutable financial events. Audit logs stream to your finance stack.",
            },
            {
              title: "API key fortress",
              description:
                "No OAuth, no latency. Rotate keys, scope them to squads, and keep access offline-ready.",
            },
            {
              title: "Stripe-native billing",
              description:
                "Launch subscription checkout in seconds with secure payment orchestration.",
            },
          ].map((card) => (
            <div key={card.title} className="glass-panel rounded-3xl p-6">
              <h3 className="font-display text-lg mb-3">{card.title}</h3>
              <p className="text-sm text-slate-300">{card.description}</p>
            </div>
          ))}
        </div>
      </section>

      <PricingSection />

      <footer className="border-t border-slate-900 py-10">
        <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-6 text-xs text-slate-500 md:flex-row">
          <span>Zero Echelon Outpost</span>
          <span>Audit logs retained for all transactions.</span>
        </div>
      </footer>
    </main>
  );
}
