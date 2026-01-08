"""
Stripe API client wrapper for Outpost multi-tenant SaaS.

Provides low-level Stripe API operations with caching and error handling.
"""
import os
import stripe
from typing import Optional, Dict, Any
from functools import lru_cache
from datetime import datetime


class StripeClient:
    """Low-level Stripe API client with configuration management."""

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.environ.get("STRIPE_SECRET_KEY")
        if not self.api_key:
            raise ValueError("STRIPE_SECRET_KEY not configured")
        stripe.api_key = self.api_key

        # Product IDs for subscription tiers (configurable via env)
        self.products = {
            "free": os.environ.get("STRIPE_PRODUCT_FREE", "prod_free"),
            "pro": os.environ.get("STRIPE_PRODUCT_PRO", "prod_pro"),
            "enterprise": os.environ.get("STRIPE_PRODUCT_ENTERPRISE", "prod_enterprise")
        }

        # Price IDs for subscription tiers
        self.prices = {
            "free": os.environ.get("STRIPE_PRICE_FREE", "price_free"),
            "pro": os.environ.get("STRIPE_PRICE_PRO", "price_pro"),
            "enterprise": os.environ.get("STRIPE_PRICE_ENTERPRISE", "price_enterprise")
        }

        # Portal configuration
        self.portal_config_id = os.environ.get("STRIPE_PORTAL_CONFIG_ID")

        # Webhook secret for signature verification
        self.webhook_secret = os.environ.get("STRIPE_WEBHOOK_SECRET")

    def create_customer(
        self,
        email: str,
        name: str,
        metadata: Optional[Dict[str, str]] = None
    ) -> stripe.Customer:
        """
        Create a new Stripe customer.

        Args:
            email: Customer email address
            name: Customer/tenant name
            metadata: Additional metadata (tenant_id, etc.)

        Returns:
            Stripe Customer object
        """
        return stripe.Customer.create(
            email=email,
            name=name,
            metadata=metadata or {}
        )

    def get_customer(self, customer_id: str) -> Optional[stripe.Customer]:
        """Retrieve a Stripe customer by ID."""
        try:
            return stripe.Customer.retrieve(customer_id)
        except stripe.error.InvalidRequestError:
            return None

    def update_customer(
        self,
        customer_id: str,
        **kwargs
    ) -> stripe.Customer:
        """Update a Stripe customer."""
        return stripe.Customer.modify(customer_id, **kwargs)

    def delete_customer(self, customer_id: str) -> stripe.Customer:
        """Delete (archive) a Stripe customer."""
        return stripe.Customer.delete(customer_id)

    def create_checkout_session(
        self,
        customer_id: str,
        price_id: str,
        success_url: str,
        cancel_url: str,
        metadata: Optional[Dict[str, str]] = None
    ) -> stripe.checkout.Session:
        """
        Create a Stripe Checkout session for subscription.

        Args:
            customer_id: Stripe customer ID
            price_id: Stripe price ID for the subscription tier
            success_url: URL to redirect on successful checkout
            cancel_url: URL to redirect on cancelled checkout
            metadata: Additional metadata

        Returns:
            Checkout Session with URL for redirect
        """
        return stripe.checkout.Session.create(
            customer=customer_id,
            payment_method_types=["card"],
            line_items=[{
                "price": price_id,
                "quantity": 1
            }],
            mode="subscription",
            success_url=success_url,
            cancel_url=cancel_url,
            metadata=metadata or {}
        )

    def create_portal_session(
        self,
        customer_id: str,
        return_url: str
    ) -> stripe.billing_portal.Session:
        """
        Create a Stripe Customer Portal session.

        Allows customers to manage their subscription, update payment methods,
        view invoices, etc.

        Args:
            customer_id: Stripe customer ID
            return_url: URL to return to after portal session

        Returns:
            Portal Session with URL for redirect
        """
        params = {
            "customer": customer_id,
            "return_url": return_url
        }
        if self.portal_config_id:
            params["configuration"] = self.portal_config_id

        return stripe.billing_portal.Session.create(**params)

    def get_subscription(self, subscription_id: str) -> Optional[stripe.Subscription]:
        """Retrieve a subscription by ID."""
        try:
            return stripe.Subscription.retrieve(subscription_id)
        except stripe.error.InvalidRequestError:
            return None

    def list_customer_subscriptions(
        self,
        customer_id: str,
        status: Optional[str] = None
    ) -> list:
        """List all subscriptions for a customer."""
        params = {"customer": customer_id, "limit": 10}
        if status:
            params["status"] = status
        return list(stripe.Subscription.list(**params))

    def cancel_subscription(
        self,
        subscription_id: str,
        at_period_end: bool = True
    ) -> stripe.Subscription:
        """
        Cancel a subscription.

        Args:
            subscription_id: Stripe subscription ID
            at_period_end: If True, cancel at end of billing period

        Returns:
            Updated Subscription object
        """
        if at_period_end:
            return stripe.Subscription.modify(
                subscription_id,
                cancel_at_period_end=True
            )
        else:
            return stripe.Subscription.delete(subscription_id)

    def construct_webhook_event(
        self,
        payload: bytes,
        sig_header: str
    ) -> stripe.Event:
        """
        Construct and verify a webhook event.

        Args:
            payload: Raw request body bytes
            sig_header: Stripe-Signature header value

        Returns:
            Verified Stripe Event object

        Raises:
            stripe.error.SignatureVerificationError: If signature is invalid
        """
        if not self.webhook_secret:
            raise ValueError("STRIPE_WEBHOOK_SECRET not configured")

        return stripe.Webhook.construct_event(
            payload,
            sig_header,
            self.webhook_secret
        )

    def get_price_for_tier(self, tier: str) -> str:
        """Get the Stripe price ID for a subscription tier."""
        tier_lower = tier.lower()
        if tier_lower not in self.prices:
            raise ValueError(f"Unknown tier: {tier}. Valid tiers: {list(self.prices.keys())}")
        return self.prices[tier_lower]
