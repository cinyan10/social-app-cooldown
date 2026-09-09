# Social Cooldown

Social Cooldown is a native macOS menu-bar app that enforces a one-hour cooldown between quitting and reopening Discord or QQ. When a monitored app is launched before the cooldown expires, Social Cooldown blocks the launch and presents a short, deliberate challenge before allowing the next launch.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 or later (included with Xcode 15+)

## Development

### Run

Open the repository in Xcode (`File → Open…` and select the folder or `Package.swift`), select the `SocialCooldown` executable scheme, and run it. The app is an accessory/menu-bar application. On its first launch, macOS may ask for permission to control the monitored applications so the blocker can terminate an early launch.

From Terminal, the core package can be built and tested with:

```sh
swift test
swift build
```

To create a local menu-bar app bundle with the correct `Info.plist` and bundle identifier:

```sh
./scripts/build-app.sh
open .build/SocialCooldown.app
```

To stop any running copy, rebuild, and launch the new version in one step:

```sh
./scripts/restart-app.sh
```

This development-only script targets the exact `SocialCooldown` process name. It uses a normal termination signal first and force-stops that process only if it does not exit promptly.

When distributed as a signed `.app`, the included `Resources/Info.plist` sets the application bundle identifier to `com.cinyan10.SocialCooldown`.

## Configuration

The bundle identifiers default to `com.hnc.Discord` and `com.tencent.qq`. Use “Application identifiers…” in the menu bar to override them for installed regional builds.

`⌘Q` is intentionally ignored. Use the menu-bar command to quit, which requires confirmation.

Cooldown timestamps and configured bundle identifiers are stored in the standard macOS user defaults domain. The app registers itself as a login item through `SMAppService.mainApp` when launched.

## License

This project is available under the [MIT License](LICENSE).
