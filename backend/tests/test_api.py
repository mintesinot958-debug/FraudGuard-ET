import os
import tempfile
import unittest
import asyncio
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

_test_directory = tempfile.TemporaryDirectory()
os.environ["DATABASE_URL"] = f"sqlite:///{Path(_test_directory.name, 'test.db').as_posix()}"
os.environ["JWT_SECRET"] = "test-only-secret-with-more-than-32-characters"
os.environ["ADMIN_EMAILS"] = "admin@example.com"

from fastapi.testclient import TestClient

from app.database import engine
from app.main import app


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.client = TestClient(app)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.client.close()
        engine.dispose()
        _test_directory.cleanup()

    def register(self, email: str, password: str = "safe-password-123") -> str:
        response = self.client.post(
            "/auth/register", json={"email": email, "password": password}
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["access_token"]

    def test_ai_uses_groq_when_configured(self) -> None:
        from app.main import _get_ai_response

        with (
            patch("app.main.settings", SimpleNamespace(groq_api_key="test-key")),
            patch(
                "app.main._ask_groq",
                new_callable=AsyncMock,
                return_value="Stay safe.",
            ) as ask_groq,
        ):
            response = asyncio.run(_get_ai_response("Check a payment"))

        self.assertEqual(response, "Stay safe.")
        ask_groq.assert_awaited_once_with("Check a payment")

    def test_ai_requires_a_groq_key(self) -> None:
        from fastapi import HTTPException
        from app.main import _get_ai_response

        with (
            patch("app.main.settings", SimpleNamespace(groq_api_key=None)),
            patch("app.main._ask_groq", new_callable=AsyncMock) as ask_groq,
            self.assertRaises(HTTPException) as raised,
        ):
            asyncio.run(_get_ai_response("Check a payment"))

        self.assertEqual(raised.exception.status_code, 503)
        self.assertIn("GROQ_API_KEY", raised.exception.detail)
        ask_groq.assert_not_awaited()

    def test_health_and_registration(self) -> None:
        self.assertEqual(self.client.get("/health").json(), {"status": "ok"})
        token = self.register("user@example.com")
        response = self.client.get(
            "/auth/me", headers={"Authorization": f"Bearer {token}"}
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["role"], "user")

    @patch("app.main.verify_with_cheki")
    def test_geo_blocked_receipt_is_not_marked_verified(self, verify) -> None:
        from app.cheki import ChekiResult

        verify.return_value = ChekiResult(
            verified=False,
            decoded_only=False,
            parsed=False,
            amount=None,
            details={"fallbackUrl": "https://official.example/receipt"},
            reasons=["Provider is geo-blocked."],
        )
        token = self.register("receipt@example.com")
        response = self.client.post(
            "/transactions/verify",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "bank": "telebirr",
                "reference": "DET0SAMPLE",
            },
        )
        self.assertEqual(response.status_code, 201, response.text)
        result = response.json()
        self.assertEqual(result["verification_status"], "unverified")
        self.assertGreaterEqual(result["risk_score"], 35)
        self.assertEqual(
            result["verification_details"]["fallbackUrl"],
            "https://official.example/receipt",
        )

    @patch("app.main.verify_with_cheki")
    def test_receipt_uses_cheki_amount_without_user_amount(self, verify) -> None:
        from app.cheki import ChekiResult

        verify.return_value = ChekiResult(
            verified=True,
            decoded_only=False,
            parsed=False,
            amount=1250.5,
            details={"senderName": "ABEBE", "receiverName": "TIGIST"},
            reasons=["The issuing bank confirmed this receipt."],
        )
        token = self.register("confirmed@example.com")
        response = self.client.post(
            "/transactions/verify",
            headers={"Authorization": f"Bearer {token}"},
            json={"bank": "cbe", "reference": "CBE-RECEIPT-LINK"},
        )
        self.assertEqual(response.status_code, 201, response.text)
        result = response.json()
        self.assertEqual(result["verification_status"], "verified")
        self.assertEqual(result["amount"], 1250.5)
        self.assertEqual(result["verification_details"]["receiverName"], "TIGIST")
        verify.assert_called_once_with(
            "cbe",
            "CBE-RECEIPT-LINK",
            account_number=None,
            phone_number=None,
            qr_data=None,
        )

    @patch("app.main.verify_with_cheki")
    def test_entered_amount_must_match_bank_record(self, verify) -> None:
        from app.cheki import ChekiResult

        verify.return_value = ChekiResult(
            verified=True,
            decoded_only=False,
            parsed=False,
            amount=1250.5,
            details={"amount": 1250.5},
            reasons=["The issuing bank confirmed this receipt."],
        )
        token = self.register("mismatch@example.com")
        response = self.client.post(
            "/transactions/verify",
            headers={"Authorization": f"Bearer {token}"},
            json={"bank": "cbe", "reference": "receipt123", "amount": 1500},
        )
        self.assertEqual(response.status_code, 201, response.text)
        result = response.json()
        self.assertEqual(result["verification_status"], "unverified")
        self.assertGreaterEqual(result["risk_score"], 80)
        self.assertTrue(any("Amount mismatch" in item for item in result["reasons"]))

    @patch("app.main.verify_with_cheki")
    def test_boa_decoded_only_is_not_verified(self, verify) -> None:
        from app.cheki import ChekiResult

        verify.return_value = ChekiResult(
            verified=False,
            decoded_only=True,
            parsed=False,
            amount=100,
            details={"decodedOnly": True},
            reasons=["QR was decoded but not confirmed."],
        )
        token = self.register("decoded@example.com")
        response = self.client.post(
            "/transactions/verify",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "bank": "boa",
                "reference": "AB12345678",
                "account_number": "12345",
            },
        )
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["verification_status"], "unverified")
        self.assertTrue(response.json()["verification_details"]["decodedOnly"])

    @patch("app.main.verify_with_cheki")
    def test_geoblocked_bank_fallback_is_kept_unverified(self, verify) -> None:
        from app.cheki import ChekiResult

        verify.return_value = ChekiResult(
            verified=False,
            decoded_only=False,
            parsed=False,
            amount=None,
            details={"fallbackUrl": "https://official.example/receipt"},
            reasons=["Provider is geo-blocked."],
        )
        token = self.register("fallback@example.com")
        response = self.client.post(
            "/transactions/verify",
            headers={"Authorization": f"Bearer {token}"},
            json={"bank": "telebirr", "reference": "DET0SAMPLE"},
        )
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["verification_status"], "unverified")
        self.assertEqual(
            response.json()["verification_details"]["fallbackUrl"],
            "https://official.example/receipt",
        )

    def test_transfer_history_is_private_and_admin_can_review_alerts(self) -> None:
        user_token = self.register("merchant@example.com")
        admin_token = self.register("admin@example.com")
        response = self.client.post(
            "/transactions/score",
            headers={"Authorization": f"Bearer {user_token}"},
            json={
                "amount": 95000,
                "hour": 2,
                "account_age_days": 3,
                "transactions_24h": 1,
                "new_recipient": True,
                "sim_changed": True,
            },
        )
        self.assertEqual(response.status_code, 201, response.text)
        transaction_id = response.json()["id"]
        self.assertGreaterEqual(response.json()["risk_score"], 80)
        self.assertEqual(len(self.client.get(
            "/transactions",
            headers={"Authorization": f"Bearer {user_token}"},
        ).json()), 1)
        self.assertEqual(len(self.client.get(
            "/transactions",
            headers={"Authorization": f"Bearer {admin_token}"},
        ).json()), 0)
        alerts = self.client.get(
            "/admin/alerts", headers={"Authorization": f"Bearer {admin_token}"}
        )
        self.assertEqual(alerts.status_code, 200)
        self.assertEqual(alerts.json()[0]["id"], transaction_id)
        updated = self.client.patch(
            f"/admin/alerts/{transaction_id}",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"status": "Confirmed Fraud"},
        )
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.json()["review_status"], "Confirmed Fraud")

    def test_admin_route_rejects_regular_user(self) -> None:
        token = self.register("notadmin@example.com")
        response = self.client.get(
            "/admin/alerts", headers={"Authorization": f"Bearer {token}"}
        )
        self.assertEqual(response.status_code, 403)

    def test_community_reports_require_moderation_before_publication(self) -> None:
        user_token = self.register("reporter@example.com")
        other_user_token = self.register("other-reporter@example.com")
        with patch(
            "app.main.settings",
            SimpleNamespace(admin_emails=frozenset({"community-moderator@example.com"})),
        ):
            admin_token = self.register("community-moderator@example.com")
        report_body = {
            "category": "phishing",
            "title": "Fake bank support message",
            "description": "A message impersonated my bank and asked me to open a suspicious link.",
            "indicator": "https://example.invalid/fake-bank",
            "provider": "Example Bank",
        }

        unauthenticated = self.client.post(
            "/community/reports", json=report_body
        )
        self.assertEqual(unauthenticated.status_code, 401)

        submitted = self.client.post(
            "/community/reports",
            headers={"Authorization": f"Bearer {user_token}"},
            json=report_body,
        )
        self.assertEqual(submitted.status_code, 201, submitted.text)
        report = submitted.json()
        self.assertEqual(report["status"], "pending")
        self.assertNotIn("user_id", report)
        self.assertEqual(self.client.get("/community/reports").json(), [])
        my_reports = self.client.get(
            "/community/my-reports",
            headers={"Authorization": f"Bearer {user_token}"},
        )
        self.assertEqual(my_reports.status_code, 200, my_reports.text)
        self.assertEqual([item["id"] for item in my_reports.json()], [report["id"]])
        self.assertEqual(my_reports.json()[0]["status"], "pending")
        self.assertEqual(
            self.client.get(
                "/community/my-reports",
                headers={"Authorization": f"Bearer {other_user_token}"},
            ).json(),
            [],
        )

        forbidden = self.client.get(
            "/admin/community/reports",
            headers={"Authorization": f"Bearer {user_token}"},
        )
        self.assertEqual(forbidden.status_code, 403)

        admin_reports = self.client.get(
            "/admin/community/reports",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        self.assertEqual(admin_reports.status_code, 200, admin_reports.text)
        self.assertEqual(len(admin_reports.json()), 1)
        report_id = report["id"]
        published = self.client.patch(
            f"/admin/community/reports/{report_id}",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"status": "published"},
        )
        self.assertEqual(published.status_code, 200, published.text)
        self.assertEqual(published.json()["status"], "published")
        self.assertEqual(
            self.client.get(
                "/community/my-reports",
                headers={"Authorization": f"Bearer {user_token}"},
            ).json()[0]["status"],
            "published",
        )
        second_report = self.client.post(
            "/community/reports",
            headers={"Authorization": f"Bearer {user_token}"},
            json={
                **report_body,
                "title": "Another suspicious support message",
            },
        )
        self.assertEqual(second_report.status_code, 201, second_report.text)
        rejected = self.client.patch(
            f"/admin/community/reports/{second_report.json()['id']}",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"status": "rejected"},
        )
        self.assertEqual(rejected.status_code, 200, rejected.text)
        self.assertEqual(
            {
                item["status"]
                for item in self.client.get(
                    "/community/my-reports",
                    headers={"Authorization": f"Bearer {user_token}"},
                ).json()
            },
            {"published", "rejected"},
        )
        admin_headers = admin_reports.request.headers
        trends = self.client.get(
            "/admin/community/report-trends?days=30",
            headers=admin_headers,
        )
        self.assertEqual(trends.status_code, 200, trends.text)
        self.assertEqual(trends.json()["total_reviewed"], 2)
        self.assertEqual(trends.json()["published"], 1)
        self.assertEqual(trends.json()["rejected"], 1)
        self.assertEqual(
            trends.json()["by_category"],
            [{"category": "phishing", "count": 2}],
        )
        self.assertEqual(
            trends.json()["by_provider"],
            [{"provider": "Example Bank", "count": 2}],
        )
        invalid_period = self.client.get(
            "/admin/community/report-trends?days=500",
            headers=admin_headers,
        )
        self.assertEqual(invalid_period.status_code, 422)
        public_reports = self.client.get("/community/reports")
        self.assertEqual(public_reports.status_code, 200)
        self.assertEqual(public_reports.json()[0]["id"], report_id)

        invalid_status = self.client.patch(
            f"/admin/community/reports/{report_id}",
            headers={"Authorization": f"Bearer {admin_token}"},
            json={"status": "pending"},
        )
        self.assertEqual(invalid_status.status_code, 422)

        blank_title = self.client.post(
            "/community/reports",
            headers={"Authorization": f"Bearer {user_token}"},
            json={**report_body, "title": "   "},
        )
        self.assertEqual(blank_title.status_code, 422)

    @patch("app.main.verify_with_cheki")
    def test_payment_reconciliation_finds_mismatches_duplicates_and_private_data(
        self, verify
    ) -> None:
        from app.cheki import ChekiResult

        user_token = self.register("reconcile@example.com")
        other_user_token = self.register("other-reconcile@example.com")
        verify.side_effect = lambda bank, reference, **kwargs: ChekiResult(
            verified=True,
            decoded_only=False,
            parsed=True,
            amount={
                "DIFF-REF": 110,
                "DUP-REF": 250,
                "UNMATCHED-REF": 75,
                "MATCH-REF": 500,
            }[reference],
            details={},
            reasons=["The issuing bank confirmed this receipt."],
        )
        headers = {"Authorization": f"Bearer {user_token}"}

        for reference in (
            "DIFF-REF",
            "DUP-REF",
            "DUP-REF",
            "UNMATCHED-REF",
            "MATCH-REF",
        ):
            receipt = self.client.post(
                "/transactions/verify",
                headers=headers,
                json={"bank": "cbe", "reference": reference},
            )
            self.assertEqual(receipt.status_code, 201, receipt.text)
            self.assertEqual(receipt.json()["verification_status"], "verified")

        mismatch = self.client.post(
            "/reconciliation/expected",
            headers=headers,
            json={
                "provider": "CBE",
                "expected_amount": 100,
                "reference": "DIFF-REF",
                "description": "Invoice A",
            },
        )
        self.assertEqual(mismatch.status_code, 201, mismatch.text)

        duplicate = self.client.post(
            "/reconciliation/expected",
            headers=headers,
            json={
                "provider": "cbe",
                "expected_amount": 250,
                "reference": "DUP-REF",
                "description": "Invoice B",
            },
        )
        self.assertEqual(duplicate.status_code, 201, duplicate.text)

        matched = self.client.post(
            "/reconciliation/expected",
            headers=headers,
            json={
                "provider": "cbe",
                "expected_amount": 500,
                "reference": "MATCH-REF",
                "description": "Invoice C",
            },
        )
        self.assertEqual(matched.status_code, 201, matched.text)

        missing = self.client.post(
            "/reconciliation/expected",
            headers=headers,
            json={
                "provider": "cbe",
                "expected_amount": 900,
                "reference": "NOT-RECEIVED",
                "description": "Invoice D",
            },
        )
        self.assertEqual(missing.status_code, 201, missing.text)

        reconciliation = self.client.get("/reconciliation", headers=headers)
        self.assertEqual(reconciliation.status_code, 200, reconciliation.text)
        expected = {
            item["description"]: item
            for item in reconciliation.json()["expected_payments"]
        }
        self.assertEqual(expected["Invoice A"]["status"], "amount_mismatch")
        self.assertEqual(expected["Invoice A"]["actual_transactions"][0]["amount"], 110)
        self.assertEqual(expected["Invoice B"]["status"], "duplicate")
        self.assertEqual(len(expected["Invoice B"]["actual_transactions"]), 2)
        self.assertEqual(expected["Invoice C"]["status"], "matched")
        self.assertEqual(expected["Invoice D"]["status"], "missing")
        self.assertEqual(
            [item["reference"] for item in reconciliation.json()["unmatched_received"]],
            ["UNMATCHED-REF"],
        )

        other_reconciliation = self.client.get(
            "/reconciliation",
            headers={"Authorization": f"Bearer {other_user_token}"},
        )
        self.assertEqual(other_reconciliation.status_code, 200)
        self.assertEqual(other_reconciliation.json()["expected_payments"], [])
        self.assertEqual(other_reconciliation.json()["unmatched_received"], [])

        hidden = self.client.delete(
            f"/reconciliation/expected/{mismatch.json()['id']}",
            headers={"Authorization": f"Bearer {other_user_token}"},
        )
        self.assertEqual(hidden.status_code, 404)

        removed = self.client.delete(
            f"/reconciliation/expected/{mismatch.json()['id']}",
            headers=headers,
        )
        self.assertEqual(removed.status_code, 204)

    def test_admin_can_publish_text_and_image_education_posts(self) -> None:
        import base64

        with patch(
            "app.main.settings",
            SimpleNamespace(admin_emails=frozenset({"education-editor@example.com"})),
        ):
            admin_token = self.register("education-editor@example.com")
        user_token = self.register("education-reader@example.com")
        admin_headers = {"Authorization": f"Bearer {admin_token}"}
        user_headers = {"Authorization": f"Bearer {user_token}"}

        forbidden = self.client.post(
            "/admin/education/posts",
            headers=user_headers,
            data={
                "post_type": "text",
                "title": "Payment safety",
                "description": "Never share your payment PIN.",
            },
        )
        self.assertEqual(forbidden.status_code, 403)

        text_post = self.client.post(
            "/admin/education/posts",
            headers=admin_headers,
            data={
                "post_type": "text",
                "title": "Payment safety",
                "description": "Never share your payment PIN.",
                "category": "security",
            },
        )
        self.assertEqual(text_post.status_code, 201, text_post.text)
        self.assertEqual(text_post.json()["post_type"], "text")
        self.assertEqual(text_post.json()["description"], "Never share your payment PIN.")
        self.assertIsNone(text_post.json()["image_url"])

        missing_image = self.client.post(
            "/admin/education/posts",
            headers=admin_headers,
            data={
                "post_type": "image",
                "title": "Check the official app",
                "description": "Do not trust screenshots alone.",
            },
        )
        self.assertEqual(missing_image.status_code, 422)

        invalid_image = self.client.post(
            "/admin/education/posts",
            headers=admin_headers,
            data={
                "post_type": "image",
                "title": "Invalid upload",
                "description": "",
            },
            files={"image_file": ("fake.png", b"not an image", "image/png")},
        )
        self.assertEqual(invalid_image.status_code, 415)

        png = base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII="
        )
        image_post = self.client.post(
            "/admin/education/posts",
            headers=admin_headers,
            data={
                "post_type": "image",
                "title": "Check the official app",
                "description": "A payment screenshot alone is not proof.",
                "category": "general",
            },
            files={"image_file": ("safety.png", png, "image/png")},
        )
        self.assertEqual(image_post.status_code, 201, image_post.text)
        self.assertEqual(image_post.json()["post_type"], "image")
        image_url = image_post.json()["image_url"]
        self.assertTrue(image_url.startswith("/uploads/education/"))
        self.assertEqual(self.client.get(image_url).status_code, 200)

        public_posts = self.client.get("/education")
        self.assertEqual(public_posts.status_code, 200)
        post_types = {post["post_type"] for post in public_posts.json()}
        self.assertEqual(post_types, {"text", "image"})

        for post in (text_post.json(), image_post.json()):
            deleted = self.client.delete(
                f"/admin/education/{post['id']}",
                headers=admin_headers,
            )
            self.assertEqual(deleted.status_code, 204)

    def test_login_rejects_wrong_password(self) -> None:
        self.register("login@example.com")
        response = self.client.post(
            "/auth/login",
            json={"email": "login@example.com", "password": "incorrect-password"},
        )
        self.assertEqual(response.status_code, 401)


if __name__ == "__main__":
    unittest.main()
