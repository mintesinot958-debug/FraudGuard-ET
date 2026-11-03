# Debug report

## Build-breaking
- `lib/widgets/result_card.dart`: `const EdgeInsets.top(6)` does not exist -> `const EdgeInsets.only(top: 6)`.
- `lib/main.dart`: `CardTheme(...)` passed to `ThemeData.cardTheme` -> `CardThemeData(...)` (current Flutter API).
- `flutter test`: both widget tests were stale (wrong sign-in text, no mocked SharedPreferences, labels are upper-case). Rewritten; added `test/fraud_engine_test.dart`.
ኢፕ
## New Features & AI Integration
- **Admin Management**: Added a dedicated panel for admins (orange shield icon) to view all registered users and manage educational content.
- **Education Hub**: Created a new "Learn" tab for users to access fraud prevention videos.
- **AI Safety Summaries**: Integrated **Google Gemini AI** (Gemini 1.5 Flash) to automatically generate safety tips for every educational video posted by admins.
- **Video Uploads**: Added support for both external video links (YouTube) and direct MP4 file uploads from the phone's gallery.
- **Real AI Fraud Engine**: Implemented an **Isolation Forest** machine learning model in the backend to detect anomalous transaction patterns.

## Behaviour bugs
- **Navigator Context Fix**: Restructured `main.dart` to split the `MaterialApp` and `Scaffold`, resolving the Navigator context exception when accessing the Admin Panel.
- Bank dropdown could show one bank while submitting another (`bank` state stayed `cbe`). Now kept in sync.
- Bank list spun forever when the API was down; now shows the error with a Retry button.
- FastAPI validation errors (HTTP 422) now display readable messages; sign-in/register also validate email and password length first.
- Expired session (HTTP 401) now returns to the sign-in screen automatically.
- Tab switching now uses `IndexedStack` to preserve form data and verification results between tabs.
- Language toggle now correctly refreshes all screens.
- Dashboard pull-to-refresh added; unhandled network exceptions caught.
- Verify screen now only sends bank-specific fields (account number/phone) when required by the selected provider.
- "View Official Receipt" restricted to https URLs only for security.
- Dark theme unified with a shared theme builder for consistent styling.

## Backend
- Tests: 13/13 pass. Added `python-multipart` and `google-generativeai` dependencies.
- Security: `JWT_SECRET` and `GEMINI_API_KEY` are now securely loaded from the environment/`.env`.

## Package cleanup
Removed `.venv`, `.dart_tool`, `build`, `.idea`, `__pycache__` and `fraudguard.db`.
