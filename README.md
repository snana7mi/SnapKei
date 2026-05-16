# SnapKei

SnapKei is an iOS app for Japanese sole proprietors that turns receipts and electronic invoices into bookkeeping journal entries.

## Features

- Capture receipts with camera or photo library and import PDF receipts.
- Parse receipt images through either a BYOK direct AI channel or the built-in gateway.
- Built-in AI uses the existing `llm-gateway-back` Cloudflare Worker with `appId = snapkei` and OpenRouter model `google/gemma-4-26b-a4b-it`.
- Store journal entries locally with SwiftData, including amendment/void history for bookkeeping audit trails.
- Preserve receipt image paths and SHA-256 hashes for scanner/electronic transaction evidence.
- Support household allocation, invoice qualification flags, and transitional invoice tax rates.
- Export profit and loss PDF reports and UTF-8 CSV files for accounting tools.

## Requirements

- Xcode 26+
- iOS 18.5+
- Swift 6

## Development

Open the project in Xcode:

```bash
open SnapKei.xcodeproj
```

Run the test suite from the repository root:

```bash
xcodebuild -scheme SnapKei -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```

## Backend

The built-in AI backend is not stored in this repository. It is configured in:

```text
/Users/lee/workspace/llm-gateway-back
```

The D1 migration `0026_add_snapkei_gemma.sql` registers the SnapKei app and binds it to the OpenRouter Gemma model.

## Disclaimer

SnapKei is a bookkeeping assistance tool, not tax advice. Final tax treatment should be confirmed with a licensed tax professional or the tax office.

## License

TBD
