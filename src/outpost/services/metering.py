"""
Usage metering service for Outpost multi-tenant SaaS.

Tracks job usage per tenant, enforces tier quotas, and reports to Stripe for billing.
"""
import os
import boto3
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from enum import Enum
from boto3.dynamodb.conditions import Key


class TierQuota(int, Enum):
    """Job quotas per billing period by subscription tier."""
    FREE = 10
    PRO = 100
    ENTERPRISE = 999999  # Effectively unlimited


class QuotaExceededError(Exception):
    """Raised when tenant exceeds their tier quota."""
    pass


class MeteringService:
    """
    Tracks and enforces usage quotas for tenant job submissions.

    Features:
    - Atomic counter increments in DynamoDB
    - Tier-based quota enforcement
    - Billing cycle reset support
    - Threshold alerting (80%, 100%)
    - Optional Stripe metered billing integration
    """

    def __init__(self):
        self.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        self.tenants_table_name = os.environ.get("TENANTS_TABLE", "outpost-tenants-prod")
        self.usage_table_name = os.environ.get("USAGE_TABLE", "outpost-usage-prod")
        self.tenants_table = self.dynamodb.Table(self.tenants_table_name)
        self.usage_table = self.dynamodb.Table(self.usage_table_name)

        # Stripe metered billing (optional)
        self.stripe_metering_enabled = os.environ.get("STRIPE_METERING_ENABLED", "false").lower() == "true"
        if self.stripe_metering_enabled:
            import stripe
            stripe.api_key = os.environ.get("STRIPE_SECRET_KEY")
            self.stripe = stripe
        else:
            self.stripe = None

    def get_current_period_key(self, tenant_id: str) -> str:
        """
        Generate the usage period key for the current billing cycle.

        Format: {tenant_id}#{YYYY-MM}
        """
        now = datetime.now(timezone.utc)
        return f"{tenant_id}#{now.strftime('%Y-%m')}"

    def record_job_usage(self, tenant_id: str, job_id: str) -> Dict[str, Any]:
        """
        Record a job execution and check quota.

        Args:
            tenant_id: Tenant identifier
            job_id: Job identifier (for audit)

        Returns:
            Dict with usage info: count, quota, remaining, warning

        Raises:
            QuotaExceededError: If tenant has exceeded their quota
        """
        # Get tenant tier
        tenant = self._get_tenant(tenant_id)
        if not tenant:
            raise ValueError(f"Tenant not found: {tenant_id}")

        tier = tenant.get("subscription_tier", "free").upper()
        quota = TierQuota[tier].value

        # Atomic increment in usage table
        period_key = self.get_current_period_key(tenant_id)

        try:
            response = self.usage_table.update_item(
                Key={"period_key": period_key},
                UpdateExpression="SET job_count = if_not_exists(job_count, :zero) + :inc, "
                                 "tenant_id = :tid, "
                                 "updated_at = :ts",
                ExpressionAttributeValues={
                    ":zero": 0,
                    ":inc": 1,
                    ":tid": tenant_id,
                    ":ts": datetime.now(timezone.utc).isoformat()
                },
                ReturnValues="UPDATED_NEW"
            )
            new_count = int(response["Attributes"]["job_count"])
        except Exception as e:
            raise RuntimeError(f"Failed to record usage: {e}")

        # Check quota
        remaining = max(0, quota - new_count)
        warning = None

        if new_count > quota:
            # Rollback the increment (best effort)
            self._decrement_usage(period_key)
            raise QuotaExceededError(
                f"Quota exceeded for tenant {tenant_id}. "
                f"Tier: {tier}, Limit: {quota}, Used: {new_count - 1}"
            )

        # Threshold warnings
        usage_percent = (new_count / quota) * 100 if quota > 0 else 100
        if usage_percent >= 100:
            warning = "QUOTA_REACHED"
        elif usage_percent >= 80:
            warning = "QUOTA_WARNING_80"

        # Report to Stripe metered billing (if enabled)
        if self.stripe_metering_enabled:
            self._report_to_stripe(tenant_id, tenant.get("stripe_subscription_item_id"))

        return {
            "tenant_id": tenant_id,
            "job_id": job_id,
            "period": period_key.split("#")[1],
            "count": new_count,
            "quota": quota,
            "remaining": remaining,
            "usage_percent": round(usage_percent, 1),
            "warning": warning
        }

    def get_usage(self, tenant_id: str, period: Optional[str] = None) -> Dict[str, Any]:
        """
        Get usage statistics for a tenant.

        Args:
            tenant_id: Tenant identifier
            period: Optional period (YYYY-MM). Defaults to current.

        Returns:
            Usage statistics dict
        """
        if period:
            period_key = f"{tenant_id}#{period}"
        else:
            period_key = self.get_current_period_key(tenant_id)

        tenant = self._get_tenant(tenant_id)
        tier = tenant.get("subscription_tier", "free").upper() if tenant else "FREE"
        quota = TierQuota[tier].value

        try:
            response = self.usage_table.get_item(Key={"period_key": period_key})
            item = response.get("Item", {})
            count = int(item.get("job_count", 0))
        except Exception:
            count = 0

        return {
            "tenant_id": tenant_id,
            "period": period_key.split("#")[1],
            "tier": tier.lower(),
            "count": count,
            "quota": quota,
            "remaining": max(0, quota - count),
            "usage_percent": round((count / quota) * 100, 1) if quota > 0 else 0
        }

    def check_quota(self, tenant_id: str) -> bool:
        """
        Check if tenant has remaining quota.

        Args:
            tenant_id: Tenant identifier

        Returns:
            True if tenant can submit jobs, False otherwise
        """
        usage = self.get_usage(tenant_id)
        return usage["remaining"] > 0

    def reset_usage(self, tenant_id: str, period: Optional[str] = None) -> None:
        """
        Reset usage counter (admin operation).

        Typically called at billing cycle anchor or for manual resets.

        Args:
            tenant_id: Tenant identifier
            period: Optional period. Defaults to current.
        """
        if period:
            period_key = f"{tenant_id}#{period}"
        else:
            period_key = self.get_current_period_key(tenant_id)

        self.usage_table.update_item(
            Key={"period_key": period_key},
            UpdateExpression="SET job_count = :zero, reset_at = :ts",
            ExpressionAttributeValues={
                ":zero": 0,
                ":ts": datetime.now(timezone.utc).isoformat()
            }
        )

    def get_usage_history(self, tenant_id: str, limit: int = 12) -> list:
        """
        Get historical usage across billing periods.

        Args:
            tenant_id: Tenant identifier
            limit: Number of periods to return

        Returns:
            List of usage records, newest first
        """
        try:
            # Query by tenant_id prefix using begins_with
            response = self.usage_table.query(
                KeyConditionExpression=Key("period_key").begins_with(f"{tenant_id}#"),
                ScanIndexForward=False,
                Limit=limit
            )
            return response.get("Items", [])
        except Exception:
            return []

    def _get_tenant(self, tenant_id: str) -> Optional[Dict[str, Any]]:
        """Get tenant record."""
        try:
            response = self.tenants_table.get_item(Key={"tenant_id": tenant_id})
            return response.get("Item")
        except Exception:
            return None

    def _decrement_usage(self, period_key: str) -> None:
        """Rollback a usage increment (best effort)."""
        try:
            self.usage_table.update_item(
                Key={"period_key": period_key},
                UpdateExpression="SET job_count = job_count - :dec",
                ConditionExpression="job_count > :zero",
                ExpressionAttributeValues={":dec": 1, ":zero": 0}
            )
        except Exception:
            pass  # Best effort rollback

    def _report_to_stripe(self, tenant_id: str, subscription_item_id: Optional[str]) -> None:
        """Report metered usage to Stripe (if subscription item ID is set)."""
        if not self.stripe or not subscription_item_id:
            return

        try:
            self.stripe.SubscriptionItem.create_usage_record(
                subscription_item_id,
                quantity=1,
                timestamp=int(datetime.now(timezone.utc).timestamp()),
                action="increment"
            )
        except Exception as e:
            # Log but don't fail - usage is already recorded locally
            print(f"Failed to report usage to Stripe: {e}")
