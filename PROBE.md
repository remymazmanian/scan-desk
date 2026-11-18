# Driver findings: FF-680W through ImageCaptureCore

What Epson's Image Capture driver exposes for the FastFoto FF-680W, what the app relies on, and what it works around. Everything here was measured with the probe in `Probe/` or with the app itself, over Wi-Fi, using the Epson ICA module `EPSON ES0170.app` (installed with Epson Scan 2), module version 1.0.

Run the probe:

```
cd Probe && swift build -c release && codesign -s - -f .build/release/ScanProbe
.build/release/ScanProbe list
.build/release/ScanProbe scan --dpi 300 --duplex [--color gray|bw] [--set VF_NAME=value]
```

The probe looks for a scanner whose name contains "FF-680". For any other scanner, add `--match` with part of its name as shown in Image Capture, for example `--match "ES-580W"`, to both commands. Raw scans are saved to `~/Pictures/ScanProbe` unless you pass `--out <folder>`.

## What the driver offers

| Area | Result |
|---|---|
| Discovery | Works over the network (Bonjour, transport `TCPIP`, about 1 s). USB is untested. The app prefers USB when a scanner shows up both ways. |
| Session | Opens in about 10 s over Wi-Fi. |
| Functional units | Document feeder only. |
| Resolutions | 75–1200 dpi in 1 dpi steps. Native resolution is 600 × 600. The app offers 300 and 600. |
| Bit depth | 1-bit and 8-bit per channel: 24-bit color and 8-bit gray. This is the hardware's limit (it reads at 30-bit internally but outputs 24-bit), so TIFF gives no more color than JPEG, only no compression loss. |
| Color modes | Color, gray and black and white all work. ImageCaptureCore has no API to list them. Black and white arrives as an 8-bit gray TIFF holding only black and white; the app converts it to true 1-bit for PDFs and TIFFs. |
| Duplex | Works. Each side arrives as a separate TIFF, front then back. |
| Page sizes | A4, B5, US Letter, US Legal, A5, A6, A8. Photo sizes aren't listed. The app requests a Letter-size area and lets the driver crop each page. With Auto Size Detection on, that request doesn't cap the length (see below). |
| Vendor features | Unsharp Mask, Descreening, Auto Size Detection (Off / Standard / Long Paper), Correct Document Skew, Detect Double Feed, Skip Blank Pages (Off / levels 1–30), Remove Punch Holes, Image Option (background removal, color dropout), Auto Rotation. |

## How each driver feature behaves

- **Auto Size Detection (`VF_AUTOCROP=1`): reliable, and the app uses it.** Prints come back cropped tight and straight (4.0 × 6.0 in for a 4×6 print), and paper comes back at its sheet size. The requested Letter area doesn't limit it: a 14-in sheet came back whole, both sides, at 8.43 × 14.08 in (2530 × 4224 px at 300 dpi), and saved as a correctly sized PDF. Without it, every page is the full requested area: the print at the top on a light gray-blue feeder background, padded with pure white past the end of the paper.
- **Auto Rotation (`VF_AUTOROTATE`): works for text pages only.** A sheet loaded upside down came out upright. Sideways photos stay sideways. The app turns it on in Documents mode and rotates photos itself.
- **Skip Blank Pages (`VF_BLANKPAGESKIP`): unreliable, and the app turns it off.** At level 10 it dropped blank photo backs but kept blank paper backs that had punch holes. Dropping pages inside the driver also hides which back belongs to which front.
- **Blank photo backs are dropped even with Skip Blank Pages off.** With both sides requested, Auto Size on and Skip Blank Pages off, 3 prints with blank backs came back as 3 pages. Under the same settings, blank paper backs *were* delivered. The trigger is unknown. The app therefore doesn't assume pages alternate front and back (see below).
- **Remove Punch Holes (`VF_PUNCHEDHOLE`): no visible effect.** The app doesn't use it.

## What the driver doesn't offer

- More than 24-bit color.
- A scan speed or quality setting.
- The "scanner ready" callback: `scannerDeviceDidBecomeAvailable` never arrives, so the app polls `availableFunctionalUnitTypes` after the session opens.
- Useful status: `didReceiveStatusInformation` fires every 3 s with an empty dictionary, so there are no paper-jam or progress messages.
- A trustworthy paper sensor: `documentLoaded` reported `true` right after a feeder run emptied the tray.
- Page count or end of stack: the app counts files as they arrive and treats `didCompleteScanWithError` as the end.
- The scanner's physical button: Epson's Event Manager owns it, and it keeps opening Epson's apps.

## What the app does itself

- **Front and back pairing.** Pages normally alternate front, back. Because the driver can drop a back, a page that clearly shows a picture where a back was expected closes the previous photo as "no back received" and starts a new one.
- **Blank detection.** The app looks for the densest small patch of marks on a page, ignoring the outer 6.5% margin (scanner edge lines, punch holes). Measured on real scans: a single handwritten word reached 21%, and blank backs peaked at 0.33% with punch holes included. The threshold is 3%. An earlier whole-page ink measure couldn't tell one handwritten word (0.06%) from a blank page (0.04–0.07%). Writing that sits entirely inside the outer margin still counts as blank.
- **Photo rotation.** Vision face detection at each of the four orientations; the orientation with the most upright faces wins. Photos without faces are left as scanned and can be rotated by hand.
- **Fallback crop.** If a page comes back at the full Letter area, the app outlines the print against the scanner background. Vision rectangle detection alone missed most picture sides in testing, so its result is used only when it agrees with that outline.
- **Searchable PDFs.** Vision text recognition, drawn as an invisible text layer. The first recognition after installing a build can take about 45 s while macOS prepares its model, so the app runs one tiny recognition in the background at launch.

## Measured speed (Wi-Fi)

- Photos at 300 dpi, both sides, full Letter area: about 2 s per photo.
- Photos at 600 dpi with Auto Size: about 3 s per photo.
- Documents at 300 dpi, both sides: about 1.5 s per sheet.
- A 5-page searchable PDF was saved 1.7 s after its scan ended.

## Not yet tested

- USB connection.
- A4 paper itself (it's smaller than the 14-in sheet that scanned in full), and sheets longer than 14 in.
- Long-paper mode for receipts (`VF_AUTOCROP=2`); the app doesn't offer it.
- Faint pencil writing on a photo back.
- Whether Epson ScanSmart or FastFoto scanning at the same moment can block the app.
- A back so full of writing or print that it reads as a picture side.
