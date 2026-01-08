"""
Billing service for Outpost multi-tenant SaaS.

High-level billing operations that coordinate between Stripe, DynamoDB, and audit logging.
"""
import os
import boto3
from datetime import datetime
from typing import Optional, Dict, Any, List
from enum import Enum

from src.outpost.services.stripe_client import StripeClient
from src.outpost.services.audit import AuditService
from src.outpost.models import Tenant, TenantStatus


class SubscriptionTier(str, Enum):
    FREE = "free"
    PRO = "pro"
    ENTERPRISE = "enterprise"


class SubscriptionStatus(str, Enum):
    ACTIVE = "active"
    PAST_DUE = "past_due"
    CANCELED = "canceled"
    INCOMPLETE = "incomplete"
    TRIALING = "trialing"
    UNPAID = "unpaid"


class BillingService:
    """
    High-level billing operations for tenant subscription management.

    Coordinates:
    - Stripe API calls (via StripeClient)
    - DynamoDB tenant record updates
    - Audit trail logging
    """

    def __init__(
        self,
        stripe_client: Optional[StripeClient] = None,
        audit_service: Optional[AuditService] = None
    ):
        self.stripe = stripe_client or StripeClient()
        self.audit = audit_service or AuditService()

        self.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        self.tenants_table_name = os.environ.get("TENANTS_TABLE", "outpost-tenants-prod")
        self.tenants_table = self.dynamodb.Table(self.tenants_table_name)

        # URLs for checkout redirects
        self.app_url = os.environ.get("APP_URL", "https://outpost.zeroechelon.com")

    def create_customer_for_tenant(self, tenant: Tenant) -> str:
        """
        Create a Stripe customer for a tenant and update the tenant record.

        Args:
            tenant: Tenant model instance

        Returns:
            Stripe customer ID
        """
        # Create Stripe customer
        customer = self.stripe.create_customer(
            email=tenant.email,
            name=tenant.name,
            metadata={
                "tenant_id": tenant.tenant_id,
                "created_via": "outpost_billing_service"
            }
        )

        # Update tenant record with Stripe customer ID
        self.tenants_table.update_item(
            Key={"tenant_id": tenant.tenant_id},
            UpdateExpression="SET stripe_customer_id = :cid, updated_at = :ts",
            ExpressionAttributeValues={
                ":cid": customer.id,
                ":ts": datetime.utcnow().isoformat()
            }
        )

        # Audit log
        self.audit.log_action(
            tenant_id=tenant.tenant_id,
            action="CREATE_STRIPE_CUSTOMER",
            resource=customer.id,
            metadata={"email": tenant.email}
        )

        return customer.id

    def create_checkout_session(
        self,
        tenant_id: str,
        tier: SubscriptionTier,
        success_path: str = "/billing/success",
        cancel_path: str = "/billing/cancel"
    ) -> Dict[str, str]:
        """
        Create a Stripe Checkout session for subscription upgrade.

        Args:
            tenant_id: Outpost tenant ID
            tier: Subscription tier to subscribe to
            success_path: Path to redirect on success
            cancel_path: Path to redirect on cancel

        Returns:
            Dict with 'session_id' and 'url' for redirect
        """
        # Get tenant and Stripe customer ID
        tenant_data = self._get_tenant(tenant_id)
        if not tenant_data:
            raise ValueError(f"Tenant not found: {tenant_id}")

        stripe_customer_id = tenant_data.get("stripe_customer_id")
        if not stripe_customer_id:
            # Auto-create Stripe customer if not exists
            tenant = Tenant(**tenant_data)
            stripe_customer_id = self.create_customer_for_tenant(tenant)

        # Get price ID for tier
        price_id = self.stripe.get_price_for_tier(tier.value)

        # Create checkout session
        session = self.stripe.create_checkout_session(
            customer_id=stripe_customer_id,
            price_id=price_id,
            success_url=f"{self.app_url}{success_path}?session_id={{CHECKOUT_SESSION_ID}}",
            cancel_url=f"{self.app_url}{cancel_path}",
            metadata={
                "tenant_id": tenant_id,
                "tier": tier.value
            }
        )

        # Audit log
        self.audit.log_action(
            tenant_id=tenant_id,
            action="CREATE_CHECKOUT_SESSION",
            resource=session.id,
            metadata={"tier": tier.value, "price_id": price_id}
        )

        return {
            "session_id": session.id,
            "url": session.url
        }

    def create_portal_session(self, tenant_id: str) -> Dict[str, str]:
        """
        Create a Stripe Customer Portal session.

        Args:
            tenant_id: Outpost tenant ID

        Returns:
            Dict with 'url' for redirect
        """
        tenant_data = self._get_tenant(tenant_id)
        if not tenant_data:
            raise ValueError(f"Tenant not found: {tenant_id}")

        stripe_customer_id = tenant_data.get("stripe_customer_id")
        if not stripe_customer_id:
            raise ValueError(f"Tenant {tenant_id} has no Stripe customer")

        session = self.stripe.create_portal_session(
            customer_id=stripe_customer_id,
            return_url=f"{self.app_url}/dashboard"
        )

        # Audit log
        self.audit.log_action(
            tenant_id=tenant_id,
            action="CREATE_PORTAL_SESSION",
            resource=session.id
        )

        return {"url": session.url}

    def handle_subscription_update(
        self,
        stripe_customer_id: str,
        subscription_id: str,
        status: str,
        current_period_end: Optional[int] = None
    ) -> None:
        """
        Handle subscription status update from Stripe webhook.

        Args:
            stripe_customer_id: Stripe customer ID
            subscription_id: Stripe subscription ID
            status: New subscription status
            current_period_end: Unix timestamp of period end
        """
        # Find tenant by Stripe customer ID
        tenant_data = self._get_tenant_by_stripe_id(stripe_customer_id)
        if not tenant_data:
            # Log but don't fail - might be a customer we don't track
            print(f"Warning: No tenant found for Stripe customer {stripe_customer_id}")
            return

        tenant_id = tenant_data["tenant_id"]

        # Map Stripe status to tenant status
        tenant_status = TenantStatus.ACTIVE
        if status in ["canceled", "unpaid"]:
            tenant_status = TenantStatus.SUSPENDED

        # Update tenant record
        update_expr = "SET subscription_status = :ss, subscription_id = :sid, updated_at = :ts"
        expr_values = {
            ":ss": status,
            ":sid": subscription_id,
            ":ts": datetime.utcnow().isoformat()
        }

        if current_period_end:
            update_expr += ", subscription_period_end = :pe"
            expr_values[":pe"] = current_period_end

        if tenant_data.get("status") != tenant_status.value:
            update_expr += ", #st = :status"
            expr_values[":status"] = tenant_status.value

        self.tenants_table.update_item(
            Key={"tenant_id": tenant_id},
            UpdateExpression=update_expr,
            ExpressionAttributeValues=expr_values,
            ExpressionAttributeNames={"#st": "status"} if "status" in update_expr else {}
        )

        # Audit log
        self.audit.log_action(
            tenant_id=tenant_id,
            action="SUBSCRIPTION_STATUS_UPDATE",
            resource=subscription_id,
            metadata={"status": status, "stripe_customer_id": stripe_customer_id}
        )

    def handle_payment_success(
        self,
        stripe_customer_id: str,
        invoice_id: str,
        amount_paid: int,
        currency: str
    ) -> None:
        """
        Handle successful payment from Stripe webhook.

        Args:
            stripe_customer_id: Stripe customer ID
            invoice_id: Stripe invoice ID
            amount_paid: Amount paid in cents
            currency: Currency code (e.g., 'usd')
        """
        tenant_data = self._get_tenant_by_stripe_id(stripe_customer_id)
        if not tenant_data:
            return

        tenant_id = tenant_data["tenant_id"]

        # Update tenant - ensure active status
        self.tenants_table.update_item(
            Key={"tenant_id": tenant_id},
            UpdateExpression="SET #st = :active, last_payment_at = :ts, updated_at = :ts",
            ExpressionAttributeValues={
                ":active": TenantStatus.ACTIVE.value,
                ":ts": datetime.utcnow().isoformat()
            },
            ExpressionAttributeNames={"#st": "status"}
        )

        # Audit log
        self.audit.log_action(
            tenant_id=tenant_id,
            action="PAYMENT_SUCCESS",
            resource=invoice_id,
            metadata={
                "amount": amount_paid,
                "currency": currency,
                "stripe_customer_id": stripe_customer_id
            }
        )

    def handle_payment_failure(
        self,
        stripe_customer_id: str,
        invoice_id: str,
        attempt_count: int
    ) -> None:
        """
        Handle failed payment from Stripe webhook.

        Args:
            stripe_customer_id: Stripe customer ID
            invoice_id: Stripe invoice ID
            attempt_count: Number of payment attempts
        """
        tenant_data = self._get_tenant_by_stripe_id(stripe_customer_id)
        if not tenant_data:
            return

        tenant_id = tenant_data["tenant_id"]

        # Audit log (don't change status yet - Stripe will send subscription.past_due)
        self.audit.log_action(
            tenant_id=tenant_id,
            action="PAYMENT_FAILED",
            resource=invoice_id,
            metadata={
                "attempt_count": attempt_count,
                "stripe_customer_id": stripe_customer_id
            }
        )

    def get_subscription_status(self, tenant_id: str) -> Dict[str, Any]:
        """
        Get current subscription status for a tenant.

        Returns:
            Dict with subscription details
        """
        tenant_data = self._get_tenant(tenant_id)
        if not tenant_data:
            raise ValueError(f"Tenant not found: {tenant_id}")

        return {
            "tenant_id": tenant_id,
            "subscription_status": tenant_data.get("subscription_status", "none"),
            "subscription_id": tenant_data.get("subscription_id"),
            "subscription_period_end": tenant_data.get("subscription_period_end"),
            "stripe_customer_id": tenant_data.get("stripe_customer_id")
        }

    def _get_tenant(self, tenant_id: str) -> Optional[Dict[str, Any]]:
        """Get tenant record by tenant_id."""
        response = self.tenants_table.get_item(Key={"tenant_id": tenant_id})
        return response.get("Item")

    def _get_tenant_by_stripe_id(self, stripe_customer_id: str) -> Optional[Dict[str, Any]]:
        """Get tenant record by Stripe customer ID (via GSI)."""
        # Assumes GSI: stripe_customer_id-index
        try:
            response = self.tenants_table.query(
                IndexName="stripe_customer_id-index",
                KeyConditionExpression=boto3.dynamodb.conditions.Key("stripe_customer_id").eq(stripe_customer_id),
                Limit=1
            )
            items = response.get("Items", [])
            return items[0] if items else None
        except Exception as e:
            print(f"Error querying tenant by Stripe ID: {e}")
            return None
