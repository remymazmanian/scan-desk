# Scan Desk

A native macOS app (Swift, SwiftUI, macOS 15+, Apple Silicon) for the Epson FastFoto FF-680W. It replaces both Epson FastFoto (photos) and Epson ScanSmart (documents). It talks to the scanner through Apple's Image Capture framework and Epson's official driver (installed with Epson Scan 2), and uses no third-party code. It has no telemetry, and its only network traffic is finding the scanner and scanning from it.

**Tested scanner:** Scan Desk was built for and tested on one scanner, the Epson FastFoto FF-680W. It isn't tied to that model: it works through Image Capture with any scanner that has a document feeder, so other models may work as is or with small changes (see [Other scanners](#other-scanners)). It's free and open source under the MIT license, so you're welcome to adapt it to your own scanner and workflow.

This project isn't affiliated with or endorsed by Epson. Epson, FastFoto and ScanSmart are trademarks of their owner.

## Download

Get `ScanDesk.zip` from the [latest release](https://github.com/remymazmanian/scan-desk/releases/latest), unzip it, and move **Scan Desk** to your Applications folder. The app is signed and notarized, so it opens normally. It needs macOS 15 or later on Apple Silicon, and Epson's driver, which comes with Epson Scan 2.

## Build and run

Building needs only the Xcode Command Line Tools. Running the tests uses Xcode if it's installed (see Tests).

```
scripts/build-app.sh            # builds and signs build/Scan Desk.app
scripts/build-app.sh --install  # also copies it to ~/Applications
```

**Signing:** the build script signs with a "Developer ID Application" certificate from the keychain, using the hardened runtime and a secure timestamp. To pick a specific certificate, set `SIGN_IDENTITY` to its SHA-1 hash. Without such a certificate the app is signed ad-hoc and runs only on the Mac that built it.

**Notarizing for distribution:** `NOTARY_PROFILE=<profile> scripts/build-app.sh --notarize` submits the signed app to Apple, staples the ticket, and leaves `build/ScanDesk.zip` ready to share. `<profile>` is a keychain profile created once with `xcrun notarytool store-credentials`. It needs Xcode. Without notarization, a copy downloaded on another Mac is blocked by Gatekeeper.

**Icon:** `swift scripts/make-icon.swift` redraws the icon in code and writes `App/Resources/AppIcon.icns`, which the build script bundles.

## Tests

```
scripts/test.sh
```

The tests generate their own images (synthetic prints, backs, scanner frames and text pages), so they never need real scans. They cover naming, blank and picture detection, cropping, front/back pairing (including backs the scanner drops), enhancement, manual rotation, and searchable PDFs. Automatic face-based rotation needs real photos with faces, so it is checked by hand.

## Photos mode

- Feed a stack of prints and click **Scan**. Thumbnails appear as each photo is saved, with a running count.
- **Cropping and straightening:** the scanner's own auto size detection and deskew handle this. If a page comes back uncropped, the app finds the print against the scanner background itself, using Vision rectangle detection when it agrees.
- **Rotation:** photos are turned upright automatically using face detection. To fix a photo without faces, right-click its thumbnail and choose **Rotate Left** or **Rotate Right**.
- **Backs (optional):** saved as `name_b.jpg`. Blank backs are skipped; a back with even one handwritten word is kept.
- **Enhance (optional):** restores faded color and adds light sharpening. It's saved as `name_e.jpg`, and the untouched original is always kept.
- **Naming:** files are named like `1998_Summer-Trip_0001.jpg`. Numbering continues from the highest number already in the folder.
- **Formats:** JPEG, or TIFF (lossless). The scanner outputs 24-bit color, so TIFF gives no extra color depth.
- **Photos app:** finished photos can go into Photos, either automatically after each batch or with the **Add to Photos** button. The enhanced copy is added when there is one, otherwise the original. Backs aren't added.

## Documents mode

- **Color modes:** color, grayscale, or black and white, at 300 or 600 dpi, one side or both.
- **Blank pages (optional):** skipped by the app, because the scanner's own blank-page skip is unreliable.
- **Upside-down pages:** turned upright by the scanner's text-based auto rotation.
- **Output:** one multi-page PDF with searchable text (recognized on this Mac), or one JPEG or TIFF per page.
- **Naming:** `2026-11-17_Title.pdf`. If a file with that name already exists, `_2`, `_3` and so on are added.

All settings are remembered between launches.

## Not supported

The first three are limits of the scanner or its driver; see [PROBE.md](PROBE.md).

- More than 24-bit color: a hardware limit, so FastFoto can't do it either.
- A scan speed setting.
- The scanner's physical button: it still opens Epson's apps.
- Cloud and email sending.
- Long-paper mode for receipts.

## Known limits

- **Paper size:** pages up to 8.5 in wide and at least 14 in long (Legal length) scan in full; the scanner crops each page to its real size. A4 fits inside that but hasn't been run itself. Sheets longer than 14 in are untested.
- **Connection:** tested over Wi-Fi only, not USB.
- **Rotation:** photos without faces aren't turned automatically.
- **Backs:** a back whose only writing is within about half an inch of the edge counts as blank. A back covered in dense writing or print can be mistaken for a new photo; it's still saved, as its own numbered file.
- **Scanner model:** tested with the FF-680W only. See [Other scanners](#other-scanners).

## Other scanners

Scan Desk doesn't check the scanner's name or model. It connects to the first scanner macOS finds through Image Capture (a USB connection is preferred) and needs that scanner to have a document feeder. What to expect:

- **Other Epson feeder scanners** (for example other FastFoto or ES/DS models) use the same Epson Scan 2 driver and may work unchanged, but none has been tested.
- **Feeder scanners from other brands** should scan. Epson's driver settings (auto size, deskew, auto rotate, double-feed detection) are skipped when a driver doesn't offer them, and Scan Desk's own cropping, rotation, blank detection, front/back pairing and searchable PDFs still apply. Photo cropping may need tuning for a different scanner background.
- **Flatbed scanners** aren't supported. Adding them means choosing the flatbed, setting the scan area, and finding several photos on the glass.
- **More than one scanner:** there's no picker yet; Scan Desk chooses one automatically.

To adapt Scan Desk to your scanner, start with the probe. It lists what your scanner's driver offers and runs test scans:

```
cd Probe && swift build -c release && codesign -s - -f .build/release/ScanProbe
.build/release/ScanProbe list --match "<part of your scanner's name>"
```

[PROBE.md](PROBE.md) shows what this found for the FF-680W and how the app relies on it. Then adjust `App/Sources/ScanKit/ScannerService.swift`, which holds everything that talks to the scanner.

Forks are welcome. If you get it working with another scanner, a pull request that adds it to this section, with what you changed, helps the next person.

## Layout

| Path | What |
|---|---|
| `App/Sources/ScanKit` | Scanner connection, image processing, PDF, naming, Photos import |
| `App/Sources/ScanDesk` | The SwiftUI app |
| `App/Sources/scankit-check` | Runs the processing on saved raw scans, without a scanner |
| `App/Tests` | Tests on generated images |
| `scripts/` | Build, test and icon scripts |
| `PROBE.md` | What the scanner's driver does and doesn't offer |
| `Probe/` | A command-line probe that lists what the driver exposes and runs test scans |

## License

MIT. See [LICENSE](LICENSE).
