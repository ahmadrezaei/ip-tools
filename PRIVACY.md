# Privacy Policy

IP Tools does not collect, store on a server, or share any personal data. The App Store privacy label is **Data Not Collected**. The app has no tracking (`NSPrivacyTracking = false`), no analytics and no third-party SDKs.

## Network destinations

The app talks to exactly three kinds of destinations:

1. **The target you probe.** Ping and traceroute send ICMP packets only to the host or IP address you enter.
2. **The system DNS resolver**, to turn host names into addresses.
3. **`https://stat.ripe.net/data/...` (RIPEstat, run by the RIPE NCC).** BGP lookups send the IP address, prefix or AS number you enter. If "Look up AS numbers" is on in Traceroute, the public IP addresses of the hops are sent as well. These requests carry `sourceapp=ahmadrezaei-iptools`, as RIPE NCC asks, and no user identifiers. The Traceroute settings and the About screen say this in plain words, and the lookup can be turned off.

## Stored on your device

Recent targets (up to 20) and your settings are kept locally in `UserDefaults`. **Clear History** in About removes the recents. Nothing is synced (no iCloud) and nothing leaves the device.

## Local network

The system may ask for Local Network access the first time you ping or trace an address on your own network, such as your router. The app uses it only for that purpose: "IP Tools uses the local network to ping and trace devices on your network, such as your router."

## Privacy manifest

`PrivacyInfo.xcprivacy` declares: tracking `false`, no collected data types, and the `UserDefaults` required-reason API (`CA92.1`) for the local recents and settings.

## Contact

Questions: open an issue at https://github.com/ahmadrezaei/ip-tools.
