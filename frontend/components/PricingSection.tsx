"use client";

import { useState } from "react";
import { loadStripe } from "@stripe/stripe-js";

const stripePromise = loadStripe(
  process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? ""
);

const tiers = [
  {
    name: "Free",
    price: "$0",
    cadence: "10 jobs",
    description: "Proof-of-ops launchpad for new squads.",
    priceId: "free",
    highlight: false,
  },
  {
    name: "Pro",
    price: "$9",
    cadence: "/ 100 jobs",
    description: "Zero Echelon throughput for elite operators.",
    priceId: "pro",
    highlight: true,
  },
  {
    name: "Enterprise",
    price: "$99",
    cadence: "/ unlimited",
    description: "Full orbital command with compliance-grade controls.",
    priceId: "enterprise",
    highlight: false,
  },
];

export default function PricingSection() {
  const [loading, setLoading] = useState<string | null>(null);

  async function handleCheckout(priceId: string) {
    setLoading(priceId);
    const res = await fetch("/api/checkout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ priceId }),
    });

    const data = (await res.json()) as { sessionId?: string; error?: string };
    if (!res.ok || !data.sessionId) {
      setLoading(null);
      alert(data.error ?? "Unable to start checkout.");
      return;
    }

    const stripe = await stripePromise;
    await stripe?.redirectToCheckout({ sessionId: data.sessionId });
  }

  return (
    <section id="pricing" className="py-20">
      <div className="mx-auto max-w-6xl px-6">
        <div className="flex flex-col gap-6 text-center">
          <p className="text-sm uppercase tracking-[0.3em] text-neon-400">
            Pricing Protocol
          </p>
          <h2 className="text-3xl md:text-4xl font-display">
            Field-ready plans for every unit
          </h2>
          <p className="text-base text-slate-300 max-w-2xl mx-auto">
            Each plan includes real-time audit trails, Stripe-backed billing, and
            API key access only.
          </p>
        </div>
        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {tiers.map((tier) => (
            <div
              key={tier.name}
              className={`glass-panel rounded-3xl p-8 flex flex-col gap-6 ${
                tier.highlight ? "shadow-glow border-neon-500/40" : ""
              }`}
            >
              <div className="space-y-2">
                <p className="text-sm uppercase tracking-[0.2em] text-neon-400">
                  {tier.name}
                </p>
                <div className="flex items-end gap-2">
                  <span className="text-4xl font-display">{tier.price}</span>
                  <span className="text-sm text-slate-300">{tier.cadence}</span>
                </div>
                <p className="text-sm text-slate-300">{tier.description}</p>
              </div>
              <button
                type="button"
                onClick={() => handleCheckout(tier.priceId)}
                disabled={loading === tier.priceId}
                className={`mt-auto inline-flex items-center justify-center rounded-full px-5 py-3 text-sm font-semibold transition ${
                  tier.highlight
                    ? "bg-neon-500 text-void-950 shadow-glow hover:bg-neon-400"
                    : "border border-slate-700 text-white hover:border-neon-500"
                }`}
              >
                {loading === tier.priceId ? "Initializing..." : "Start Checkout"}
              </button>
              <p className="text-xs text-slate-500">
                Powered by Stripe Checkout
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
