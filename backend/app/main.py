import asyncio
import os
import shutil
from datetime import datetime, timezone
from typing import Any

import google.generativeai as genai
import httpx
from fastapi import Depends, FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import select
from sqlalchemy.orm import Session
from pydantic import BaseModel

from .cheki import ChekiError, get_banks, verify_with_cheki
from .config import settings
from .database import Base, engine, get_db
from .fraud import RiskAssessment, fraud_scorer
from .models import Transaction, User, EducationContent
from .schemas import (
    AuthResponse,
    Credentials,
    ReceiptSubmission,
    ReviewUpdate,
    TransactionResponse,
    TransferSubmission,
    UserResponse,
    EducationResponse,
)
from .security import (
    create_access_token,
    get_current_user,
    hash_password,
    require_admin,
    verify_password,
)

# Configure Gemini only when a valid Google AI Studio key is present.
if settings.gemini_api_key:
    genai.configure(api_key=settings.gemini_api_key)

UPLOAD_DIR = "uploads/videos"
os.makedirs(UPLOAD_DIR, exist_ok=True)

Base.metadata.create_all(bind=engine)

app = FastAPI(title="FraudGuard ET AI API", version="1.0.0")
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

class ChatRequest(BaseModel):
    message: str

async def _get_ai_response(prompt: str) -> str:
    """Generate a reply using Groq when configured, otherwise use Gemini."""
    if settings.groq_api_key:
        try:
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
                        "max_tokens": 160,
                    },
                )
            if response.status_code == 401:
                raise HTTPException(
                    status_code=503,
                    detail="Groq rejected the configured API key. Replace GROQ_API_KEY with an active GroqCloud key.",
                )
            if response.status_code == 404:
                raise HTTPException(
                    status_code=503,
                    detail="The configured Groq model is unavailable for this account. Check the model ID and account access.",
                )
            if response.status_code == 429:
                raise HTTPException(
                    status_code=503,
                    detail="Groq is temporarily rate-limited. Please wait a moment and try again.",
                )
            if response.status_code >= 400:
                raise HTTPException(
                    status_code=502,
                    detail="Groq could not complete the request. Check the Groq model and API access.",
                )
            data = response.json()
            message = data["choices"][0]["message"]["content"]
            if isinstance(message, str) and message.strip():
                return message.strip()
            raise HTTPException(
                status_code=502,
                detail="Groq returned an empty response. Please try again.",
            )
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

    if not settings.gemini_api_key:
        raise HTTPException(
            status_code=503,
            detail="AI is not configured. Set GROQ_API_KEY in backend/.env and restart the backend.",
        )

    try:
        available_models = await asyncio.to_thread(lambda: list(genai.list_models()))
    except Exception as exc:  # pragma: no cover - depends on external API service
        error = str(exc).lower()
        if any(
            marker in error
            for marker in ("401", "403", "api key not valid", "invalid api key", "api_key_invalid", "forbidden")
        ):
            raise HTTPException(
                status_code=503,
                detail="Gemini rejected the configured API key. Replace GEMINI_API_KEY with an active key that has Gemini API access, then restart the backend.",
            ) from exc
        raise HTTPException(
            status_code=503,
            detail="Could not retrieve Gemini models. Check that the key is active and the Gemini API is enabled.",
        ) from exc

    text_models = [
        model
        for model in available_models
        if any(
            method.lower() == "generatecontent"
            for method in getattr(model, "supported_generation_methods", [])
        )
    ]
    text_models.sort(
        key=lambda model: (
            "flash" not in getattr(model, "name", "").lower(),
            getattr(model, "name", ""),
        )
    )
    if not text_models:
        raise HTTPException(
            status_code=503,
            detail="This key has no Gemini models enabled for text generation. Enable Gemini API access or use a key that has access to a text-generation model.",
        )

    last_error: Exception | None = None
    for model_info in text_models:
        try:
            model = genai.GenerativeModel(model_info.name)
            response = await model.generate_content_async(prompt)
            response_text = getattr(response, "text", "").strip()
            if response_text:
                return response_text
            last_error = RuntimeError(f"{model_info.name} returned an empty response")
        except Exception as exc:  # pragma: no cover - depends on external API service
            last_error = exc
            lower_error = str(exc).lower()
            if "404" in lower_error or "not found" in lower_error:
                continue
            if any(
                marker in lower_error
                for marker in (
                    "401",
                    "403",
                    "api key not valid",
                    "invalid api key",
                    "api_key_invalid",
                    "forbidden",
                    "permission denied",
                )
            ):
                raise HTTPException(
                    status_code=503,
                    detail="Gemini rejected the configured API key. Replace GEMINI_API_KEY with an active key that has Gemini API access, then restart the backend.",
                ) from exc
            if "429" in lower_error or "rate limit" in lower_error:
                raise HTTPException(
                    status_code=503,
                    detail="Gemini is temporarily rate-limited. Please wait a moment and try again.",
                ) from exc
            raise HTTPException(
                status_code=502,
                detail="Gemini could not complete the request. Check the backend logs and try again.",
            ) from exc

    if last_error is not None:
        raise HTTPException(
            status_code=503,
            detail="Gemini listed text models for this key, but none could generate a response. Check backend logs and key permissions.",
        )
    raise HTTPException(
        status_code=502,
        detail="Gemini returned an empty response. Please try again.",
    )

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
    
    content = EducationContent(title=title, video_url=final_url, description=description, category=category, ai_summary=ai_summary)
    db.add(content); db.commit(); db.refresh(content)
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

@app.delete("/admin/education/{content_id}", status_code=204)
def delete_education(content_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    item = db.get(EducationContent, content_id)
    if item:
        if item.video_url.startswith("/uploads"):
            path = item.video_url.lstrip("/")
            if os.path.exists(path): os.remove(path)
        db.delete(item); db.commit()
    return None

@app.get("/admin/users", response_model=list[UserResponse])
def admin_list_users(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return list(db.scalars(select(User).order_by(User.created_at.desc())))

@app.post("/transactions/verify", response_model=TransactionResponse, status_code=201)
def verify_receipt(body: ReceiptSubmission, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    try:
        result = verify_with_cheki(body.bank, body.reference, account_number=body.account_number, phone_number=body.phone_number, qr_data=body.qr_data)
    except ChekiError as exc: raise HTTPException(status_code=exc.status_code, detail=str(exc))
    amount = body.amount or result.amount or 0.0
    assessment = fraud_scorer.assess(amount=amount, hour=datetime.now(timezone.utc).hour, account_age_days=365, transactions_24h=0, new_recipient=False, sim_changed=False)
    item = Transaction(user_id=user.id, kind="receipt", provider=body.bank, reference=body.reference, amount=amount, verification_status="verified" if result.verified else "unverified", risk_score=assessment.score, model_score=assessment.model_score, risk_level=assessment.level, action=assessment.action, reasons=assessment.reasons, review_status="Open")
    db.add(item); db.commit(); db.refresh(item)
    return item

@app.get("/transactions", response_model=list[TransactionResponse])
def transaction_history(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return list(db.scalars(select(Transaction).where(Transaction.user_id == user.id).order_by(Transaction.created_at.desc()).limit(50)))
