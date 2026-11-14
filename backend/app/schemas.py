from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)


class PasswordResetRequest(BaseModel):
    email: EmailStr


class PasswordResetComplete(BaseModel):
    email: EmailStr
    code: str = Field(pattern=r"^\d{8}$")
    new_password: str = Field(min_length=10, max_length=128)


class UserResponse(BaseModel):
    id: int
    email: EmailStr
    role: Literal["user", "admin"]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AuthResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    user: UserResponse


class ReceiptSubmission(BaseModel):
    bank: str = Field(min_length=1, max_length=40, pattern=r"^[a-z0-9-]+$")
    reference: str | None = Field(default=None, max_length=2048)
    amount: float | None = Field(default=None, gt=0, le=100_000_000)
    account_number: str | None = Field(default=None, max_length=64)
    phone_number: str | None = Field(default=None, max_length=32)
    qr_data: str | None = Field(default=None, max_length=8192)


class TransferSubmission(BaseModel):
    amount: float = Field(gt=0, le=100_000_000)
    hour: int = Field(ge=0, le=23)
    account_age_days: int = Field(ge=0, le=100_000)
    transactions_24h: int = Field(ge=0, le=100_000)
    new_recipient: bool = False
    sim_changed: bool = False


class TransactionResponse(BaseModel):
    id: int
    kind: str
    provider: str | None
    reference: str | None
    amount: float
    verification_status: str
    risk_score: int
    model_score: int
    risk_level: str
    action: str
    reasons: list[str]
    verification_details: dict[str, object] | None
    review_status: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ReviewUpdate(BaseModel):
    status: Literal["Open", "Investigating", "Confirmed Fraud", "False Positive"]


class CommunityReportSubmission(BaseModel):
    category: Literal["phishing", "fake_receipt", "impersonation", "other"]
    title: str = Field(min_length=3, max_length=120)
    description: str = Field(min_length=10, max_length=1500)
    indicator: str | None = Field(default=None, max_length=200)
    provider: str | None = Field(default=None, max_length=50)

    @field_validator("title", "description", mode="before")
    @classmethod
    def strip_required_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("indicator", "provider", mode="before")
    @classmethod
    def strip_optional_text(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip() or None
        return value


class CommunityReportStatusUpdate(BaseModel):
    status: Literal["published", "rejected"]


class CommunityReportResponse(BaseModel):
    id: int
    category: str
    title: str
    description: str
    indicator: str | None
    provider: str | None
    status: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ExpectedPaymentSubmission(BaseModel):
    provider: str = Field(min_length=1, max_length=40)
    expected_amount: float = Field(gt=0, le=100_000_000)
    reference: str | None = Field(default=None, max_length=2048)
    description: str = Field(default="", max_length=120)

    @field_validator("provider", mode="before")
    @classmethod
    def strip_provider(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @field_validator("reference", "description", mode="before")
    @classmethod
    def strip_optional_text(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip() or None
        return value


class ReconciliationTransaction(BaseModel):
    id: int
    provider: str | None
    reference: str | None
    amount: float
    created_at: datetime


class ExpectedPaymentResult(BaseModel):
    id: int
    provider: str
    expected_amount: float
    reference: str | None
    description: str
    created_at: datetime
    status: Literal["missing", "matched", "amount_mismatch", "duplicate"]
    actual_transactions: list[ReconciliationTransaction]


class ReconciliationResponse(BaseModel):
    expected_payments: list[ExpectedPaymentResult]
    unmatched_received: list[ReconciliationTransaction]


class EducationCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    video_url: str = Field(min_length=1, max_length=500)
    description: str = Field(min_length=1, max_length=1000)
    category: str = "general"


class EducationUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(max_length=1000)
    category: str = Field(min_length=1, max_length=50)
    video_url: str | None = Field(default=None, max_length=500)

    @field_validator("title", "category")
    @classmethod
    def trim_required_fields(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("This field cannot be blank.")
        return value


class EducationResponse(BaseModel):
    id: int
    post_type: Literal["video", "text", "image"] = "video"
    title: str
    video_url: str
    image_url: str | None = None
    description: str
    ai_summary: str | None
    category: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
