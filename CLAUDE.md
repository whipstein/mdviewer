# MDViewer Project Instructions

## Release Process

**Required**: Always produce a notarized build before releasing.

```bash
./build-notarize.sh
```

This script handles building, signing, notarizing, stapling, and zip creation.
Upload the generated `build/MDViewer.zip` (already stapled) to the GitHub Release before publishing.

### Steps

1. Run `./build-notarize.sh`
2. On success, `build/MDViewer.zip` is generated
3. Create the release with `gh release create vX.X.X build/MDViewer.zip ...`
4. Releases without the zip are not allowed

### App password / notarization configuration

- Keychain profile name: `notarytool-password`
- Apple ID: matt_braunstein@yahoo.com
- Team ID: EESHX57W67
- Signing certificate: `Developer ID Application: Matthew David Braunstein (EESHX57W67)`
- If the password is regenerated, re-register it with `xcrun notarytool store-credentials "notarytool-password"`
