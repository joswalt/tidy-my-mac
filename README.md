# TidyMyMac

A native, clean-room Mac cleaner for Apple Silicon Macs on macOS 14 or newer. Trash by default, review before every removal, every run logged.

- Build spec: [docs/spec/README.md](docs/spec/README.md)
- Design and style guide: [design/](design/)
- Planning history: [docs/planning/](docs/planning/)

## Building

```bash
brew install xcodegen
xcodegen generate
open TidyMyMac.xcodeproj
```

Run `scripts/check-local.sh` for the full local check (tests, lints, signed build). The app must be installed in `/Applications` for the admin helper to work.
