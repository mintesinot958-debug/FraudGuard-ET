import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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

    def test_login_rejects_wrong_password(self) -> None:
        self.register("login@example.com")
        response = self.client.post(
            "/auth/login",
            json={"email": "login@example.com", "password": "incorrect-password"},
        )
        self.assertEqual(response.status_code, 401)


if __name__ == "__main__":
    unittest.main()
