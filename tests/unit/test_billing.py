"""
Unit tests for BillingService and StripeClient.

Uses moto for DynamoDB mocking and unittest.mock for Stripe API mocking.
"""
import unittest
import os
from unittest.mock import MagicMock, patch, PropertyMock
from moto import mock_aws
import boto3

from src.outpost.services.billing import BillingService, SubscriptionTier, SubscriptionStatus
from src.outpost.services.stripe_client import StripeClient
from src.outpost.models import Tenant, TenantStatus


class TestStripeClient(unittest.TestCase):
    """Tests for low-level Stripe client."""

    def setUp(self):
        os.environ["STRIPE_SECRET_KEY"] = "sk_test_fake"
        os.environ["STRIPE_WEBHOOK_SECRET"] = "whsec_test_fake"
        os.environ["STRIPE_PRICE_FREE"] = "price_free_test"
        os.environ["STRIPE_PRICE_PRO"] = "price_pro_test"
        os.environ["STRIPE_PRICE_ENTERPRISE"] = "price_enterprise_test"

    @patch("stripe.Customer.create")
    def test_create_customer(self, mock_create):
        mock_create.return_value = MagicMock(id="cus_test123")

        client = StripeClient()
        customer = client.create_customer(
            email="test@example.com",
            name="Test Tenant",
            metadata={"tenant_id": "ten_123"}
        )

        self.assertEqual(customer.id, "cus_test123")
        mock_create.assert_called_once_with(
            email="test@example.com",
            name="Test Tenant",
            metadata={"tenant_id": "ten_123"}
        )

    @patch("stripe.Customer.retrieve")
    def test_get_customer(self, mock_retrieve):
        mock_retrieve.return_value = MagicMock(id="cus_test123", email="test@example.com")

        client = StripeClient()
        customer = client.get_customer("cus_test123")

        self.assertEqual(customer.id, "cus_test123")
        mock_retrieve.assert_called_once_with("cus_test123")

    @patch("stripe.checkout.Session.create")
    def test_create_checkout_session(self, mock_create):
        mock_create.return_value = MagicMock(
            id="cs_test123",
            url="https://checkout.stripe.com/pay/cs_test123"
        )

        client = StripeClient()
        session = client.create_checkout_session(
            customer_id="cus_test123",
            price_id="price_pro_test",
            success_url="https://app.example.com/success",
            cancel_url="https://app.example.com/cancel",
            metadata={"tenant_id": "ten_123"}
        )

        self.assertEqual(session.id, "cs_test123")
        self.assertIn("checkout.stripe.com", session.url)

    @patch("stripe.billing_portal.Session.create")
    def test_create_portal_session(self, mock_create):
        mock_create.return_value = MagicMock(
            id="bps_test123",
            url="https://billing.stripe.com/session/bps_test123"
        )

        client = StripeClient()
        session = client.create_portal_session(
            customer_id="cus_test123",
            return_url="https://app.example.com/dashboard"
        )

        self.assertEqual(session.id, "bps_test123")
        self.assertIn("billing.stripe.com", session.url)

    def test_get_price_for_tier(self):
        client = StripeClient()

        self.assertEqual(client.get_price_for_tier("free"), "price_free_test")
        self.assertEqual(client.get_price_for_tier("pro"), "price_pro_test")
        self.assertEqual(client.get_price_for_tier("enterprise"), "price_enterprise_test")
        self.assertEqual(client.get_price_for_tier("PRO"), "price_pro_test")  # Case insensitive

    def test_get_price_for_invalid_tier(self):
        client = StripeClient()

        with self.assertRaises(ValueError) as ctx:
            client.get_price_for_tier("invalid")

        self.assertIn("Unknown tier", str(ctx.exception))


@mock_aws
class TestBillingService(unittest.TestCase):
    """Tests for high-level BillingService."""

    def setUp(self):
        self.region = "us-east-1"
        self.tenants_table_name = "outpost-tenants-prod"
        self.audit_table_name = "outpost-audit-prod"

        os.environ["TENANTS_TABLE"] = self.tenants_table_name
        os.environ["AUDIT_TABLE"] = self.audit_table_name
        os.environ["STRIPE_SECRET_KEY"] = "sk_test_fake"
        os.environ["APP_URL"] = "https://outpost.test.com"

        # Create DynamoDB tables
        self.dynamodb = boto3.resource("dynamodb", region_name=self.region)

        # Tenants table with GSI
        self.tenants_table = self.dynamodb.create_table(
            TableName=self.tenants_table_name,
            KeySchema=[
                {"AttributeName": "tenant_id", "KeyType": "HASH"}
            ],
            AttributeDefinitions=[
                {"AttributeName": "tenant_id", "AttributeType": "S"},
                {"AttributeName": "stripe_customer_id", "AttributeType": "S"}
            ],
            GlobalSecondaryIndexes=[
                {
                    "IndexName": "stripe_customer_id-index",
                    "KeySchema": [
                        {"AttributeName": "stripe_customer_id", "KeyType": "HASH"}
                    ],
                    "Projection": {"ProjectionType": "ALL"}
                }
            ],
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

        # Seed a tenant
        self.tenants_table.put_item(Item={
            "tenant_id": "ten_123",
            "name": "Test Tenant",
            "email": "test@example.com",
            "status": "active"
        })

    @patch.object(StripeClient, "create_customer")
    def test_create_customer_for_tenant(self, mock_create):
        mock_create.return_value = MagicMock(id="cus_new123")

        service = BillingService()
        tenant = Tenant(
            tenant_id="ten_new",
            name="New Tenant",
            email="new@example.com"
        )

        # Add tenant to DB first
        self.tenants_table.put_item(Item={
            "tenant_id": "ten_new",
            "name": "New Tenant",
            "email": "new@example.com",
            "status": "active"
        })

        customer_id = service.create_customer_for_tenant(tenant)

        self.assertEqual(customer_id, "cus_new123")

        # Verify DynamoDB was updated
        response = self.tenants_table.get_item(Key={"tenant_id": "ten_new"})
        self.assertEqual(response["Item"]["stripe_customer_id"], "cus_new123")

    @patch.object(StripeClient, "create_checkout_session")
    @patch.object(StripeClient, "get_price_for_tier")
    def test_create_checkout_session(self, mock_price, mock_checkout):
        mock_price.return_value = "price_pro_test"
        mock_checkout.return_value = MagicMock(
            id="cs_test123",
            url="https://checkout.stripe.com/pay/cs_test123"
        )

        # Add stripe_customer_id to tenant
        self.tenants_table.update_item(
            Key={"tenant_id": "ten_123"},
            UpdateExpression="SET stripe_customer_id = :cid",
            ExpressionAttributeValues={":cid": "cus_existing123"}
        )

        service = BillingService()
        result = service.create_checkout_session(
            tenant_id="ten_123",
            tier=SubscriptionTier.PRO
        )

        self.assertEqual(result["session_id"], "cs_test123")
        self.assertIn("checkout.stripe.com", result["url"])

    @patch.object(StripeClient, "create_portal_session")
    def test_create_portal_session(self, mock_portal):
        mock_portal.return_value = MagicMock(
            id="bps_test123",
            url="https://billing.stripe.com/session/bps_test123"
        )

        # Add stripe_customer_id to tenant
        self.tenants_table.update_item(
            Key={"tenant_id": "ten_123"},
            UpdateExpression="SET stripe_customer_id = :cid",
            ExpressionAttributeValues={":cid": "cus_existing123"}
        )

        service = BillingService()
        result = service.create_portal_session(tenant_id="ten_123")

        self.assertIn("billing.stripe.com", result["url"])

    def test_handle_subscription_update_active(self):
        # Add stripe_customer_id to tenant
        self.tenants_table.update_item(
            Key={"tenant_id": "ten_123"},
            UpdateExpression="SET stripe_customer_id = :cid",
            ExpressionAttributeValues={":cid": "cus_existing123"}
        )

        service = BillingService()
        service.handle_subscription_update(
            stripe_customer_id="cus_existing123",
            subscription_id="sub_abc123",
            status="active",
            current_period_end=1735689600
        )

        # Verify DynamoDB was updated
        response = self.tenants_table.get_item(Key={"tenant_id": "ten_123"})
        item = response["Item"]
        self.assertEqual(item["subscription_status"], "active")
        self.assertEqual(item["subscription_id"], "sub_abc123")

    def test_handle_subscription_update_canceled(self):
        # Add stripe_customer_id to tenant
        self.tenants_table.update_item(
            Key={"tenant_id": "ten_123"},
            UpdateExpression="SET stripe_customer_id = :cid",
            ExpressionAttributeValues={":cid": "cus_existing123"}
        )

        service = BillingService()
        service.handle_subscription_update(
            stripe_customer_id="cus_existing123",
            subscription_id="sub_abc123",
            status="canceled"
        )

        # Verify tenant status was updated to suspended
        response = self.tenants_table.get_item(Key={"tenant_id": "ten_123"})
        item = response["Item"]
        self.assertEqual(item["subscription_status"], "canceled")
        self.assertEqual(item["status"], "suspended")

    def test_get_subscription_status(self):
        # Add subscription details to tenant
        self.tenants_table.update_item(
            Key={"tenant_id": "ten_123"},
            UpdateExpression="SET stripe_customer_id = :cid, subscription_status = :ss, subscription_id = :sid",
            ExpressionAttributeValues={
                ":cid": "cus_existing123",
                ":ss": "active",
                ":sid": "sub_abc123"
            }
        )

        service = BillingService()
        status = service.get_subscription_status("ten_123")

        self.assertEqual(status["tenant_id"], "ten_123")
        self.assertEqual(status["subscription_status"], "active")
        self.assertEqual(status["subscription_id"], "sub_abc123")
        self.assertEqual(status["stripe_customer_id"], "cus_existing123")


if __name__ == "__main__":
    unittest.main()
