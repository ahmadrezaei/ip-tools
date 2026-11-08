# Privacy Policy

IP Tools does not collect, store on a server, or share any personal data. The App Store privacy label is **Data Not Collected**. The app has no tracking (`NSPrivacyTracking = false`), no analytics and no third-party SDKs.

## Network destinations

The app talks to exactly three kinds of destinations:

1. **The target you probe.** Ping, traceroute and the *your path* overlay on the BGP Map send ICMP packets only to the host, address or prefix you enter.
2. **The system DNS resolver**, to turn host names into addresses.
3. **`https://stat.ripe.net/data/...` (RIPEstat, run by the RIPE NCC).** This is the only place data goes besides the target you probe and your DNS resolver. The host names, IP addresses, prefixes or AS numbers you enter in BGP Map are sent to RIPEstat. If "Look up networks (ASN, via RIPEstat)" is on, the public IP addresses of traceroute hops are sent as well. These requests carry `sourceapp=ahmadrezaei-iptools`, as RIPE NCC asks, and no user identifiers. When the BGP Map draws *your path*, the app asks RIPEstat which public IP address your connection uses and which network it belongs to, and looks up the public addresses of the routers on the way (if "Look up networks" is on). RIPEstat already sees that address on every request. The app keeps it in memory only and never sends it anywhere else. The setting can be turned off, and the Traceroute settings and the About screen say this in plain words.

Nothing else leaves the device. There is no analytics and no tracking.

## Stored on your device

Recent targets (up to 20) and your settings are kept locally in `UserDefaults`. **Clear History** in About removes the recents. Nothing is synced (no iCloud) and nothing leaves the device.

## Local network

The system may ask for Local Network access the first time you ping or trace an address on your own network, such as your router. The app uses it only for that purpose: "IP Tools uses the local network to ping and trace devices on your network, such as your router."

## Privacy manifest

`PrivacyInfo.xcprivacy` declares: tracking `false`, no collected data types, and the `UserDefaults` required-reason API (`CA92.1`) for the local recents and settings.

## Contact

Questions: open an issue at https://github.com/ahmadrezaei/ip-tools.
