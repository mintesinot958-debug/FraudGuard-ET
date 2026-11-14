from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(256))
    token_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    role: Mapped[str] = mapped_column(String(20), default="user")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    transactions: Mapped[list["Transaction"]] = relationship(back_populates="user")


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    attempt_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class Transaction(Base):
    __tablename__ = "transactions"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    kind: Mapped[str] = mapped_column(String(20))
    provider: Mapped[str | None] = mapped_column(String(40), nullable=True)
    reference: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    amount: Mapped[float] = mapped_column(Numeric(14, 2))
    verification_status: Mapped[str] = mapped_column(String(20), default="not_applicable")
    risk_score: Mapped[int] = mapped_column(Integer)
    model_score: Mapped[int] = mapped_column(Integer)
    risk_level: Mapped[str] = mapped_column(String(12))
    action: Mapped[str] = mapped_column(String(20))
    reasons: Mapped[list[str]] = mapped_column(JSON)
    verification_details: Mapped[dict[str, object] | None] = mapped_column(
        JSON, nullable=True
    )
    review_status: Mapped[str] = mapped_column(String(24), default="Open", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, index=True)

    user: Mapped[User] = relationship(back_populates="transactions")


class EducationContent(Base):
    __tablename__ = "education_content"

    id: Mapped[int] = mapped_column(primary_key=True)
    post_type: Mapped[str] = mapped_column(
        String(20), default="video", server_default="video"
    )
    title: Mapped[str] = mapped_column(String(200))
    video_url: Mapped[str] = mapped_column(String(500))
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    description: Mapped[str] = mapped_column(String(1000))
    ai_summary: Mapped[str | None] = mapped_column(String(2000), nullable=True)
    category: Mapped[str] = mapped_column(String(50), default="general")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)


class CommunityReport(Base):
    __tablename__ = "community_reports"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    category: Mapped[str] = mapped_column(String(40))
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(1500))
    indicator: Mapped[str | None] = mapped_column(String(200), nullable=True)
    provider: Mapped[str | None] = mapped_column(String(50), nullable=True)
    status: Mapped[str] = mapped_column(String(20), default="pending", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, index=True
    )


class ExpectedPayment(Base):
    __tablename__ = "expected_payments"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    provider: Mapped[str] = mapped_column(String(40))
    expected_amount: Mapped[float] = mapped_column(Numeric(14, 2))
    reference: Mapped[str | None] = mapped_column(String(2048), nullable=True)
    description: Mapped[str] = mapped_column(String(120), default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utc_now, index=True
    )
