# Reps — project instructions

## Testing workflow: build + install on Ichigo

After making code changes that the user will test, **build, auto-sign, and install
on the physical device "Ichigo" automatically** — don't wait to be asked. Anurag does
the on-device testing.

- Device: **Ichigo** — iPhone 15 Pro, `id=00008130-000A685E1110001C`
- Signing is already automatic (team `2LWQ9LQUGT`, bundle `com.anurag.reps`).

**New files:** the project is XcodeGen-based (`project.yml`) with explicit file
lists — a brand-new `.swift` file won't compile until you regenerate:
```
xcodegen generate
```
Regenerating drops `DEVELOPMENT_TEAM` (not in `project.yml`), so always pass it
on the build command (below).

Build:
```
xcodebuild -project Reps.xcodeproj -scheme Reps -configuration Debug \
  -destination 'id=00008130-000A685E1110001C' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=2LWQ9LQUGT CODE_SIGN_STYLE=Automatic \
  -derivedDataPath build/ichigo build
```

Install:
```
xcrun devicectl device install app --device 00008130-000A685E1110001C \
  build/ichigo/Build/Products/Debug-iphoneos/Reps.app
```

Notes:
- If Ichigo's id changes, rediscover with `xcrun devicectl list devices`.
- SourceKit may report spurious "Cannot find 'Palette'/'LogStore'/… in scope"
  cross-file errors in the editor; trust the `xcodebuild` result, not those.
