import unittest
from unittest.mock import patch

import httpx

from app.cheki import ChekiError, verify_with_cheki


class ChekiClientTests(unittest.TestCase):
    @patch("app.cheki.httpx.post")
    def test_posts_reference_and_optional_account_without_auth(self, post) -> None:
        post.return_value = httpx.Response(
            200,
            json={
                "success": True,
                "verified": True,
                "amount": 1250.5,
                "senderName": "ABEBE",
                "receiverName": "TIGIST",
                "sourceUrl": "https://bank.example/receipt",
            },
            request=httpx.Request("POST", "https://cheki.et/api/verify"),
        )

        result = verify_with_cheki(
            "cbe",
            "https://mbreciept.cbe.com.et/receipt123",
            account_number="12345678",
        )

        self.assertTrue(result.verified)
        self.assertEqual(result.amount, 1250.5)
        self.assertEqual(result.details["receiverName"], "TIGIST")
        self.assertEqual(
            post.call_args.kwargs["json"],
            {
                "bank": "cbe",
                "reference": "https://mbreciept.cbe.com.et/receipt123",
                "accountNumber": "12345678",
            },
        )
        self.assertNotIn("Authorization", post.call_args.kwargs["headers"])

    @patch("app.cheki.httpx.post")
    def test_decoded_only_is_never_verified(self, post) -> None:
        post.return_value = httpx.Response(
            200,
            json={"success": True, "verified": False, "decodedOnly": True},
            request=httpx.Request("POST", "https://cheki.et/api/verify"),
        )

        result = verify_with_cheki("boa", "AB12345678", account_number="12345")

        self.assertFalse(result.verified)
        self.assertTrue(result.decoded_only)

    @patch("app.cheki.httpx.post")
    def test_geo_block_fallback_is_not_verified(self, post) -> None:
        post.return_value = httpx.Response(
            502,
            json={
                "success": False,
                "error": "Provider is geo-blocked",
                "fallbackUrl": "https://official.example/receipt",
            },
            request=httpx.Request("POST", "https://cheki.et/api/verify"),
        )

        result = verify_with_cheki("telebirr", "DET0SAMPLE")

        self.assertFalse(result.verified)
        self.assertEqual(
            result.details["fallbackUrl"], "https://official.example/receipt"
        )

    @patch("app.cheki.httpx.post")
    def test_rate_limit_is_returned_as_retryable_api_error(self, post) -> None:
        post.return_value = httpx.Response(
            429,
            json={"success": False, "error": "Rate limited"},
            headers={"Retry-After": "15"},
            request=httpx.Request("POST", "https://cheki.et/api/verify"),
        )

        with self.assertRaises(ChekiError) as caught:
            verify_with_cheki("cbe", "receipt123")

        self.assertEqual(caught.exception.status_code, 429)
        self.assertEqual(caught.exception.retry_after, "15")


if __name__ == "__main__":
    unittest.main()
