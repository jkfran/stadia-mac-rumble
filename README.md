# Stadia Controller rumble over Bluetooth on macOS (Ryujinx and other SDL apps)

**It works** — wirelessly, over the Mac's own Bluetooth, no driver and no system changes.
Verified in-game (Mario Kart 8 Deluxe) with Google Stadia controllers on macOS 26 / Apple Silicon.

This corrects a common belief (and the main Stadia compatibility tracker) that macOS has no Stadia
controller rumble. It does.

## The short version

On macOS, SDL already talks to the Stadia through its own HIDAPI Stadia driver, which supports Bluetooth
rumble, **by default**. So in an SDL-based app you usually don't need to configure anything special — you
just need the app's own rumble setting turned on.

**Ryujinx:** Options → Input → pick the player → set **Rumble** on (strong/weak above 0). That's the whole fix.

That's it. If a Stadia "doesn't rumble" in an SDL app on a Mac, the app's rumble toggle is almost certainly off.

## Why people think it's impossible (and the one thing to not break)

On macOS this controller is **only** visible to SDL through SDL's HIDAPI joystick driver. Apple's
GameController framework does not pick up the Stadia at all. SDL's HIDAPI system is enabled by default, so
this normally just works — but if you (or a guide) disabled it, the controller disappears from SDL entirely:

```
SDL_JOYSTICK_HIDAPI=0   # do NOT do this on macOS: the Stadia vanishes from SDL
```

For the record, these hints are **not required** — the defaults already select the rumble-capable driver
(verified: with no hints at all, SDL reports the pad as type `GOOGLE_STADIA` with rumble capability):

```
SDL_JOYSTICK_HIDAPI=1
SDL_JOYSTICK_HIDAPI_STADIA=1
SDL_JOYSTICK_MFI=0
```

## How to confirm the driver is active

With an SDL app running, the app's own process should have the controller's HID device open — that's SDL's
HIDAPI driver. `ioreg -l -w0 | grep -A40 Stadia | grep IOUserClientCreator` lists the openers; the app
(e.g. `Ryujinx`) should be among them. SDL also identifies the pad as controller type `GOOGLE_STADIA` (9).

## Developer note: sending rumble yourself via IOKit (outside SDL)

If you talk to the controller directly with `IOHIDDeviceSetReport` (not through SDL), there's a trap specific
to the Bluetooth Stadia on macOS: it is an `IOHIDUserDevice` owned by Apple's Bluetooth daemon, and the buffer
you send **must include the report-ID byte**. The USB-style "payload only" buffer is accepted (the call
returns `kIOReturnSuccess`) and then **silently dropped** — nothing reaches the motors, with no error.

```c
// Works: 5-byte buffer, report ID 0x05 inside it, report ID also passed as the parameter
uint8_t on[5]  = { 0x05, strongLo, strongHi, weakLo, weakHi };  // magnitudes 0..0xFFFF, little-endian
IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 5, on, 5);

// Accepted but silently dropped over Bluetooth:
uint8_t bad[4] = { strongLo, strongHi, weakLo, weakHi };
IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 5, bad, 4);
```

Shared mode (`kIOHIDOptionsTypeNone`) is enough; no exclusive seize needed. This is also how hidapi (and
therefore SDL) sends it, which is why SDL's driver works. The report format is the same one the Linux
`hid-google-stadiaff` driver uses.

`stadia-rumble-test.m` is a standalone ~40-line checker that uses this directly (independently of SDL):

```
clang -fobjc-arc -framework Foundation -framework IOKit stadia-rumble-test.m -o stadia-rumble-test && ./stadia-rumble-test
```

Run it with the controller connected and awake (press a button first), and feel for a 1.5 s buzz.

## Verified setup

| Item | Value |
|---|---|
| macOS | 26.5.1 (Tahoe), Apple Silicon (M4 Mac mini) |
| Controller | Google Stadia Controller, Bluetooth-mode firmware, paired in System Settings |
| App | Ryujinx 1.2 (Ryubing fork), bundling SDL 2.30.0 |
| Game | Mario Kart 8 Deluxe — rumble on drifts, boosts, hits |

## Caveats

- Verified on Apple Silicon / macOS 26 / SDL 2.30. Other SDL apps (RetroArch, Dolphin, PPSSPP) should behave
  the same via SDL's HIDAPI path; not individually tested.
- The controller drops its Bluetooth link when idle; it must be awake when a rumble is sent.
- SDL added Stadia Bluetooth rumble in Feb 2023 (`SDL_hidapi_stadia.c`). This repo documents that it works on
  macOS in practice and how to confirm it, plus the direct-IOKit gotcha above.

## Credits

Found and verified by Fran (jkfran). Rumble driver work by the SDL maintainers (`SDL_hidapi_stadia.c`) and the
Linux `hid-google-stadiaff` authors, who documented the report format.
