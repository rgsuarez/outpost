"""
Unit tests for Stripe webhook handler.
"""
import unittest
import json
import os
from unittest.mock import MagicMock, patch
from moto import mock_aws
import boto3

from src.outpost.functions.api.webhooks import WebhookHandler, handler


@mock_aws
class TestWebhookHandler(unittest.TestCase):
    """Tests for webhook event processing."""

    def setUp(self):
        self.region = "us-east-1"
        self.tenants_table_name = "outpost-tenants-prod"
        self.audit_table_name = "outpost-audit-prod"

        os.environ["TENANTS_TABLE"] = self.tenants_table_name
        os.environ["AUDIT_TABLE"] = self.audit_table_name
        os.environ["STRIPE_SECRET_KEY"] = "sk_test_fake"
        os.environ["STRIPE_WEBHOOK_SECRET"] = "whsec_test_fake"

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

        # Seed a tenant
        self.tenants_table.put_item(Item={
            "tenant_id": "ten_123",
            "name": "Test Tenant",
            "email": "test@example.com",
            "stripe_customer_id": "cus_test123",
            "status": "active"
        })

    def test_process_subscription_created(self):
        """Test processing subscription.created event."""
        webhook = WebhookHandler()

        event = {
            "id": "evt_test_sub_created",
            "type": "customer.subscription.created",
            "data": {
                "object": {
                    "id": "sub_abc123",
                    "customer": "cus_test123",
                    "status": "active",
                    "current_period_end": 1735689600
                }
            }
        }

        result = webhook.process_event(event)

        self.assertEqual(result["status"], "processed")
        self.assertEqual(result["event_type"], "customer.subscription.created")

        # Verify tenant was updated
        response = self.tenants_table.get_item(Key={"tenant_id": "ten_123"})
        item = response["Item"]
        self.assertEqual(item["subscription_status"], "active")
        self.assertEqual(item["subscription_id"], "sub_abc123")

    def test_process_subscription_canceled(self):
        """Test processing subscription.deleted event."""
        webhook = WebhookHandler()

        event = {
            "id": "evt_test_sub_deleted",
            "type": "customer.subscription.deleted",
            "data": {
                "object": {
                    "id": "sub_abc123",
                    "customer": "cus_test123"
                }
            }
        }

        result = webhook.process_event(event)

        self.assertEqual(result["status"], "processed")

        # Verify tenant status changed to suspended
        response = self.tenants_table.get_item(Key={"tenant_id": "ten_123"})
        item = response["Item"]
        self.assertEqual(item["subscription_status"], "canceled")
        self.assertEqual(item["status"], "suspended")

    def test_process_payment_succeeded(self):
        """Test processing invoice.payment_succeeded event."""
        webhook = WebhookHandler()

        event = {
            "id": "evt_test_payment",
            "type": "invoice.payment_succeeded",
            "data": {
                "object": {
                    "id": "in_abc123",
                    "customer": "cus_test123",
                    "amount_paid": 2900,
                    "currency": "usd"
                }
            }
        }

        result = webhook.process_event(event)

        self.assertEqual(result["status"], "processed")

        # Verify audit entry was created
        response = self.audit_table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key("tenant_id").eq("ten_123")
        )
        items = response.get("Items", [])
        self.assertTrue(any(item["action"] == "PAYMENT_SUCCESS" for item in items))

    def test_idempotency_duplicate_event(self):
        """Test that duplicate events are skipped."""
        webhook = WebhookHandler()

        event = {
            "id": "evt_duplicate_test",
            "type": "customer.subscription.updated",
            "data": {
                "object": {
                    "id": "sub_abc123",
                    "customer": "cus_test123",
                    "status": "active"
                }
            }
        }

        # Process first time
        result1 = webhook.process_event(event)
        self.assertEqual(result1["status"], "processed")

        # Process second time (duplicate)
        result2 = webhook.process_event(event)
        self.assertEqual(result2["status"], "skipped")
        self.assertEqual(result2["reason"], "duplicate_event")

    def test_unhandled_event_type(self):
        """Test that unhandled event types are ignored gracefully."""
        webhook = WebhookHandler()

        event = {
            "id": "evt_unhandled",
            "type": "some.unknown.event",
            "data": {"object": {}}
        }

        result = webhook.process_event(event)

        self.assertEqual(result["status"], "ignored")
        self.assertEqual(result["reason"], "unhandled_event_type")

    def test_checkout_completed(self):
        """Test processing checkout.session.completed event."""
        webhook = WebhookHandler()

        event = {
            "id": "evt_checkout",
            "type": "checkout.session.completed",
            "data": {
                "object": {
                    "id": "cs_test123",
                    "customer": "cus_test123",
                    "subscription": "sub_new123",
                    "metadata": {"tenant_id": "ten_123"}
                }
            }
        }

        result = webhook.process_event(event)

        self.assertEqual(result["status"], "processed")
        self.assertEqual(result["result"]["action"], "checkout_completed")


class TestLambdaHandler(unittest.TestCase):
    """Tests for Lambda handler function."""

    def test_missing_signature_header(self):
        """Test that missing signature returns 400."""
        event = {
            "body": "{}",
            "headers": {}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("Missing Stripe-Signature", response["body"])

    @patch.object(WebhookHandler, "verify_and_construct_event")
    def test_invalid_signature(self, mock_verify):
        """Test that invalid signature returns 400."""
        mock_verify.return_value = None

        event = {
            "body": "{}",
            "headers": {"Stripe-Signature": "invalid_sig"}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 400)
        self.assertIn("verification failed", response["body"])

    @patch.object(WebhookHandler, "verify_and_construct_event")
    @patch.object(WebhookHandler, "process_event")
    def test_successful_processing(self, mock_process, mock_verify):
        """Test successful webhook processing."""
        mock_verify.return_value = {"id": "evt_test", "type": "test"}
        mock_process.return_value = {"status": "processed"}

        event = {
            "body": "{}",
            "headers": {"Stripe-Signature": "valid_sig"}
        }

        response = handler(event, None)

        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body["status"], "processed")


if __name__ == "__main__":
    unittest.main()
