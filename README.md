# USB Device Info
[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-yellow.svg)](https://opensource.org/licenses/)
**USBDevInfo** is an open-source Android application that lets you inspect USB and input devices connected to your phone or tablet.  
It provides clear, human-readable information about devices, their capabilities, and how Android sees them.
---

## Features

### USB device inspection
- View connected USB devices (OTG, hubs, accessories)
- See Vendor ID (VID) and Product ID (PID)
- Identify vendor and product names using a local USB IDs database
- Inspect device class, subclass, and protocol

### Input device detection
- Detect keyboards, mice, and other input devices
- Show input sources (keyboard, mouse, joystick, etc.)
- Display motion ranges for advanced input devices

### Detailed device view
- USB specification version and speed
- Interfaces and endpoints
- Configurations and power requirements
- Device descriptor fields (when permission is granted)

### History
- Automatically records previously inspected devices
- Quickly reopen past devices
- Search by name, VID:PID, serial, or device path
- Remove or restore history entries

### Permission-aware
- Clearly indicates when Android permission is required
- Explains why certain fields may be missing
- Permission is requested per device, not globally

### Offline USB IDs database
- Ships with a built-in USB IDs database
- No dependency on external websites at runtime
- Optional manual update from settings

---

## Privacy

USBDevInfo:
- Does **not** collect analytics
- Does **not** send device data to any server
- Works fully offline (except optional database updates)
- Stores history locally on your device only

---

## Typical use cases

- Identify unknown USB devices
- Debug USB accessories or OTG setups
- Inspect interfaces and endpoints
- Verify input device behavior
- Quickly check VID/PID without a computer

---

## Requirements

- Android device with USB host / OTG support
- Android permission is required **per device** to read:
  - Manufacturer / product strings
  - Serial number
  - Raw USB descriptors

---

## License
This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.
---

## Contributions

Issues, improvements, and contributions are welcome.

If you:
- Find a bug
- Have a feature idea
- Want to improve the UI/UX

Feel free to open an issue or submit a pull request.

---

## Credits

- USB ID data sourced from the public `usb.ids` database

