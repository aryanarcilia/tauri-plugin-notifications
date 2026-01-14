# Firebase Setup for iOS

## Required Linker Flag

Firebase requires the `-ObjC` linker flag to properly load Objective-C categories.

### Add linker flag in Xcode:

1. Open your project in Xcode
2. Select your app target
3. Go to **Build Settings**
4. Search for "Other Linker Flags"
5. Add `-ObjC` to **Other Linker Flags**

### Screenshot reference:

```
Build Settings → Linking → Other Linker Flags
Add: -ObjC
```

### Alternative: Add to tauri.conf.json

```json
{
  "tauri": {
    "bundle": {
      "iOS": {
        "frameworks": [],
        "developmentTeam": "YOUR_TEAM_ID"
      }
    }
  }
}
```

Then create/modify `gen/apple/YourApp.xcconfig`:

```
OTHER_LDFLAGS = $(inherited) -ObjC
```

## Troubleshooting

If you see errors like:

- `unrecognized selector sent to class`
- `+[NSError messagingErrorWithCode:failureReason:]`

This means the `-ObjC` flag is missing.

## Verification

After adding the flag:

1. Clean build folder (Cmd+Shift+K)
2. Rebuild project
3. Run on device or simulator

The app should now work without crashes.
