# Outpost Frontend

Next.js 14 App Router frontend for Zero Echelon Outpost with Stripe Checkout, API key auth, and audit logging.

## Quick start

```bash
cd frontend
npm install
cp .env.example .env.local
npm run dev
```

Open `http://localhost:3000/outpost`.

## Stripe setup

1. Create Stripe Prices for each plan and paste their IDs into `.env.local`.
2. Configure a webhook endpoint pointing to `/api/webhook`.
3. Add the webhook signing secret as `STRIPE_WEBHOOK_SECRET`.

## API key auth

All API endpoints that simulate Outpost services require `x-api-key` and only use API keys (no OAuth).
Set `OUTPOST_API_KEY` in `.env.local`.

## Audit-ready financial logs

Every checkout session, Stripe webhook event, and simulated job creation is appended to:

`frontend/logs/transactions.log`

Entries are JSON lines for easy ingestion by finance or compliance tooling.
