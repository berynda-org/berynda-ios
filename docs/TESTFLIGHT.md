# Internal TestFlight delivery

The `Internal TestFlight` workflow is manual-only. It runs the package, app,
and deterministic UI tests before it imports signing material, archives a
Release build, validates the IPA, uploads it to App Store Connect, and retains
the signed IPA plus dSYMs for 30 days.

## Required Apple material

- an Apple Distribution certificate exported as a password-protected `.p12`;
- an App Store provisioning profile for `org.berynda.ios` with Associated
  Domains enabled;
- an App Store Connect API key with the least-privileged role that can upload
  builds; and
- the API key ID and issuer ID shown by App Store Connect.

Create a fresh provisioning profile after changing an App ID capability.
Never commit a certificate, profile, private key, password, or encoded secret.

## Required GitHub Actions secrets

| Secret | Value |
| --- | --- |
| `APP_STORE_CERTIFICATE_P12_BASE64` | Base64 of the distribution `.p12` |
| `APP_STORE_CERTIFICATE_P12_PASSWORD` | Password used to export the `.p12` |
| `APP_STORE_PROFILE_BASE64` | Base64 of the App Store `.mobileprovision` |
| `APP_STORE_PROFILE_NAME` | Exact provisioning-profile name |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect issuer UUID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | Base64 of `AuthKey_<KEY_ID>.p8` |

Base64 is an encoding, not encryption. The encoded values belong only in
GitHub Actions secrets. Restrict repository administration and workflow-file
changes to trusted maintainers, and revoke the API key if repository access is
ever in doubt.

## First upload checklist

1. Confirm Bundle ID `org.berynda.ios`, Team ID `KHMPLP3CXQ`, version `0.1.0`,
   and the App Store Connect record `6808289031`.
2. Add all seven repository secrets.
3. Run `Internal TestFlight` from GitHub Actions.
4. Wait for Apple processing, answer the build's export-compliance prompt if
   Apple still presents it, and add the build to the internal testing group.
5. Install on a real iPhone and iPad and execute the Milestone A acceptance
   journeys from `docs/IMPLEMENTATION-PLAN.md`.
