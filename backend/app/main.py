import hashlib
import hmac
import logging
import os
import secrets
import smtplib
import shutil
import uuid
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from typing import Any

import httpx

from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    HTTPException,
    UploadFile,
    File,
    Form,
    Query,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import delete, func, inspect, select, text, update
from sqlalchemy.orm import Session
from pydantic import BaseModel

from .cheki import ChekiError, get_banks, verify_with_cheki
from .config import settings
from .database import Base, engine, get_db
from .fraud import RiskAssessment, fraud_scorer
from .models import (
    CommunityReport,
    ExpectedPayment,
    Transaction,
    User,
    EducationContent,
    PasswordResetToken,
)
from .schemas import (
    AuthResponse,
    CommunityReportResponse,
    CommunityReportStatusUpdate,
    CommunityReportSubmission,
    Credentials,
    ExpectedPaymentResult,
    ExpectedPaymentSubmission,
    ReceiptSubmission,
    ReconciliationResponse,
    ReconciliationTransaction,
    ReviewUpdate,
    TransactionResponse,
    TransferSubmission,
    UserResponse,
    EducationResponse,
    EducationUpdate,
    PasswordResetComplete,
    PasswordResetRequest,
)
from .security import (
    create_access_token,
    get_current_user,
    hash_password,
    require_admin,
    verify_password,
)

UPLOAD_ROOT = os.getenv("UPLOADS_DIR", "uploads")
UPLOAD_DIR = os.path.join(UPLOAD_ROOT, "videos")
IMAGE_UPLOAD_DIR = os.path.join(UPLOAD_ROOT, "education")
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(IMAGE_UPLOAD_DIR, exist_ok=True)
logger = logging.getLogger(__name__)

Base.metadata.create_all(bind=engine)
user_columns = {column["name"] for column in inspect(engine).get_columns("users")}
if "token_version" not in user_columns:
    with engine.begin() as connection:
        connection.execute(
            text(
                "ALTER TABLE users "
                "ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0"
            )
        )
education_columns = {
    column["name"] for column in inspect(engine).get_columns("education_content")
}
with engine.begin() as connection:
    if "post_type" not in education_columns:
        connection.execute(
            text(
                "ALTER TABLE education_content "
                "ADD COLUMN post_type VARCHAR(20) NOT NULL DEFAULT 'video'"
            )
        )
    if "image_url" not in education_columns:
        connection.execute(
            text("ALTER TABLE education_content ADD COLUMN image_url VARCHAR(500)")
        )

app = FastAPI(title="FraudGuard ET AI API", version="1.0.0")
app.mount("/uploads", StaticFiles(directory=UPLOAD_ROOT), name="uploads")


app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.cors_origins),
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)


def _password_reset_email_configured() -> bool:
    smtp_credentials_match = (settings.smtp_username is None) == (
        settings.smtp_password is None
    )
    return bool(
        settings.smtp_host
        and settings.smtp_from_email
        and smtp_credentials_match
        and settings.smtp_starttls
    )


def _password_reset_code_hash(user_id: int, code: str) -> str:
    message = f"password-reset:{user_id}:{code}".encode()
    return hmac.new(settings.jwt_secret.encode(), message, hashlib.sha256).hexdigest()


def _send_password_reset_code(email: str, code: str) -> None:
    message = EmailMessage()
    message["Subject"] = "Your FraudGuard password reset code"
    message["From"] = settings.smtp_from_email
    message["To"] = email
    message.set_content(
        f"Your FraudGuard password reset code is {code}.\n\n"
        "It expires in 15 minutes. If you did not request this code, "
        "you can ignore this email."
    )

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as smtp:
        if settings.smtp_starttls:
            smtp.starttls()
        if settings.smtp_username is not None:
            smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(message)


def _deliver_password_reset_code(email: str, code: str) -> None:
    try:
        _send_password_reset_code(email, code)
    except (OSError, ValueError, smtplib.SMTPException):
        logger.exception("Could not send password reset email.")


_RESET_REQUEST_MESSAGE = (
    "If an account exists for that email, a password reset code has been sent."
)
_RESET_CODE_INVALID_MESSAGE = "The reset code is invalid or expired."


@app.post("/auth/forgot-password", status_code=202)
def request_password_reset(
    body: PasswordResetRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
) -> dict[str, str]:
    if not _password_reset_email_configured():
        raise HTTPException(
            status_code=503,
            detail="Password reset email is not configured on the server.",
        )

    now = datetime.now(timezone.utc)
    email = str(body.email).strip().lower()
    user = db.scalar(select(User).where(User.email == email))
    if user is None:
        return {"message": _RESET_REQUEST_MESSAGE}

    db.execute(
        delete(PasswordResetToken).where(
            PasswordResetToken.expires_at < now - timedelta(days=1)
        )
    )
    recent_minute_count = db.scalar(
        select(func.count()).select_from(PasswordResetToken).where(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.created_at >= now - timedelta(minutes=1),
        )
    )
    recent_hour_count = db.scalar(
        select(func.count()).select_from(PasswordResetToken).where(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.created_at >= now - timedelta(hours=1),
        )
    )
    if recent_minute_count or recent_hour_count >= 5:
        return {"message": _RESET_REQUEST_MESSAGE}

    db.execute(
        update(PasswordResetToken)
        .where(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.used_at.is_(None),
        )
        .values(used_at=now)
    )
    code = f"{secrets.randbelow(100_000_000):08d}"
    reset_token = PasswordResetToken(
        user_id=user.id,
        token_hash=_password_reset_code_hash(user.id, code),
        created_at=now,
        expires_at=now + timedelta(minutes=15),
    )
    db.add(reset_token)
    db.commit()
    background_tasks.add_task(_deliver_password_reset_code, email, code)
    return {"message": _RESET_REQUEST_MESSAGE}


@app.post("/auth/reset-password")
def complete_password_reset(
    body: PasswordResetComplete,
    db: Session = Depends(get_db),
) -> dict[str, str]:
    email = str(body.email).strip().lower()
    user = db.scalar(select(User).where(User.email == email))
    if user is None:
        raise HTTPException(status_code=400, detail=_RESET_CODE_INVALID_MESSAGE)

    now = datetime.now(timezone.utc)
    reset_token = db.scalar(
        select(PasswordResetToken)
        .where(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.used_at.is_(None),
            PasswordResetToken.expires_at > now,
            PasswordResetToken.attempt_count < 5,
        )
        .order_by(PasswordResetToken.created_at.desc())
    )
    if reset_token is None:
        raise HTTPException(status_code=400, detail=_RESET_CODE_INVALID_MESSAGE)

    expected_hash = _password_reset_code_hash(user.id, body.code)
    if not hmac.compare_digest(reset_token.token_hash, expected_hash):
        reset_token.attempt_count += 1
        if reset_token.attempt_count >= 5:
            reset_token.used_at = now
        db.commit()
        raise HTTPException(status_code=400, detail=_RESET_CODE_INVALID_MESSAGE)

    user.password_hash = hash_password(body.new_password)
    user.token_version += 1
    reset_token.used_at = now
    db.execute(
        update(PasswordResetToken)
        .where(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.id != reset_token.id,
            PasswordResetToken.used_at.is_(None),
        )
        .values(used_at=now)
    )
    db.commit()
    return {"message": "Password reset successful. Please sign in again."}


class ChatRequest(BaseModel):
    message: str

async def _ask_groq(prompt: str) -> str:
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {settings.groq_api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": "openai/gpt-oss-20b",
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 400,
            },
        )
    if response.status_code >= 400:
        raise RuntimeError(f"Groq HTTP {response.status_code}: {response.text[:200]}")
    message = response.json()["choices"][0]["message"]["content"]
    if isinstance(message, str) and message.strip():
        return message.strip()
    raise RuntimeError("Groq returned an empty response")


async def _get_ai_response(prompt: str) -> str:
    """Generate an AI response using Groq."""
    if not settings.groq_api_key:
        raise HTTPException(
            status_code=503,
            detail="AI is not configured. Set GROQ_API_KEY in backend/.env and restart the backend.",
        )
    try:
        return await _ask_groq(prompt)
    except httpx.TimeoutException as exc:
        raise HTTPException(
            status_code=504,
            detail="Groq did not respond in time. Please try again.",
        ) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502,
            detail="Could not connect to Groq. Check the backend's internet connection.",
        ) from exc
    except Exception as exc:
        print(f"Groq AI provider failed: {exc}")
        raise HTTPException(
            status_code=503,
            detail="Groq AI service is temporarily unavailable. Check the API key and model access, then try again.",
        ) from exc


@app.post("/ai/chat")
async def ai_chat(req: ChatRequest, user: User = Depends(get_current_user)):
    prompt = (f"You are FraudGuard AI, a safety expert for digital payments in Ethiopia. "
              f"A user asks: '{req.message}'. Answer briefly and helpfully in under 35 words.")
    response_text = await _get_ai_response(prompt)
    return {"response": response_text}

@app.post("/admin/education", response_model=EducationResponse, status_code=201)
async def add_education(
    title: str = Form(...),
    description: str = Form(...),
    category: str = Form("general"),
    video_url: str = Form(None),
    video_file: UploadFile = File(None),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin)
):
    final_url = video_url
    if video_file:
        filename = f"{datetime.now().timestamp()}_{video_file.filename}"
        with open(os.path.join(UPLOAD_DIR, filename), "wb") as buffer:
            shutil.copyfileobj(video_file.file, buffer)
        final_url = f"/uploads/videos/{filename}"

    prompt = f"Write a 1-sentence safety tip for a video titled '{title}' about {category}."
    ai_summary = await _get_ai_response(prompt)
    
    content = EducationContent(
        post_type="video",
        title=title,
        video_url=final_url,
        description=description,
        category=category,
        ai_summary=ai_summary,
    )
    db.add(content); db.commit(); db.refresh(content)
    return content


@app.post(
    "/admin/education/posts",
    response_model=EducationResponse,
    status_code=201,
)
async def add_education_post(
    post_type: str = Form(...),
    title: str = Form(...),
    description: str = Form(""),
    category: str = Form("general"),
    image_file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    title = title.strip()
    description = description.strip()
    category = category.strip() or "general"
    if post_type not in {"text", "image"}:
        raise HTTPException(
            status_code=422, detail="Post type must be 'text' or 'image'."
        )
    if not title or len(title) > 200:
        raise HTTPException(
            status_code=422, detail="Title must contain 1 to 200 characters."
        )
    if len(description) > 1000:
        raise HTTPException(
            status_code=422, detail="Text content must not exceed 1000 characters."
        )

    image_url = None
    if post_type == "text":
        if not description:
            raise HTTPException(status_code=422, detail="Text content is required.")
        if image_file is not None:
            raise HTTPException(
                status_code=422, detail="Text-only posts cannot include an image."
            )
    else:
        if image_file is None:
            raise HTTPException(status_code=422, detail="An image is required.")
        extensions = {
            "image/jpeg": (".jpg", (b"\xff\xd8\xff",)),
            "image/png": (".png", (b"\x89PNG\r\n\x1a\n",)),
            "image/webp": (".webp", (b"RIFF",)),
        }
        if image_file.content_type not in {
            "application/octet-stream",
            *extensions.keys(),
        }:
            raise HTTPException(
                status_code=415, detail="Use a JPEG, PNG, or WebP image."
            )
        image_bytes = await image_file.read(5 * 1024 * 1024 + 1)
        if len(image_bytes) > 5 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Images must be 5 MB or less.")
        if image_bytes.startswith(b"\xff\xd8\xff"):
            detected_type = "image/jpeg"
        elif image_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
            detected_type = "image/png"
        elif image_bytes.startswith(b"RIFF") and image_bytes[8:12] == b"WEBP":
            detected_type = "image/webp"
        else:
            raise HTTPException(
                status_code=415, detail="The uploaded file is not a valid image."
            )
        if image_file.content_type not in {
            "application/octet-stream",
            detected_type,
        }:
            raise HTTPException(
                status_code=415, detail="Image content does not match its file type."
            )
        extension = extensions[detected_type][0]
        filename = f"{uuid.uuid4().hex}{extension}"
        with open(os.path.join(IMAGE_UPLOAD_DIR, filename), "wb") as target:
            target.write(image_bytes)
        image_url = f"/uploads/education/{filename}"

    content = EducationContent(
        post_type=post_type,
        title=title,
        video_url="",
        image_url=image_url,
        description=description,
        category=category,
    )
    db.add(content)
    try:
        db.commit()
    except Exception:
        db.rollback()
        if image_url is not None:
            image_path = image_url.lstrip("/")
            if os.path.exists(image_path):
                os.remove(image_path)
        raise
    db.refresh(content)
    return content

# standard endpoints
@app.get("/health")
def health() -> dict[str, str]: return {"status": "ok"}

@app.get("/cheki/banks")
def cheki_banks() -> dict[str, Any]:
    try:
        return get_banks()
    except ChekiError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc

@app.post("/auth/register", response_model=AuthResponse, status_code=201)
def register(body: Credentials, db: Session = Depends(get_db)) -> AuthResponse:
    email = str(body.email).lower()
    user = User(email=email, password_hash=hash_password(body.password), role="admin" if email in settings.admin_emails else "user")
    db.add(user)
    try: db.commit()
    except Exception: db.rollback(); raise HTTPException(status_code=409, detail="Email taken.")
    db.refresh(user)
    return AuthResponse(access_token=create_access_token(user), user=UserResponse.model_validate(user))

@app.post("/auth/login", response_model=AuthResponse)
def login(body: Credentials, db: Session = Depends(get_db)) -> AuthResponse:
    user = db.scalar(select(User).where(User.email == str(body.email).lower()))
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials.")
    return AuthResponse(access_token=create_access_token(user), user=UserResponse.model_validate(user))

@app.get("/education", response_model=list[EducationResponse])
def list_education(db: Session = Depends(get_db)):
    return list(db.scalars(select(EducationContent).order_by(EducationContent.created_at.desc())))

@app.post(
    "/community/reports",
    response_model=CommunityReportResponse,
    status_code=201,
)
def submit_community_report(
    body: CommunityReportSubmission,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    report = CommunityReport(
        user_id=user.id,
        category=body.category,
        title=body.title.strip(),
        description=body.description.strip(),
        indicator=body.indicator.strip() if body.indicator else None,
        provider=body.provider.strip() if body.provider else None,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return report


@app.get("/community/reports", response_model=list[CommunityReportResponse])
def list_community_reports(db: Session = Depends(get_db)):
    return list(
        db.scalars(
            select(CommunityReport)
            .where(CommunityReport.status == "published")
            .order_by(CommunityReport.created_at.desc())
            .limit(100)
        )
    )


@app.get(
    "/community/my-reports",
    response_model=list[CommunityReportResponse],
)
def list_my_community_reports(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return list(
        db.scalars(
            select(CommunityReport)
            .where(CommunityReport.user_id == user.id)
            .order_by(CommunityReport.created_at.desc())
            .limit(100)
        )
    )


@app.get(
    "/admin/community/reports",
    response_model=list[CommunityReportResponse],
)
def admin_list_community_reports(
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    return list(
        db.scalars(
            select(CommunityReport)
            .order_by(CommunityReport.created_at.desc())
            .limit(200)
        )
    )


@app.get("/admin/community/report-trends")
def community_report_trends(
    days: int = Query(default=30, ge=0, le=365),
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    filters = [CommunityReport.status.in_(("published", "rejected"))]
    if days:
        filters.append(
            CommunityReport.created_at
            >= datetime.now(timezone.utc) - timedelta(days=days)
        )

    reviewed = select(CommunityReport).where(*filters).subquery()
    status_counts = db.execute(
        select(reviewed.c.status, func.count()).group_by(reviewed.c.status)
    ).all()
    category_counts = db.execute(
        select(reviewed.c.category, func.count())
        .group_by(reviewed.c.category)
        .order_by(func.count().desc(), reviewed.c.category)
    ).all()
    provider_counts = db.execute(
        select(
            func.coalesce(reviewed.c.provider, "Not specified"),
            func.count(),
        )
        .group_by(reviewed.c.provider)
        .order_by(func.count().desc(), reviewed.c.provider)
    ).all()

    statuses = dict(status_counts)
    return {
        "days": days,
        "total_reviewed": sum(statuses.values()),
        "published": statuses.get("published", 0),
        "rejected": statuses.get("rejected", 0),
        "by_category": [
            {"category": category, "count": count}
            for category, count in category_counts
        ],
        "by_provider": [
            {"provider": provider, "count": count}
            for provider, count in provider_counts
        ],
    }


@app.patch(
    "/admin/community/reports/{report_id}",
    response_model=CommunityReportResponse,
)
def admin_update_community_report(
    report_id: int,
    body: CommunityReportStatusUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    report = db.get(CommunityReport, report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Community report not found.")
    report.status = body.status
    db.commit()
    db.refresh(report)
    return report


@app.delete("/admin/community/reports/{report_id}", status_code=204)
def admin_delete_community_report(
    report_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    report = db.get(CommunityReport, report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Community report not found.")
    db.delete(report)
    db.commit()
    return None


@app.post(
    "/reconciliation/expected",
    response_model=ExpectedPaymentResult,
    status_code=201,
)
def add_expected_payment(
    body: ExpectedPaymentSubmission,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    expected = ExpectedPayment(
        user_id=user.id,
        provider=body.provider,
        expected_amount=body.expected_amount,
        reference=body.reference,
        description=body.description or "",
    )
    db.add(expected)
    db.commit()
    db.refresh(expected)
    return {
        "id": expected.id,
        "provider": expected.provider,
        "expected_amount": float(expected.expected_amount),
        "reference": expected.reference,
        "description": expected.description,
        "created_at": expected.created_at,
        "status": "missing",
        "actual_transactions": [],
    }


@app.get("/reconciliation", response_model=ReconciliationResponse)
def reconcile_payments(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    expected_payments = list(
        db.scalars(
            select(ExpectedPayment)
            .where(ExpectedPayment.user_id == user.id)
            .order_by(ExpectedPayment.created_at.desc())
            .limit(200)
        )
    )
    received_payments = list(
        db.scalars(
            select(Transaction)
            .where(
                Transaction.user_id == user.id,
                Transaction.kind == "receipt",
                Transaction.verification_status == "verified",
            )
            .order_by(Transaction.created_at.desc())
        )
    )
    used_transaction_ids: set[int] = set()
    results: list[dict[str, Any]] = []

    for expected in expected_payments:
        expected_provider = expected.provider.strip().casefold()
        expected_reference = (expected.reference or "").strip().casefold()
        candidates = [
            received
            for received in received_payments
            if received.id not in used_transaction_ids
            and (received.provider or "").strip().casefold() == expected_provider
            and (
                (received.reference or "").strip().casefold() == expected_reference
                if expected_reference
                else abs(float(received.amount) - float(expected.expected_amount)) <= 0.01
            )
        ]
        if not candidates:
            status = "missing"
        elif len(candidates) > 1:
            status = "duplicate"
            used_transaction_ids.update(item.id for item in candidates)
        else:
            received = candidates[0]
            used_transaction_ids.add(received.id)
            status = (
                "matched"
                if abs(float(received.amount) - float(expected.expected_amount)) <= 0.01
                else "amount_mismatch"
            )
        results.append(
            {
                "id": expected.id,
                "provider": expected.provider,
                "expected_amount": float(expected.expected_amount),
                "reference": expected.reference,
                "description": expected.description,
                "created_at": expected.created_at,
                "status": status,
                "actual_transactions": [
                    {
                        "id": item.id,
                        "provider": item.provider,
                        "reference": item.reference,
                        "amount": float(item.amount),
                        "created_at": item.created_at,
                    }
                    for item in candidates
                ],
            }
        )

    unmatched = [
        item
        for item in received_payments
        if item.id not in used_transaction_ids
    ]
    return {
        "expected_payments": results,
        "unmatched_received": [
            ReconciliationTransaction(
                id=item.id,
                provider=item.provider,
                reference=item.reference,
                amount=float(item.amount),
                created_at=item.created_at,
            )
            for item in unmatched
        ],
    }


@app.delete("/reconciliation/expected/{expected_id}", status_code=204)
def delete_expected_payment(
    expected_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    expected = db.scalar(
        select(ExpectedPayment).where(
            ExpectedPayment.id == expected_id,
            ExpectedPayment.user_id == user.id,
        )
    )
    if expected is None:
        raise HTTPException(status_code=404, detail="Expected payment not found.")
    db.delete(expected)
    db.commit()
    return None


@app.patch("/admin/education/{content_id}", response_model=EducationResponse)
def update_education(
    content_id: int,
    body: EducationUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin),
):
    item = db.get(EducationContent, content_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Educational content not found.")
    item.title = body.title.strip()
    item.description = body.description.strip()
    item.category = body.category.strip()
    if item.post_type == "video" and body.video_url is not None:
        item.video_url = body.video_url.strip()
    db.commit()
    db.refresh(item)
    return item


@app.delete("/admin/education/{content_id}", status_code=204)
def delete_education(content_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    item = db.get(EducationContent, content_id)
    if item:
        for media_url in (item.video_url, item.image_url or ""):
            if media_url.startswith("/uploads/"):
                upload_root = os.path.abspath(UPLOAD_ROOT)
                path = os.path.abspath(
                    os.path.join(UPLOAD_ROOT, media_url.removeprefix("/uploads/"))
                )
                try:
                    is_upload = os.path.commonpath((upload_root, path)) == upload_root
                except ValueError:
                    is_upload = False
                if is_upload and os.path.isfile(path):
                    os.remove(path)
        db.delete(item); db.commit()
    return None

@app.get("/admin/users", response_model=list[UserResponse])
def admin_list_users(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return list(db.scalars(select(User).order_by(User.created_at.desc())))

@app.get("/auth/me", response_model=UserResponse)
def auth_me(user: User = Depends(get_current_user)):
    return user


@app.post("/transactions/verify", response_model=TransactionResponse, status_code=201)
def verify_receipt(body: ReceiptSubmission, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        result = verify_with_cheki(
            body.bank,
            body.reference,
            account_number=body.account_number,
            phone_number=body.phone_number,
            qr_data=body.qr_data,
        )
    except ChekiError as exc:
        raise HTTPException(status_code=exc.status_code, detail=str(exc))

    amount = float(result.amount if result.amount is not None else (body.amount or 0.0))
    verified = bool(result.verified) and not result.decoded_only
    reasons = list(result.reasons)
    extra_points = 0
    if body.amount is not None and result.amount is not None and abs(body.amount - result.amount) > 0.01:
        verified = False
        extra_points = 80
        reasons.append(
            f"Amount mismatch: you entered ETB {body.amount:,.2f} but the bank record shows ETB {result.amount:,.2f}."
        )
    elif not verified:
        extra_points = 35

    assessment = fraud_scorer.assess(
        amount=amount, hour=datetime.now(timezone.utc).hour,
        account_age_days=365, transactions_24h=0, new_recipient=False, sim_changed=False,
    )
    score = min(100, max(assessment.score, extra_points))
    level = "low" if score < 30 else "medium" if score < 60 else "high"
    action = "allow" if score < 30 else "step_up" if score < 60 else "hold" if score < 80 else "block"
    item = Transaction(
        user_id=user.id, kind="receipt", provider=body.bank, reference=body.reference,
        amount=amount, verification_status="verified" if verified else "unverified",
        risk_score=score, model_score=assessment.model_score, risk_level=level, action=action,
        reasons=reasons + assessment.reasons, verification_details=result.details,
        review_status="Open",
    )
    db.add(item); db.commit(); db.refresh(item)
    return item


@app.post("/transactions/score", response_model=TransactionResponse, status_code=201)
def score_transfer(body: TransferSubmission, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    assessment = fraud_scorer.assess(
        amount=body.amount, hour=body.hour, account_age_days=body.account_age_days,
        transactions_24h=body.transactions_24h, new_recipient=body.new_recipient,
        sim_changed=body.sim_changed,
    )
    score = assessment.score
    if body.new_recipient and body.sim_changed and body.amount >= 50_000:
        score = max(score, 85)
    level = "low" if score < 30 else "medium" if score < 60 else "high"
    action = "allow" if score < 30 else "step_up" if score < 60 else "hold" if score < 80 else "block"
    item = Transaction(
        user_id=user.id, kind="transfer", provider=None, reference=None, amount=body.amount,
        verification_status="not_applicable", risk_score=score, model_score=assessment.model_score,
        risk_level=level, action=action, reasons=assessment.reasons, verification_details=None,
        review_status="Open",
    )
    db.add(item); db.commit(); db.refresh(item)
    return item


@app.get("/admin/alerts", response_model=list[TransactionResponse])
def admin_alerts(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return list(db.scalars(
        select(Transaction).where(Transaction.risk_score >= 30)
        .order_by(Transaction.created_at.desc()).limit(100)
    ))


@app.patch("/admin/alerts/{transaction_id}", response_model=TransactionResponse)
def admin_update_alert(transaction_id: int, body: ReviewUpdate, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    item = db.get(Transaction, transaction_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Alert not found.")
    item.review_status = body.status
    db.commit(); db.refresh(item)
    return item


@app.get("/transactions", response_model=list[TransactionResponse])
def transaction_history(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return list(db.scalars(select(Transaction).where(Transaction.user_id == user.id).order_by(Transaction.created_at.desc()).limit(50)))
