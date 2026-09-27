# Zelda Amiibo AR

An iPhone/iPad app for browsing a local Zelda Amiibo catalog and placing two preserved scans in AR. Requires iOS 18 or later and Xcode 27 (the existing project format/toolchain). No third-party dependencies, network service, or LiDAR requirement.

## Run

1. Open `Zelda Amiibo AR Project.xcodeproj` and choose the **Zelda Amiibo AR** scheme.
2. Select a connected iPhone/iPad running iOS 18+ and verify the existing signing team works for your device.
3. Run, open **Smash Brothers Young Link**, and tap **Place in your room**. Allow camera access.
4. Move slowly around a well-lit table or floor. When the center target turns green, tap **Place here**, or tap a detected surface directly.
5. Adjust size and rotation. Tap another surface to move the figure. **Restart** clears the placement and scans the room again.
6. Open `QR Cards/index.html` on a second screen (or print it), tap **Scan QR**, and scan either card.

Simulator supports the catalog and detail screens. AR presents an explicit unsupported-device screen instead of opening the camera.

## Scope and behavior

- 26 individually identified figures migrated from 23 legacy entries; combined figures share their existing artwork and reward notes.
- Only Young Link and Ocarina of Time Link have 3D scans. The remaining figures are clearly marked catalog-only.
- Both USDZ files are bundled locally. The legacy project and original assets are untouched.
- QR codes select catalog entries. They do not provide a continuously tracked marker pose. A model stays on the world surface where it was placed.
- One placed model at a time. Scanning another code selects a new figure and clears the previous placement.
- Scans are normalized to 12 cm tall, centered horizontally, and grounded by visible bounds. This is a starting display size, not a measured physical calibration. Per-model height, yaw, and vertical offset live in `Resources/amiibos.json`.
- Permission denial, unsupported devices, missing models, tracking limitations, interruptions, and session errors have visible handling. Backgrounding pauses AR; closing the screen tears it down.

## Structure

- `Models/Amiibo.swift`: stable catalog schema, validation, and QR resolution.
- `Resources/amiibos.json`: bundled metadata; USDZ files live alongside it.
- `Services/ModelLibrary.swift`: async loading, caching, normalization, and independent clones.
- `Services/QRScanner.swift`: serial Vision barcode analysis away from the main actor.
- `AR/ARExperienceController.swift`: owns session lifecycle, selection, placement, and throttled scanning.
- `Views/ARExperienceView.swift`: camera UI, status, controls, and the RealityKit bridge.
- `ContentView.swift`: searchable catalog and figure details.

QR payload format: `zelda-amiibo://figure/<stable-id>`. Raw stable IDs and the known legacy names `SSB_Young_Link` and `OOT_Link` are also accepted. Unknown payloads never become file paths or network requests.

## Validation

From the project directory:

```sh
xcodebuild -project 'Zelda Amiibo AR Project.xcodeproj' -scheme 'Zelda Amiibo AR' -sdk iphonesimulator -derivedDataPath /tmp/zelda-amiibo-build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project 'Zelda Amiibo AR Project.xcodeproj' -scheme 'Zelda Amiibo AR' -sdk iphoneos -derivedDataPath /tmp/zelda-amiibo-device-build CODE_SIGNING_ALLOWED=NO build
xcrun swiftc 'Zelda Amiibo AR/Models/Amiibo.swift' Validation/CatalogChecks.swift -o /tmp/zelda-catalog-checks
/tmp/zelda-catalog-checks "$PWD"
```

The standalone validation utility checks catalog IDs, aliases, asset existence, rejected QR inputs, invalid catalog data, and QR image round trips through Vision. It regenerates the two PNG cards. It needs macOS graphics/Vision access.

## Real-device acceptance checklist

- First launch asks for camera access; denial shows Settings recovery.
- Young Link and Ocarina of Time Link both load with textures and sit on a detected horizontal surface.
- Placement remains stable as you walk around; size and rotation controls work.
- Both QR cards select the correct model; unrelated codes show a useful message.
- Background/foreground, interruption, restart, and leaving/reopening the camera recover without duplicate models.
- Verify apparent height, upright orientation, and model base position against the original figures; adjust metadata if needed.

The reward text is preserved historical content, not a newly verified game database. The art and models are your existing project assets; no new Nintendo artwork is generated.

To validate the same model loader against the built app’s resources on macOS:

```sh
xcrun swiftc -parse-as-library 'Zelda Amiibo AR/Models/Amiibo.swift' 'Zelda Amiibo AR/Services/ModelLibrary.swift' Validation/ModelChecks.swift -o /tmp/zelda-model-checks
/tmp/zelda-model-checks '/tmp/zelda-amiibo-build/Build/Products/Debug-iphonesimulator/Zelda Amiibo AR.app'
```

This loads both USDZs using RealityKit and verifies normalized height, grounding, centering, independent cache clones, and missing-file errors. It does not replace testing world tracking on a phone.
