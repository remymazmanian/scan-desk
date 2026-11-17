# Phase 1 probe: FF-680W through ImageCaptureCore

Probe tool: `Probe/` (SwiftPM CLI, no dependencies). Build and run:

```
cd Probe && swift build -c release && codesign -s - -f .build/release/ScanProbe
.build/release/ScanProbe list
.build/release/ScanProbe scan --dpi 300 --duplex [--color gray|bw] [--set VF_NAME=value]
```

Driver used: Epson ICA module `EPSON ES0170.app` (installed by Epson Scan 2), module version 1.0.

## What works

| Area | Result |
|---|---|
| Discovery | Works over the network (Bonjour, transport `TCPIP`, about 1 s). The scanner wasn't plugged in over USB during the probe, so USB is **untested**. The probe prefers USB when both show up. |
| Session | Opens in about 10 s over Wi-Fi. |
| Functional units | **Document feeder only.** There's no flatbed or film unit, which is expected for this hardware. |
| Resolutions | 75–1200 dpi in 1 dpi steps. Preferred values are 75, 100, 150, 200, 240, 300, 400, 600 and 1200. Native resolution is 600 × 600. |
| Bit depth | 1-bit and 8-bit per channel. |
| Duplex | **Supported and confirmed working.** One sheet gives two separate TIFF files, in front-then-back order (`scan.tiff`, `scan 1.tiff`). |
| Page sizes | A4, B5, US Letter, US Legal, A5, A6, A8. The physical feeder area is 8.5 × 240 in (long-paper mode). Photo sizes such as 4R (4×6) aren't listed, so the app has to scan a larger area and crop. |
| Output | File-based TIFF, RGB, 8-bit, with correct DPI in the header. At 300 dpi with a Letter area, each side is 2550 × 3300 px. One duplex sheet took 6.6 s from request to finish over Wi-Fi. |
| Vendor features | Unsharp Mask (Off/Low/Middle/High), Descreening, **Auto Size Detection** (Off / Standard / Long Paper), **Correct Document Skew** (bool, on by default), **Detect Double Feed** (bool, on), **Skip Blank Pages** (Off / levels 1–30), Remove Punch Holes, Image Option (background removal and color dropout), **Auto Rotation** (bool). |

## What doesn't work or isn't exposed

- **No 16-bit or 48-bit color.** The ICA driver offers 8-bit per channel only. FastFoto's own app can't be matched on bit depth through this route.
- **No scan speed or quality-mode setting.** Nothing like FastFoto's speed or quality toggle is exposed.
- **No photo-specific modes.** There's no FastFoto-style "back side only if it has writing" and no built-in photo restoration. Skip Blank Pages exists, but it's a document-style feature, and its effect on photo backs is untested.
- **Color modes can't be listed.** ImageCaptureCore has no API for the supported pixel types. RGB works. Gray and BW are untested (the driver accepts 1-bit, so BW is likely).
- **The "ready" callback never fires.** `scannerDeviceDidBecomeAvailable` never arrives from this driver, so the app has to poll `availableFunctionalUnitTypes` after the session opens. The probe handles this.
- **Status messages are empty.** `didReceiveStatusInformation` fires every 3 s with an empty dictionary, so the app can't use it for progress or paper-jam messages.
- **The paper sensor looks unreliable.** `documentLoaded` still reported `true` right after the feeder scan finished. This needs another look with a known-empty feeder before the app relies on it.
- **Not exposed: page count, end-of-stack, paper jam.** The app should count files as they arrive and treat `didCompleteScanWithError` as end of stack.

## Scope: one app replacing FastFoto and ScanSmart

The app has a **Photos** mode (the FastFoto replacement) and a **Documents** mode (the ScanSmart replacement), sharing one scanner connection.

The Documents mode needs these, all built from Apple frameworks with no dependencies:

- **Output:** multi-page PDF from one feeder run (PDFKit), plus single JPEG, PNG or TIFF.
- **Searchable PDF:** text recognition on-device (Vision), with an invisible text layer added to the PDF.
- **Color modes:** Color, Gray and Black & White. They depend on the driver accepting Gray and BW, which still needs testing.
- **Clean-up:** blank-page skipping, auto page size and deskew. The driver offers all three as built-in features; the app adds its own fallback.
- **Long receipts or paper:** uses the driver's long-paper mode (the feeder is 8.5 × 240 in).
- **Naming:** a date pattern plus an optional title, saved into a folder you pick.

ScanSmart features that are **out of scope** under the "no network" rule: sending to cloud services or email, and Epson Connect. You can still share a finished file through the standard macOS Share menu, which uses your existing apps and doesn't make the scan app itself call anything.

The scanner's physical button can't be taken over through Image Capture, because Epson's Event Manager owns it. It will keep opening FastFoto or ScanSmart unless that's changed in Event Manager. Scans start from the app.

## Photo test 1: 300 dpi, duplex, driver features off

Stack of 9 prints (about 4×6), 18 files, **17.5 s total** over Wi-Fi (about 2 s per photo with both sides). Raw output is in `~/Pictures/ScanProbe/300dpi-rgb-duplex-*`.

- **Order:** strictly alternating, front then back. Odd files (`scan.tiff`, `scan 2.tiff`…) are the image sides, even files are the backs, so pairing is trivial.
- **Front side:** the driver's "front" is the printed image side, as the prints were loaded.
- **Frame:** every file is the full requested area (2550 × 3300 px for Letter). The print sits at the top, against a light gray-blue feeder background. Below the end of the print, the area is padded with white. So the app must crop every file, and scanning a Letter-length area for a 6-in print wastes transfer time.
- **Edges:** print edges show clear contrast against the gray background, which is a good case for Vision rectangle detection.
- **Backs:** the blank backs show as a plain white rectangle on gray, with about 2.5 MB files against about 5.4 MB for fronts. Blank detection on the cropped back (low variance, little ink) looks easy.
- **Rotation:** at least one print came out with its picture sideways. Auto-rotation is needed. The driver's `VF_AUTOROTATE` is untested; the fallback is face orientation from Vision.

## Still to test

Photos (reload the same stack):

- [ ] 600 dpi with the driver's Auto Size Detection, Auto Rotation and Skip Blank Pages switched on (`--set VF_AUTOCROP=1 --set VF_AUTOROTATE=true --set VF_BLANKPAGESKIP=10`). This checks timing, file size, and whether the driver can do the cropping, rotation and blank-back skipping itself.

Documents (2–3 pages of anything non-sensitive):

- [ ] Gray at 300 dpi (`--color gray`) and Black & White (`--color bw`): does the driver accept them?
- [ ] Auto Size Detection plus Skip Blank Pages, duplex, on a mixed stack.
- [ ] Long-paper mode on a receipt (`--set VF_AUTOCROP=2`).

Other:

- [ ] USB connection (optional).
- [ ] Whether ScanSmart or FastFoto running at the same time can block a scan from our app.

## Toolchain note

Only the Command Line Tools are installed, not Xcode. That's enough to build and ad-hoc sign a SwiftPM executable. For the phase 2 SwiftUI app, the options are (a) install Xcode, or (b) keep SwiftPM and wrap the binary in an `.app` bundle with a small build script. Option (b) works with what's installed now.

## Verdict so far

A combined FastFoto and ScanSmart replacement looks **feasible**, with two caveats: 8-bit color only, and no speed control. Batch feeding, duplex, 300 and 600 dpi, and TIFF output all work through Apple's public API. The driver even offers its own auto-size, deskew and rotation, which the app can use alongside or instead of Vision.
