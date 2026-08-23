# Android release signing

GitHub Releases publish an installable Android APK only when it is signed by the
same persistent project key on every release. The release workflow deliberately
fails before publication when that key is unavailable; it never substitutes a
temporary debug key or uploads an unsigned APK.

`v0.4.0-beta.1` is the first Android GitHub testing pre-release. It publishes an
APK for sideloading, not a Google Play installation. The matching Desktop beta,
APK, and checksum file are all distributed from the same tagged release.

## Decide the long-term key boundary first

Android permits an installed app to update only when the new APK has the same
application ID and signing identity. Before generating the key, choose how the
future Google Play channel will relate to GitHub sideloads:

- To support updates between GitHub and Google Play, use the same permanent app
  signing identity for both channels and configure Play App Signing accordingly.
- If Google Play uses a different app signing key, users cannot update a GitHub
  installation with the Play build (or the reverse) without uninstalling first.
- Do not treat the Play upload key as automatically equivalent to the app signing
  key. They may be different identities.

This decision is difficult to reverse after an APK has been distributed.

## Provisioned project identity

The permanent project app-signing certificate was provisioned on 2026-08-23:

- alias: `dsh-remote-app-signing`
- algorithm: RSA 4096 / SHA256withRSA
- valid through: 2095-02-02
- certificate SHA-256:
  `52:1C:EF:4B:A0:6C:39:A5:B7:04:F5:5D:13:10:9C:91:8F:43:35:8D:D8:AF:53:07:01:C7:3E:79:3C:29:3A:AA`

When enrolling in Play App Signing, choose the option to provide the existing
app-signing key. Do not accept a newly generated Play app-signing identity for
this package. After enrollment, compare Play Console's app-signing certificate
SHA-256 fingerprint with the value above. A separate Play upload key may be
introduced later without changing this app-signing identity.

## Generate and retain the project key

Create the key outside the repository and let `keytool` prompt for passwords and
certificate identity instead of placing secrets in shell history:

```sh
keytool -genkeypair -v \
  -keystore DSH-Remote-Android-release.jks \
  -alias dsh-remote-release \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

Keep at least two encrypted offline backups and store the passwords in a password
manager. Losing the key prevents updates to existing GitHub APK installations.
Never commit the keystore, its base64 representation, or passwords.

Inspect the certificate before configuring CI:

```sh
keytool -list -v -keystore DSH-Remote-Android-release.jks
```

## GitHub Actions secrets

The tag release job requires all four repository Actions secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Upload the keystore without writing its base64 value to a repository file:

```sh
base64 < DSH-Remote-Android-release.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

The last three commands read their values from the terminal prompt.

## Release behavior

For the `v0.4.0-beta.1` tag, the workflow:

1. verifies the tag matches `package.json`;
2. sets Android `versionName` to `0.4.0-beta.1` and assigns a monotonic
   `versionCode` that is newer than prior public APKs;
3. runs Android unit tests, AndroidTest compilation, lint, screenshot validation,
   Release APK assembly, and Release AAB assembly;
4. verifies the APK signature and embedded version with Android build tools;
5. verifies the AAB JAR signature and confirms that its certificate matches the
   APK certificate;
6. creates a GitHub **Pre-release** and publishes
   `DSH-Remote-Android-v0.4.0-beta.1.apk` as a user-downloadable asset;
7. retains `DSH-Remote-Android-v0.4.0-beta.1.aab` as a separate Actions artifact for
   future Play Console submission.

`SHA256SUMS.txt` is generated after the Android APK and desktop installers are
downloaded into the publish job, so the APK is covered by the same release digest
file as the macOS and Windows artifacts.

Users must reach this build through
`/releases/tag/v0.4.0-beta.1` or the Releases list. GitHub's `/releases/latest`
route excludes pre-releases and will continue to resolve to the latest stable
Desktop release. Consumer installation, checksum, update, and beta-feedback
instructions are maintained in [`android/README.md`](../android/README.md) and
[`android/README.zh-CN.md`](../android/README.zh-CN.md).
