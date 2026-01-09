import { NextResponse } from "next/server";
import { stripe } from "../../../lib/stripe";
import { appendAuditLog } from "../../../lib/audit";

export const runtime = "nodejs";

const priceMap: Record<string, string | undefined> = {
  free: process.env.STRIPE_PRICE_FREE,
  pro: process.env.STRIPE_PRICE_PRO,
  enterprise: process.env.STRIPE_PRICE_ENTERPRISE,
};

export async function POST(request: Request) {
  try {
    const { priceId } = (await request.json()) as { priceId?: string };
    const stripePriceId = priceId ? priceMap[priceId] : undefined;

    if (!stripePriceId) {
      return NextResponse.json(
        { error: "Invalid price selection." },
        { status: 400 }
      );
    }

    const origin = request.headers.get("origin") ?? "";
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: stripePriceId, quantity: 1 }],
      success_url: `${origin}/outpost?checkout=success`,
      cancel_url: `${origin}/outpost?checkout=cancel`,
      metadata: {
        plan: priceId ?? "unknown",
      },
    });

    await appendAuditLog({
      type: "checkout_session_created",
      sessionId: session.id,
      plan: priceId,
    });

    return NextResponse.json({ sessionId: session.id });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
