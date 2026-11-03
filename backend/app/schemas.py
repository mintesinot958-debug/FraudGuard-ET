from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)


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


class EducationCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    video_url: str = Field(min_length=1, max_length=500)
    description: str = Field(min_length=1, max_length=1000)
    category: str = "general"


class EducationResponse(BaseModel):
    id: int
    title: str
    video_url: str
    description: str
    ai_summary: str | None
    category: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
