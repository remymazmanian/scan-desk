# Scanner

A native macOS app (Swift, SwiftUI, macOS 15+, Apple Silicon) for the Epson FastFoto FF-680W. It replaces both Epson FastFoto (photos) and Epson ScanSmart (documents). It talks to the scanner through Apple's Image Capture framework and Epson's official driver, and uses no third-party code. Its only network activity is finding the scanner.

## Build and run

Building needs only the Xcode Command Line Tools. Running the tests uses Xcode if it's installed (see Tests).

```
scripts/build-app.sh            # builds and signs build/Scanner.app
scripts/build-app.sh --install  # also copies it to ~/Applications
```

**Signing:** the build script signs with a "Developer ID Application" certificate from the keychain, using the hardened runtime and a secure timestamp. To pick a specific certificate, set `SIGN_IDENTITY` to its SHA-1 hash. Without such a certificate the app is signed ad-hoc and runs only on the Mac that built it. Builds aren't notarized yet, so a copy downloaded on another Mac would be blocked by Gatekeeper.

## Tests

```
scripts/test.sh
```

The tests generate their own images (synthetic prints, backs, scanner frames and text pages), so they never need real scans. They cover naming, blank and picture detection, cropping, front/back pairing (including backs the scanner drops), enhancement, manual rotation, and searchable PDFs. Automatic face-based rotation needs real photos with faces, so it is checked by hand.

## Photos mode

- Feed a stack of prints and click **Scan**. Thumbnails appear as each photo is saved, with a running count.
- **Cropping and straightening:** the scanner's own auto size detection and deskew handle this. If a page comes back uncropped, the app finds the print against the scanner background itself, using Vision rectangle detection when it agrees.
- **Rotation:** photos are turned upright automatically using face detection. To fix a photo without faces, right-click its thumbnail and choose **Rotate Left** or **Rotate Right**.
- **Backs (optional):** saved as `name_b.jpg`. Blank backs are detected and skipped.
- **Enhance (optional):** restores faded color and adds light sharpening. It's saved as `name_e.jpg`, and the untouched original is always kept.
- **Naming:** files are named like `1998_Summer-Trip_0001.jpg`. Numbering continues from the highest number already in the folder.
- **Formats:** JPEG, or TIFF (lossless). The scanner outputs 24-bit color, so TIFF gives no extra color depth.
- **Photos app:** finished photos can go into Photos, either automatically after each batch or with the **Add to Photos** button.

## Documents mode

- **Color modes:** color, grayscale, or black and white, at 300 or 600 dpi, one side or both.
- **Blank pages:** skipped by the app, because the scanner's own blank-page skip is unreliable.
- **Upside-down pages:** turned upright by the scanner's text-based auto rotation.
- **Output:** one multi-page PDF with searchable text (recognized on this Mac), or one JPEG or TIFF per page.
- **Naming:** `2026-11-17_Title.pdf`. If a file with that name already exists, `_2`, `_3` and so on are added.

All settings are remembered between launches.

## Not supported

These limits are all confirmed by the probe; see [PROBE.md](PROBE.md).

- More than 24-bit color: a hardware limit, so FastFoto can't do it either.
- A scan speed setting.
- The scanner's physical button: it still opens Epson's apps.
- Cloud and email sending.

## Layout

| Path | What |
|---|---|
| `App/Sources/ScanKit` | Scanner connection, image processing, PDF, naming, Photos import |
| `App/Sources/Scanner` | The SwiftUI app |
| `App/Sources/scankit-check` | Runs the processing on saved raw scans, without a scanner |
| `Probe/` | The phase 1 capability probe |
