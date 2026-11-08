# Contributing

Thanks for your interest! Issues and pull requests are welcome.

## Build & test

```sh
swift build            # debug build
swift test             # unit tests
./build_app.sh         # release build -> LocationSpoofer.app
```

Requires macOS 26+ and Xcode 26+ (developed with Xcode 27.2 / Swift 6.4).

## Translations

UI text uses the Traditional Chinese source string as the key. Translations for
English and Japanese live in `Localization/translations.json`.

```sh
python3 scripts/localization.py check      # find missing / mismatched translations
python3 scripts/localization.py generate   # regenerate Resources/*.lproj
```

Rules of thumb:

- Static SwiftUI text (`Text("…")`, `Button("…")`) is localized automatically.
- Any string built in code must go through `L("…%@…", value)`. Never interpolate
  with `"\(value)"` inside a translatable literal — the checker will flag it.
- Keep the same format specifiers (`%@`, `%lld`, `%.1f`) in every language;
  use positional ones (`%1$@`) if the word order changes.

To add a language: add it to `AppLanguage` and `Localizer.resolve`, add a column
to `translations.json` / `LANGS` in `scripts/localization.py`, and list it in
`CFBundleLocalizations` in `build_app.sh`.

## Screenshots

`LS_SCREENSHOT_DIR=out LS_LANG=en LocationSpoofer.app/Contents/MacOS/LocationSpoofer`
runs a demo mode that never touches a device or your saved data and saves
screenshots of its own window. macOS asks for Screen Recording permission the
first time.

## Scope

The app can only set latitude/longitude through `devicectl`; it cannot set
altitude, speed or course. Please keep that in mind when proposing features.
