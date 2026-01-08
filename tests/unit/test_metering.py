"""
Unit tests for MeteringService.
"""
import unittest
import os
from moto import mock_aws
import boto3
from datetime import datetime, timezone

from src.outpost.services.metering import MeteringService, TierQuota, QuotaExceededError


@mock_aws
class TestMeteringService(unittest.TestCase):
    """Tests for usage metering service."""

    def setUp(self):
        self.region = "us-east-1"
        self.tenants_table_name = "outpost-tenants-prod"
        self.usage_table_name = "outpost-usage-prod"

        os.environ["TENANTS_TABLE"] = self.tenants_table_name
        os.environ["USAGE_TABLE"] = self.usage_table_name
        os.environ["STRIPE_METERING_ENABLED"] = "false"

        self.dynamodb = boto3.resource("dynamodb", region_name=self.region)

        # Tenants table
        self.tenants_table = self.dynamodb.create_table(
            TableName=self.tenants_table_name,
            KeySchema=[{"AttributeName": "tenant_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "tenant_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST"
        )

        # Usage table
        self.usage_table = self.dynamodb.create_table(
            TableName=self.usage_table_name,
            KeySchema=[{"AttributeName": "period_key", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "period_key", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST"
        )

        # Seed a free tier tenant
        self.tenants_table.put_item(Item={
            "tenant_id": "ten_free",
            "name": "Free Tenant",
            "email": "free@example.com",
            "subscription_tier": "free",
            "status": "active"
        })

        # Seed a pro tier tenant
        self.tenants_table.put_item(Item={
            "tenant_id": "ten_pro",
            "name": "Pro Tenant",
            "email": "pro@example.com",
            "subscription_tier": "pro",
            "status": "active"
        })

        self.service = MeteringService()

    def test_tier_quotas(self):
        """Verify tier quota values."""
        self.assertEqual(TierQuota.FREE.value, 10)
        self.assertEqual(TierQuota.PRO.value, 100)
        self.assertEqual(TierQuota.ENTERPRISE.value, 999999)

    def test_record_job_usage_first_job(self):
        """Test recording first job for a tenant."""
        result = self.service.record_job_usage("ten_free", "job_001")

        self.assertEqual(result["tenant_id"], "ten_free")
        self.assertEqual(result["count"], 1)
        self.assertEqual(result["quota"], 10)
        self.assertEqual(result["remaining"], 9)
        self.assertIsNone(result["warning"])

    def test_record_job_usage_increments(self):
        """Test that usage increments correctly."""
        self.service.record_job_usage("ten_free", "job_001")
        self.service.record_job_usage("ten_free", "job_002")
        result = self.service.record_job_usage("ten_free", "job_003")

        self.assertEqual(result["count"], 3)
        self.assertEqual(result["remaining"], 7)

    def test_quota_warning_at_80_percent(self):
        """Test warning when usage reaches 80%."""
        # Free tier has 10 jobs. 8 jobs = 80%
        for i in range(8):
            result = self.service.record_job_usage("ten_free", f"job_{i}")

        self.assertEqual(result["warning"], "QUOTA_WARNING_80")
        self.assertEqual(result["usage_percent"], 80.0)

    def test_quota_reached_at_100_percent(self):
        """Test warning when quota is exactly reached."""
        # Use all 10 jobs
        for i in range(10):
            result = self.service.record_job_usage("ten_free", f"job_{i}")

        self.assertEqual(result["warning"], "QUOTA_REACHED")
        self.assertEqual(result["remaining"], 0)

    def test_quota_exceeded_raises_error(self):
        """Test that exceeding quota raises QuotaExceededError."""
        # Use all 10 jobs
        for i in range(10):
            self.service.record_job_usage("ten_free", f"job_{i}")

        # 11th job should fail
        with self.assertRaises(QuotaExceededError) as ctx:
            self.service.record_job_usage("ten_free", "job_overflow")

        self.assertIn("Quota exceeded", str(ctx.exception))
        self.assertIn("Limit: 10", str(ctx.exception))

    def test_pro_tier_has_higher_quota(self):
        """Test that pro tier has 100 job quota."""
        result = self.service.record_job_usage("ten_pro", "job_001")

        self.assertEqual(result["quota"], 100)
        self.assertEqual(result["remaining"], 99)

    def test_get_usage(self):
        """Test retrieving usage statistics."""
        self.service.record_job_usage("ten_free", "job_001")
        self.service.record_job_usage("ten_free", "job_002")

        usage = self.service.get_usage("ten_free")

        self.assertEqual(usage["count"], 2)
        self.assertEqual(usage["tier"], "free")
        self.assertEqual(usage["quota"], 10)
        self.assertEqual(usage["remaining"], 8)

    def test_get_usage_no_usage(self):
        """Test getting usage for tenant with no recorded usage."""
        usage = self.service.get_usage("ten_pro")

        self.assertEqual(usage["count"], 0)
        self.assertEqual(usage["remaining"], 100)

    def test_check_quota_has_remaining(self):
        """Test quota check when tenant has remaining quota."""
        self.assertTrue(self.service.check_quota("ten_free"))

    def test_check_quota_exhausted(self):
        """Test quota check when quota is exhausted."""
        # Use all 10 jobs
        for i in range(10):
            self.service.record_job_usage("ten_free", f"job_{i}")

        self.assertFalse(self.service.check_quota("ten_free"))

    def test_reset_usage(self):
        """Test resetting usage counter."""
        # Record some usage
        for i in range(5):
            self.service.record_job_usage("ten_free", f"job_{i}")

        # Reset
        self.service.reset_usage("ten_free")

        # Verify reset
        usage = self.service.get_usage("ten_free")
        self.assertEqual(usage["count"], 0)

    def test_tenant_not_found(self):
        """Test recording usage for non-existent tenant."""
        with self.assertRaises(ValueError) as ctx:
            self.service.record_job_usage("ten_nonexistent", "job_001")

        self.assertIn("Tenant not found", str(ctx.exception))

    def test_period_key_format(self):
        """Test that period key uses correct format."""
        now = datetime.now(timezone.utc)
        expected_period = now.strftime("%Y-%m")

        key = self.service.get_current_period_key("ten_free")

        self.assertEqual(key, f"ten_free#{expected_period}")


if __name__ == "__main__":
    unittest.main()
