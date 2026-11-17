# Phase 1 probe: FF-680W through ImageCaptureCore

Probe tool: `Probe/` (SwiftPM CLI, no dependencies). Build and run:

```
cd Probe && swift build -c release && codesign -s - -f .build/release/ScanProbe
.build/release/ScanProbe list
.build/release/ScanProbe scan --dpi 300 --duplex
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

## Still to test (needs real photos in the feeder)

- [ ] A stack of 3–5 photos at 300 dpi, duplex: page order, and which physical side counts as "front".
- [ ] The same stack at 600 dpi: timing and file size.
- [ ] The driver's Auto Size Detection, Deskew and Auto Rotation on photos, compared with doing it in Vision.
- [ ] Skip Blank Pages on photo backs.
- [ ] USB connection (optional).

The test scan run so far went through whatever was already in the feeder. That turned out to be a printed document, not photos, so it only confirms the mechanics above.

## Toolchain note

Only the Command Line Tools are installed, not Xcode. That's enough to build and ad-hoc sign a SwiftPM executable. For the phase 2 SwiftUI app, the options are (a) install Xcode, or (b) keep SwiftPM and wrap the binary in an `.app` bundle with a small build script. Option (b) works with what's installed now.

## Verdict so far

A full FastFoto replacement looks **feasible**, with two caveats: 8-bit color only, and no speed control. Batch feeding, duplex, 300 and 600 dpi, and TIFF output all work through Apple's public API. The driver even offers its own auto-size, deskew and rotation, which the app can use alongside or instead of Vision.
