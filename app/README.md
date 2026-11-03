# CSave - Phase 1 + 2

## Backend
cd backend && npm install && cp .env.example .env   (fill in real keys on the SERVER only)
npm start

## App
cd app && flutter create . && flutter pub get   (flutter create adds the android/ios folders)
Follow android_notes/README_ANDROID.txt for fingerprint setup.
Edit flutter_app.env -> API_BASE_URL (10.0.2.2 works for the Android emulator).
flutter run

## Make an admin
Register in the app, then in MongoDB set that user's role to "admin" (roles can never be self-assigned).
## Approve KYC (until the KYC screen is built)
In MongoDB set kycStatus to "approved" on a test user.
