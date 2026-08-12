# QBook

QBook is the mobile reference generator for Concrete Equipment Hire Limited.

## Version 0.1

- Starting reference is deliberately **not hard-coded**.
- On first launch, choose the next unused reference.
- Generates five-digit references such as `01281`.
- Saves reference history locally on the phone.
- Copies generated references to the clipboard.
- Includes a **Retry last payment** function that keeps the same reference while allowing the description to be changed.
- The next reference can be changed later from the settings button.

## Android APK

Every push to `main` runs the GitHub Actions workflow **Build QBook APK**.

After a successful build:

1. Open the repository's **Actions** tab.
2. Open the latest **Build QBook APK** run.
3. Under **Artifacts**, download **QBook-Android**.
4. The ZIP contains `QBook.apk`.

## Important

This first build stores data locally on the phone. It does not yet connect to the QBook Google Sheet or QuickBooks.
