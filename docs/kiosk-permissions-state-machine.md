# Kiosk permissions and lifecycle

This project currently ships an Android Flutter app. Android device-owner Lock
Task is the production lockdown path; consumer devices can use Android screen
pinning, which is weaker and may show the system confirmation UI when an
operator explicitly starts it. The app does not implement iOS native lockdown.
On iOS, Guided Access must be enabled by staff or Single App Mode must be
configured by the venue's MDM; this repository currently has no iOS Runner
project.

## Permission configuration

`lib/kiosk_permissions.dart` is the source of truth:

| Permission / capability | Class | Feature | Rationale and fallback |
|---|---|---|---|
| Camera | Critical | Capture | Used to take booth photos; the booth is unavailable until granted. |
| Storage / Photos | Critical | Save and print | Uses app storage and Android scoped MediaStore; legacy Android requests write storage only when required. |
| Bluetooth | Optional | ESP32 and paired printer | Android 12+ scan/connect runtime grants are requested during setup. Location is not requested; legacy Android BLE scanning may therefore be unavailable. |
| Network | Optional, no runtime prompt | Upload / QR download | Uses normal Internet access; local capture and saving continue offline. |

No contacts, SMS, call-log, microphone, fine/coarse-location, or accessibility
permission is present in the merged Android manifest. Plugin-contributed
microphone, broad read-storage, and location permissions are explicitly removed
by the app manifest. A Gradle build check verifies the final merged permission
allowlist for each variant, including expected plugin infrastructure
permissions (`ACCESS_NETWORK_STATE`, `WAKE_LOCK`, and AndroidX's generated
dynamic-receiver permission). Internet is a normal Android install-time
permission, not a guest prompt. Android 10+ uses scoped MediaStore for the
public photo copy and app-private storage for working files.

## Lifecycle state diagram

```text
BOOT
  ├─ device-owner + saved kiosk enabled ──> LOCK_TASK_RESTORE
  │                                           ├─ critical access good -> READY
  │                                           └─ critical access missing -> UNAVAILABLE
  └─ otherwise ────────────────────────────> SETUP_REQUIRED / ADMIN_LOGIN

SETUP_REQUIRED
  └─ authenticated operator -> PROVISIONING
       ├─ request/check declared grants; permanently denied -> APP_SETTINGS
       ├─ camera/storage pre-flight fails -> PROVISIONING (Go Live blocked)
       ├─ optional Bluetooth/network/printer fails -> READY_WITH_DEGRADED_FEATURES
       └─ critical grants + camera + writable storage pass -> GO_LIVE

GO_LIVE
  ├─ device owner -> LOCK_TASK (no system controls; boot relaunch supported)
  ├─ consumer device -> SCREEN_PINNING (operator confirms Android pin dialog)
  └─ enter attract/guest flow; no permission requests are called

READY / READY_WITH_DEGRADED_FEATURES
  ├─ inactivity timeout -> ATTRACT
  ├─ permission revoked, camera fails, or critical storage check fails
  │      -> UNAVAILABLE (no OS prompt)
  └─ five taps in the unavailable-screen top-left corner -> ADMIN_LOGIN

UNAVAILABLE
  └─ authenticated admin -> PROVISIONING / DIAGNOSTICS -> restore permission
         -> pre-flight -> GO_LIVE, or Exit kiosk mode -> SERVICE
```

Permission status values are represented as granted, denied, permanently
denied, limited, not determined, and not required. The Flutter policy test
rejects undeclared app-manifest permissions and permission/settings calls
outside the setup service. The Android Gradle pre-build and merged-manifest
checks reject new permissions contributed by plugins as well as permission
requests outside the setup service.

## Recovery and diagnostics

The authenticated operator setup screen shows permission state, last captured
error, writable/free app storage, printer configuration, battery/charging,
uptime, and the active Lock Task path. Exit requires the existing admin
password after the five-tap recovery hotspot. Android device-owner mode is
reselected on boot and starts the app via the boot receiver; consumer screen
pinning is not silently re-pinned on boot because Android may display a system
confirmation to guests.

The inactivity timeout can be configured in admin settings (30 seconds, 1, 2,
or 5 minutes). Photo delivery uses the existing scoped QR/upload flow; no
broad photo-library permission is needed on Android 10+.
