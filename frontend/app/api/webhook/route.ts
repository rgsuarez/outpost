import { NextResponse } from "next/server";
import Stripe from "stripe";
import { stripe } from "../../../lib/stripe";
import { appendAuditLog } from "../../../lib/audit";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const signature = request.headers.get("stripe-signature");
  const body = await request.text();

  if (!signature || !process.env.STRIPE_WEBHOOK_SECRET) {
    return NextResponse.json(
      { error: "Missing Stripe webhook configuration." },
      { status: 400 }
    );
  }

  let event: Stripe.Event;

  try {
    event = stripe.webhooks.constructEvent(
      Buffer.from(body),
      signature,
      process.env.STRIPE_WEBHOOK_SECRET
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid signature";
    return NextResponse.json({ error: message }, { status: 400 });
  }

  await appendAuditLog({
    type: "stripe_event",
    eventId: event.id,
    eventType: event.type,
    data: event.data.object,
  });

  return NextResponse.json({ received: true });
}
