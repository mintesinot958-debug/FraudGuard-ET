# FraudGuard ET - Digital Payment Fraud Detection and Verification

Flutter client and FastAPI backend for payment receipt verification and transaction risk review.

## Backend connection

The app connects automatically to the deployed Render API at
`https://fraudguard-et-1.onrender.com`. No device IP address, URL entry, or
local tunnel is required. Previously saved backend URLs are discarded.

---

## Run locally

### 1. Start the API
Python 3.10-3.13 is recommended. In PowerShell:

```powershell
cd backend
python -m pip install -r requirements.txt
# Start the server (host 0.0.0.0 is required for phone access)
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 2. Run Flutter
From the project root:
```bash
flutter pub get
flutter run
```

**Note:** The Flutter app continues to use the deployed Render API when run
locally. Starting the local backend above does not change the app's endpoint.

## Implemented features
- **QR & Receipt Scanning**: Uses Google ML Kit to scan both QR codes and text from paper or screenshots.
- **Message Analyzer**: Detects scams in SMS/Telegram messages via text or camera scan.
- **Risk Scoring**: Rule-based scoring for transfers (SIM swap detection, velocity checks).
- **Multi-language**: Full support for English and Amharic.
- **Backend**: Connects to the deployed Render API automatically.

## Production Notes
- The app uses the HTTPS Render API; no device-specific network settings or
  local HTTP endpoint are needed.
- Disabling Impeller is recommended for older devices (like Samsung M-series) to prevent black screens.

## Deploy the backend to Render

1. Push this repository to GitHub and create a new **Blueprint** in Render from that repository.
2. Render will read `render.yaml` and create the FastAPI service, PostgreSQL database, and persistent upload disk.
3. During setup, enter the admin email(s) for `ADMIN_EMAILS`. If you host a browser-based client, set `CORS_ORIGINS` in the service environment to its exact origin(s); the Android app does not use CORS.
4. The app is configured for `https://fraudguard-et-1.onrender.com`; no phone
   or computer IP address needs to be added to Render.

Keep the generated `JWT_SECRET` private. The PostgreSQL database stores app records, and the mounted disk stores uploaded education media across service restarts and deploys.
