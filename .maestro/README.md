# Maestro UI smoke tests

These flows run against the Android application on an emulator or a real test device. They do not add SDKs, Firebase calls, Firestore listeners, or production telemetry to the app.

## Run locally

1. Build and install the debug APK for `com.wassally.app`.
2. Install the Maestro CLI: https://maestro.mobile.dev/getting-started/installing-maestro
3. From the repository root run:

```bash
maestro test .maestro/flows/login-smoke.yaml
```

The smoke flow only launches the app and verifies the login screen's visible content. It deliberately does not tap Google sign-in, which requires a real configured test account and interactive Google authentication.

Add authenticated customer/store-owner/courier journeys only after dedicated non-production test accounts and safe test data are available. Never run destructive order/account flows against production.
