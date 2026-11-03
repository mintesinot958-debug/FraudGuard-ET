from dataclasses import dataclass
from typing import Any

import httpx

_BASE_URL = "https://cheki.et/api"
_TIMEOUT_SECONDS = 15.0


class ChekiError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        status_code: int = 502,
        retry_after: str | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.retry_after = retry_after


@dataclass(frozen=True)
class ChekiResult:
    verified: bool
    decoded_only: bool
    parsed: bool
    amount: float | None
    details: dict[str, Any]
    reasons: list[str]


def _response_object(response: httpx.Response) -> dict[str, Any]:
    try:
        body = response.json()
    except ValueError as exc:
        raise ChekiError("Cheki returned an invalid response.") from exc
    if not isinstance(body, dict):
        raise ChekiError("Cheki returned an invalid response.")
    return body


def get_banks() -> dict[str, Any]:
    try:
        response = httpx.get(f"{_BASE_URL}/banks", timeout=_TIMEOUT_SECONDS)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        raise ChekiError("Could not load the current Cheki bank directory.") from exc
    return _response_object(response)


def get_health() -> dict[str, Any]:
    try:
        response = httpx.get(f"{_BASE_URL}/health", timeout=_TIMEOUT_SECONDS)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        raise ChekiError("Could not load Cheki bank service status.") from exc
    return _response_object(response)


def verify_with_cheki(
    bank: str,
    reference: str | None,
    *,
    account_number: str | None = None,
    phone_number: str | None = None,
    qr_data: str | None = None,
) -> ChekiResult:
    payload: dict[str, str] = {"bank": bank}
    if reference:
        payload["reference"] = reference.strip()
    if account_number:
        payload["accountNumber"] = account_number.strip()
    if phone_number:
        payload["phoneNumber"] = phone_number.strip()
    if qr_data:
        payload["qrData"] = qr_data.strip()
    if len(payload) == 1:
        raise ChekiError(
            "Enter a receipt reference, receipt link, or QR data.",
            status_code=422,
        )

    try:
        response = httpx.post(
            f"{_BASE_URL}/verify",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=_TIMEOUT_SECONDS,
        )
    except httpx.HTTPError as exc:
        raise ChekiError("Could not contact Cheki to verify this receipt.") from exc

    body = _response_object(response)
    if response.status_code == 429:
        raise ChekiError(
            str(body.get("error") or "Cheki rate limit reached. Try again shortly."),
            status_code=429,
            retry_after=response.headers.get("Retry-After"),
        )
    if response.status_code == 502:
        fallback_url = body.get("fallbackUrl")
        reason = str(
            body.get("error")
            or "The issuing provider is not reachable from Cheki's hosted service."
        )
        details = {
            key: body[key]
            for key in ("bank", "bankCode", "sourceUrl", "fallbackUrl")
            if isinstance(body.get(key), str)
        }
        return ChekiResult(
            verified=False,
            decoded_only=False,
            parsed=False,
            amount=None,
            details=details,
            reasons=[
                reason,
                *(
                    ["Open the official receipt page to check the amount, receiver, and date."]
                    if fallback_url
                    else []
                ),
            ],
        )
    if response.status_code == 422:
        return ChekiResult(
            verified=False,
            decoded_only=False,
            parsed=False,
            amount=None,
            details={
                key: body[key]
                for key in ("bank", "bankCode", "checkedUrl", "fallbackUrl")
                if isinstance(body.get(key), str)
            },
            reasons=[str(body.get("error") or "Cheki could not confirm this receipt.")],
        )
    if response.status_code == 404:
        raise ChekiError(
            str(body.get("error") or "This bank or receipt format is not supported by Cheki."),
            status_code=422,
        )
    if response.status_code == 413:
        raise ChekiError(
            str(body.get("error") or "The receipt data is too large for Cheki."),
            status_code=413,
        )
    if response.status_code == 400:
        raise ChekiError(
            str(body.get("error") or "Check the receipt details and try again."),
            status_code=422,
        )
    if response.status_code >= 400:
        raise ChekiError(
            str(body.get("error") or "Cheki could not process this receipt."),
            status_code=502,
        )

    result = body.get("result", body)
    if not isinstance(result, dict):
        raise ChekiError("Cheki returned an invalid verification result.")

    decoded_only = result.get("decodedOnly") is True
    parsed = result.get("parsed") is True
    amount_value = result.get("amount")
    amount = (
        float(amount_value)
        if isinstance(amount_value, (int, float)) and not isinstance(amount_value, bool)
        else None
    )
    details = {
        key: result[key]
        for key in (
            "bank",
            "bankCode",
            "currency",
            "senderName",
            "receiverName",
            "sourceUrl",
            "fallbackUrl",
            "date",
            "decodedOnly",
            "parsed",
        )
        if key in result and isinstance(result[key], (str, bool))
    }
    if amount is not None:
        details["amount"] = amount

    confirmed = (
        (result.get("verified") is True or body.get("verified") is True)
        and not decoded_only
        and not parsed
    )
    reasons = (
        ["The issuing bank confirmed this receipt."]
        if confirmed
        else [
            str(result.get("reason") or body.get("error") or "The issuing bank did not confirm this receipt.")
        ]
    )
    if decoded_only:
        reasons.append("The receipt QR was decoded but not confirmed by the bank.")
    if parsed:
        reasons.append("Receipt text was parsed but not confirmed by the bank.")

    return ChekiResult(
        verified=confirmed,
        decoded_only=decoded_only,
        parsed=parsed,
        amount=amount,
        details=details,
        reasons=reasons,
    )
