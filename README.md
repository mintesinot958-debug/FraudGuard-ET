# FraudGuard ET - Digital Payment Fraud Detection and Verification

Flutter client and FastAPI backend for payment receipt verification and transaction risk review.

## 🚀 Permanent Connection Setup (Physical Devices)

When running on a real phone, your computer's IP address changes often. Use one of these two "permanent" methods instead:

### Option A: USB Tunneling (Recommended for Development)
This makes the phone think the server is running inside the phone itself.
1. Connect your phone via USB and enable USB Debugging.
2. Run this command on your computer:
   ```bash
   adb reverse tcp:8000 tcp:8000
   ```
3. In the App, tap the **"Connected to"** text at the bottom and set the URL to:
   **`http://127.0.0.1:8000`**

### Option B: Cloud Tunneling (Works anywhere, even without USB)
1. Download [ngrok](https://ngrok.com/).
2. Start your backend, then run: `ngrok http 8000`
3. Copy the `https://...` address ngrok gives you.
4. In the App, tap the **"Connected to"** text and paste that URL.

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

**Note:** If you see "Connection failed", tap the URL at the bottom of the Sign-in screen to update your computer's IP. Ensure you use a **colon** (e.g., `:8000`), not a dot.

## Implemented features
- **QR & Receipt Scanning**: Uses Google ML Kit to scan both QR codes and text from paper or screenshots.
- **Message Analyzer**: Detects scams in SMS/Telegram messages via text or camera scan.
- **Risk Scoring**: Rule-based scoring for transfers (SIM swap detection, velocity checks).
- **Multi-language**: Full support for English and Amharic.
- **Dynamic Config**: Change Server IP directly in the app without rebuilding.

## Production Notes
- Release builds on Android block plain `http://` APIs. Use an `https://` URL (like ngrok or a real server) for production.
- Ensure `android:usesCleartextTraffic="true"` is in your Manifest for local testing.
- Disabling Impeller is recommended for older devices (like Samsung M-series) to prevent black screens.
