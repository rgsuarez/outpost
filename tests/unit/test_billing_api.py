"""
Unit tests for Billing Portal API.
"""
import unittest
import json
import os
from unittest.mock import MagicMock, patch
from moto import mock_aws
import boto3

from src.outpost.functions.api.billing import BillingAPI, handler


@mock_aws
class TestBillingAPI(unittest.TestCase):
    """Tests for BillingAPI class."""

    def setUp(self):
        self.region = "us-east-1"
        self.tenants_table_name = "outpost-tenants-prod"
        self.audit_table_name = "outpost-audit-prod"
        self.usage_table_name = "outpost-usage-prod"

        os.environ["TENANTS_TABLE"] = self.tenants_table_name
        os.environ["AUDIT_TABLE"] = self.audit_table_name
        os.environ["USAGE_TABLE"] = self.usage_table_name
        os.environ["STRIPE_SECRET_KEY"] = "sk_test_fake"
        os.environ["APP_URL"] = "https://outpost.test.com"

        self.dynamodb = boto3.resource("dynamodb", region_name=self.region)

        # Tenants table with GSI
        self.tenants_table = self.dynamodb.create_table(
            TableName=self.tenants_table_name,
            KeySchema=[{"AttributeName": "tenant_id", "KeyType": "HASH"}],
            AttributeDefinitions=[
                {"AttributeName": "tenant_id", "AttributeType": "S"},
                {"AttributeName": "stripe_customer_id", "AttributeType": "S"}
            ],
            GlobalSecondaryIndexes=[{
                "IndexName": "stripe_customer_id-index",
                "KeySchema": [{"AttributeName": "stripe_customer_id", "KeyType": "HASH"}],
                "Projection": {"ProjectionType": "ALL"}
            }],
            BillingMode="PAY_PER_REQUEST"
        )

        # Audit table
        self.audit_table = self.dynamodb.create_table(
            TableName=self.audit_table_name,
            KeySchema=[
                {"AttributeName": "tenant_id", "KeyType": "HASH"},
                {"AttributeName": "timestamp", "KeyType": "RANGE"}
            ],
            AttributeDefinitions=[
                {"AttributeName": "tenant_id", "AttributeType": "S"},
                {"AttributeName": "timestamp", "AttributeType": "S"}
            ],
            BillingMode="PAY_PER_REQUEST"
        )

        # Usage table
        self.usage_table = self.dynamodb.create_table(
            TableName=self.usage_table_name,
            KeySchema=[{"AttributeName": "period_key", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "period_key", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST"
        )

        # Seed tenant
        self.tenants_table.put_item(Item={
            "tenant_id": "ten_123",
            "name": "Test Tenant",
            "email": "test@example.com",
            "stripe_customer_id": "cus_test123",
            "subscription_status": "active",
            "subscription_tier": "pro",
            "status": "active"
        })

    @patch("src.outpost.services.billing.BillingService.create_portal_session")
    def test_get_portal_url(self, mock_portal):
        """Test getting Stripe portal URL."""
        mock_portal.return_value = {"url": "https://billing.stripe.com/session/test"}

        api = BillingAPI()
        result = api.get_portal_url("ten_123")

        self.assertIn("url", result)
        self.assertIn("billing.stripe.com", result["url"])

    def test_get_usage(self):
        """Test getting usage statistics."""
        api = BillingAPI()
        result = api.get_usage("ten_123")

        self.assertEqual(result["tenant_id"], "ten_123")
        self.assertIn("count", result)
        self.assertIn("quota", result)
        self.assertIn("remaining", result)

    def test_get_subscription_status(self):
        """Test getting subscription status."""
        api = BillingAPI()
        result = api.get_subscription_status("ten_123")

        self.assertEqual(result["tenant_id"], "ten_123")
        self.assertEqual(result["subscription_status"], "active")

    @patch("src.outpost.services.billing.BillingService.create_checkout_session")
    def test_create_checkout(self, mock_checkout):
        """Test creating checkout session."""
        mock_checkout.return_value = {
            "session_id": "cs_test123",
            "url": "https://checkout.stripe.com/test"
        }

        api = BillingAPI()
        result = api.create_checkout("ten_123", "pro")

        self.assertEqual(result["session_id"], "cs_test123")
        self.assertIn("checkout.stripe.com", result["url"])

    def test_create_checkout_invalid_tier(self):
        """Test checkout with invalid tier."""
        api = BillingAPI()

        with self.assertRaises(ValueError) as ctx:
            api.create_checkout("ten_123", "invalid_tier")

        self.assertIn("Invalid tier", str(ctx.exception))


class TestLambdaHandler(unittest.TestCase):
    """Tests for Lambda handler function."""

    def test_missing_tenant_context(self):
        """Test that missing tenant returns 401."""
        event = {
            "httpMethod": "GET",
            "path": "/billing/portal",
            "headers": {},
            "requestContext": {}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 401)
        self.assertIn("Unauthorized", response["body"])

    @patch.object(BillingAPI, "get_portal_url")
    def test_get_portal(self, mock_portal):
        """Test GET /billing/portal."""
        mock_portal.return_value = {"url": "https://billing.stripe.com/test"}

        event = {
            "httpMethod": "GET",
            "path": "/billing/portal",
            "headers": {"X-Tenant-ID": "ten_123"},
            "requestContext": {}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertIn("url", body)

    @patch.object(BillingAPI, "get_usage")
    def test_get_usage(self, mock_usage):
        """Test GET /billing/usage."""
        mock_usage.return_value = {
            "tenant_id": "ten_123",
            "count": 5,
            "quota": 100,
            "remaining": 95
        }

        event = {
            "httpMethod": "GET",
            "path": "/billing/usage",
            "headers": {"X-Tenant-ID": "ten_123"},
            "requestContext": {},
            "queryStringParameters": None
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body["count"], 5)

    @patch.object(BillingAPI, "get_subscription_status")
    def test_get_status(self, mock_status):
        """Test GET /billing/status."""
        mock_status.return_value = {
            "tenant_id": "ten_123",
            "subscription_status": "active"
        }

        event = {
            "httpMethod": "GET",
            "path": "/billing/status",
            "headers": {"X-Tenant-ID": "ten_123"},
            "requestContext": {}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body["subscription_status"], "active")

    @patch.object(BillingAPI, "create_checkout")
    def test_post_checkout(self, mock_checkout):
        """Test POST /billing/checkout."""
        mock_checkout.return_value = {
            "session_id": "cs_test",
            "url": "https://checkout.stripe.com/test"
        }

        event = {
            "httpMethod": "POST",
            "path": "/billing/checkout",
            "headers": {"X-Tenant-ID": "ten_123"},
            "body": json.dumps({"tier": "pro"}),
            "requestContext": {}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body["session_id"], "cs_test")

    def test_not_found(self):
        """Test 404 for unknown route."""
        event = {
            "httpMethod": "GET",
            "path": "/billing/unknown",
            "headers": {"X-Tenant-ID": "ten_123"},
            "requestContext": {}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 404)


if __name__ == "__main__":
    unittest.main()
