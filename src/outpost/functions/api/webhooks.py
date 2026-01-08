"""
Stripe webhook handler for Outpost multi-tenant SaaS.

Handles subscription lifecycle events from Stripe and updates tenant status accordingly.
"""
import json
import os
import hashlib
from typing import Dict, Any, Optional

from src.outpost.services import BillingService, AuditService
from src.outpost.services.stripe_client import StripeClient


class WebhookHandler:
    """
    Processes Stripe webhook events for subscription lifecycle management.

    Handles:
    - customer.subscription.created/updated/deleted
    - invoice.payment_succeeded/failed
    - checkout.session.completed

    Features:
    - Signature verification
    - Idempotent processing (stores processed event IDs)
    - Audit trail for all events
    """

    def __init__(self):
        self.stripe_client = StripeClient()
        self.billing = BillingService(stripe_client=self.stripe_client)
        self.audit = AuditService()

        # For idempotency tracking (in production, use DynamoDB)
        self._processed_events: set = set()

    def verify_and_construct_event(
        self,
        payload: bytes,
        sig_header: str
    ) -> Optional[Dict[str, Any]]:
        """
        Verify webhook signature and construct event.

        Args:
            payload: Raw request body bytes
            sig_header: Stripe-Signature header value

        Returns:
            Stripe event object or None if verification fails
        """
        try:
            event = self.stripe_client.construct_webhook_event(payload, sig_header)
            return event
        except Exception as e:
            print(f"Webhook signature verification failed: {e}")
            return None

    def is_duplicate_event(self, event_id: str) -> bool:
        """
        Check if event has already been processed (idempotency).

        In production, this would check DynamoDB.
        """
        return event_id in self._processed_events

    def mark_event_processed(self, event_id: str) -> None:
        """Mark event as processed."""
        self._processed_events.add(event_id)

    def process_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Process a verified Stripe webhook event.

        Args:
            event: Stripe event object

        Returns:
            Processing result dict
        """
        event_id = event.get("id")
        event_type = event.get("type")
        data = event.get("data", {}).get("object", {})

        # Idempotency check
        if self.is_duplicate_event(event_id):
            return {
                "status": "skipped",
                "reason": "duplicate_event",
                "event_id": event_id
            }

        # Route to appropriate handler
        handler_map = {
            "customer.subscription.created": self._handle_subscription_created,
            "customer.subscription.updated": self._handle_subscription_updated,
            "customer.subscription.deleted": self._handle_subscription_deleted,
            "invoice.payment_succeeded": self._handle_payment_succeeded,
            "invoice.payment_failed": self._handle_payment_failed,
            "checkout.session.completed": self._handle_checkout_completed,
        }

        handler = handler_map.get(event_type)
        if handler:
            try:
                result = handler(data)
                self.mark_event_processed(event_id)
                return {
                    "status": "processed",
                    "event_id": event_id,
                    "event_type": event_type,
                    "result": result
                }
            except Exception as e:
                return {
                    "status": "error",
                    "event_id": event_id,
                    "event_type": event_type,
                    "error": str(e)
                }
        else:
            # Unhandled event type - acknowledge but don't process
            self.mark_event_processed(event_id)
            return {
                "status": "ignored",
                "event_id": event_id,
                "event_type": event_type,
                "reason": "unhandled_event_type"
            }

    def _handle_subscription_created(self, subscription: Dict[str, Any]) -> Dict[str, str]:
        """Handle new subscription creation."""
        customer_id = subscription.get("customer")
        subscription_id = subscription.get("id")
        status = subscription.get("status")
        current_period_end = subscription.get("current_period_end")

        self.billing.handle_subscription_update(
            stripe_customer_id=customer_id,
            subscription_id=subscription_id,
            status=status,
            current_period_end=current_period_end
        )

        return {"action": "subscription_created", "subscription_id": subscription_id}

    def _handle_subscription_updated(self, subscription: Dict[str, Any]) -> Dict[str, str]:
        """Handle subscription status update."""
        customer_id = subscription.get("customer")
        subscription_id = subscription.get("id")
        status = subscription.get("status")
        current_period_end = subscription.get("current_period_end")

        self.billing.handle_subscription_update(
            stripe_customer_id=customer_id,
            subscription_id=subscription_id,
            status=status,
            current_period_end=current_period_end
        )

        return {"action": "subscription_updated", "status": status}

    def _handle_subscription_deleted(self, subscription: Dict[str, Any]) -> Dict[str, str]:
        """Handle subscription cancellation/deletion."""
        customer_id = subscription.get("customer")
        subscription_id = subscription.get("id")

        self.billing.handle_subscription_update(
            stripe_customer_id=customer_id,
            subscription_id=subscription_id,
            status="canceled"
        )

        return {"action": "subscription_deleted", "subscription_id": subscription_id}

    def _handle_payment_succeeded(self, invoice: Dict[str, Any]) -> Dict[str, str]:
        """Handle successful payment."""
        customer_id = invoice.get("customer")
        invoice_id = invoice.get("id")
        amount_paid = invoice.get("amount_paid", 0)
        currency = invoice.get("currency", "usd")

        self.billing.handle_payment_success(
            stripe_customer_id=customer_id,
            invoice_id=invoice_id,
            amount_paid=amount_paid,
            currency=currency
        )

        return {"action": "payment_succeeded", "amount": amount_paid}

    def _handle_payment_failed(self, invoice: Dict[str, Any]) -> Dict[str, str]:
        """Handle failed payment."""
        customer_id = invoice.get("customer")
        invoice_id = invoice.get("id")
        attempt_count = invoice.get("attempt_count", 1)

        self.billing.handle_payment_failure(
            stripe_customer_id=customer_id,
            invoice_id=invoice_id,
            attempt_count=attempt_count
        )

        return {"action": "payment_failed", "attempt_count": attempt_count}

    def _handle_checkout_completed(self, session: Dict[str, Any]) -> Dict[str, str]:
        """Handle checkout session completion."""
        # Checkout completion means customer subscribed successfully
        # The subscription.created event will handle the actual subscription setup
        customer_id = session.get("customer")
        subscription_id = session.get("subscription")
        tenant_id = session.get("metadata", {}).get("tenant_id")

        if tenant_id:
            self.audit.log_action(
                tenant_id=tenant_id,
                action="CHECKOUT_COMPLETED",
                resource=session.get("id"),
                metadata={
                    "customer_id": customer_id,
                    "subscription_id": subscription_id
                }
            )

        return {"action": "checkout_completed", "subscription_id": subscription_id}


def handler(event, context):
    """
    Lambda handler for Stripe webhooks.

    Expects:
    - POST request with Stripe event in body
    - Stripe-Signature header for verification
    """
    webhook_handler = WebhookHandler()

    # Get raw body and signature
    body = event.get("body", "")
    if event.get("isBase64Encoded"):
        import base64
        body = base64.b64decode(body)
    elif isinstance(body, str):
        body = body.encode("utf-8")

    headers = event.get("headers", {})
    # Headers might be lowercase in API Gateway v2
    sig_header = headers.get("Stripe-Signature") or headers.get("stripe-signature")

    if not sig_header:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Missing Stripe-Signature header"})
        }

    # Verify and construct event
    stripe_event = webhook_handler.verify_and_construct_event(body, sig_header)
    if not stripe_event:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Webhook signature verification failed"})
        }

    # Process the event
    try:
        result = webhook_handler.process_event(stripe_event)

        # Always return 200 to Stripe to acknowledge receipt
        # Even if we ignore or skip the event
        return {
            "statusCode": 200,
            "body": json.dumps(result)
        }
    except Exception as e:
        print(f"Webhook processing error: {e}")
        # Still return 200 to prevent Stripe retries for application errors
        # Log the error for investigation
        return {
            "statusCode": 200,
            "body": json.dumps({
                "status": "error",
                "error": str(e)
            })
        }
