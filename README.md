# Stadia Controller rumble over Bluetooth on macOS (Ryujinx and other SDL apps)

**Yes, it works. Wirelessly, over the Mac's own Bluetooth, no driver, no system changes.**
Verified in-game (Mario Kart 8 Deluxe) with two Stadia controllers.

## TL;DR

SDL already knows how to rumble the Stadia over Bluetooth on macOS (added by the SDL maintainers in Feb 2023).
The catch: on macOS, SDL hands game controllers to Apple's GameController framework by default, and that path has
no Stadia rumble. You have to make SDL use its own Stadia driver. Set these for the app:

```
SDL_JOYSTICK_HIDAPI=1
SDL_JOYSTICK_HIDAPI_STADIA=1
SDL_JOYSTICK_MFI=0
```

Then turn rumble on in the app's controller settings (Ryujinx: Options > Input > the player > Rumble, enable).

## Verified setup

| Item | Value |
|---|---|
| macOS | 26.5.1 (Tahoe), Apple Silicon (M4 Mac mini) |
| Controller | Google Stadia Controller, Bluetooth-mode firmware, paired in System Settings |
| App | Ryujinx 1.2 (Ryubing fork), bundling SDL 2.30.0 |
| Game | Mario Kart 8 Deluxe, rumble on drifts, boosts, hits |

## Making it stick for apps you launch from the Finder / a frontend

GUI apps do not read your shell profile. Put the hints into the login session instead, and any app launched
*afterwards* (a frontend like ES-DE, and the emulators it starts) inherits them:

```
launchctl setenv SDL_JOYSTICK_HIDAPI 1
launchctl setenv SDL_JOYSTICK_HIDAPI_STADIA 1
launchctl setenv SDL_JOYSTICK_MFI 0
```

To make that survive reboots, run it at login with a LaunchAgent, `~/Library/LaunchAgents/com.local.sdl-hints.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.local.sdl-hints</string>
  <key>ProgramArguments</key><array>
    <string>/bin/sh</string><string>-c</string>
    <string>launchctl setenv SDL_JOYSTICK_HIDAPI 1; launchctl setenv SDL_JOYSTICK_HIDAPI_STADIA 1; launchctl setenv SDL_JOYSTICK_MFI 0</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
```

Load it once: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.sdl-hints.plist`

## How to confirm it took effect

With the game running, the Ryujinx process itself should have the controller's HID device open (that is SDL's own
driver at work). `ioreg -l -w0 | grep -A40 'StadiaTXPQ' | grep IOUserClientCreator` lists the openers; look for
`Ryujinx` among them. If only system processes appear, the hints did not reach the app.

## For developers: the one-byte trap when talking to the controller directly

If you send the rumble report yourself with IOKit (`IOHIDDeviceSetReport`), the Bluetooth Stadia is an
`IOHIDUserDevice` owned by Apple's Bluetooth daemon, and the daemon expects the **raw packet including the
report-ID byte**. The USB-style "payload only" buffer is accepted (the call returns `kIOReturnSuccess`) and then
silently dropped. Nothing reaches the motors and you get no error.

```c
// Works: 5 bytes, report ID inside the buffer, report ID also passed as the parameter
uint8_t on[5] = { 0x05, strongLo, strongHi, weakLo, weakHi };   // magnitudes 0..0xFFFF, little-endian
IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 5, on, 5);

// Accepted but silently dropped over Bluetooth:
uint8_t bad[4] = { strongLo, strongHi, weakLo, weakHi };
IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 5, bad, 4);
```

Shared mode (`kIOHIDOptionsTypeNone`) is enough; no exclusive seize, no daemon changes.
hidapi (and therefore SDL) already includes the report ID in the buffer, which is why SDL's driver works.
Report format is the same one the Linux `hid-google-stadiaff` driver uses.

`stadia-rumble-test.m` in this repo is a 40-line checker: build it, run it with the controller awake, and feel for a
1.5 s buzz.

```
clang -fobjc-arc -framework Foundation -framework IOKit stadia-rumble-test.m -o stadia-rumble-test && ./stadia-rumble-test
```

## Caveats and what is not yet pinned down

- The three hints together are verified. Whether all three are strictly required was not isolated.
- Tested only on Apple Silicon and SDL 2.30. Other SDL apps (RetroArch, Dolphin, PPSSPP) should behave the same if
  they use SDL's HIDAPI joystick path; not yet tried.
- The controller drops its Bluetooth link when idle; it must be awake (a button press) when a rumble is sent.
- macOS's own game-controller service keeps a claim on the pad. That does not block rumble, but if your app opens the
  controller exclusively it can block *other* apps' input. SDL opens it shared.

## Credits

Found and verified by Fran (jkfran). Driver work by the SDL maintainers (`SDL_hidapi_stadia.c`) and the
Linux `hid-google-stadiaff` authors, who documented the report format.
