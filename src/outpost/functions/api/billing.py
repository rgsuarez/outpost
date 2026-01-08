"""
Billing Portal API endpoints for Outpost multi-tenant SaaS.

Provides self-service billing management for tenants:
- GET /billing/portal - Redirect to Stripe Customer Portal
- GET /billing/usage - Get current usage statistics
- POST /billing/checkout - Create checkout session for subscription
"""
import json
import os
from typing import Dict, Any, Optional

from src.outpost.services import BillingService, SubscriptionTier, MeteringService, AuditService


class BillingAPI:
    """
    API handler for billing-related endpoints.

    All endpoints require authentication via API key (tenant context from authorizer).
    """

    def __init__(self):
        self.billing = BillingService()
        self.metering = MeteringService()
        self.audit = AuditService()
        self.app_url = os.environ.get("APP_URL", "https://outpost.zeroechelon.com")

    def get_portal_url(self, tenant_id: str) -> Dict[str, str]:
        """
        Generate Stripe Customer Portal URL for self-service billing management.

        Args:
            tenant_id: Authenticated tenant ID

        Returns:
            Dict with 'url' for redirect to Stripe portal
        """
        result = self.billing.create_portal_session(tenant_id)

        self.audit.log_action(
            tenant_id=tenant_id,
            action="ACCESS_BILLING_PORTAL",
            resource="stripe_portal"
        )

        return result

    def get_usage(self, tenant_id: str, period: Optional[str] = None) -> Dict[str, Any]:
        """
        Get current usage statistics for the tenant.

        Args:
            tenant_id: Authenticated tenant ID
            period: Optional billing period (YYYY-MM)

        Returns:
            Usage statistics dict
        """
        return self.metering.get_usage(tenant_id, period)

    def create_checkout(
        self,
        tenant_id: str,
        tier: str,
        success_path: str = "/billing/success",
        cancel_path: str = "/billing/cancel"
    ) -> Dict[str, str]:
        """
        Create a Stripe Checkout session for subscription upgrade.

        Args:
            tenant_id: Authenticated tenant ID
            tier: Target subscription tier (free, pro, enterprise)
            success_path: Redirect path on success
            cancel_path: Redirect path on cancel

        Returns:
            Dict with 'session_id' and 'url' for checkout redirect
        """
        try:
            subscription_tier = SubscriptionTier(tier.lower())
        except ValueError:
            raise ValueError(f"Invalid tier: {tier}. Valid tiers: free, pro, enterprise")

        return self.billing.create_checkout_session(
            tenant_id=tenant_id,
            tier=subscription_tier,
            success_path=success_path,
            cancel_path=cancel_path
        )

    def get_subscription_status(self, tenant_id: str) -> Dict[str, Any]:
        """
        Get current subscription status for the tenant.

        Args:
            tenant_id: Authenticated tenant ID

        Returns:
            Subscription status dict
        """
        return self.billing.get_subscription_status(tenant_id)


def handler(event, context):
    """
    Lambda handler for billing API endpoints.

    Routes:
    - GET /billing/portal -> Stripe Customer Portal URL
    - GET /billing/usage -> Current usage statistics
    - GET /billing/status -> Subscription status
    - POST /billing/checkout -> Create checkout session
    """
    api = BillingAPI()

    http_method = event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method")
    path = event.get("path") or event.get("rawPath", "")

    # Get tenant_id from authorizer context
    tenant_id = event.get("requestContext", {}).get("authorizer", {}).get("tenant_id")
    if not tenant_id:
        # Fallback for testing
        tenant_id = event.get("headers", {}).get("X-Tenant-ID")

    if not tenant_id:
        return {
            "statusCode": 401,
            "body": json.dumps({"error": "Unauthorized - missing tenant context"})
        }

    try:
        # Route based on path
        if path.endswith("/portal"):
            if http_method == "GET":
                result = api.get_portal_url(tenant_id)
                return {
                    "statusCode": 200,
                    "body": json.dumps(result)
                }

        elif path.endswith("/usage"):
            if http_method == "GET":
                query_params = event.get("queryStringParameters") or {}
                period = query_params.get("period")
                result = api.get_usage(tenant_id, period)
                return {
                    "statusCode": 200,
                    "body": json.dumps(result)
                }

        elif path.endswith("/status"):
            if http_method == "GET":
                result = api.get_subscription_status(tenant_id)
                return {
                    "statusCode": 200,
                    "body": json.dumps(result)
                }

        elif path.endswith("/checkout"):
            if http_method == "POST":
                body = json.loads(event.get("body", "{}"))
                tier = body.get("tier", "pro")
                success_path = body.get("success_path", "/billing/success")
                cancel_path = body.get("cancel_path", "/billing/cancel")

                result = api.create_checkout(
                    tenant_id=tenant_id,
                    tier=tier,
                    success_path=success_path,
                    cancel_path=cancel_path
                )
                return {
                    "statusCode": 200,
                    "body": json.dumps(result)
                }

        # No matching route
        return {
            "statusCode": 404,
            "body": json.dumps({"error": "Not found"})
        }

    except ValueError as e:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": str(e)})
        }
    except Exception as e:
        print(f"Billing API error: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Internal server error"})
        }
