# IP Tools: Ping & Traceroute — Design Spec (v1)

Status: **draft for approval**, no code written yet.
Companion files: [`mockup.html`](mockup.html) (visual mockups, open in a browser), [`mockup-your-route.html`](mockup-your-route.html) (v1.1 mockups: BGP "Your route", clearer "All routes", Ping count control) and [`icon.svg`](icon.svg) (app icon).

**v1.1 addendum (draft for approval, 2026-11-08):** BGP Map gets a new default view, **Your route** (§6.11), the existing graph becomes **All routes (worldwide)** with a plain-English summary and legend (§6.12), and Ping gets a visible count control (§4.3). Privacy wording changes are in §9; types, signatures and the parallel work split are in §12.7.

**v1.2 addendum (draft for approval, 2026-11-25):** a fourth tool, **Whois**, opens on *your public IP* (IPv4 and IPv6, checked separately) with the whois of your network, and looks up any IP, prefix, AS number or host name. Data stays RIPEstat-only. Spec, decisions to confirm and the work split: §14. Mockups: [`mockup-whois.html`](mockup-whois.html).

| | |
|---|---|
| App Store name | IP Tools: Ping & Traceroute |
| Bundle ID | `com.ahmadrezaei.iptools` |
| Platforms | iOS 17+, iPadOS 17+ (iPhone + iPad, universal) |
| Stack | Swift 6, SwiftUI, Swift Charts, Observation, Network.framework (path monitor only), BSD sockets. No third-party dependencies. |
| Licence / source | MIT, `github.com/ahmadrezaei/ip-tools` |
| Backend | None. Probes run on-device. BGP data and hop ASNs come from the public RIPEstat Data API. |

---

## 0. Key decisions at a glance

1. **Three tools and nothing more:** Ping, Traceroute, BGP Map. No whois, DNS lookup, port scan, Wi-Fi info or widgets in v1.
2. **Navigation:** iPhone uses a `TabView` with three tabs. iPad (regular width) uses a `NavigationSplitView` whose sidebar lists the tools plus recent targets, and an `.inspector` for AS details. One `RootView` switches on `horizontalSizeClass`.
3. **One shared target bar component** in every tool, with a single shared recent-targets history (20 items).
4. **ICMP over unprivileged `SOCK_DGRAM` sockets** for both ping and traceroute (traceroute raises `IP_TTL` / `IPV6_UNICAST_HOPS` step by step). One code path, no raw sockets, no entitlements.
5. **Traceroute shows each hop's ASN.** One `network-info` call per public hop, cached and allowed to fail. It costs little and links the tools together: tap an ASN badge to open the BGP Map. There is a settings toggle to turn it off.
6. **BGP Map = layered AS graph, origin on the right.** Columns are BFS distance from the origin. Each column shows the top 6 ASes and folds the rest into a "+N more" bucket. Edge width shows how many paths use the edge. Nodes highlight on tap. The graph pans and zooms, and a **List** mode shows the same data. List is the default when VoiceOver is on.
7. **RIPEstat calls per map: 2 or 3 requests.** `looking-glass` and `network-info`/`prefix-overview` run in parallel, then **one bulk `as-names` call** names every AS on the graph. (Verified: `as-names` accepts a comma-separated list. 296 ASNs came back in one request.)
8. **Project setup:** a local Swift package `IPToolsKit` holds all code, including the SwiftUI features, so `swift build` and `swift test` work on a Mac with no simulator. A thin Xcode app target uses **folder-synchronised groups**, so parallel agents never edit `project.pbxproj`.
9. **(v1.1) BGP Map opens on "Your route":** a short chain of networks from *your* network to the destination's origin AS, e.g. `You · AS24940 Hetzner → AS13335 Cloudflare → AS15169 Google`. It comes from a finished traceroute that was handed over, else from a RIS path that contains your AS, else from a quick background traceroute. The worldwide graph stays one tap away as **All routes**.
10. **(v1.1) Ping count is on the main screen:** a "10 pings ▾" menu chip under the target bar with presets and a custom value.

---

## 1. Product principles

- **Simple:** each screen has one input, one primary button and live results. Settings are a short sheet per tool, and every setting has a sensible default.
- **Native:** SF Symbols, system colours, `ContentUnavailableView`, Dynamic Type up to AX5, Dark Mode, VoiceOver labels on every control and result, Reduce Motion respected, monospaced digits (`.monospacedDigit()`) so live numbers don't jitter.
- **Honest data:** show what was measured or observed and where it came from ("RIPE RIS, 23 collectors, updated 12:32 UTC"). Never invent values.
- **Private:** no accounts, analytics, ads or tracking. Network traffic goes only to the probe target and `stat.ripe.net`.

---

## 2. Information architecture & navigation

### 2.1 iPhone (compact width)
`TabView` with three tabs, each with its own `NavigationStack`:

| Tab | Title | SF Symbol |
|---|---|---|
| Ping | Ping | `dot.radiowaves.left.and.right` |
| Traceroute | Traceroute | `point.topleft.down.to.point.bottomright.curvepath` |
| BGP Map | BGP Map | `point.3.connected.trianglepath.dotted` |

Each tool's toolbar (trailing): **Share** (`square.and.arrow.up`, disabled until results exist) and **Settings** (`gearshape`, opens that tool's settings sheet; BGP has no settings, so it shows only Share). The Settings sheet ends with an **About** section: version, privacy summary, "Source code on GitHub", licence, "BGP data: RIPE NCC RIPEstat" attribution, and Clear History.

Large navigation titles in the empty state; inline titles once results exist (the BGP Map always uses inline, to give the graph room).

### 2.2 iPad (regular width)
`NavigationSplitView` (two columns, `.balanced`):
- **Sidebar:** "IP Tools" title.
  - Section *Tools:* Ping, Traceroute, BGP Map.
  - Section *Recent:* the shared recents. Tapping one opens the tool it was last used with and fills in the target. It does not auto-start.
  - Footer row: Settings (opens a sheet that has all three tools' settings plus About).
- **Detail:** the selected tool's view, the same view as on iPhone, laid out wider.
- **Inspector** (`.inspector(isPresented:)`, BGP Map only): AS details for the selected node. It replaces the iPhone's selection card and sheet.
- The window can be resized to compact (Slide Over or narrow Split View). `RootView` then falls back to the tab layout. State lives in models owned above the layout switch, so nothing is lost.

### 2.3 Cross-tool links (via `AppRouter`)
- Traceroute hop → context menu: **Ping this hop**, **Map in BGP**, Copy IP, Copy Hostname.
- Traceroute hop ASN badge (tap) → BGP Map for that hop's IP.
- BGP AS details → **Map prefixes of ASxxxx** (ASN input) and **Copy ASN**. **Open in RIPEstat** opens `https://stat.ripe.net/AS<n>` in Safari via `openURL`.
- Ping or Traceroute result header → **Map in BGP** button (shown when the target is a public address).

The router switches tool/tab and hands over the target. Cross-links **pre-fill and auto-start** (the user asked for a specific action). Recents only pre-fill.

**(v1.1)** When the Traceroute tab opens the BGP Map (header **Map in BGP**, hop **Map in BGP**, or a hop's ASN badge) after its run has *finished or stopped*, the request also carries a `TraceSnapshot` (§12.7). For the trace target it is the whole trace; for a hop it is the hops up to and including that hop. BGP "Your route" reuses it instead of probing again (§6.11.2). Ping's **Map in BGP** carries no snapshot.

### 2.4 Keyboard (iPad hardware keyboard)
⌘1/⌘2/⌘3 switch tool · ⌘L focuses the target field · ⌘R or Return starts · ⌘. stops · ⌘⇧C copies results.

---

## 3. Shared components

### 3.1 Target bar (`TargetInputBar`)
- A rounded text field (fill: `quaternarySystemFill`) with a leading tool glyph, a trailing clear button, and the **primary button** to its right:
  - Ping/Traceroute: **Start** (`.borderedProminent`, tint `.blue`). While running it becomes **Stop** (tint `.red`).
  - BGP: **Map**. While loading it becomes **Cancel**.
  - The button is disabled while the field is empty or invalid, or while offline (except Stop/Cancel).
- Placeholders: Ping/Traceroute "IP address or hostname"; BGP "IP, prefix, ASN or hostname".
- Text input settings: `.keyboardType(.URL)`, `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()`, `.submitLabel(.go)`. The input is trimmed. A full URL (`https://example.com/x`) is reduced to its host. `[2001:db8::1]` brackets and `%zone` suffixes are accepted.
- **Validation (live and local, no network):** `TargetParser` classifies the input as IPv4, IPv6, hostname, prefix (`a.b.c.d/n` or `x::/n`, BGP only) or ASN (`AS13335`, `as13335`, `13335` with ≤10 digits, BGP only). For ping/trace, a bare number is treated as invalid rather than as a hostname. Invalid input gets a red footnote under the field ("Not a valid IP address or hostname"). This does not block typing.
- **Recents dropdown:** when the field is focused and empty (or its text matches a prefix of a recent), a list of up to 5 matching recents appears below the bar. Each shows the target and "Ping · 2 min ago". Swipe to delete.
- **Recents store:** one shared list, newest first, max 20, de-duplicated case-insensitively by normalized target, persisted in `UserDefaults` (`recents.v1`, JSON). An entry is added when a run *starts successfully* (after resolution), not on every keystroke.

### 3.2 Run header (`RunHeader`)
One line under the bar, showing the run state: a pulsing green dot (static when Reduce Motion is on) followed by "Pinging **1.1.1.1** · one.one.one.one · 56 bytes". Once stopped: "Stopped after 20 pings". If the input was a hostname: "example.com → 93.184.215.14 (IPv4)".

### 3.3 Offline banner
`NetworkMonitor` wraps `NWPathMonitor`. When the path is not satisfied, a yellow banner appears under the target bar: `wifi.slash` "You're offline. Connect to run Ping, Traceroute or BGP Map." Primary buttons are disabled. A run in progress keeps going; ICMP will report errors on its own. Recents can still be browsed.

### 3.4 State views
Every tool renders one of: **Empty** → **Resolving/Loading** → **Running/Results** → **Finished**, or **Error**. Errors use `ContentUnavailableView` with a title, a description and a **Try Again** button. Errors in the middle of a run (e.g. send failures) appear inline in rows, and the screen keeps working.

### 3.5 Share / copy
`ShareLink(item: String)` with a plain-text export that mimics CLI output (formats in §4.6, §5.6, §6.10). Long-press on any row → Copy. BGP can also share an **image of the graph** (`ImageRenderer` → PNG).

### 3.6 Colours & thresholds
- RTT colour, used as a dot or tint and always next to the number: `< 80 ms` green, `80–199 ms` orange, `≥ 200 ms` red, timeout `tertiaryLabel` grey.
- The app tint is system blue. The BGP origin node uses tint fill. The selected path uses tint stroke.

---

## 4. Ping

### 4.1 Layout (iPhone, top to bottom)
1. Target bar + Start/Stop.
   - **(v1.1) Options row** under the bar: the **count chip** "10 pings ▾" (§4.3.1), then "every 1 s · 56 bytes" in secondary text. Tapping that text opens Ping Settings.
2. Run header. While running it includes progress: "Pinging **1.1.1.1** · 3 of 10 · 56 bytes" ("· 3 sent" when the count is Until stopped).
3. **Stats grid** (card, 3 × 2): Min · Avg · Max · Jitter · Loss (orange if > 0, red if ≥ 50 %) · Received "19 of 20". The values are `--` until the first reply arrives.
4. **RTT chart** (card, height 140 pt, Swift Charts): `LineMark` + `PointMark` for RTT (ms) against sequence number. Only the last 60 samples are shown, so it scrolls. Timeouts are red `xmark` marks on the x-axis baseline, and the line breaks at them. A dashed `RuleMark` shows the average. The y-axis starts at 0 and ends at a "nice" max (≥ max RTT × 1.2). `chartXAxis` labels the first and last sequence numbers. Accessibility: `.accessibilityChartDescriptor` gives a summary ("20 samples, min 11.8, avg 14.2, max 22.3 ms").
5. **Replies list** (newest first): colour dot · `#seq` · "64 bytes · ttl 58" · RTT "13.6 ms" (semibold, monospaced digits). A timeout row reads "Request timed out" in secondary colour. An error row shows a red message (e.g. "Destination unreachable (host)").

On iPad (regular width), the stats grid and chart sit side by side above the list.

### 4.2 States
| State | UI |
|---|---|
| Empty | `ContentUnavailableView("Ping a Host", systemImage: "dot.radiowaves.left.and.right", description: "Measure round-trip time to any IPv4 or IPv6 address or hostname.")` + example chips `1.1.1.1`, `2606:4700:4700::1111`, `apple.com`, + recents |
| Resolving | Run header "Resolving apple.com…" with a `ProgressView`. Stop is available. |
| Running | As in the layout. Rows stream in. |
| Finished | Header "Finished · 20 sent, 19 received". Start reads "Start" again. Results stay visible until the next Start. |
| Stopped by user | Header "Stopped". Results stay. |
| Resolve error | ContentUnavailableView "Couldn't Resolve apple.cmo" + "Check the spelling or your DNS." + Try Again |
| No address for chosen IP version | "apple.com has no IPv6 address" (when the preference is IPv6 only) |
| Send error (fatal) | e.g. `ENETUNREACH` on the first send: "No IPv6 route — this network doesn't support IPv6." Run stops. |
| Local network denied | "Local Network access is off" + button **Open Settings** (`UIApplication.openSettingsURLString`) |
| Offline | Offline banner, Start disabled |
| App backgrounded | The run is stopped when `scenePhase` becomes `.background` (not on `.inactive`, so system alerts, Control Center and the Local Network prompt don't stop it). Header: "Stopped — app moved to background". |

### 4.3 Settings (sheet, "Ping Settings")
| Setting | Options | Default |
|---|---|---|
| Count | 5, 10, 20, 50, 100, Until stopped, **Custom… (1–10,000)** (v1.1) | **10** |
| Interval | 0.2, 0.5, 1, 2 s | **1 s** |
| Timeout | 1, 2, 5 s | **2 s** |
| Packet size (payload bytes) | 16, 56, 120, 512, 1024, 1472 (v4) / 1452 (v6) | **56** |
| IP version (shared with Traceroute) | Automatic, IPv4, IPv6 | **Automatic** |

Nothing else (no TTL, no DF bit, no QoS). "Automatic" uses the first address `getaddrinfo` returns with `AI_ADDRCONFIG`. That follows the system's RFC 6724 ordering, so it prefers IPv6 on IPv6-capable networks, just as Safari would.

#### 4.3.1 Count chip on the Ping screen (v1.1)
Owner request: "on default 10 ping, add option user can change how many ping must be". Count used to live only behind the gear, and nobody found it.

- **Placement:** an options row directly under the target bar, on iPhone and iPad: `[10 pings ▾]  every 1 s · 56 bytes`. The chip is a SwiftUI `Menu` styled as a capsule (fill `quaternarySystemFill`, tint text, footnote semibold, min height 32 pt, hit area 44 pt). The label reads "5 pings", "10 pings", "37 pings", "1 ping" or "Until stopped".
- **Menu contents** (a `Picker(.inline)` inside the `Menu`, with the current value checked): 5 · 10 · 20 · 50 · 100 · Until stopped · divider · **Custom…**. When the current count is not a preset, a checked row "Custom (37)" appears above "Custom…".
- **Custom…** opens an `.alert("Number of Pings")` with a `TextField` (`.keyboardType(.numberPad)`, pre-filled with the last custom value) and the message "Between 1 and 10,000." **Set** is disabled unless the text is an integer in 1...10_000. **Cancel** keeps the old value. Values over 10,000 show the message in red. No other validation UI is needed.
- **One value, two places.** The chip and the settings sheet both bind `SettingsStore.ping.count` (`Int?`, `nil` = Until stopped; already persisted in `settings.v1`). The settings sheet's Count picker gets the same "Custom (37)" row and a "Custom…" button that opens the same alert. The last custom value is remembered for pre-filling in `@AppStorage("ping.lastCustomCount")`, which lives in PingFeature, so SharedUI is unchanged.
- **While running** (`resolving` or `running`): the chip is `.disabled` (secondary text, no chevron tint). The run uses the count captured at Start. The run header shows "3 of 10". On Finished it shows "Finished · 10 sent, 10 received" as before. A changed count takes effect on the next Start.
- **VoiceOver:** "Ping count, 10 pings, pop-up button. Double-tap to change." While disabled, the hint is "Available when ping is stopped."
- **Keyboard (iPad):** no new shortcut. The chip is reachable with Tab.

### 4.4 Statistics definitions (`PingStatistics`)
- `sent`: probes whose outcome is known (reply, timeout or error). In-flight probes are not counted.
- `received`: replies. `loss = 1 − received/sent`.
- `min/avg/max`: over replies. `stddev`: population standard deviation.
- `jitter`: mean absolute difference between consecutive *received* RTTs (RFC 3550-style, without smoothing).
- Late replies (arriving after the timeout) are ignored and the probe stays a timeout. Duplicate replies are ignored.

### 4.5 Sequence behaviour
Probes are sent on a fixed schedule (`t0 + n·interval`) regardless of replies. Each probe times out on its own. Outcomes can complete out of order (when timeout > interval), so the list is sorted by sequence.

### 4.6 Export text
```
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: icmp_seq=0 ttl=58 time=13.2 ms
Request timeout for icmp_seq 10
...
--- 1.1.1.1 ping statistics ---
20 packets transmitted, 19 packets received, 5.0% packet loss
round-trip min/avg/max/stddev = 11.8/14.2/22.3/2.1 ms, jitter 2.3 ms
— IP Tools for iOS, 2026-11-07 12:34 UTC
```

---

## 5. Traceroute

### 5.1 Layout
1. Target bar + Start/Stop.
2. While running: run header "Tracing 8.8.8.8 · hop 7 of max 30" with a determinate `ProgressView` (hop/maxHops). After a finish that reached the target: **summary card** with a green `checkmark.circle.fill`, "Reached dns.google in 10 hops", "8.8.8.8 · AS15169 Google · 12.9 ms". If not reached: orange `exclamationmark.triangle` "Didn't reach 8.8.8.8 within 30 hops".
3. Column caption: `HOP · HOST · AVG · 3 PROBES (MS)`.
4. **Hop list.** One row per TTL:
   - Leading: hop number in a circle (green filled for the destination).
   - Title: reverse-DNS hostname (middle-truncated) or the IP if there is no PTR.
   - Subtitle: **ASN badge** ("AS7922 Comcast", tappable) or a grey "Private" badge for RFC 1918/CGNAT/ULA/link-local addresses, followed by the IP when the title is a hostname.
   - Trailing: average RTT (semibold), with the three probe RTTs below it in caption2 ("9.4 · 8.9 · 10.2"). Lost probes show as `*`.
   - No reply at all: title "No reply", subtitle `* * *`, trailing "—".
   - If probes for one TTL came back from **different addresses** (ECMP), show the first address as the title and add "+1 other". The full list appears in the context menu.
5. Rows appear live. A placeholder row ("Hop 7…" with a spinner) shows the hop being probed.

### 5.2 States
Same pattern as Ping. Empty: `ContentUnavailableView("Trace a Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: "See every router between you and a host, with response times and the network (AS) each one belongs to.")` + examples `8.8.8.8`, `1.1.1.1`, `apple.com`. Finished, stopped, error, offline, local-network-denied and backgrounded states are as for Ping. The hops found so far stay visible on stop or error.

Destination-unreachable replies (ICMP type 3 / ICMPv6 type 1) end the trace. They are labelled on the row ("!H host unreachable", "!N net unreachable", "!P prohibited") and summarised as "Stopped: host unreachable at hop 9".

### 5.3 Settings ("Traceroute Settings")
| Setting | Options | Default |
|---|---|---|
| Max hops | 15, 30, 64 | **30** |
| Timeout per probe | 1, 2, 3 s | **2 s** |
| Probes per hop | 1, 3 | **3** |
| Resolve hostnames (reverse DNS) | on/off | **on** |
| Look up networks (ASN, via RIPEstat) | on/off | **on** |
| IP version (shared) | Automatic, IPv4, IPv6 | Automatic |

Footnote under the ASN toggle: "Sends the public hop IP addresses to RIPEstat (RIPE NCC) to find which network they belong to."

### 5.4 Probing algorithm (summary; details in §10)
For `ttl` in `1...maxHops`: set the hop limit and send `probesPerHop` echo requests back-to-back (about 10 ms apart). Wait until all have answered or the per-probe timeout has passed, then emit `hopFinished`. Stop when an Echo Reply comes from the target (`reachedDestination`), when Destination Unreachable arrives, or when `maxHops` is reached. The worst case is 30 silent hops × 2 s = 60 s. That is acceptable for v1 because results stream in. One possible future speed-up is a sliding window of 3 TTLs in flight.

### 5.5 Enrichment (in `TraceModel`, not in the prober)
- **Reverse DNS:** for each new distinct hop address, call `Resolver.reverseName(for:timeout: 2s)` concurrently (at most 4 in flight). Results are cached for the session.
- **ASN:** for each new distinct public hop address, call RIPEstat `network-info` (at most 4 in flight, cached in memory for the app session, keyed by IP). The prefix it returns is also cached, so other IPs in that prefix can reuse the result. Then one `as-names` bulk call names the ASNs. It is re-run as new ASNs appear, debounced by 500 ms. Failures leave the badge blank, with no error UI. If the setting is off, no request is made.

### 5.6 Export text
```
traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 3 probes
 1  router.lan (192.168.1.1)  1.8 ms  2.0 ms  1.7 ms
 2  96.120.24.29 [AS7922]  9.4 ms  8.9 ms  10.2 ms
 ...
 7  * * *
10  dns.google (8.8.8.8) [AS15169]  12.9 ms  12.6 ms  13.1 ms
— IP Tools for iOS, 2026-11-07 12:34 UTC
```

---

## 6. BGP Map

### 6.1 Input handling
| Input | Example | Resolution |
|---|---|---|
| IPv4 / IPv6 address | `1.1.1.1` | `network-info` (prefix + origin) ‖ `looking-glass?resource=<ip>` (RIPEstat expands the IP to its covering routed prefix, as verified) |
| Prefix | `1.1.1.0/24`, `2606:4700::/32` | `prefix-overview` (origins + holder + announced) ‖ `looking-glass?resource=<prefix>` |
| ASN | `AS13335`, `13335` | `as-overview` (holder) + `announced-prefixes` → **prefix picker** sheet (searchable list, IPv4 first, then shortest prefix first; shows a count, e.g. "5,748 prefixes"). Choosing a prefix maps it. A shortcut, "Map most-specific of first 50", is *not* offered, to keep it simple. |
| Hostname | `cloudflare.com` | Resolve on-device (`Resolver`, preference Automatic), then treat as an IP. The header shows "cloudflare.com → 104.16.132.229". |
| Private / reserved | `10.1.2.3`, `192.168.0.0/16`, `fd00::/8`, `AS64512` | Detected locally, no request: "10.0.0.0/8 is a private range and isn't routed on the public Internet." (Private ASNs 64512–65534 and 4200000000–4294967294 get the same treatment.) |

`looking-glass` returns `400` for ASNs (verified: "AS13335 is of unsupported type ASN"). The ASN flow therefore always goes through the picker.

Request plan per map, run as a `TaskGroup` with the whole group cancellable:
1. Parallel: `looking-glass` + (`network-info` | `prefix-overview`) + `routing-status` (visibility, optional, non-blocking).
2. After the graph is built: **one** `as-names` call with every ASN in the *collapsed* graph plus the ASNs in "+more" buckets. It is chunked at 200 ASNs per request to keep URLs under ~2 KB.
3. The graph appears as soon as step 1 is done, with "AS13335" labels. Names fade in after step 2.

### 6.2 Screen layout (iPhone)
1. Inline title "BGP Map", Share in the toolbar. Below it the target bar + **Map**.
2. **Prefix header card:** prefix in SF Mono bold 20 pt ("1.1.1.0/24"). "Origin [AS13335] Cloudflare, Inc." (the ASN badge is tappable → AS details). Chips: "360 paths" · "23 collectors" · "Seen by 319/319 peers" (from `routing-status`, omitted if it fails) · "Updated 12:32 UTC" (on iPad, or in details on iPhone). A MOAS warning chip appears if there are several origins: "2 origin ASes".
3. **Segmented control:** Graph | List (`Picker(.segmented)`). The default is Graph, or List when `accessibilityVoiceOverEnabled` is on. The choice is remembered per session.
   **(v1.1) Replaced** by `Your route | All routes` (§6.11.1). Graph/List becomes a toggle inside All routes (§6.12). The header card's chips move into the All routes summary.
4. **Graph canvas:** fills the remaining height. Rounded container, subtle background (`secondarySystemGroupedBackground`). A floating **Fit** button (`arrow.up.left.and.arrow.down.right`) sits bottom-right.
5. **Selection card** (floating, above the tab bar, appears when a node is selected): "AS3356 · Level 3 Parent, LLC" / "Transit · 4 paths (1.1%) · 1 hop from origin" / **Details ›**. Details opens a sheet with `.presentationDetents([.medium, .large])` showing `ASDetailView`. Tapping empty canvas clears the selection.
6. Toolbar menu (`ellipsis.circle` on iPhone; "Top 6 ▾" on iPad): **Show per row:** Top 6 (default) · Top 12 · Top 30. **Share as text / Share as image**.

### 6.3 Graph construction (`GraphBuilder`): exact rules
Input: an `[ObservedPath]`, one per RIS peer route (`as_path` split on spaces, peer first, origin last).

1. **Clean each path.**
   a. Tokens of the form `{a,b,…}` (AS_SET) are dropped, and the path is flagged `hadASSet`.
   b. Prepending is collapsed: consecutive duplicates are reduced to one.
   c. If an ASN still appears twice (a loop or poisoning), the path is discarded (`discardedPaths += 1`).
   d. Empty paths are discarded.
2. **Origins:** the set of last ASNs. The primary origin is the most frequent one. If there is more than one origin → MOAS. All origins go in layer 0.
3. **Counts per AS:** `pathCount[a]` = number of cleaned paths that contain `a`. `transitCount[a]` = number of paths where `a` is neither first nor last. `isPeer[a]` = `a` is the first ASN of at least one path (it is itself a RIS peer).
4. **Edges:** for each consecutive pair `(p[i], p[i+1])`, add a directed edge `from → to` (toward the origin) and increment its `pathCount`.
5. **Layers:** BFS from the origins over *reversed* edges. `layer[a]` = shortest graph distance to any origin. (Shortest graph distance is used, not position in the path. That guarantees every non-origin node has at least one edge into the next column.) Edge kind: `forward` if `layer[from] == layer[to] + 1`, `lateral` if the layers are equal, `backward` if `layer[from] < layer[to]`. A 2-layer skip is impossible by construction.
6. **Rank within layer:** `score = pathCount + transitCount`. Transit paths count double, so real upstreams rise above route-server peers. Ties are broken by lower ASN.
7. **Collapse:** keep the top *K* per layer (K = 6, 12 or 30; the origin layer is never collapsed). The rest go into one node, `.more(layer:)`, with `collapsed = [ASN]` and `pathCount = Σ`. Edges are re-pointed to the bucket, parallel edges are merged (counts summed), and self-loops are dropped.
8. **Output:** `ASGraph(nodes, edges, origins, totalPaths, discardedPaths, layerCount)`. The cleaned paths are kept so the graph can answer `paths(through:)` for highlighting and details.

Sanity check against real data (1.1.1.0/24, 2026-11-07): 360 paths from 23 collectors, 296 ASes, 4 layers (1 / 240 / 48 / 7 ASes). With K = 6 there are 22 nodes and ~27 edges, which is readable. The mockup graph was generated by a reference implementation of exactly these rules.

### 6.4 Layout (`LayeredLayout`): exact rules
Coordinates are in points, before zoom. **The graph is vertical: layers are rows, the origin row is at the BOTTOM, and edges flow downward toward the destination.**
- Metrics: node 104 × 44, node gap 10 (within a row), row gap 44, padding 16, row caption band 18.
- **Rows:** each row is a caption band plus a node band. `y(layer) = padding + (maxLayer − layer) × (18 + 44 + 44) + 18`. Layer 0 (origin) is the bottom row, the farthest networks are at the top. Each row has a left-aligned caption above it: "ORIGIN", "1 HOP", "2 HOPS"…
- **Order within a row (barycentre, deterministic, left to right):**
  1. Layer 0: origins sorted by `pathCount` descending.
  2. For layer `k = 1…max`: sort the nodes by the weighted mean index of their forward-edge targets in layer `k−1` (weights = edge `pathCount`, at least 1). Ties go to higher score, then lower ASN.
  3. One refinement pass from `k = max−1` down to 1, using the mean index of incoming forward sources in layer `k+1`. Accept the new order only if the count of crossing forward edges does not increase.
  4. The `.more` bucket is always last (rightmost) in its row.
- **Horizontal:** each row is centred against the widest row. `x = padding + (W − rowWidth)/2 + i × (104 + 10)`.
- **Edges:** forward edges are cubic Béziers from the source's bottom-middle to the target's top-middle, with control points at the vertical midpoint (`c1 = (x1, my)`, `c2 = (x2, my)`). Lateral and backward edges arc *above* the row: from the source's top-middle to the target's top-middle, with control points pulled up by `min(40, 18 + |Δx|·0.2)`. They are drawn **dashed**.
- **Stroke width** = `1.5 + 6 × √(edge.pathCount / totalPaths)`, so roughly 1.5–7.5 pt. Colour is `secondaryLabel` at 0.35 opacity. Edges are drawn in ascending count, so thick edges sit on top. Highlighted edges are drawn last. Your-path edges (§6.11) are at least 3 pt wide.
- **Canvas size** = `(padding·2 + W) × (padding·2 + (L+1)·(18+44) + L·44)`, where `W` is the widest row and `L = maxLayer`.

### 6.5 Rendering & interaction (`GraphCanvasView`)
- **Orientation and opening view:** vertical (§6.4). The graph opens at `scale = min(1.0, max(0.7, viewH/canvasH))`, ignoring the width, so it never opens zoomed in past 1×. Horizontally it centres on the your-path span (the blue overlay nodes plus the origin) when that span fits the view; if it does not, it favours the YOU node (the overlay node farthest from the origin) and shows as much of the origin as fits. With no overlay it centres on the origin node. It is clamped so the graph never leaves a gap at either side when it is wider than the view. When the overlay arrives after the graph and the user has not panned or zoomed, the opening view is re-applied so it centres on the path. A graph shorter than the view is centred vertically. A taller one is anchored with the origin row at the bottom edge and the rest is reached by panning. The Fit button and a double-tap still show the whole graph. The Fit button lives in the header row, not over the canvas, so it never covers a node.
- **Header:** collapsed by default to one compact line (prefix, origin, your-path status, Graph/List, Fit, an info button). The info button or the line expands the full card (prefix, origin, chips, your-path chip). The state is kept for the session only.
- **Edges:** one SwiftUI `Canvas`, drawing the paths from `EdgeGeometry`. **Nodes:** real SwiftUI `Button`s positioned with `.position()` in a `ZStack` of the canvas size, so hit testing and VoiceOver come for free. The whole stack gets one `.scaleEffect(scale, anchor: .topLeading)` + `.offset(pan)`.
- **Gestures:** `MagnifyGesture` (scale 0.3…3.0, anchored at the pinch location) running simultaneously with `DragGesture` (pan, clamped so at least 80 pt of graph stays visible). Double-tap on empty space toggles between "fit" and 1.0× at that point. The Fit button animates to fit.
- **Node view:** a rounded rect with corner radius 10.
  - Line 1: "AS13335", semibold 14 pt, monospaced digits.
  - Line 2: short name (caption 11 pt, secondary, 1 line, tail-truncated).
  - The origin is filled with tint and uses white text.
  - A small green dot at top-right means `isPeer`.
  - The `.more` bucket has a dashed outline, reads "+234 more" / "328 paths", and opens a list sheet when tapped.
  - Dynamic Type: node text scales up to `.xxLarge` (`dynamicTypeSize(...DynamicTypeSize.xxLarge)`). At larger sizes List mode is better, and the graph shows a hint chip saying so.
- **Selection:** tapping a node selects it. Every path through it is highlighted: tint stroke at +1 pt width on edges, nodes stay at full opacity. All other nodes drop to 0.35 opacity. Haptic `.selection`. On iPhone the selection card appears; on iPad the inspector opens.
- **Performance budget:** K ≤ 30 means at most ~4 × 31 nodes. `Canvas` redraws are cheap, and layout is computed once per (graph, K) off the main actor.

### 6.6 AS details (`ASDetailView`, sheet on iPhone / inspector on iPad)
- "SELECTED AS" caption, "AS3356" (title), holder name in full (from `as-names`).
- Badges: role (**Origin** / **Transit** = transitCount > 0 / **Peer** = only ever first) · "1 hop from origin".
- Tiles: "Paths through: 4 (1.1% of 360)" · "Collectors: 2 (RRC00, RRC25)".
- "Paths through AS3356": the unique cleaned paths, monospaced, with the selected ASN in tint. The list is capped at 50 and has a "Show all" link.
- For a `.more` bucket: a list of the collapsed ASes (ASN, name, paths). Tapping one promotes it: K grows just enough to show it, and it is selected.
- Actions: **Map prefixes of AS3356** (goes through the ASN flow), **Copy ASN**, **Open in RIPEstat** (Safari).

### 6.7 List mode (accessibility fallback, `BGPListView`)
An inset grouped `List`:
- **Origin** section: a row with ASN, name, path count and a bar.
- One section per layer, e.g. "1 hop from origin · 240 ASes". Rows show ASN, name and role, with a horizontal bar (`pathCount / totalPaths`) and the count. The top K are shown, then "Show all 240" (all ASes, uncollapsed, sorted by score).
- **AS paths** section, e.g. "· 268 unique": unique paths with the collector count, sorted by frequency.
- Each row's VoiceOver label: "AS 3356, Level 3 Parent, transit, 4 paths, 1 hop from origin". Tapping opens `ASDetailView`.

### 6.8 VoiceOver in Graph mode
The canvas is `.accessibilityElement(children: .contain)` with the label "AS path graph, 22 networks, 4 rows". Nodes are ordered row by row from the origin outward (`.accessibilitySortPriority`). Each node is a button with the same label as its List row, plus the hint "Double-tap to highlight its paths". A rotor action switches to List.

### 6.9 States
| State | UI |
|---|---|
| Empty | `ContentUnavailableView("Map BGP Paths", systemImage: "point.3.connected.trianglepath.dotted", description: "See how networks around the world reach an IP address, prefix or AS — live routes from RIPE RIS collectors.")` + chips `1.1.1.1`, `8.8.8.0/24`, `AS13335` + recents (mockup) |
| Loading | Header skeleton (`redacted(.placeholder)`), canvas with a centred `ProgressView("Fetching routes from RIPEstat…")`, Cancel button |
| ASN picker | Sheet: "Prefixes announced by AS13335", search field, sections IPv4 / IPv6 |
| Not announced | `network-info` returns `asns: []` / `prefix: ""`, or `looking-glass` returns `rrcs: []` → "1.2.3.4 isn't announced in BGP right now" (icon `antenna.radiowaves.left.and.right.slash`) |
| Private / reserved | Local message as in §6.1 |
| Low visibility | Paths < 3 → the graph is still shown, with the chip "Seen by few collectors" |
| Rate-limited (HTTP 429) or 5xx | "RIPEstat is busy. Try again in a moment." + Try Again |
| Timeout (> 30 s) | "RIPEstat didn't respond." + Try Again |
| Offline | Offline banner, Map disabled |

### 6.10 Export
Text:
```
BGP paths for 1.1.1.0/24 (origin AS13335 Cloudflare, Inc.)
Source: RIPE RIS via RIPEstat looking-glass, 23 collectors, 360 paths, 2026-11-07 12:32 UTC
Upstreams (1 hop): AS24482 SG.GS (10), AS3356 Level 3 (4), ...
Unique AS paths:
  24482 13335   ×10
  924 6939 3356 13335   ×1
  ...
```
Image: an `ImageRenderer` of the graph at 2× scale, with a caption.

### 6.11 Your route (v1.1)

> **Update (owner request).** The BGP Map keeps the v1.0 UI: one graph with a Graph/List control, the prefix header and the selection card. The "Your route | All routes" tabs, the vertical/horizontal chain views, the All routes summary card and the legend were removed. The measuring logic below (`YourRouteModel`, `RouteMeasurer`, `MyNetworkLocator`, `ASChainBuilder`) still runs in the background. Its result is drawn **on the graph as a blue overlay**: the path's edges are blue (solid for measured and BGP-sourced hops, dashed for the unknown stretch), its nodes have a blue outline, and your own AS has a "YOU" badge. ASes of the path that no RIS route contains are added to the graph (`GraphBuildOptions.highlightPath`, with no route counts, so all counts and stats are unchanged). A header chip shows "Measuring your path…", "━ Your path" or "Your path: partial"; tapping it, or the YOU node, opens the AS details with the "On your route" section. List mode tags these ASes "Your path", and the text export gets one "Your path: …" line. The layout, chain and card descriptions in the rest of this section are historical.


**Problem.** Owner: "Can the BGP map show the current path? It is so unclear." The graph shows ~300 routes *other* networks use toward the origin. It never shows the route the user's own traffic takes, and first-time users can't read it.
**Goal.** In one glance a non-expert sees "this is the path my traffic takes": a short chain of networks from *you* to the destination.

```
You · AS24940 Hetzner  →  AS13335 Cloudflare  →  AS15169 Google · 8.8.8.0/24
```

#### 6.11.1 Placement & navigation
- Under the prefix header card is a segmented control, **`Your route | All routes`** (`Picker(.segmented)`, `BGPMapModel.view: BGPView`). **Your route is the default**, also when VoiceOver is on, because the chain is already a list. The choice is remembered for the app session.
- **List is not a third segment.** It is another representation of All routes, so it lives inside All routes (§6.12). Three segments would mix "what" with "how".
- The **prefix header card** becomes compact in both views: prefix (SF Mono bold 20 pt) and "Origin [AS15169] Google LLC". Its chips move to the All routes summary.
- **iPad:** the same segmented control sits in the detail column under the header. Tapping a chain node opens the existing **inspector** (§6.6) with an extra "On your route" section (§6.11.8).
- **Share** (toolbar) exports the visible view: the route text (§6.11.11) in Your route, §6.10 in All routes.

#### 6.11.2 Where the chain comes from (decision order)
Evaluated once the BGP fetch (§6.1 step 1) **and** "your network" (§6.11.3) have both finished. The first rule that applies wins:

| # | Source | Condition | Label shown |
|---|---|---|---|
| 1 | **Handed-over trace** | The router request carried a `TraceSnapshot` whose `target.address` equals the address being mapped (IP/hostname input), and it is ≤ 10 min old | "Measured by traceroute" + "from your traceroute at 12:41" |
| 2 | **BGP from your network** (Source A) | `myASN` is known and appears in ≥ 1 cleaned RIS path for this prefix | "Seen in BGP from your network" |
| 3 | **Fresh traceroute** (Source B, the common case) | otherwise, and the target is publicly routable | "Measured by traceroute" |

- Rule 2 needs no probing, so it is instant. Its footer offers **Measure with traceroute**, which forces rule 3 and replaces the chain with the measured one.
- Rule 3 is the common case. Verified 2026-11-08 from AS24940: none of the 369 RIS routes to 8.8.8.0/24 contain AS24940. Most user networks (home ISPs, mobile carriers, clouds) are not RIS peers.
- **Measure again** (footer, `arrow.clockwise`) always runs rule 3.

#### 6.11.3 Locating your network
1. `GET whats-my-ip/data.json?sourceapp=…` (no `resource`) → `data.ip` (verified: `{"ip":"91.107.240.242"}`). RIPEstat echoes the source address of the HTTPS connection, which it already sees on every request.
2. `network-info?resource=<that ip>` → `asns[0]` = `myASN`, `prefix` (verified: `91.107.240.242` → `{"asns":["24940"],"prefix":"91.107.128.0/17"}`).
3. The name comes from the same bulk `as-names` call as the graph (`myASN` is added to the list).
- Both run **in parallel with** the §6.1 requests (the client cap of 4 concurrent still holds). `whats-my-ip` is **never served from the response cache**.
- The result is cached as `MyNetwork` for the app session. It is invalidated when `NetworkMonitor.pathGeneration` changes (Wi-Fi ↔ cellular, VPN up/down) or after 30 min.
- If several ASNs come back, the first is used. If `asns` is empty or the call fails, `myASN = nil`. This is **not fatal**: the first node becomes "Your network", with no ASN.
- The address family doesn't matter. If RIPEstat saw IPv6 but the target is IPv4, the ASN is almost always the same. A different ASN is handled by rule 5 of §6.11.5.

#### 6.11.4 Source A: chain from a RIS path (`ASChainBuilder.fromBGP`)
1. Input: `graph.cleanedPaths` (prepends collapsed, loops and AS_SETs removed, §6.3 rule 1), `myASN`, origins.
2. For every path containing `myASN` at index *i*, take the suffix `p[i...]` (it always ends at an origin).
3. Group identical suffixes. Choose the one with the most paths. Ties go to the shorter suffix, then the lexicographically smaller ASN list.
4. Nodes: `suffix[0]` → role **you**. Middle ASNs → **transit**. Last → **destination**. Provenance `.bgp`. Each node gets `routeCount` (the paths with that suffix) and the collectors that saw them.
5. If `myASN` is an origin, the chain is one node, role `youAndDestination`.
- Caption under the status: "Your network announces this route to RIPE collectors RRC01 (London) and RRC03 (Amsterdam)." With the `bgp-state` fallback there are no locations, so only "RRC01, RRC03" is shown.

#### 6.11.5 Source B: quick traceroute (`RouteMeasurer`)
**Probe target:** IP input → that IP. Hostname → the address already resolved for the map. Prefix → the first usable address (IPv4 /≤30: network + 1; /31–/32: network; IPv6: network + 1). ASN → the chosen prefix, as for a prefix.
**Probe options (fixed, not the user's Traceroute settings):** `TraceOptions(maxHops: 30, probesPerHop: 2, timeout: 1.5)`. The IP version follows the probe target's family.
**Hop → ASN:** for each new public hop address, `api.networkInfo(ip)` (the client's 5-min cache and 4-request cap apply). Names come from a debounced (500 ms) `as-names` bulk call, as in §5.5. **This only happens if Settings › Traceroute › "Look up networks" is on.** If it is off, see the states table, §6.11.9.
**Stop rules** are checked after every trace event *and* every ASN result. The trace task is cancelled on the first one that applies:

| Rule | Condition | Outcome |
|---|---|---|
| a | Echo Reply from the probe target | done, `reachedTarget = true` |
| b | Destination Unreachable | done if the last AS is an origin, else partial |
| c | Prefix-derived target, and a hop's ASN is an origin | done ("Reached Google's network at hop 8"), with no need to hit `.1` |
| d | Origin AS already reached, then 3 silent hops in a row | done ("Reached Google's network. 8.8.8.8 itself didn't answer.") |
| e | 5 silent hops in a row before any origin hop | **partial** (stalled) |
| f | `maxHops` reached | done if the last AS is an origin, else partial |

A typical run takes 5–15 s. Lifecycle:
- It starts automatically when rule 3 is chosen, even if the user is looking at All routes.
- It is cancelled by a new **Map**, by **Cancel**, by the status card's **Stop**, or when the app moves to the background ("Stopped: app moved to background", with the known part kept as partial).
- It does not touch the Traceroute tab's state and does not add a recent (the map already did).
- Public targets never trigger the Local Network prompt.

#### 6.11.6 Building the chain from hops (`ASChainBuilder.fromTrace`): exact rules
Input: `[ChainHop]` ordered by TTL, `myASN?`, origins, `finished: Bool`. The builder is pure and cheap, and it re-runs on every update, so the chain grows live.
1. **Classify each hop:** `silent` (no reply) · `privateAddress` (not publicly routable: RFC 1918, CGNAT 100.64/10, link-local, ULA, loopback, using `IPAddress.isPubliclyRoutable`) · `unknownNetwork` (public, but ASN pending, failed or unannounced, e.g. most IXP LAN addresses) · `network(asn)`.
2. **Leading block:** every hop before the first `network` hop belongs to the **You** node. These are usually private Wi-Fi, CGNAT or VPN hops.
3. **Merge runs:** consecutive `network` hops with the same ASN form one segment. Non-network hops *between two hops of the same ASN* are absorbed into that segment: its TTL range spans them, but they add no RTT. Non-network hops between *different* ASNs are dropped and counted in `skippedHops`. Details shows them as "2 hops without a known network".
4. **No loops:** if a segment's ASN equals an earlier segment's ASN, everything from the earlier segment through this one is merged into the earlier segment.
5. **You node:** if `myASN` equals the first segment's ASN, that segment *is* the You node (and absorbs the leading block). Otherwise a separate You node (`asn: myASN`, possibly `nil`) holds the leading block and is placed first. Example from this machine: the public IP is in AS24940 Hetzner, hops 1–3 are private and hop 4 is already Cloudflare (a tunnel), so the chain is You · AS24940 (hops 1–3) → AS13335 (hops 4–7) → AS15169 (hops 8–11). No warning is shown. The You node says "Your public IP is in this network".
6. **Destination:**
   - If the last segment's ASN is an origin, it becomes role **destination** and `completion = .complete`.
   - Otherwise an **expected** destination node (primary origin, provenance `.expected`, `gapBefore = true`) is appended, with `completion = .gap`, or `.inProgress` while measuring. The stitching rule (§6.11.7) may then turn `.gap` into `.stitched`.
7. **Roles:** first = you, last = destination, everything else = transit. If `myASN` is an origin, the chain is a single `youAndDestination` node ("This address is on your own network").
8. **Per node:** `ttls` = the TTL range of the segment's answered hops · `answeredHops` · `rttRange` = min…max over every answered probe RTT in the segment · `addresses` (distinct, in order) and hostnames, for details.

Worked example (8.8.8.8 from AS24940, hop 10 silent):

| TTL | Address | Class | → node |
|---|---|---|---|
| 1–3 | 192.168.70.1, 172.16.21.1, 10.99.7.1 | private | You · AS24940 Hetzner (hops 1–3) |
| 4–7 | 104.28.0.0, 172.71.133.1, 141.101.67.186, 141.101.67.57 | AS13335 | Cloudflare (hops 4–7) |
| 8–9 | 108.170.255.223, 72.14.237.93 | AS15169 | Google (hops 8–11) |
| 10 | * * | silent, absorbed (between two Google hops) | |
| 11 | 8.8.8.8 dns.google | AS15169, echo reply | reached |

#### 6.11.7 Partial results and the stitching rule (decision: stitch, clearly marked)
When a measured chain ends in `.gap`, the last measured ASN is *X* and *X* is not an origin:
- If *X* appears in ≥ 1 cleaned RIS path for this prefix, take the suffixes from *X* to the origin and pick the most common one (same tie-break as §6.11.4). Its ASNs after *X* are appended with provenance `.bgp`. The connectors from *X* onward are **dashed**, each such node has a small **"from BGP"** tag, and `completion = .stitched`. Status: "Traceroute stopped in Arelion at hop 9. The rest is the most common BGP route from Arelion (6 of 369 routes)."
- If *X* is in no RIS path, nothing is stitched. A **"?" gap** sits between *X* and the expected destination: a dashed connector with a 22 pt circle containing "?". Status: "Traceroute couldn't see past hop 7. The networks between Cloudflare and Google are unknown."
- Never stitch when the trace reached an origin, from a You node with no ASN, or into Source A chains.
- Real-data note: AS13335 appears in **0 of 369** RIS routes to 8.8.8.0/24. Cloudflare→Google is a link RIPE collectors don't see. A stall inside Cloudflare therefore shows the honest "?" gap, not invented hops. This is why measured data comes first.

#### 6.11.8 Layout
**iPhone (vertical chain, top = you, bottom = destination).** The view scrolls vertically, which suits 393 pt. Each card is full width, so names don't truncate, Dynamic Type works up to AX5, and it reads like a list. A horizontal chain fits only about 3 nodes at 393 pt.
1. **Status card** (`RouteStatusCard`): icon (22 pt) + title + subtitle.
   - Done: green `checkmark.circle.fill`, "**3 networks** between you and 8.8.8.8", "Measured by traceroute · 11 hops · 12:41".
   - Measuring: `ProgressView`, "Measuring your route… hop 6", "Traceroute from this device · usually 5–15 s", and a trailing **Stop** button (bordered, small).
   - Partial: orange `exclamationmark.triangle`. Seen in BGP: tint `point.3.connected.trianglepath.dotted`.
2. **Chain** (`YourRouteView`): node cards (`ChainNodeView`, `secondarySystemGroupedBackground`, corner 12, min height 64) joined by a **connector rail**: a 2.5 pt line centred on the 32 pt role circles. The rail is solid `tint` for measured links, dashed `secondaryLabel` for `.bgp` or `.expected` links, and has the "?" bubble in a gap.
   - Role circle: You = green fill + `person.fill`. Transit = `fill` + `arrow.down`. Destination = blue (tint) fill + `flag.fill`, matching the blue origin in All routes.
   - Line 1: name, semibold 17 ("Cloudflare"), then the ASN badge (`asn` style, monospaced digits).
   - Line 2 (footnote, secondary): the role text, "Your network" · "Transit network" · "Destination · announces 8.8.8.0/24".
   - Line 3 (footnote): traceroute nodes show "Hops 4–7 · 128–151 ms" with an RTT colour dot (§3.6) for the range's **lower** bound (the latency of reaching that network). BGP nodes show "Seen in 2 routes". Expected nodes show "Not reached yet" while measuring, or "Not reached" when done. The You node shows "Hops 1–3 (local) · 3–133 ms" (VoiceOver: "hops 1 to 3 on your local network"), or "No hops seen before the next network" when it has none.
   - "from BGP" tag (caption2, `fill` capsule) on stitched nodes. The trailing chevron → AS details.
   - Expected nodes are drawn at 0.45 opacity with a dashed outline.
   - **Live growth:** new nodes slide in from the top (0.2 s, opacity only with Reduce Motion). A pending row "Hop 7…" with a spinner sits under the last measured node.
3. **Footer:** the source line (caption, secondary): "Measured from this device · networks looked up at RIPEstat". Buttons: **Measure again** (`arrow.clockwise`) and **Show 11 hops** (disclosure, compact hop rows grouped under their AS: TTL, host/IP, avg RTT, the same visual as §5.1 rows without the context menu). Plus a privacy footnote, once per session: "Your public IP and the routers' addresses were looked up at RIPEstat (RIPE NCC)."

**iPad (regular width): horizontal chain**, left = you, right = destination, the same direction as All routes. Node cards share the width equally (150–220 pt wide, min height 108), with 26 pt arrow connectors between them. Use it when `nodes × 150 + (nodes − 1) × 26 ≤ available width` and Dynamic Type < `.accessibility1`, otherwise fall back to the vertical chain. Three nodes fit beside the open inspector. Longer chains go vertical. The status card sits above it and the footer below it. Selecting a node opens the inspector:
- the usual §6.6 content, and
- a new first section, **"On your route"**: role, hops, RTT range, and the hop rows inside that AS (TTL · host or IP · avg RTT).
- If the ASN is in no RIS path (e.g. Cloudflare for 8.8.8.0/24), the paths tile reads "Not in any of the 369 RIS routes to this prefix" and the line "Traceroute shows the real path; RIPE collectors only see part of the Internet."

`ASDetailView` must accept an ASN that is **not in the graph** (today it assumes a `GraphNode`).

#### 6.11.9 States
| State | UI (status card + chain) |
|---|---|
| Locating | "Finding your network…" · You node skeleton (`redacted(.placeholder)`) · destination node shown (known from §6.1) |
| Measuring | As in §6.11.8. The chain grows. The destination is dimmed with a dashed rail |
| Done | Green status. All nodes solid |
| Partial: gap | Orange "Traceroute couldn't see past hop 7" · "?" gap · **Measure again** |
| Partial: stitched | Orange "Traceroute stopped in Arelion at hop 9" · dashed "from BGP" nodes |
| Stopped (user / background) | "Stopped at hop 6" · known part kept, as partial · **Measure again** |
| Seen in BGP | Tint icon, "Seen in BGP from your network" · nodes say "Seen in N routes" · **Measure with traceroute** |
| Your own network | Single node, "8.8.8.8 is on your own network (AS15169 Google)" |
| Network lookups off | `ContentUnavailableView("Network Lookups Are Off", systemImage: "network.slash", description: "Your route needs to look up which network each router belongs to (via RIPEstat).")` + button **Turn On Lookups** (sets `settings.trace.lookUpASNs = true`, then measures). Source A still works without it |
| Your network unknown | Not an error. First node "Your network", no ASN |
| Trace can't start (`NetError` socket/route) | `ErrorStateView` with the §4.2 copy (e.g. "No IPv6 route — this network doesn't support IPv6.") + Try Again. All routes still works |
| No public hop answered | Partial: You → "?" → destination · "No router on the way answered. Some networks block traceroute." |
| Private / not announced / RIPEstat busy / offline | Exactly as §6.9. They apply to the whole BGP tab, and both segments are hidden |
| Measurement unavailable (`traceService == nil`, tests/previews) | "Route measurement isn't available here." |

#### 6.11.10 Accessibility
- The chain container is `.accessibilityElement(children: .contain)`. Its label is **one sentence**, built by `YourRouteModel.accessibilitySentence`:
  - "Your route to 8.8.8.8, measured by traceroute: from your network, AS 24940 Hetzner, through AS 13335 Cloudflare, to AS 15169 Google, the destination. 11 hops."
  - Partial: "… through AS 13335 Cloudflare, then unknown networks, to AS 15169 Google, the destination. Traceroute stopped at hop 7."
  - BGP: "Your route to 8.8.8.8, seen in BGP: from your network, AS 3320 Deutsche Telekom, directly to AS 15169 Google, the destination."
- Each node is a button: "Transit network, AS 13335, Cloudflare, hops 4 to 7, 128 to 151 milliseconds." Hint: "Double-tap for details." Nodes are read in chain order.
- The status card is `.isHeader`. Each change of measuring progress posts an `.announcement` at most every 3 s ("Cloudflare found at hop 4"), plus one when it finishes.
- ASNs are spoken as "AS 13335" (the space prevents "AS" being read as "as"). Colour is never the only signal: role text, dashed rails *and* the "from BGP" tag all say the same thing.

#### 6.11.11 Export (Your route)
```
Your route to 8.8.8.8 (8.8.8.0/24, origin AS15169 Google LLC)
Measured by traceroute from this device, 2026-11-08 12:41 UTC, 11 hops
  You  AS24940  Hetzner Online   hops 1–3    3–133 ms
   →   AS13335  Cloudflare       hops 4–7    128–151 ms
   →   AS15169  Google           hops 8–11   139–152 ms   (reached 8.8.8.8)
— IP Tools for iOS
```
A BGP-sourced route prints "Seen in BGP from your network (RRC01, RRC03)" and "×2 routes" instead of hops. Stitched nodes are suffixed "(from BGP)". A gap prints `   ?   unknown networks`.

### 6.12 All routes (worldwide): clarity changes (v1.1)

> **Update (owner request).** The "All routes" tab, the summary card and the legend were removed; the BGP Map is the v1.0 graph again (columns "ORIGIN / 1 HOP / 2 HOPS", v1.0 header chips). Of this section only the bug fixes still apply: pinning the user's AS (item 4) and the AS-name handling. The rest is historical.

The graph rules in §6.3–§6.5 are unchanged except where noted.
1. **Name:** the segment "All routes". VoiceOver: "All routes worldwide".
2. **Summary card** (`AllRoutesSummaryCard`, replaces the header chips). It is made of plain sentences built by `RoutesSummary`:
   - Line 1, bold: "**369 routes** from 23 RIPE collectors" (the segment already says "worldwide").
   - Line 2: "**75%** connect to Google directly. Most others pass through **AS214292 DE-CIX** or **AS3356 Level 3**."
     - *direct %* = cleaned paths of length ≤ 2 ÷ total, as an integer percent.
     - *handoffs* = up to 2 layer-1 ASes with the highest `transitCount` (> 0), with ties going to the higher score.
     - The second sentence is omitted when there are none.
     - Verified on 8.8.8.0/24 today: 275/369 = 75%, transit counts DE-CIX 9 and Level 3 8.
   - Line 3, about you (only if `myASN` is known):
     - "**Your network** (AS3320 Deutsche Telekom) is in 2 routes, highlighted below", or
     - "Your network (AS24940 Hetzner) isn't in these routes. **See Your route ›**", which switches the segment.
   - Trailing icon button: **List** (`list.bullet`) ⇄ **Graph** (`point.3.connected.trianglepath.dotted`). It replaces the old Graph|List segment. It defaults to List when VoiceOver is on.
   - Secondary chips under the text (caption): "Seen by 319/319 peers", "Updated 12:32 UTC" (iPad), and the MOAS warning when present.
3. **Column headers** (graph) and **section titles** (list), in plain words:
   - layer 0 "DESTINATION"
   - layer 1 "NEXT TO GOOGLE", using the origin's uppercased short name, cut to 12 characters, and "NEXT TO ORIGIN" when the name is unknown or MOAS
   - layer *n* ≥ 2 "*n* STEPS AWAY"
   - List sections: "Next to Google · 229 networks", "2 steps away · 70 networks".
4. **Your network is never folded:** `GraphBuildOptions.pinned = [myASN]`. A pinned AS that would fall into "+N more" is kept as an extra node after the top K, before the bucket, so that column shows K + 1. It gets a 2 pt **green** ring and a "YOU" capsule badge (caption2 bold, green fill, white text) on its top-left corner. VoiceOver: "Your network, AS 3320 …".
5. **Legend** (`GraphLegend`): one compact row at the bottom of the canvas container (`bar-bg` material, caption2, 24 pt high, wraps to two lines at large sizes). Items:
   - blue box: **Destination**
   - a thin and a thick line: **Thicker = more routes**
   - green dot: **RIPE peer**
   - dashed box: **Grouped (+N more)**
   - green ring: **You** (only when pinned)
   A trailing `info.circle` opens "How to read this map": a 5-line sheet with the same items plus "Columns count steps away from the destination. Routes are seen by RIPE RIS collectors, not measured from your device." Hidden in List mode.
6. **List mode** shows the same summary card on top. Rows are unchanged (§6.7) apart from the section titles and a "You" badge.

---

## 7. App icon

`docs/icon.svg`: 1024 × 1024, full-bleed, no transparency, no text.

**Concept: "the route that pings back."** A white four-hop polyline (traceroute / AS path) climbs from the lower left to a large destination dot in the upper right. Three concentric **ping rings** radiate from the destination and run off the canvas edge. The rings are cut where the route crosses them, so the line stays crisp. The background is a deep blue diagonal gradient (`#2F7BFF → #1747C9 → #0A1F66`) with a soft cyan glow behind the destination.

Why it works: rings mean "ping/signal" and the hop path means "traceroute/network path". The symbols are understood without text. The large dot and rings still read at 40 px in Spotlight. It is distinct from Apple's own blue utility icons because of the diagonal composition and the glow. Previews at 180/120/80/58/40 px are in `mockup.html`.

Implementation: export a 1024 PNG (e.g. `rsvg-convert -w 1024 docs/icon.svg > AppIcon.png`) into the `AppIcon` asset as a single-size iOS icon. Optionally add dark and tinted variants: a dark variant with a black background and blue route; a tinted variant as a white glyph only.

---

## 8. App Store metadata

- **Name (27/30):** IP Tools: Ping & Traceroute
- **Subtitle (29/30):** `BGP Map, AS Path & ASN Lookup`
- **Keywords (96/100):**
  `network,looking,glass,tracert,icmp,latency,ipv6,prefix,route,hop,jitter,mtr,ripe,peering,isp,dns`
  (None of the words in the name or subtitle are repeated: ip, tools, ping, traceroute, bgp, map, as, path, asn, lookup. Apple indexes name + subtitle + keywords together, so "asn lookup", "as path", "bgp map", "looking glass", "network tools" and "ip tools" all match.)
- **Promotional text (166/170):**
  `Ping and trace any IPv4 or IPv6 host, then see how the Internet reaches it: a live BGP map of AS paths from RIPE RIS route collectors. Free, open source, no tracking.`
- **Category:** Utilities (primary), Developer Tools (secondary). **Age rating:** 4+. **Price:** Free.
- **Description:**

```
IP Tools is a fast, no-nonsense network toolkit for iPhone and iPad: ping, traceroute, and a visual BGP map that shows how the Internet reaches any IP address, prefix or ASN.

PING
• Ping any IPv4 or IPv6 address or hostname
• Live round-trip time chart
• Min / avg / max, jitter and packet loss at a glance
• Choose count, interval, timeout and packet size

TRACEROUTE
• Trace the route to any host, hop by hop, over IPv4 or IPv6
• Reverse-DNS hostnames and response times for every hop
• See which network (ASN) each router belongs to — spot where your ISP hands off to a transit provider or CDN
• Ping or map any hop with one tap

BGP MAP — AS PATH VIEWER
• Enter an IP, prefix or AS number and get a graph of the AS paths toward the origin AS
• Built from live routes seen by RIPE RIS route collectors around the world — a looking glass in your pocket
• See upstreams, transit providers and peers, with edge thickness showing how many paths use each link
• Tap any AS for its name, role and every path through it
• Accessible list view for VoiceOver users

MADE FOR NETWORK PEOPLE
Network engineers, sysadmins, NOC staff, ISP support, gamers chasing lag, and anyone curious about how the Internet is wired together.

PRIVATE AND OPEN SOURCE
• No account, no ads, no tracking, no data collected
• Ping and traceroute run entirely on your device
• BGP and ASN data comes from the public RIPEstat API by the RIPE NCC
• MIT-licensed source code on GitHub: github.com/ahmadrezaei/ip-tools

Supports Dark Mode, Dynamic Type, VoiceOver, iPad split view and keyboard shortcuts.
```

- **Screenshots (6.9" iPhone and 13" iPad):**
  1. Ping running ("Live ping with jitter & loss")
  2. Traceroute with ASNs ("Every hop, every network")
  3. BGP graph ("See the AS paths to any IP")
  4. AS details ("Who carries the traffic")
  5. iPad split view
  6. Dark mode
- **Support URL:** GitHub repo. **Privacy policy URL:** `PRIVACY.md` on GitHub (Pages or raw).

---

## 9. Privacy

- **App Privacy "nutrition label": Data Not Collected.** No tracking (`NSPrivacyTracking = false`). No third-party SDKs.
- **Network destinations:**
  1. The user's probe target: ICMP only.
  2. The system DNS resolver.
  3. `https://stat.ripe.net/data/...`: BGP lookups (the user's IP/prefix/ASN) and, if enabled, traceroute hop IPs.
  RIPEstat requests carry `sourceapp=ahmadrezaei-iptools` (as RIPE NCC asks) and no user identifiers. The About screen and the traceroute ASN toggle footnote say this in plain words.
- **(v1.1) Your route.** BGP Map now also (a) asks RIPEstat for the device's public IP (`whats-my-ip`) and its network (`network-info` on that IP), and (b) when it measures, sends ICMP traceroute probes to the map's target and looks up the public router addresses at RIPEstat. This is honest and low-risk: RIPEstat already sees the public IP as the source of every HTTPS request, the app never stores the IP (memory only, cleared on network change), and nothing goes anywhere new. The privacy label stays **Data Not Collected**. Hop lookups follow the existing "Look up networks" toggle (§6.11.9).
  - **PRIVACY.md wording change.** Item 1 becomes: "**The target you probe.** Ping, traceroute and BGP Map's *Your route* send ICMP packets only to the host, address or prefix you enter." Add to item 3: "When BGP Map shows *Your route*, the app asks RIPEstat which public IP address your connection uses and which network it belongs to, and looks up the public addresses of the routers on the way (if "Look up networks" is on). RIPEstat already sees that address on every request. The app keeps it in memory only and never sends it anywhere else."
  - **About screen:** add one line under the RIPEstat line: "Your route: your public IP and router addresses are looked up at RIPEstat."
  - **Traceroute toggle footnote** (§5.3) becomes: "Sends the public hop IP addresses to RIPEstat (RIPE NCC) to find which network they belong to. Also used by BGP Map › Your route."
- **Stored locally:** recents (≤ 20 targets) and settings, in `UserDefaults`. Clear History is in About. Nothing is synced (no iCloud in v1).
- **`PrivacyInfo.xcprivacy`:** `NSPrivacyTracking: false`, `NSPrivacyCollectedDataTypes: []`, `NSPrivacyAccessedAPITypes: [{ NSPrivacyAccessedAPICategoryUserDefaults, reasons: ["CA92.1"] }]`.
- **Info.plist:** `NSLocalNetworkUsageDescription` = "IP Tools uses the local network to ping and trace devices on your network, such as your router." No `NSBonjourServices`. No ATS exceptions (everything is HTTPS).
- **`PRIVACY.md`** in the repo restates the above for the App Store privacy-policy URL.

---

## 10. Technical feasibility: ICMP on iOS

**Verdict: feasible without entitlements.** Darwin supports "non-privileged ICMP" sockets: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` and `socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)`. Apple's own *SimplePing* sample uses them. XNU implements them on top of raw IP, restricting *sends* to echo-type messages. Incoming ICMP, including Time Exceeded and Destination Unreachable, is delivered to the socket, and that is what makes traceroute work. The same sockets work on macOS without root, so `swift test` can exercise the real code path on a Mac. Pitfalls and how the design handles each:

| # | Pitfall | Handling |
|---|---|---|
| 1 | **Other traffic arrives on the socket.** Darwin delivers ICMP messages that other ICMP sockets (other apps or sessions) receive too. | Every session picks a random 16-bit `identifier`. Replies are matched on `(identifier, sequence)`. The payload starts with an 8-byte session nonce, which is checked on echo replies. Anything that doesn't match is dropped. |
| 2 | **The IPv4 receive buffer includes the IP header**, but IPv6 does not. | `ICMPCodec.parse` reads the IHL (`(b[0] & 0x0F) * 4`) on v4, strips the header and reads the reply TTL from the header. On v6 the hop limit needs `IPV6_RECVHOPLIMIT` + `recvmsg` cmsg. That is optional in v1, so the TTL column shows "—" for v6. |
| 3 | **Checksums.** The ICMPv4 checksum must be computed by the app. The ICMPv6 checksum is computed by the kernel (pseudo-header). | `ICMPCodec.checksum` (RFC 1071) applies to v4 only. v6 sends 0. |
| 4 | **Traceroute matching.** Time Exceeded (v4 type 11 / v6 type 3) and Unreachable (v4 3 / v6 1) messages quote the original packet: the inner IP header (v4: 20+ bytes, IHL-aware; v6: 40 bytes) plus the first 8 bytes of the original ICMP header, which contain our id and seq. | `parse` extracts a `QuotedEcho(identifier, sequence)`. The Tracer keeps `seq → (ttl, probeIndex, sentAt)`. The sender is the hop address (`recvfrom` source). |
| 5 | **The TTL setting is per socket.** | Send sequentially. `setsockopt(IP_TTL)` / `setsockopt(IPV6_UNICAST_HOPS)` goes immediately before each `sendto`, on one serial queue, so a probe can never go out with the wrong TTL. |
| 6 | **Timeouts / no `SO_RCVTIMEO` loop.** | A `DispatchSourceRead` on a serial queue receives packets. Timeouts come from per-probe deadlines checked by a timer (every 50 ms) on the same queue. No thread blocks. `ContinuousClock` is used for RTT. |
| 7 | **Sequence wrap** (UInt16). | Wire seq = `UInt16(truncatingIfNeeded: n)`. Pending entries expire on timeout, so after 65 536 probes a stale entry can't be confused with a new one. |
| 8 | **Local Network privacy prompt** (iOS 14+). It is triggered by sending to local addresses (192.168/16, 10/8, 172.16/12, link-local, ULA, multicast). | `NSLocalNetworkUsageDescription` is set. Pinging a LAN host shows the system prompt once. If denied, `sendto` fails (`EHOSTUNREACH`/`EPERM`) only for local destinations → `NetError.localNetworkDenied` → the UI explains and offers Open Settings. Traceroutes to public hosts don't send to local addresses. Replies *from* the LAN router (hop 1) are received normally. **Verify on device in the first spike.** |
| 9 | **IPv6 availability.** | "Automatic" uses `AI_ADDRCONFIG`, so v6 is only chosen if the device has a v6 address. `ENETUNREACH`/`EHOSTUNREACH` on the first v6 send → "This network doesn't support IPv6". |
| 10 | **Reverse DNS can block.** `getnameinfo` is synchronous and can't be cancelled. | Run it on a detached task with `NI_NAMEREQD`, race it against a 2 s timeout, and ignore late results. Concurrency is capped at 4. |
| 11 | **Backgrounding.** Sockets are suspended. | RootView stops runs when `scenePhase` becomes `.background`. No background modes are requested. |
| 12 | **Rate limiting and ICMP filtering by routers** ("* * *" hops, unusually high RTT at a hop but not beyond it). | Normal traceroute behaviour. The UI shows it honestly. A help footnote in Settings explains that hops which don't reply are common. |
| 13 | **Simulator.** | The simulator uses the Mac's network stack. ICMP works, so most testing doesn't need a device. Local-network prompt behaviour differs, so test that on device. |

**Fallback, if Time Exceeded turns out not to be delivered on some iOS version (low probability):** UDP-probe traceroute is not possible without raw receive. The documented fallback would be to show the hops found so far plus an error. This is the main item to prove in the **day-1 spike** (Agent A, §12.6).

---

## 11. RIPEstat Data API: endpoints & fields used

Base: `https://stat.ripe.net/data/<call>/data.json?resource=<r>&sourceapp=ahmadrezaei-iptools`
Every response has the same envelope (verified 2026-11-07):

```json
{ "status": "ok" | "error", "status_code": 200, "messages": [["info"|"warning"|"error", "text"]],
  "data_call_name": "...", "version": "x.y", "cached": false, "time": "2026-11-07T12:32:48.993082", "data": { ... } }
```
Errors return HTTP 4xx with `status: "error"`, `data: {}` and the reason in `messages` (e.g. a bad resource type → 400). The client treats `status != "ok"` as `RIPEstatError.api(messages)`. Timestamps are ISO-8601 **without a timezone (UTC)** and sometimes have fractional seconds, so a custom parser is needed. **Watch the types: ASNs are strings in some calls and integers in others.** The models normalise everything to `UInt32`.

| Call | Used for | Fields read (exact names) | Verified sample |
|---|---|---|---|
| `network-info` | IP → prefix + origin (BGP IP input, traceroute ASN) | `data.prefix` (String, `""` if unrouted), `data.asns` ([**String**]) | `1.1.1.1` → `{"asns":["13335"],"prefix":"1.1.1.0/24"}`; `10.0.0.1` → `{"asns":[],"prefix":""}`; v6 works (`2606:4700:4700::/48`); ASN input → 400 |
| `looking-glass` | **Main graph data** | `data.rrcs[]` → `.rrc` ("RRC01"), `.location` ("London, GB"), `.peers[]` → `.as_path` (String, space-separated, origin last), `.asn_origin` (**String**), `.prefix`, `.peer` (peer IP), `.last_updated`; `data.latest_time` | `1.1.1.0/24`: 23 rrcs, 360 peers, path lengths 1–4. IP input is auto-expanded to its prefix (info message). Private prefix → `rrcs: []`. ASN → 400. Response ~130 KB, so allow a **30 s timeout**. Ignored: `community`, `largeCommunity`, `next_hop`, `origin`. |
| `as-names` | **Bulk** AS holder names for graph nodes and hop badges | `data.names` (object: `"13335": "CLOUDFLARENET - Cloudflare, Inc."`) | `resource=13335,6939,174` → 3 names; 296 comma-separated ASNs (1.7 KB URL) → 296 names in one call. Repeating `resource=` does **not** work (only the last value is used). |
| `prefix-overview` | Prefix input: origins + holder + announced | `data.announced` (Bool), `data.asns[]` → `.asn` (**Int**), `.holder` (String); `data.resource`; `data.block.desc` (optional) | `1.1.1.0/24` → `announced: true`, `asns: [{asn: 13335, holder: "CLOUDFLARENET - Cloudflare, Inc."}]` |
| `as-overview` | ASN input header | `data.holder` (String), `data.announced` (Bool), `data.resource` (String "13335") | `AS13335` → `holder: "CLOUDFLARENET - Cloudflare, Inc.", announced: true` |
| `announced-prefixes` | ASN input → prefix picker | `data.prefixes[]` → `.prefix` (ignore `timelines`) | AS13335 → 5,748 prefixes, ~3.6 s. Show a spinner and cache. |
| `whats-my-ip` (v1.1) | Your route: the device's public IP | `data.ip` (String). No `resource` parameter. **Never cached** | 2026-11-08: `{"data":{"ip":"91.107.240.242"}}` → `network-info` → `asns ["24940"]`, `prefix "91.107.128.0/17"` |
| `bgp-state` (fallback, already implemented) | Graph routes when `looking-glass` is empty | `data.bgp_state[]` → `.path` ([Int]), `.source_id` ("00-102.208.105.2" → collector RRC00) | 2026-11-08: `looking-glass` 8.8.8.0/24 returned `rrcs: []` twice; `bgp-state` returned 369 routes, 23 collectors, layers 1/229/70/7 |
| `routing-status` | Header chip "Seen by X/Y peers" (optional) | `data.visibility.v4.ris_peers_seeing`, `.total_ris_peers` (and `v6`), `data.origins[].origin` (**Int**), `data.last_seen.time` | `1.1.1.0/24` → v4 319/319 |

**Short name rule** (`ASName.short(_:)`, used on nodes and badges):
1. If the holder contains `" - "`, take the text after the first occurrence. Otherwise drop the first whitespace token when there is more than one, because it is the AS handle.
2. Strip one trailing legal suffix from: `, Inc.`, ` Inc.`, `, LLC`, ` LLC`, ` Ltd.`, ` Ltd`, ` Limited`, ` S.A.`, ` SA`, ` GmbH`, ` B.V.`, ` B.V`, ` AB`, ` AG`, ` S.p.A.`, ` e.V.`, ` UG`, ` Sdn Bhd`, ` Pte. Ltd.`.
3. Trim. The UI truncates as needed.

Examples: `CLOUDFLARENET - Cloudflare, Inc.` → `Cloudflare`; `GCORE G-Core Labs S.A.` → `G-Core Labs`; `HURRICANE - Hurricane Electric LLC` → `Hurricane Electric`; `TWELVE99 Arelion Sweden AB` → `Arelion Sweden`.

**Etiquette:**
- At most 4 concurrent requests per app.
- In-memory response cache (`NSCache`, 5 min TTL, keyed by URL). Names are also cached for the session.
- On 429, back off; no automatic retry loop.
- A descriptive `User-Agent: IPTools/1.0 (iOS; github.com/ahmadrezaei/ip-tools)`.

---

## 12. Architecture

### 12.1 Repository & project setup (decision)
```
ip-tools/
├─ IPTools.xcodeproj            # one iOS app target "IPTools"; created once in Phase 0
├─ App/                         # folder-synchronised group (Xcode 16+) — no pbxproj edits when files change
│  ├─ IPToolsApp.swift          # @main, 10 lines: WindowGroup { RootView(environment: .live) }
│  ├─ Assets.xcassets           # AppIcon (from docs/icon.svg), AccentColor
│  ├─ Info.plist                # NSLocalNetworkUsageDescription, display name "IP Tools"
│  └─ PrivacyInfo.xcprivacy
├─ IPToolsKit/                  # local Swift package — ALL code lives here
│  ├─ Package.swift             # swift-tools-version 6.0; platforms .iOS(.v17), .macOS(.v14)
│  ├─ Sources/
│  │  ├─ NetCore/  RIPEstat/  BGPGraph/            # logic (no SwiftUI)
│  │  └─ SharedUI/ PingFeature/ TraceFeature/ BGPFeature/ AppShell/   # SwiftUI
│  └─ Tests/
│     ├─ NetCoreTests/  RIPEstatTests/ (Fixtures/*.json)  BGPGraphTests/  FeatureTests/
├─ scripts/  build.sh  test.sh  icon.sh
├─ docs/  DESIGN.md  mockup.html  icon.svg
├─ README.md  LICENSE (MIT)  PRIVACY.md  .gitignore  .github/workflows/ci.yml
```

**Why this setup:**
- **Agents work from the command line.** `swift build` and `swift test` (on the Mac host) cover ~90 % of the code with no simulator and no Xcode GUI. A full build is `xcodebuild -project IPTools.xcodeproj -scheme IPTools -destination 'generic/platform=iOS Simulator' build`.
- **No merge conflicts on the project file.** All Swift files live in the package. The app target uses a synchronised folder, so `project.pbxproj` is written once in Phase 0 and never touched again. Adding a file means dropping it into a target's directory.
- **No XcodeGen/Tuist.** No extra tool to install or maintain, which keeps with "no third-party dependencies".
- **The unit tests live in the package's test targets** (`swift test`, and runnable on an iOS Simulator via `xcodebuild test -scheme IPToolsKit-Package`). That is the "unit test target". An additional app-level test target is unnecessary.
- **Rule:** UI targets must also compile for macOS 14, so that `swift build` works everywhere. The few iOS-only modifiers (`keyboardType`, `textInputAutocapitalization`, `navigationBarTitleDisplayMode`, `UIPasteboard`, `openSettingsURLString`) are wrapped once in `SharedUI/Platform.swift` and used through those wrappers.
- **Swift 6 language mode,** strict concurrency. View models are `@MainActor @Observable`. Services are `Sendable`.

### 12.2 Module dependency graph
```
                 ┌──────────┐   ┌──────────┐   ┌──────────┐
   logic         │ NetCore  │   │ RIPEstat │   │ BGPGraph │      (no inter-dependencies)
                 └────┬─────┘   └────┬─────┘   └────┬─────┘
                      │              │              │
                 ┌────▼──────────────▼──────────────▼─────┐
   ui            │               SharedUI                 │  (depends on NetCore only, for IPAddress/TargetParser/options types)
                 └────┬───────────────┬───────────────┬───┘
                 ┌────▼─────┐   ┌─────▼──────┐   ┌────▼──────┐
                 │PingFeat. │   │TraceFeat.  │   │BGPFeature │
                 │NetCore   │   │NetCore,    │   │RIPEstat,  │
                 │SharedUI  │   │RIPEstat,   │   │BGPGraph,  │
                 └────┬─────┘   │SharedUI    │   │NetCore,   │
                      │         └─────┬──────┘   │SharedUI   │
                      │               │          └────┬──────┘
                 ┌────▼───────────────▼───────────────▼─────┐
                 │                AppShell                  │  (RootView, AppEnvironment, Settings/About)
                 └────────────────────┬─────────────────────┘
                                 App target (IPToolsApp.swift)
```
BGPGraph does **not** depend on RIPEstat. It takes a neutral `[ObservedPath]`, and BGPFeature does the conversion. So the graph agent and the API agent never wait on each other.

### 12.3 Public interfaces (Swift signatures, frozen in Phase 0)

#### NetCore (`Sources/NetCore/`)
Files: `IPAddress.swift`, `TargetParser.swift`, `Resolver.swift`, `NetError.swift`, `ICMPCodec.swift`, `ICMPSocket.swift`, `Pinger.swift`, `PingTypes.swift`, `PingStatistics.swift`, `Tracer.swift`, `TraceTypes.swift`, `Mocks/MockPingService.swift`, `Mocks/MockTraceService.swift`.

```swift
public struct IPAddress: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Family: Sendable, Hashable, Codable { case v4, v6 }
    public let bytes: [UInt8]                       // 4 or 16
    public var family: Family { get }
    public init?(_ string: String)                  // inet_pton; accepts "[v6]" and "%zone"
    public init?(bytes: [UInt8])
    public var description: String { get }          // inet_ntop (RFC 5952 for v6)
    public var isPubliclyRoutable: Bool { get }     // false for RFC1918, 100.64/10, 127/8, 169.254/16, 0/8, 224/4, 240/4,
                                                    // ::1, fe80::/10, fc00::/7, ff00::/8, 2001:db8::/32 …
    public var scopeLabel: String? { get }          // "Private", "CGNAT", "Link-local", "Loopback" or nil
}

public enum Target: Hashable, Sendable {
    case ip(IPAddress)
    case hostname(String)
    case prefix(IPAddress, length: Int)             // BGP only
    case asn(UInt32)                                // BGP only
}
public enum TargetParser {
    public enum Mode: Sendable { case host, bgp }   // .host = Ping/Trace (ip|hostname), .bgp = all four
    public static func parse(_ raw: String, mode: Mode) -> Target?   // trims, strips URL scheme/path, brackets
    public static func normalized(_ raw: String) -> String           // key used for recents
}

public enum AddressPreference: String, Codable, Sendable, CaseIterable { case automatic, ipv4, ipv6 }

public struct ResolvedTarget: Hashable, Sendable {
    public let input: String                        // what the user typed (trimmed)
    public let address: IPAddress                   // the address that will be probed
    public let hostname: String?                    // nil if input was an IP literal
    public let allAddresses: [IPAddress]
}

public enum Resolver {
    /// Literal IPs return immediately; hostnames use getaddrinfo(AI_ADDRCONFIG) off the main thread.
    public static func resolve(_ input: String, preference: AddressPreference) async throws -> ResolvedTarget   // throws NetError
    /// getnameinfo(NI_NAMEREQD) raced against `timeout`; nil on failure or timeout.
    public static func reverseName(for address: IPAddress, timeout: Duration = .seconds(2)) async -> String?
}

public enum NetError: Error, Sendable, Equatable {
    case invalidTarget(String)
    case resolutionFailed(host: String, reason: String)
    case noAddress(host: String, family: IPAddress.Family)
    case socketUnavailable(errno: Int32)
    case networkUnreachable(family: IPAddress.Family)   // ENETUNREACH / no v6 route
    case localNetworkDenied
    case sendFailed(errno: Int32)
}

// --- ICMP primitives ---
public struct QuotedEcho: Sendable, Equatable { public let identifier: UInt16; public let sequence: UInt16 }
public enum ICMPMessage: Sendable, Equatable {
    case echoReply(identifier: UInt16, sequence: UInt16, payload: [UInt8])
    case timeExceeded(QuotedEcho?)
    case destinationUnreachable(code: UInt8, QuotedEcho?)
    case other(type: UInt8, code: UInt8)
}
public enum ICMPCodec {
    public static func echoRequest(family: IPAddress.Family, identifier: UInt16, sequence: UInt16, payload: [UInt8]) -> [UInt8]
    /// Strips the IPv4 header when present; returns message + IPv4 TTL if available.
    public static func parse(_ datagram: [UInt8], family: IPAddress.Family) -> (message: ICMPMessage, ttl: Int?)?
    public static func checksum(_ bytes: [UInt8]) -> UInt16       // RFC 1071
}
public struct ICMPPacket: Sendable {
    public let message: ICMPMessage
    public let from: IPAddress
    public let ttl: Int?
    public let byteCount: Int
    public let receivedAt: ContinuousClock.Instant
}
public final class ICMPSocket: @unchecked Sendable {          // internally serialised on a private DispatchQueue
    public init(family: IPAddress.Family) throws               // NetError.socketUnavailable
    public func send(_ bytes: [UInt8], to: IPAddress, hopLimit: Int? = nil) throws -> ContinuousClock.Instant  // NetError
    public var packets: AsyncStream<ICMPPacket> { get }        // single consumer
    public func close()
}

// --- Ping ---
public struct PingOptions: Codable, Hashable, Sendable {
    public var count: Int?            = 10       // nil = until stopped
    public var interval: TimeInterval = 1.0
    public var timeout: TimeInterval  = 2.0
    public var payloadSize: Int       = 56
    public static let `default` = PingOptions()
}
public struct PingSample: Identifiable, Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case reply(rtt: TimeInterval, bytes: Int, ttl: Int?, from: IPAddress)   // rtt in seconds
        case timeout
        case unreachable(code: UInt8, from: IPAddress)
        case error(NetError)
    }
    public var id: Int { sequence }
    public let sequence: Int                  // 0-based, monotonically increasing
    public let sentAt: Date
    public let outcome: Outcome
}
public protocol PingService: Sendable {
    /// Emits one sample per probe as its outcome becomes known; finishes after `count` probes,
    /// or runs until the consuming Task is cancelled. Throws NetError for fatal setup/send errors.
    func ping(_ target: ResolvedTarget, options: PingOptions) -> AsyncThrowingStream<PingSample, Error>
}
public struct Pinger: PingService { public init() }
public struct PingStatistics: Hashable, Sendable {
    public let sent: Int, received: Int
    public var lossFraction: Double { get }
    public let min: TimeInterval?, avg: TimeInterval?, max: TimeInterval?, stddev: TimeInterval?, jitter: TimeInterval?
    public init(samples: some Collection<PingSample>)
}

// --- Traceroute ---
public struct TraceOptions: Codable, Hashable, Sendable {
    public var maxHops: Int = 30
    public var probesPerHop: Int = 3
    public var timeout: TimeInterval = 2.0
    public static let `default` = TraceOptions()
}
public enum ProbeResult: Hashable, Sendable {
    case timeExceeded(from: IPAddress, rtt: TimeInterval)
    case echoReply(from: IPAddress, rtt: TimeInterval)          // reached the target
    case unreachable(from: IPAddress, rtt: TimeInterval, code: UInt8)
    case timeout
    public var address: IPAddress? { get }
    public var rtt: TimeInterval? { get }
}
public enum TraceCompletion: Hashable, Sendable {
    case reachedDestination(hops: Int)
    case unreachable(atHop: Int, code: UInt8)
    case maxHopsExceeded
}
public enum TraceEvent: Hashable, Sendable {
    case probe(ttl: Int, index: Int, result: ProbeResult)
    case hopFinished(ttl: Int)
    case finished(TraceCompletion)
}
public protocol TraceService: Sendable {
    func trace(_ target: ResolvedTarget, options: TraceOptions) -> AsyncThrowingStream<TraceEvent, Error>
}
public struct Tracer: TraceService { public init() }

// --- Mocks (used by previews & UI tests; ship in NetCore so every agent has them on day 1) ---
public struct MockPingService: PingService { public init(script: [PingSample.Outcome], interval: Duration = .milliseconds(300)) }
public struct MockTraceService: TraceService { public init(hops: [[ProbeResult]], delay: Duration = .milliseconds(250)) }
```

#### RIPEstat (`Sources/RIPEstat/`)
Files: `RIPEstatClient.swift`, `Envelope.swift`, `Models.swift`, `ASName.swift`, `DateParsing.swift`, `MockRIPEstat.swift`.

```swift
public protocol RIPEstatAPI: Sendable {
    func networkInfo(_ ip: String) async throws -> NetworkInfo
    func prefixOverview(_ prefix: String) async throws -> PrefixOverview
    func lookingGlass(_ resource: String) async throws -> LookingGlass        // ip or prefix
    func asOverview(_ asn: UInt32) async throws -> ASOverview
    func asNames(_ asns: [UInt32]) async throws -> [UInt32: String]          // chunks of 200 internally
    func announcedPrefixes(_ asn: UInt32) async throws -> [String]
    func routingStatus(_ prefix: String) async throws -> RoutingStatus
}
public final class RIPEstatClient: RIPEstatAPI, Sendable {
    public init(session: URLSession = .shared,
                baseURL: URL = URL(string: "https://stat.ripe.net/data/")!,
                sourceApp: String = "ahmadrezaei-iptools",
                maxConcurrent: Int = 4)
}
public enum RIPEstatError: Error, Sendable, Equatable {
    case offline, timeout, rateLimited
    case http(status: Int)
    case api(messages: [String])          // status != "ok"
    case decoding(String)
}

public struct NetworkInfo: Sendable, Hashable { public let prefix: String?; public let originASNs: [UInt32] }   // "" → nil
public struct ASHolder: Sendable, Hashable { public let asn: UInt32; public let holder: String; public var shortName: String { get } }
public struct PrefixOverview: Sendable, Hashable { public let resource: String; public let announced: Bool; public let origins: [ASHolder] }
public struct ASOverview: Sendable, Hashable { public let asn: UInt32; public let holder: String?; public let announced: Bool }
public struct RoutingStatus: Sendable, Hashable {
    public struct Visibility: Sendable, Hashable { public let seeing: Int; public let total: Int }
    public let v4: Visibility?, v6: Visibility?
    public let origins: [UInt32]
}
public struct LookingGlass: Sendable, Hashable {
    public struct Route: Sendable, Hashable {
        public let collector: String          // "RRC01"
        public let peerIP: String
        public let prefix: String
        public let asPath: [UInt32]           // AS_SET tokens removed, order preserved (peer first, origin last)
        public let hadASSet: Bool
        public let rawASPath: String
        public let lastUpdated: Date?
    }
    public struct Collector: Sendable, Hashable { public let id: String; public let location: String }
    public let collectors: [Collector]
    public let routes: [Route]
    public let latestTime: Date?
}
public enum ASName { public static func short(_ holder: String) -> String }   // rule in §11
public struct MockRIPEstat: RIPEstatAPI { public init(fixtureBundle: Bundle) }   // serves Tests/Fixtures JSON
```

#### BGPGraph (`Sources/BGPGraph/`)
Files: `ObservedPath.swift`, `ASGraph.swift`, `GraphBuilder.swift`, `LayeredLayout.swift`, `GraphLayout.swift`.

```swift
import CoreGraphics
public struct ObservedPath: Hashable, Sendable {
    public let asns: [UInt32]                  // peer first, origin last (raw; builder cleans)
    public let collector: String
    public let peerIP: String
    public init(asns: [UInt32], collector: String, peerIP: String)
}
public enum NodeID: Hashable, Sendable { case asn(UInt32), more(layer: Int) }
public struct GraphNode: Identifiable, Hashable, Sendable {
    public let id: NodeID
    public let layer: Int
    public let pathCount: Int
    public let transitCount: Int
    public let isOrigin: Bool
    public let isPeer: Bool
    public let collapsed: [UInt32]             // non-empty only for .more
    public var role: Role { get }              // .origin, .transit, .peer
    public enum Role: Sendable { case origin, transit, peer }
}
public struct GraphEdge: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case forward, lateral, backward }
    public var id: String { get }              // "\(from)>\(to)"
    public let from: NodeID, to: NodeID
    public let pathCount: Int
    public let kind: Kind
}
public struct GraphBuildOptions: Hashable, Sendable {
    public var maxNodesPerLayer: Int = 6       // 6 / 12 / 30
    public init(maxNodesPerLayer: Int = 6)
}
public struct ASGraph: Sendable {
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    public let origins: [UInt32]
    public let totalPaths: Int
    public let discardedPaths: Int
    public let layerCount: Int
    public let cleanedPaths: [ObservedPath]
    public func node(_ id: NodeID) -> GraphNode?
    public func paths(through asn: UInt32) -> [ObservedPath]
    public func highlightedEdges(through asn: UInt32) -> Set<String>   // edge ids after collapsing
    public func allASNs(inLayer: Int) -> [UInt32]                     // uncollapsed, sorted by score (List "Show all")
}
public enum GraphBuilder {
    public static func build(from paths: [ObservedPath], options: GraphBuildOptions = .init()) -> ASGraph
}
public struct LayoutMetrics: Hashable, Sendable {
    public var nodeSize = CGSize(width: 112, height: 44)
    public var columnSpacing: CGFloat = 56
    public var rowSpacing: CGFloat = 12
    public var padding: CGFloat = 24
    public var headerHeight: CGFloat = 18
    public init()
}
public struct EdgeGeometry: Identifiable, Hashable, Sendable {
    public let id: String
    public let start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint
    public let lineWidth: CGFloat
    public let kind: GraphEdge.Kind
}
public struct GraphLayout: Sendable {
    public let size: CGSize
    public let frames: [NodeID: CGRect]
    public let edges: [EdgeGeometry]
    public let columnHeaders: [(layer: Int, centerX: CGFloat)]
}
public enum LayeredLayout {
    public static func layout(_ graph: ASGraph, metrics: LayoutMetrics = .init()) -> GraphLayout
}
```

#### SharedUI (`Sources/SharedUI/`)
Files: `Tool.swift`, `AppRouter.swift`, `RecentsStore.swift`, `SettingsStore.swift`, `NetworkMonitor.swift`, `TargetInputBar.swift`, `RecentsSuggestions.swift`, `RunHeader.swift`, `OfflineBanner.swift`, `ErrorStateView.swift`, `DisplayableError.swift`, `Formatters.swift`, `RTTColor.swift`, `Platform.swift`, `ExampleChips.swift`.

```swift
public enum Tool: String, CaseIterable, Codable, Identifiable, Sendable {
    case ping, traceroute, bgp
    public var id: String { rawValue }
    public var title: LocalizedStringKey { get }
    public var systemImage: String { get }
}
public struct ToolRequest: Equatable, Sendable { public let target: String; public let autostart: Bool }

@MainActor @Observable public final class AppRouter {
    public var selectedTool: Tool
    public init(selectedTool: Tool = .ping)
    public func open(_ tool: Tool, target: String, autostart: Bool)
    public func takeRequest(for tool: Tool) -> ToolRequest?          // consumed by the tool's view on appear/change
}
public struct RecentTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String          // TargetParser.normalized
    public let display: String
    public let lastTool: Tool
    public let date: Date
}
@MainActor @Observable public final class RecentsStore {
    public private(set) var items: [RecentTarget]
    public init(defaults: UserDefaults = .standard, limit: Int = 20)
    public func record(_ target: String, tool: Tool)
    public func remove(_ item: RecentTarget)
    public func clear()
    public func suggestions(matching text: String, limit: Int = 5) -> [RecentTarget]
}
public struct TraceSettings: Codable, Hashable, Sendable {
    public var options: TraceOptions = .default
    public var resolveHostnames = true
    public var lookUpASNs = true
}
@MainActor @Observable public final class SettingsStore {
    public var ping: PingOptions
    public var trace: TraceSettings
    public var addressPreference: AddressPreference
    public init(defaults: UserDefaults = .standard)                 // persists on change (JSON, key "settings.v1")
}
@MainActor @Observable public final class NetworkMonitor {
    public private(set) var isOnline: Bool
    public init()                                                   // NWPathMonitor on a private queue
}
public protocol DisplayableError: Error {
    var title: String { get }
    var message: String { get }
    var systemImage: String { get }
    var action: ErrorAction? { get }                                // .retry, .openSettings
}
public enum ErrorAction: Sendable { case retry, openSettings }

public struct TargetInputBar: View {
    public init(text: Binding<String>, placeholder: LocalizedStringKey, systemImage: String,
                mode: TargetParser.Mode, primaryTitle: LocalizedStringKey, isRunning: Bool, isEnabled: Bool,
                recents: RecentsStore, onSubmit: @escaping () -> Void, onStop: @escaping () -> Void)
}
public struct RunHeader: View { public init(text: AttributedString, isLive: Bool) }
public struct OfflineBanner: View { public init() }
public struct ErrorStateView: View { public init(_ error: any DisplayableError, retry: @escaping () -> Void) }
public struct ExampleChips: View { public init(_ examples: [String], onTap: @escaping (String) -> Void) }
public enum Format {
    public static func rtt(_ seconds: TimeInterval) -> String       // "13.6 ms", "1.24 s"
    public static func percent(_ fraction: Double) -> String        // "5%"
    public static func relative(_ date: Date) -> String             // "2 min ago"
}
public enum RTTColor { public static func color(for seconds: TimeInterval?) -> Color }
public enum Clipboard { public static func copy(_ string: String) }
public extension View {
    func hostInputTraits() -> some View          // keyboardType/.never/autocorrect off (iOS only)
    func inlineNavigationTitle() -> some View
}
```

#### Feature modules (each exports one View + one Model)
```swift
// PingFeature — Files: PingModel.swift, PingView.swift, PingStatsGrid.swift, PingChart.swift, PingRow.swift, PingSettingsView.swift, PingExport.swift
@MainActor @Observable public final class PingModel {
    public enum Phase: Equatable { case idle, resolving, running, finished, stopped(reason: String?), failed(String) }
    public var targetText: String
    public private(set) var phase: Phase
    public private(set) var resolved: ResolvedTarget?
    public private(set) var samples: [PingSample]
    public private(set) var stats: PingStatistics
    public init(service: any PingService, settings: SettingsStore, recents: RecentsStore)
    public func start()
    public func stop(reason: String? = nil)
    public var exportText: String { get }
}
public struct PingView: View { public init(model: PingModel) }

// TraceFeature — Files: TraceModel.swift, TraceView.swift, HopRow.swift, TraceSummaryCard.swift, TraceSettingsView.swift, ASNLookup.swift, TraceExport.swift
public struct HopASN: Hashable, Sendable { public let asn: UInt32; public let name: String?; public let prefix: String? }
public struct TraceHop: Identifiable, Hashable, Sendable {
    public var id: Int { ttl }
    public let ttl: Int
    public var probes: [ProbeResult]
    public var addresses: [IPAddress]          // distinct, in arrival order
    public var hostname: String?
    public var asn: HopASN?
    public var isDestination: Bool
}
public actor ASNLookup {                        // cache + concurrency limit around RIPEstatAPI
    public init(api: any RIPEstatAPI)
    public func lookup(_ address: IPAddress) async -> HopASN?
    public func names(for asns: [UInt32]) async -> [UInt32: String]
}
@MainActor @Observable public final class TraceModel {
    public enum Phase: Equatable { case idle, resolving, tracing(currentTTL: Int), finished(TraceCompletion), stopped(String?), failed(String) }
    public var targetText: String
    public private(set) var phase: Phase
    public private(set) var hops: [TraceHop]
    public init(service: any TraceService, asnLookup: ASNLookup, settings: SettingsStore, recents: RecentsStore, router: AppRouter)
    public func start(); public func stop(reason: String? = nil)
    public var exportText: String { get }
}
public struct TraceView: View { public init(model: TraceModel) }

// BGPFeature — Files: BGPMapModel.swift, BGPQuery.swift, BGPMapView.swift, PrefixHeaderCard.swift, GraphCanvasView.swift,
//                     ZoomPanState.swift, NodeView.swift, SelectionCard.swift, ASDetailView.swift, BGPListView.swift,
//                     PrefixPickerView.swift, BGPExport.swift
public enum BGPQuery: Hashable, Sendable { case address(IPAddress, hostname: String?), prefix(String), asn(UInt32) }
public struct BGPResult: Sendable {
    public let prefix: String
    public let origins: [ASHolder]
    public let graph: ASGraph
    public let collectors: [LookingGlass.Collector]
    public let visibility: RoutingStatus.Visibility?
    public let latestTime: Date?
    public var names: [UInt32: String]
}
@MainActor @Observable public final class BGPMapModel {
    public enum Phase: Equatable { case idle, loading(String), pickingPrefix(asn: UInt32, holder: String?, prefixes: [String]), loaded, failed(String) }
    public var targetText: String
    public var maxNodesPerLayer: Int            // 6 / 12 / 30 → rebuilds graph + layout off-main
    public var selection: NodeID?
    public var displayMode: DisplayMode         // .graph / .list
    public enum DisplayMode: Sendable { case graph, list }
    public private(set) var phase: Phase
    public private(set) var result: BGPResult?
    public private(set) var layout: GraphLayout?
    public init(api: any RIPEstatAPI, recents: RecentsStore, router: AppRouter)
    public func map()                            // parses targetText → BGPQuery → fetch
    public func choosePrefix(_ prefix: String)
    public func cancel()
    public var exportText: String { get }
}
public struct BGPMapView: View { public init(model: BGPMapModel) }

// AppShell — Files: AppEnvironment.swift, RootView.swift, PhoneTabsView.swift, SplitRootView.swift, Sidebar.swift, SettingsView.swift, AboutView.swift
@MainActor public final class AppEnvironment {
    public let router: AppRouter, recents: RecentsStore, settings: SettingsStore, network: NetworkMonitor
    public let ping: PingModel, trace: TraceModel, bgp: BGPMapModel
    public static func live() -> AppEnvironment                      // Pinger, Tracer, RIPEstatClient
    public static func preview() -> AppEnvironment                   // Mock services
}
public struct RootView: View { public init(environment: AppEnvironment) }
```

### 12.4 Work split for parallel agents

**Phase 0: Scaffold (1 agent, run first, short).**
- Create the repo layout, `Package.swift` with all 8 targets plus test targets, and the Xcode project with a synchronised `App/` folder that depends on the `AppShell` product.
- Add `scripts/build.sh` (`swift build` + `xcodebuild … build`), `scripts/test.sh` (`swift test`), CI, LICENSE, README stub, `.gitignore`.
- Commit **every public type in §12.3 as a compiling stub** (`fatalError("TODO")` bodies, or trivial values), the working **Mock services**, and the **RIPEstat JSON fixtures** (curl the 7 calls for `1.1.1.1`, `1.1.1.0/24`, `AS13335`, `10.0.0.1` into `Tests/RIPEstatTests/Fixtures/`).
- After Phase 0, **`Package.swift` and the §12.3 signatures are frozen.** Changes go through the coordinator.

**Phase 1: four agents in parallel, each owning whole directories:**

| Agent | Owns | Deliverable | Depends on (already stubbed) |
|---|---|---|---|
| **A: Networking** | `Sources/NetCore/`, `Tests/NetCoreTests/` | Day-1 spike: confirm on a device that Time Exceeded arrives on a DGRAM ICMP socket (§10). Then `IPAddress`, `TargetParser`, `Resolver`, `ICMPCodec` (unit tests with captured byte fixtures for v4/v6 echo reply, time exceeded and unreachable), `ICMPSocket`, `Pinger`, `PingStatistics`, `Tracer`. Integration tests ping `127.0.0.1` and `::1` (and `1.1.1.1` behind an env flag). | — |
| **B: Data & graph** | `Sources/RIPEstat/`, `Sources/BGPGraph/`, their tests | Client + models + `ASName`, all decoded from fixtures. `GraphBuilder` + `LayeredLayout`, tested on the 1.1.1.0/24 fixture (expected: 4 layers, layer sizes 1/240/48/7, origin 13335, K = 6 → 22 nodes), plus MOAS, AS_SET, prepend and loop fixtures. Deterministic output, so layouts can be snapshot-compared. | — |
| **C: Shell + Ping + Trace UI** | `Sources/SharedUI/`, `Sources/AppShell/`, `Sources/PingFeature/`, `Sources/TraceFeature/`, `App/` | All of §2–5, built against `MockPingService`/`MockTraceService`/`MockRIPEstat`. Previews for every state. | NetCore and RIPEstat types (stubs) |
| **D: BGP UI** | `Sources/BGPFeature/`, `Tests/FeatureTests/BGP*` | All of §6 UI: canvas, zoom/pan, nodes, selection, list mode, details/inspector, prefix picker, export. Uses `MockRIPEstat` + fixture-built graphs. App icon asset (`scripts/icon.sh`). | BGPGraph + RIPEstat (stubs), SharedUI components (C provides `TargetInputBar` early; D can use a temporary local field until then) |

- **Conflict rules:** an agent never edits a directory it doesn't own. If a needed shared-component change comes up (e.g. a new `TargetInputBar` parameter), the requesting agent asks C, the owner. If it is urgent, it adds an extension in its own module.
- **Phase 2: Integration (1 agent).** Wire up `AppEnvironment.live()`. Test end-to-end on a simulator and one physical iPhone (local network prompt, IPv6 on cellular, backgrounding). Run an accessibility pass (VoiceOver, AX5 text), take App Store screenshots, write README/PRIVACY.

### 12.5 Testing strategy
- **NetCore:** pure codec tests with byte arrays (v4 with IHL 5 and 6, v6, quoted payloads, bad checksum, foreign identifier ignored). Loopback ping tests, which run on macOS CI. `PingStatistics` maths.
- **RIPEstat:** decode every fixture, cover error envelopes (400 with messages, 429), string vs int ASN normalisation, timestamp parsing, `ASName.short` table tests.
- **BGPGraph:** builder rules 1–8 each have a focused test. Layout tests check no overlaps, columns ordered by layer, `.more` last, and determinism (same input → identical frames).
- **Features:** model tests with mock services (state transitions, recents recorded on successful start, stop on background, export text golden files).
- **CI** (GitHub Actions, macOS runner): `swift test` + `xcodebuild build` for the iOS Simulator.

### 12.6 Conventions
- **Localisation:** String Catalog (`Localizable.xcstrings`) in each UI module, English only in v1, every user-facing string localisable.
- **Formatting:** Swift 6 defaults, 4-space indent, one main type per file. Files carry no attribution comments beyond the MIT header.
- **Logging:** `os.Logger(subsystem: "com.ahmadrezaei.iptools", category: <module>)`, with no PII at `.public`.

### 12.7 v1.1 architecture: Your route, All routes, Ping count
There are **no `Package.swift` changes.** BGPFeature already depends on NetCore, RIPEstat, BGPGraph and SharedUI. BGPFeature must **not** depend on TraceFeature. A finished trace crosses over as a neutral `TraceSnapshot` (SharedUI), and BGPFeature does its own hop→ASN lookups through `RIPEstatAPI` (the client's URL cache makes repeats free).

```
Traceroute tab ──TraceSnapshot──▶ AppRouter ──ToolRequest.trace──▶ BGPMapModel
                                                                   ├─ RIPEstat: looking-glass ‖ network-info ‖ whats-my-ip→network-info
                                                                   ├─ BGPGraph: GraphBuilder(pinned: myASN) → All routes + RoutesSummary
                                                                   └─ YourRouteModel: snapshot | ASChainBuilder.fromBGP | RouteMeasurer(TraceService + networkInfo)
                                                                                      → ASChainBuilder.fromTrace → stitch → ASChain → views
```

**RIPEstat** (new: `WhatsMyIP` in `Models.swift`, parsing in `Parsing.swift`, fixture `whats-my-ip.json`)
```swift
public struct WhatsMyIP: Sendable, Hashable { public let ip: String }
public protocol RIPEstatAPI: Sendable {
    // … existing …
    func whatsMyIP() async throws -> WhatsMyIP        // GET whats-my-ip/data.json?sourceapp=…, never cached, 10 s timeout
}
public extension RIPEstatAPI {                        // keeps existing test fakes compiling
    func whatsMyIP() async throws -> WhatsMyIP { throw RIPEstatError.api(messages: ["whats-my-ip not supported"]) }
}
// RIPEstatClient + MockRIPEstat implement it; MockRIPEstat serves whats-my-ip.json (91.107.240.242).
```

**BGPGraph** (new files `ASChain.swift`, `ASChainBuilder.swift`, `RoutesSummary.swift`; changed `GraphBuilder.swift` for `pinned`)
```swift
public struct GraphBuildOptions: Hashable, Sendable {
    public var maxNodesPerLayer: Int = 6
    public var pinned: Set<UInt32> = []               // never folded into "+N more" (§6.12 item 4)
    public init(maxNodesPerLayer: Int = 6, pinned: Set<UInt32> = [])
}
public struct ChainHop: Hashable, Sendable {           // neutral input; BGPGraph has no NetCore dependency
    public enum Kind: Hashable, Sendable { case silent, privateAddress, unknownNetwork, network(UInt32) }
    public let ttl: Int
    public let kind: Kind
    public let address: String?
    public let hostname: String?
    public let rtts: [TimeInterval]                   // answered probes only, seconds
    public let reachedTarget: Bool                    // echo reply from the probe target
    public init(ttl: Int, kind: Kind, address: String? = nil, hostname: String? = nil, rtts: [TimeInterval] = [], reachedTarget: Bool = false)
}
public struct ASChain: Hashable, Sendable {
    public enum Source: Hashable, Sendable { case traceroute(handedOver: Bool, measuredAt: Date), bgp(collectors: [String]) }
    public enum Completion: Hashable, Sendable { case inProgress, complete, gap, stitched }
    public struct Node: Identifiable, Hashable, Sendable {
        public enum Role: Hashable, Sendable { case you, transit, destination, youAndDestination }
        public enum Provenance: Hashable, Sendable { case measured, bgp, expected }
        public var id: String { get }                 // "you" when asn == nil, else "AS<n>"
        public let asn: UInt32?                       // nil only for an unidentified You node
        public let role: Role
        public let provenance: Provenance
        public let ttls: ClosedRange<Int>?            // measured nodes
        public let answeredHops: Int
        public let rttRange: ClosedRange<TimeInterval>?
        public let hops: [ChainHop]                   // the hops inside this node (for "Show hops" / inspector)
        public let routeCount: Int?                   // .bgp nodes
        public let gapBefore: Bool                    // draw the "?" gap before this node
    }
    public let nodes: [Node]
    public let source: Source
    public let completion: Completion
    public let reachedTarget: Bool
    public let lastTTL: Int?
    public let skippedHops: Int
    public var asnSequence: [UInt32] { get }
}
public enum ASChainBuilder {
    /// §6.11.6. Pure; call on every update.
    public static func fromTrace(_ hops: [ChainHop], myASN: UInt32?, origins: [UInt32], finished: Bool,
                                 source: ASChain.Source) -> ASChain
    /// §6.11.4. nil when no cleaned path contains myASN.
    public static func fromBGP(_ cleanedPaths: [ObservedPath], myASN: UInt32, origins: [UInt32]) -> ASChain?
    /// §6.11.7. Returns `chain` unchanged unless completion == .gap and a suffix exists.
    public static func stitch(_ chain: ASChain, cleanedPaths: [ObservedPath], origins: [UInt32]) -> ASChain
}
public struct RoutesSummary: Hashable, Sendable {     // §6.12 item 2
    public let totalRoutes: Int
    public let collectorCount: Int
    public let directFraction: Double                 // paths with ≤ 2 ASNs ÷ total
    public let handoffs: [UInt32]                     // ≤ 2 layer-1 ASNs by transitCount
    public let myASNRouteCount: Int?                  // nil when myASN unknown; 0 = not present
    public init(graph: ASGraph, collectorCount: Int, myASN: UInt32?)
}
```

**SharedUI** (new `TraceSnapshot.swift`; changed `AppRouter.swift`, `NetworkMonitor.swift`)
```swift
public struct TraceSnapshot: Hashable, Sendable {
    public struct Hop: Hashable, Sendable {
        public let ttl: Int
        public let address: IPAddress?                 // first responder
        public let hostname: String?
        public let asn: UInt32?
        public let rtts: [TimeInterval]
        public let reachedTarget: Bool
        public init(ttl: Int, address: IPAddress?, hostname: String?, asn: UInt32?, rtts: [TimeInterval], reachedTarget: Bool)
    }
    public let target: ResolvedTarget
    public let hops: [Hop]
    public let completion: TraceCompletion?
    public let finishedAt: Date
    public init(target: ResolvedTarget, hops: [Hop], completion: TraceCompletion?, finishedAt: Date)
}
public struct ToolRequest: Equatable, Sendable {
    public let target: String; public let autostart: Bool
    public let trace: TraceSnapshot?                  // new
    public init(target: String, autostart: Bool, trace: TraceSnapshot? = nil)
}
// AppRouter
public func open(_ tool: Tool, target: String, autostart: Bool, trace: TraceSnapshot? = nil)
// NetworkMonitor
public private(set) var pathGeneration: Int          // +1 whenever interface types, status or gateways change
```

**TraceFeature** (changed `TraceModel.swift` only)
```swift
/// Hops 1…ttl (all when nil), only for finished/stopped runs; nil while running or empty.
public func snapshot(upTo ttl: Int? = nil) -> TraceSnapshot?
// mapTarget() → router.open(.bgp, target:, autostart: true, trace: snapshot())
// mapHop(_:)  → router.open(.bgp, target:, autostart: true, trace: snapshot(upTo: hop.ttl)), with the hop marked reachedTarget
```

**NetCore:** no changes. `TraceService`/`Tracer`, `TraceOptions`, `IPAddress.isPubliclyRoutable` are reused as they are. `MockTraceService` drives previews and tests.

**BGPFeature** (new files `YourRouteModel.swift`, `MyNetworkLocator.swift`, `RouteMeasurer.swift`, `PrefixMath.swift`, `YourRouteView.swift`, `ChainNodeView.swift`, `ChainRail.swift`, `HorizontalChainView.swift`, `RouteStatusCard.swift`, `RouteHopsList.swift`, `RouteExport.swift`, `AllRoutesSummaryCard.swift`, `GraphLegend.swift`. Changed: `BGPMapModel.swift`, `BGPMapView.swift`, `PrefixHeaderCard.swift`, `GraphCanvasView.swift`, `NodeView.swift`, `BGPListView.swift`, `ASDetailView.swift`, `BGPExport.swift`, `BGPPreviewData.swift`)
```swift
public enum BGPView: String, Sendable, CaseIterable { case yourRoute, allRoutes }
public struct MyNetwork: Hashable, Sendable { public let ip: String; public let asn: UInt32?; public let prefix: String?; public var name: String? }
actor MyNetworkLocator {                              // whats-my-ip → network-info, cached per pathGeneration (≤ 30 min)
    init(api: any RIPEstatAPI)
    func current(generation: Int) async -> MyNetwork?
}
struct RouteMeasurer: Sendable {                       // §6.11.5
    enum Update: Sendable { case hops([ChainHop]), finished(reachedOrigin: Bool), failed(Error) }
    init(service: any TraceService, api: any RIPEstatAPI)
    func measure(_ target: ResolvedTarget, origins: Set<UInt32>, prefixTarget: Bool) -> AsyncStream<Update>
}
@MainActor @Observable public final class YourRouteModel {
    public enum Phase: Equatable { case idle, locating, measuring(ttl: Int), done, partial(String), stopped(String),
                                   lookupsOff, unavailable, failed(String) }
    public private(set) var phase: Phase
    public private(set) var chain: ASChain?
    public private(set) var myNetwork: MyNetwork?
    public var selection: String?                     // ASChain.Node.id
    public func measureAgain()
    public func stop(reason: String? = nil)
    public var exportText: String { get }             // §6.11.11
    public var accessibilitySentence: String { get }  // §6.11.10
}
@MainActor @Observable public final class BGPMapModel {
    // … existing …
    public var view: BGPView                          // default .yourRoute
    public let route: YourRouteModel
    public private(set) var summary: RoutesSummary?
    public init(api: any RIPEstatAPI, recents: RecentsStore, router: AppRouter,
                traceService: (any TraceService)? = nil,      // nil → Your route shows "unavailable" (keeps tests offline)
                settings: SettingsStore? = nil, network: NetworkMonitor? = nil)
    public func stopForBackground()                   // stops a running measurement
}
```

**PingFeature** (new `PingCountMenu.swift`; changed `PingView.swift`, `PingSettingsView.swift`, `PingModel.swift` for the "3 of 10" header). No SharedUI change: the value is `SettingsStore.ping.count`, and the last custom value is in `@AppStorage("ping.lastCustomCount")`.

**AppShell** (changed `AppEnvironment.swift`, `AboutView.swift`, `RootView.swift`): pass `Tracer()`, `settings` and `network` to `BGPMapModel`. `preview()` adds a `MockTraceService` script for the 8.8.8.8 trace in §6.11.6. RootView calls `bgp.stopForBackground()` on `.background`. About gets the privacy line from §9.

#### 12.7.1 Work split: three parallel agents, no file overlap
**Step 0 (coordinator, ~15 min, before the agents start):** commit the signatures above as compiling stubs (`fatalError("TODO")` bodies, `whatsMyIP` default extension, `ToolRequest.trace` defaulting to nil, `BGPMapModel.init` new parameters defaulted) so every agent builds against them. After that the signatures are frozen, and changes go through the coordinator.

| Agent | Owns (exclusive) | Delivers | Tests |
|---|---|---|---|
| **L: Data & chain logic** | `Sources/RIPEstat/`, `Sources/BGPGraph/`, `Tests/RIPEstatTests/` (+ `Fixtures/whats-my-ip.json`), `Tests/BGPGraphTests/` (+ `Fixtures/bgp-state_8.8.8.0-24.json`, captured live) | `whatsMyIP` (client, parsing, mock), `GraphBuildOptions.pinned`, `ASChain`, `ASChainBuilder.fromTrace/fromBGP/stitch`, `RoutesSummary` | Table tests for every §6.11.6 rule using the worked example; the AS24940 ≠ first-hop case; A-B-A loop fold; absorbed silent hop; gap vs stitch (stitch through AS1299 on the 8.8.8.0/24 fixture; no stitch through AS13335); fromBGP on AS3320 → `[3320, 15169]` ×2; summary 369 / 23 / 75% / [214292, 3356]; pinned AS3320 stays visible with K = 6 |
| **B: BGP UI** | `Sources/BGPFeature/`, `Tests/FeatureTests/BGP*` (new helpers go in `BGPTestSupport.swift`, not in the shared `TestSupport.swift`) | §6.11 and §6.12 UI: segments, Your route (vertical + iPad horizontal), status card, rail, hops list, measurer, locator, model, stop rules, stitching wiring, inspector "On your route", ASDetailView for non-graph ASNs, summary card, legend, column headers, YOU badge, export, previews for every §6.11.9 state | Model tests with `MockTraceService` + fake API: source choice order 1→2→3, each stop rule a–f, partial/stopped/lookups-off states, snapshot reuse and its 10-min expiry |
| **S: Shell, Trace, Ping** | `Sources/SharedUI/`, `Sources/TraceFeature/`, `Sources/PingFeature/`, `Sources/AppShell/`, `App/`, `Tests/FeatureTests/{Ping,Trace,Shell,SharedUI,FeatureSmoke}Tests.swift`, `Tests/FeatureTests/TestSupport.swift`, `PRIVACY.md`, `README.md` | `TraceSnapshot`, router `trace:` parameter, `NetworkMonitor.pathGeneration`, `TraceModel.snapshot(upTo:)` + cross-links, **Ping count chip (§4.3.1)** + settings-sheet sync + "3 of 10" header, AppEnvironment wiring + preview trace script, background stop, About/PRIVACY/footnote wording (§9) | Snapshot contents (full / up to hop, nil while running); router carries the snapshot; ping count: custom validation 1…10,000, chip ⇄ settings sync, disabled while running, header "3 of 10" |

Merge order: L → S → B (B's integration test of the handed-over trace needs S's router). Any order compiles thanks to Step 0. Phase 2 (one agent): run on a device on cellular, with VPN on and off, and on IPv6. Retake `docs/screenshots/iphone-bgp-map.png` in the Your route view.

---

## 13. Open questions & risks

**Decisions for you (the owner):**
1. **Hop ASN lookups default ON.** This sends public hop IPs to RIPEstat. It is privacy-friendly (no identifiers) but is network traffic you might prefer to be opt-in. *Recommendation: ON, with the clear footnote.*
2. **ASN input → prefix picker** (vs. an aggregated "upstreams of this AS" graph built from `asn-neighbours`). *Recommendation: picker for v1; it's simpler and exact.*
3. **Default column size K = 6** on both iPhone and iPad. iPad could default to 12. *Recommendation: 6 everywhere for a consistent first look; the menu is one tap away.*
4. **Ping default count: 10** — DECIDED by owner (stop after 10; "Until stopped" stays available in settings).
5. **Minimum iOS 17.** That gives `@Observable`, `ContentUnavailableView`, `.inspector` and `MagnifyGesture`. iOS 18's `.sidebarAdaptable` TabView would simplify navigation but would drop iOS 17 users. *Recommendation: keep 17 and the size-class switch.*
6. **Category:** Utilities vs Developer Tools as the primary. *Recommendation: Utilities, which has broader search traffic.*

**v1.1 decisions for you (Your route & Ping count):**
7. **Source A before a fresh traceroute.** When your AS is a RIS peer, the BGP path shows instantly with no probing, and "Measure with traceroute" is one tap away. *Recommendation: yes.* The alternative is to always measure (truer but slower, and it probes on every map).
8. **Stitching a stalled trace with a BGP suffix,** dashed and tagged "from BGP". *Recommendation: yes, as specified in §6.11.7.* The alternative is to always show the "?" gap.
9. **Hop lookups follow the Traceroute "Look up networks" toggle.** *Recommendation: yes,* to respect a user who turned it off. Your route then asks to turn it on.
10. **Auto-measure on every Map.** A ~10 s traceroute runs in the background even if the user only wanted All routes. *Recommendation: yes,* because Your route is the default view. The alternative is a "Measure my route" button.
11. **Custom ping count upper bound 10,000** (2.8 h at 1 s). *Recommendation: keep.*

**Risks:**
- **R1 (medium impact, low probability):** ICMP Time Exceeded may not reach DGRAM sockets on some iOS release, which would break traceroute. *Mitigation:* the day-1 device spike, before any UI work depends on it.
- **R2: RIPEstat availability, rate limits or schema drift.** *Mitigation:* tolerant decoding (unknown fields ignored, all optional except the core ones), clear error state, fixtures in tests, and `sourceapp` set so RIPE can contact the project.
- **R3: Graph readability for heavily peered origins** (Cloudflare has 240 neighbours). *Mitigation:* top-K collapsing with a "+N more" bucket, transit-weighted ranking, List mode. Verified on real data.
- **R4: Local Network prompt confusion.** *Mitigation:* the prompt appears only when the user targets a LAN address, and the denied state explains how to fix it.
- **R5: App Review.** Network utilities with ICMP are common and allowed. Make sure the description does not over-claim (no "speed test").
- **R6: Reverse DNS latency** slowing the traceroute UI. *Mitigation:* async enrichment that never blocks the probe loop.
- **R7 (v1.1): Traceroute and BGP disagree** (e.g. Cloudflare → Google is in no RIS route). *Mitigation:* every chain says where it came from. Measured data wins, stitched parts are tagged, and the inspector explains that collectors see only part of the Internet.
- **R8 (v1.1): The You AS is not the first traced AS** (VPN, iCloud Private Relay, tunnels). *Mitigation:* rule 5 in §6.11.6 shows both without claiming a hop inside the user's AS. Private Relay does not affect ICMP, but it may change what `whats-my-ip` returns for Safari. The app uses URLSession, which Private Relay does not proxy by default.

**Out of scope for v1 (deliberately):** mtr-style continuous traceroute, TCP/UDP ping, whois, DNS lookup tool, history of past results, iCloud sync, widgets/Live Activities, Mac Catalyst, localisation beyond English.

---

## 14. My IP & Whois (v1.2)

Status: **draft for approval** (2026-11-25). No code written yet. Mockups: [`mockup-whois.html`](mockup-whois.html).
This section supersedes §0 item 1 ("no whois") and the "whois" entry in §13 *Out of scope*.

**Owner request:** "add feature to app to show my current ip and my ip whois. also user can whois custom ip. first design it and after my approve start it"

Decisions that need the owner's answer are marked **[Confirm Dn]**, each with the recommended pick. The full list is in §14.18.

### 14.0 Decisions at a glance

1. **A fourth tool, "Whois", with your own IP as its default content.** iPhone gets a fourth tab (`person.text.rectangle`). iPad gets a fourth sidebar row. The screen opens on **Your public IP** (IPv4 and IPv6) with the whois of your network underneath. Typing any IP, prefix, AS number or host name in the target bar looks that up instead. **[Confirm D1]**
2. **Both address families.** The app asks RIPEstat `whats-my-ip` twice, once pinned to IPv4 and once pinned to IPv6, using `Network.framework` (`NWProtocolIP.Options.version`). `URLSession` cannot force a family. If one family has no route, that row says so plainly ("No IPv6 on this network"). The whois below shows **IPv4 by default** when both exist, with an `IPv4 | IPv6` switch. **[Confirm D3]**
3. **Data source: RIPEstat only.** `whois` (raw RIR objects for ARIN, RIPE NCC, APNIC and AFRINIC), plus `network-info` / `prefix-overview` / `as-overview` for BGP facts, `abuse-contact-finder`, `rir-stats-country` and `as-names`. No RDAP, so the privacy promise stays one sentence: "only RIPEstat is contacted". The known gaps (LACNIC has no records, RIPE-style objects carry an org *handle* but no org *name*, ARIN fails on bare IPv6 addresses) have specified fallbacks (§14.7, §14.9). **[Confirm D2]**
4. **One summary card, normalised across RIRs**, with the raw records one tap away. Every field in the card says where it came from when it isn't the registry itself (e.g. "Network operator · from AS22548").
5. **Accepted input:** IPv4/IPv6 address, prefix, AS number and host name. A host name is resolved on the device and the *address* is looked up, with a clear line that this is not domain-registration whois. **[Confirm D5]**
6. **Private, reserved, CGNAT, documentation and special ASNs are answered locally,** with no request, using full IANA special-purpose tables (new in NetCore). IPv4-mapped, NAT64 and 6to4 IPv6 addresses offer "Look up 8.8.8.8 instead".
7. **Approximate location** (MaxMind GeoLite2, through RIPEstat `maxmind-geo-lite`) as one clearly labelled row, on screen only, never in the export. **[Confirm D4]**
8. **"This device" card:** the device's own local addresses (Wi-Fi, cellular, VPN) read with `getifaddrs`, never sent anywhere, plus a one-line NAT/CGNAT explanation. **[Confirm D7]**
9. **Cross-links both ways** through `AppRouter`: Traceroute hop → *Whois this hop* / *Whois AS7922*; Ping and Traceroute result headers → Whois icon button; BGP AS details → *Whois AS3356*; BGP toolbar menu → *Whois 1.1.1.0/24*. From Whois → **Ping**, **Traceroute**, **Map in BGP**, and drill-down into the origin AS. **[Confirm D10]**
10. **Store metadata:** keep the name, change the subtitle to `Whois, BGP Map & ASN Lookup` (27/30), new keywords (100/100), add a Whois screenshot. **[Confirm D8, D9]**
11. **Architecture:** a new module `WhoisFeature` (NetCore, RIPEstat, SharedUI), new RIPEstat calls and a pure `WhoisSummarizer`, new NetCore special-purpose tables and local-interface reader, `Tool.whois`. Three parallel agents with no file overlap (§14.16).

### 14.1 Goals and non-goals

**Goals.** In one glance: "this is my public IP (v4 and v6), this is the network it belongs to, who runs it, which country, and where to report abuse". The same card for any IP, prefix or AS. Honest about where each value comes from. Works for every RIR, degrading gracefully where RIPEstat has less data.

**Non-goals (v1.2):** domain-name registration whois (`whois example.com` at a TLD registry); RDAP; a map view of the location; history of past lookups beyond the shared recents; reverse whois (by org or e-mail); bulk lookups; widgets.

### 14.2 Navigation and placement

#### 14.2.1 Recommendation: a fourth tool, named "Whois"
| Option | Verdict |
|---|---|
| **A. Fourth tab "Whois", My IP as its default content** (recommended) | One obvious place for both requests. "Whois" matches the existing naming (tools are named after what they do: Ping, Traceroute, BGP Map). Your IP is simply the whois of *you*, so it opens with no typing. A 4-item tab bar is standard (5 is the limit before "More"). ⌘1–3 keep their meaning; Whois is ⌘4. |
| B. Fourth tab "My IP" | Friendlier for casual users, but custom whois and cross-links ("Whois this hop" landing in "My IP") read oddly, and the tab name doesn't carry the search keyword. |
| C. Inside BGP Map (whois section in AS details / prefix header) | Hidden. Nobody looks for "my IP" in a BGP graph. BGP's screen is already dense. |
| D. A sheet from the toolbar of every tool | Not discoverable, no recents, no iPad sidebar presence. |

| Tab | Title | SF Symbol |
|---|---|---|
| 4th (after BGP Map) | Whois | `person.text.rectangle` |

Alternatives considered for the symbol: `text.magnifyingglass` (reads as "search text"), `network` (already used for the RIPEstat row in About), `globe` (reads as "web"). `person.text.rectangle` reads as "who holds this", it's in SF Symbols 4 (iOS 16+), and it is distinct from the other three tab glyphs.

- **iPhone:** `TabView` gains a fourth tab, Whois, with its own `NavigationStack` (as the others). The order stays Ping · Traceroute · BGP Map · Whois, so nobody's muscle memory breaks.
- **iPad:** the sidebar's *Tools* section lists four rows (`Tool.allCases`). Recents show "8.8.8.8 · Whois · 2 min ago" and reopen the Whois tool (pre-fill only, no auto-start, as for the other tools).
- **Toolbar (trailing):** **Share** (`square.and.arrow.up`, a `Menu`: *Share Summary* · *Share Full Record* · *Copy Summary*; in My IP mode it shares the My IP text) and **Refresh** (`arrow.clockwise`, My IP mode only). No Settings sheet (like BGP Map). About stays reachable from the other tools' Settings and the iPad sidebar.
- **Titles:** large title "Whois" in My IP mode; inline title "Whois" once a custom result is shown.
- **Keyboard (iPad, §2.4 extended):** ⌘4 opens Whois. ⌘L focuses the target. ⌘R or Return looks up. ⌘. cancels. ⌘⇧C copies the summary. ⌘⇧M (new, Whois only) returns to My IP.

#### 14.2.2 Cross-tool links (all through `AppRouter`, auto-start = true)
| From | Control | Opens |
|---|---|---|
| Traceroute hop (context menu, public address only) | **Whois this hop** (`person.text.rectangle`) | Whois `<hop IP>` |
| Traceroute hop with a known ASN (context menu) | **Whois AS7922** | Whois `AS7922` |
| Traceroute result header (public target) | icon-only capsule button `person.text.rectangle`, beside **Map in BGP**. VoiceOver: "Whois 8.8.8.8" | Whois `<target IP>` |
| Ping result header (public target) | the same icon button beside **Map in BGP** | Whois `<target IP>` |
| BGP AS details (`ASDetailView`, sheet and inspector) | **Whois AS3356** (new button in the actions group, between *Map prefixes of AS3356* and *Copy ASN*) | Whois `AS3356` |
| BGP toolbar menu (`ellipsis.circle` on iPhone, the trailing menu on iPad) | **Whois 1.1.1.0/24** | Whois `<mapped prefix>` |
| Whois result, address | **Ping** · **Traceroute** · **Map in BGP** (action row) | the tool with that address (the original host name if one was typed) |
| Whois result, prefix | **Map in BGP** | BGP Map with the prefix |
| Whois result, AS | **Map in BGP** | BGP Map with `AS<n>` (goes through the prefix picker, §6.1) |
| Whois result, origin AS row | tap | Whois `AS<n>` (in place, drill-down) |
| Whois raw record link to `stat.ripe.net/<resource>` | tap | Whois `<resource>` in place (no Safari) |
| Whois raw record link to any other `https:` URL | tap | Safari (`openURL`), only when tapped |
| Abuse e-mail | tap | `mailto:` (Mail), long-press → Copy |
| My IP row | context menu | Copy · Share · Map in BGP (the routes toward your own network). No Ping/Traceroute: probing your own public address only measures your router. |

Private addresses: Ping and Traceroute are allowed from the local "Private address" card (pinging your router is legitimate). Map in BGP is hidden for private and reserved space.

### 14.3 iPhone layout

The screen has two **modes** on one view, not two screens. The target bar is always at the top, as in every other tool.

#### 14.3.1 My IP mode (default; target field empty)
1. **Target bar** (`TargetInputBar`, mode `.bgp`): placeholder "IP, prefix, ASN or hostname", leading glyph `person.text.rectangle`, primary button **Look Up** (disabled while the field is empty or invalid, or offline). While loading it becomes **Stop** (red), as for the other tools.
2. Section caption **YOUR PUBLIC IP**. **My IP card** (`MyIPCard`), two rows:
   - Leading family badge (`IPv4` / `IPv6`, caption2 bold, capsule, `fill`), then the address in SF Mono 17 semibold (IPv6 at 15 pt, wraps onto two lines at most, never truncates, `minimumScaleFactor(0.8)`), then the reverse-DNS name in footnote secondary ("www.ripe.net"), or "No reverse DNS".
   - Trailing **Copy** button (`doc.on.doc`, 44 pt hit area).
   - The selected row (the family whose whois is shown below) has a 2 pt tint leading bar and `blue-soft` background. Tapping a row selects it.
   - A row with no address shows the reason in secondary text: "No IPv6 on this network", "IPv4 not available (IPv6-only network)", "Checking…" (with `ProgressView`), or "Couldn't check" + a small **Retry**.
   - Footer (caption, secondary): "As RIPEstat sees this app's connection · 9:41". A second line appears only when a VPN interface is up: "A VPN is active, so this is the VPN's address."
3. **Whois for: `IPv4 | IPv6`** segmented control. Only shown when both families have an address. It mirrors the row selection (two ways to do the same thing; the segmented control is the accessible, obvious one).
4. Section caption **YOUR NETWORK**. **Summary card** (`WhoisSummaryCard`, §14.3.3) for the selected address.
5. **Records row** (card, one row): "Raw records · 1 object, 1 route ›" → pushes `RawRecordsView` (§14.10).
6. **This device** card (`DeviceAddressesCard`) **[Confirm D7]**: "Wi-Fi · 192.168.1.23", "Cellular · 10.172.4.18", "VPN (utun4) · 10.8.0.2", and IPv6 global addresses. Under it one sentence of interpretation (rules in §14.5.6), e.g. "Your router translates 192.168.1.23 to 193.0.6.139 (NAT)." Footnote: "Read from this device. Never sent anywhere."
7. **Look up something else:** example chips `8.8.8.8` · `2606:4700::/32` · `AS13335`, then the shared **Recent** list (`RecentsList`), as in the other tools' empty states.

Pull to refresh re-checks both families (`refreshMyIP()`).

#### 14.3.2 Result mode (after **Look Up**, a cross-link, or a drill-down)
1. Target bar with the query and **Look Up**.
2. **Context line** (footnote, one line): leading **‹ My IP** link button (returns to My IP mode, clears the field), then trailing secondary text:
   - address: reverse DNS name if any ("dns.google"), then "· ARIN" (the RIR);
   - host name input: "apple.com → 17.253.144.10" and, on the next line, "This is the network that hosts the address, not the domain's registration." When the host name has several addresses, an "Other addresses ▾" menu lets the user pick one (re-runs the lookup for it);
   - prefix: "Announced by AS13335" / "Not announced in BGP";
   - AS: "Announcing prefixes" / "Not announcing any prefix".
3. **Summary card** (§14.3.3).
4. **Action row** (`WhoisActions`): up to three equal-width bordered buttons with icon above label (footnote): **Ping** (`dot.radiowaves.left.and.right`), **Traceroute** (`point.topleft.down.to.point.bottomright.curvepath`), **Map in BGP** (`point.3.connected.trianglepath.dotted`). Prefixes and ASes show only Map in BGP (full width). At accessibility sizes the row becomes a vertical list.
5. **Records card**, two rows: "Registry records · 4 objects ›" and "Routing registry (IRR) · 1 route ›". Both push `RawRecordsView`, scrolled to that section.
6. **Source footnote:** "Source: ARIN whois via RIPEstat, updated 13:40 UTC. Registry data can be out of date."

#### 14.3.3 Summary card (`WhoisSummaryCard`)
Card (`cardBackground`, corner 12). Header, then key–value rows (`WhoisRow`): key in footnote secondary (fixed 112 pt column), value in body, selectable (`.textSelection(.enabled)`), long-press → Copy. Missing values are **omitted**, never shown as "—", except Abuse, which shows "Not listed" because its absence matters.

**Header:** network → CIDR in SF Mono bold 20 ("8.8.8.0/24"; several CIDRs → the first plus "+1"); subtitle "GOGL · Google LLC" (name · organization). AS → "AS13335" bold 20; subtitle "CLOUDFLARENET · Cloudflare, Inc.". In My IP mode the header is the CIDR that contains your address.

**Rows, in this order (network):**
| Row | Example | Notes |
|---|---|---|
| Organization | Google LLC | Label switches to **Holder** when taken from `descr`, and to **Network operator** when taken from the origin AS's holder name; then a caption under the value: "from description" / "from AS24940". Org handle in caption2 ("GOGL", "ORG-RIEN1-RIPE"). |
| Range | 8.8.8.0 – 8.8.8.255 | Only when it adds information (always for IPv4; for IPv6 only if not a single CIDR). |
| Country | 🇺🇸 United States | Flag (hidden from VoiceOver) + `Locale.current.localizedString(forRegionCode:)`. Codes that are not countries (`EU`, `AP`, `ZZ`) show as "EU (region)". Caption "from RIR statistics" when not from the record. |
| Registry | ARIN · Direct Allocation | RIR display name · status/net type (as published). An `info.circle` opens a 6-line glossary of common statuses (Allocated PA, Assigned PA, Assigned PI, Direct Allocation, Reallocated, Reassigned). |
| Origin AS | [AS15169] Google › | ASN badge (`asn` style) + short name; tap → Whois AS. Several origins → one badge each (MOAS). "Not announced in BGP" in orange when `network-info`/`prefix-overview` has no origin. If the IRR route objects name a different origin than BGP, a caption says "Registered route object: AS8966 (RADB)". |
| Abuse | network-abuse@google.com | Tint, tap → Mail, long-press → Copy. Several → one per line (max 3, then "+2 more" in raw). |
| Location | United States · approx. | **[Confirm D4]** City when known ("Nuremberg, DE · approx."). `info.circle` → "Estimated by MaxMind GeoLite2 (via RIPEstat). Often wrong for mobile, VPN and cloud addresses." |
| Registered | 28 Dec 2023 | Date only, medium style. "· changed 19 Mar 2026" appended when last-modified exists. |
| Reverse DNS | dns.google | Only in result mode for an address (My IP shows it in the IP row). |

**Rows (AS):** Organization · AS name · Country · Registry · Announcing ("Yes, in BGP now" / "No") · Abuse · Registered.

**Notes strip** (inside the card, under the rows, caption, `fill` background) when present: LACNIC limited data, low confidence, partial data (§14.11). Each note has a single short sentence.

#### 14.3.4 Local verdict card (private / reserved input, no request)
`LocalAddressCard`: icon (`lock` for private, `building.2` for CGNAT, `book.closed` for documentation, `arrow.triangle.2.circlepath` for loopback, `antenna.radiowaves.left.and.right` for multicast, `nosign` for reserved), title ("Private address"), one sentence, then rows: **Range** `192.168.0.0/16` · **Type** Private use · **Standard** RFC 1918 · **Routed on the Internet** No. Actions: Ping and Traceroute (enabled for private, link-local and CGNAT; hidden for documentation, multicast, reserved), no Map. For IPv4-mapped / NAT64 / 6to4 addresses: a prominent **Look up 8.8.8.8 instead** button. Under the card, a hint row: "Your public IP is 193.0.6.139 ›" (returns to My IP), shown when My IP is known.

### 14.4 iPad layout (regular width)

- **Sidebar:** Tools (Ping, Traceroute, BGP Map, **Whois**), Recent, Settings.
- **Detail toolbar row** (as BGP on iPad): "Whois" title, target field (max 300 pt), **Look Up**, then trailing Share menu and the **inspector toggle** (`sidebar.right`).
- **Detail content: one column** (with the sidebar and the inspector open the detail column is only ~550–730 pt, too narrow for two):
  - **Your public IP as two tiles** side by side (`IPv4 | IPv6`, each the same content as an iPhone row: badge, address, reverse DNS, Copy). They stay on top **in result mode too**, so your own IP is always one glance away. Tapping a tile shows that address's whois (My IP mode, that family selected; the selected tile gets the tint bar). Below 520 pt they stack as on iPhone.
  - **This device** as one disclosure row ("This device · Wi-Fi 192.168.1.23 · behind NAT ›") that expands in place to the full card.
  - **The subject:** context line, summary card, action row, routing-registry note. When the inspector is hidden and the detail column is ≥ 760 pt, the summary's key–value rows flow into two columns.
- **Inspector (320 pt, `.inspector`):** **Raw records** for the current subject, the same content as `RawRecordsView` (§14.10). Default **shown** when the window is ≥ 1100 pt wide (landscape 11"/13"), hidden otherwise. The choice is remembered for the session. The records rows in the main column are hidden while the inspector is shown, since they would only duplicate it.
- Slide Over / narrow Split View → compact width → the iPhone layout, state preserved (models live in `AppEnvironment`).

### 14.5 Your public IP: how it is found

#### 14.5.1 What is and isn't feasible on iOS
| Approach | Verdict |
|---|---|
| `URLSession` → `whats-my-ip` (what BGP "Your route" does today) | Works, but returns **one** address: whichever family Happy Eyeballs picked (usually IPv6 on dual-stack networks). `URLSession` has no API to force a family. |
| `URLSession` to `https://193.0.6.150/…` (a literal IP) | Pins the family, but TLS validation and SNI break (the certificate is for `stat.ripe.net`); needs a custom trust evaluator and a hard-coded IP. Rejected: fragile. |
| **`Network.framework` `NWConnection` to `stat.ripe.net:443`, `NWProtocolIP.Options.version = .v4` / `.v6`, TLS on, minimal HTTP/1.1 GET** | **Chosen.** Family is pinned by the stack; SNI and certificate checks are the system's (host name endpoint); no entitlement; works on macOS too, so `swift test` can exercise it. Cost: a ~120-line HTTP/1.1 reader (status line, headers, `Content-Length` or `chunked`), unit-tested with byte fixtures. |
| `getifaddrs` local IPv6 global address | Often equals the public IPv6 (no NAT on v6), but not always (VPN, NPTv6, several temporary addresses), and gives nothing for IPv4 behind NAT. Used only for the *This device* card, not as "your public IP". |
| Family-specific RIPEstat host names | None exist (checked 2026-11-25: `ipv4.stat.ripe.net`, `stat-v4.ripe.net` don't resolve). `stat.ripe.net` has both `A 193.0.6.150` and `AAAA 2001:67c:2e8:22::c100:696`. |

#### 14.5.2 Pinned-family fetch (`RIPEstatClient.whatsMyIP(over:)`)
```
NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp)      // tcp.connectionTimeout = 6
(params.defaultProtocolStack.internetProtocol as! NWProtocolIP.Options).version = .v4 | .v6
NWConnection(host: "stat.ripe.net", port: 443, using: params)
→ .ready: send "GET /data/whats-my-ip/data.json?sourceapp=ahmadrezaei-iptools HTTP/1.1\r\n
                Host: stat.ripe.net\r\nUser-Agent: IPTools/1.2 (iOS; github.com/ahmadrezaei/ip-tools)\r\n
                Accept: application/json\r\nConnection: close\r\n\r\n"
→ receive until isComplete (cap 64 KB) → HTTP1Response.parse → RIPEstatParsing.whatsMyIP(body)
```
- Host and path come from the client's `baseURL`, so tests can point it elsewhere. No ALPN is offered, so the server answers HTTP/1.1.
- Goes through the client's `ConcurrencyGate` (4 max). **Never cached.** Total timeout **8 s**.
- **No route for the family:** the connection enters `.waiting` with a path that is unsatisfied for that family, or fails with `ENETUNREACH`/`EHOSTUNREACH`/DNS "no such record". After a 1.5 s grace in `.waiting`, it throws `PublicIPError.noRoute(version)`. Timeout → `.timeout(version)`; TLS failure → `.tls`; a non-2xx status → `.badResponse(status:)` (429 → `RIPEstatError.rateLimited`, so the busy copy is shared).
- **Skip doomed requests:** `NetworkMonitor` exposes `supportsIPv4` / `supportsIPv6` from `NWPath`. If the path reports no IPv6, the IPv6 row shows "No IPv6 on this network" with **no request**.
- **Fallback:** if both pinned requests fail with something other than `noRoute` (e.g. a proxy that breaks raw TLS connections), the model calls the existing `whatsMyIP()` (URLSession) once and files the answer under the family of the address it returns. The other row shows "Couldn't check".
- **Family mismatch:** the model parses the answer with `IPAddress`. If an IPv6-pinned request comes back with an IPv4 address (a proxy or a VPN terminating the connection), the IPv6 row becomes "No IPv6 through this connection" and the address is ignored there. Identical answers for both rows are de-duplicated.

#### 14.5.3 Special networks
- **IPv6-only with NAT64/DNS64 and 464XLAT (CLAT)** (e.g. T-Mobile US): the IPv4-pinned connection goes out through the CLAT, so RIPEstat sees the carrier's NAT64 IPv4 pool address. That *is* your public IPv4, so it is shown normally. Without CLAT the IPv4 request fails with no route: "IPv4 not available (IPv6-only network)". Test with macOS Internet Sharing's "Create NAT64 Network" (§14.16 Phase 2).
- **VPN:** RIPEstat sees the VPN exit. The footer says so when `NWPath` reports an `.other` interface in use or a `utun`/`ipsec` interface has a non-link-local address.
- **iCloud Private Relay** only relays Safari and unencrypted HTTP; it doesn't change this app's HTTPS traffic. The info popover says: "Safari with iCloud Private Relay shows a different address. This is the address other apps and servers see."
- **CGNAT:** RIPEstat always sees a public address. CGNAT is detected locally (§14.5.6).

#### 14.5.4 Lifecycle and caching (`MyIPLocator`, actor)
- Runs when the Whois tool **first appears** in a session, when it appears again after `NetworkMonitor.pathGeneration` changed, on pull-to-refresh / Refresh, and when the network changes **while the tool is visible** (debounced 2 s, because path updates come in bursts). **[Confirm D6]**
- Both families run **in parallel**; each row fills in as soon as its answer arrives. Typical total: under 1 s.
- Cached per `pathGeneration`, at most 30 minutes (same policy as `MyNetworkLocator`, §6.11.3). Failures are not cached. Memory only.
- Then the **selected family's** address goes through the normal IP lookup (§14.8). The other family's whois loads only when selected, and is cached for the snapshot's lifetime.
- **Default selection:** IPv4 if found, else IPv6. Rationale: it's what people mean by "my IP" in support chats and abuse reports, and it is the one that differs from the device address (NAT). **[Confirm D3]**
- BGP "Your route" keeps its own `MyNetworkLocator` for v1.2 (no cross-module dependency). Merging both into one shared locator is a v1.3 clean-up.

#### 14.5.5 Reverse DNS
For your public addresses and for looked-up addresses, `Resolver.reverseName(for:timeout: 2s)` on the device (system resolver, already a listed destination). No RIPEstat call. Failure → "No reverse DNS".

#### 14.5.6 This device (local addresses, `LocalInterfaces`)
- `getifaddrs`, keeping interfaces that are up and running, not loopback. IPv4 addresses and IPv6 addresses that are global (2000::/3) or ULA; link-local is dropped.
- Interface kind by BSD name: `en0` → Wi-Fi; `pdp_ip*` → Cellular; other `en*` → Wired; `utun*`/`ipsec*` **with a non-link-local address** → VPN (iOS keeps several idle `utun` interfaces with link-local addresses only; those are ignored); anything else → its name. **Verify the names on device.**
- Interpretation line (first match wins):
  1. Local IPv4 in 100.64.0.0/10 → "Your carrier uses CGNAT: 100.72.13.5 is shared space, and many customers share 193.0.6.139."
  2. Local IPv4 is private and public IPv4 is known → "Your router translates 192.168.1.23 to 193.0.6.139 (NAT)."
  3. A local IPv6 equals the public IPv6 → "Your IPv6 address is reachable as is (no NAT)."
  4. Otherwise no line.
- Nothing from this card is sent anywhere or exported unless the user copies it.

### 14.6 Input handling

Reuses `TargetInputBar` with `mode: .bgp` (IP, prefix, ASN, host name; the invalid-input footnote is already "Not a valid IP address, prefix, AS number or hostname") and `TargetParser.parse(_, mode: .bgp)`. Trimming, URL stripping, brackets and `%zone` work as everywhere else.

| Input | Example | Handling |
|---|---|---|
| IPv4 / IPv6 | `8.8.8.8`, `2001:4860:4860::8888` | Special-purpose check (below), then the address plan (§14.8). |
| Prefix | `1.1.1.0/24`, `2001:4860::/32` | Check whether the prefix lies inside a special range, then the prefix plan. Host bits set (`1.1.1.7/24`) are normalised to the network (`1.1.1.0/24`) and the context line says "Showing 1.1.1.0/24". |
| ASN | `AS13335`, `as13335`, `13335` | Reserved-ASN check, then the AS plan. |
| Host name | `apple.com` | `Resolver.resolve(_, preference: settings.addressPreference)`, then the address plan for the resolved address. Context line explains it's the hosting network, not the domain's registration. Resolve failure → the §4.2 "Couldn't Resolve" copy. |

**Special-purpose IPv4** (IANA registry; new `IPAddress.specialPurpose`): `0.0.0.0/8` This network (RFC 791) · `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` Private use (RFC 1918) · `100.64.0.0/10` Shared address space, CGNAT (RFC 6598) · `127.0.0.0/8` Loopback (RFC 1122) · `169.254.0.0/16` Link-local (RFC 3927) · `192.0.0.0/24` IETF protocol assignments (RFC 6890) · `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` Documentation (RFC 5737) · `192.88.99.0/24` 6to4 relay anycast, deprecated (RFC 7526) · `198.18.0.0/15` Benchmarking (RFC 2544) · `224.0.0.0/4` Multicast (RFC 5771) · `240.0.0.0/4` Reserved (RFC 1112) · `255.255.255.255/32` Limited broadcast (RFC 919).

**Special-purpose IPv6:** `::/128` Unspecified · `::1/128` Loopback · `::ffff:0:0/96` IPv4-mapped (offer the embedded IPv4) · `64:ff9b::/96` NAT64 well-known prefix (RFC 6052, offer the embedded IPv4) · `100::/64` Discard (RFC 6666) · `2001::/32` Teredo (RFC 4380) · `2001:db8::/32` and `3fff::/20` Documentation (RFC 3849, RFC 9637) · `2002::/16` 6to4 (RFC 3056, offer the embedded IPv4) · `fc00::/7` Unique local (RFC 4193) · `fe80::/10` Link-local (RFC 4291) · `ff00::/8` Multicast (RFC 4291).

**Reserved ASNs** (new `ReservedASN.lookup`): 0 (RFC 7607) · 23456 AS_TRANS (RFC 6793) · 64496–64511 and 65536–65551 Documentation (RFC 5398) · 64512–65534 and 4200000000–4294967294 Private use (RFC 6996) · 65535 and 4294967295 Reserved (RFC 7300) · 65552–131071 Reserved by IANA.

These tables are new and separate from `IPAddress.isPubliclyRoutable` / `scopeLabel`, whose behaviour (traceroute "Private" badges, BGP rejection) is unchanged in v1.2. Unifying them is a follow-up.

Copy for the local card: "**192.168.1.1** is in 192.168.0.0/16, a private range (RFC 1918). It's only used inside local networks, so no registry has a whois record for it." CGNAT: "…shared address space (RFC 6598). Carriers use it inside their networks for CGNAT; it never appears on the public Internet." Documentation: "…reserved for documentation and examples (RFC 5737). It is never used on real networks." ASN: "AS64512 is a private-use AS number (RFC 6996). Networks use it internally; it has no registry record."

### 14.7 Data source decision

**Recommendation: RIPEstat only.** **[Confirm D2]**

| | RIPEstat (`whois` + helpers) | RDAP (`rdap.org` bootstrap → RIR servers) |
|---|---|---|
| Privacy story | Unchanged: "only RIPEstat is contacted" | Adds `rdap.org` (a third party, not an RIR) and five RIR hosts, plus redirects. PRIVACY.md, About and README grow a list. |
| Coverage | ARIN, RIPE NCC, APNIC, AFRINIC raw objects. **LACNIC: no records** (only IRR route objects). Verified 2026-11-25 for 200.160.2.3, 200.160.0.0/20, 2001:12ff::1 and AS22548. | All five, structured. |
| Org name, RIPE/APNIC/AFRINIC | Only the `org:` handle (RIPEstat returns the inetnum/aut-num object, not the organisation object). | Full entity with name. |
| Abuse contact | `abuse-contact-finder` (RIPEstat queries RDAP server-side): worked for ARIN, RIPE, APNIC, IPv6, AS; failed once for LACNIC with a backend error. | Direct. |
| ARIN IPv6 | A bare address fails ("No match found for + ! 2001 = 4860:4860::8888." — RIPEstat mis-splits the key on the colon). The covering prefix works. | Works. |
| Engineering | One client, one cache, one etiquette, fixtures already in place. | New client, bootstrap, redirects, five server behaviours, rate limits per RIR. |

The gaps have fallbacks (§14.9): LACNIC → AS holder name, RIR statistics country, IRR origin, `abuse-contact-finder`; RIPE-style org → `descr`, then the origin AS's holder name, labelled as such; ARIN IPv6 → retry with the `network-info` prefix. **RDAP stays a possible v1.3 opt-in** ("Fetch the full record from the registry (RDAP)", off by default), if users ask for LACNIC detail.

**Geolocation [Confirm D4]:** recommended **on**, through RIPEstat `maxmind-geo-lite` (so still RIPEstat-only), as one "approx." row with the caveat popover, never in the export, never on a map. Attribution in About: "Location data: GeoLite2 by MaxMind, via RIPEstat." If the owner prefers to avoid location entirely, drop the row and the call; nothing else changes.

### 14.8 Request plans

All calls go through `RIPEstatClient` (4 concurrent max, 5-min URL cache except `whats-my-ip`, `sourceapp` on every call). Every helper call may fail on its own without failing the lookup.

**Address `a`** (public):
1. In parallel: `whois?resource=a` ‖ `network-info?resource=a` ‖ `abuse-contact-finder?resource=a` ‖ `rir-stats-country?resource=a`. On device, in parallel: `Resolver.reverseName(a)`.
2. Then:
   - **ARIN IPv6 retry:** if the whois response is "no match" (§14.9.1) and `network-info` returned a prefix, run `whois?resource=<prefix>` once and use it.
   - `as-names` for the BGP origins ∪ IRR origins (one bulk call, names cache).
   - `maxmind-geo-lite?resource=a` (only if D4 is approved).
3. The summary card appears when step 1 is complete (≈ 1–2 s). Names and location fade in after step 2.

**Prefix `p`:** `whois?resource=p` ‖ `prefix-overview?resource=p` ‖ `abuse-contact-finder?resource=p` ‖ `rir-stats-country?resource=p` → `as-names` (origins without holders, IRR origins). No geolocation, no reverse DNS.

**AS `n`:** `whois?resource=AS<n>` ‖ `as-overview?resource=AS<n>` ‖ `abuse-contact-finder?resource=AS<n>` ‖ `rir-stats-country?resource=AS<n>` → `as-names([n])` only if `as-overview` gave no holder.

**Host name:** resolve on device → the address plan.

**My IP:** `whats-my-ip` pinned v4 ‖ pinned v6 (§14.5.2) → the address plan for the selected family. Cost of opening the tab cold: 2 + 4 + 1–2 = 7–8 requests, then nothing for 30 min on the same network. Switching to the other family costs 5–6 more, once.

**Failure policy:** if `whois` **and** the BGP call (`network-info`/`prefix-overview`/`as-overview`) both fail, the lookup fails (§14.11). If only `whois` fails, show the card with the BGP/abuse/country facts and the note "Registry record unavailable right now." + **Try Again**. Any other single failure only removes its rows (and adds a `missing(part)` note in raw view, not on the card).

**Cancellation:** a new Look Up, Stop, ⌘., leaving to My IP, or `scenePhase == .background` cancels the task group. Results already shown stay.

**Recents:** recorded with `Tool.whois` when a lookup *starts successfully* (after parse and, for host names, after resolution), same rule as §3.1. My IP fetches never record.

### 14.9 Parsing and normalisation (`WhoisSummarizer`, pure, in RIPEstat)

#### 14.9.1 The raw response
`data.records`: array of objects; each object is an array of `{key, value, comment, details_link}`. `data.irr_records`: same shape. `data.authorities`: e.g. `["arin"]`. `data.resource`, `data.query_time`. `messages` may contain `info` ("IP address has been converted to a prefix", ignored) and `warning` ("Authoritative RIR could not be identified. Best match is returned!" → `lowConfidence`).

Cleaning: trim every key and value (ARIN values end with a space). Keep empty values (they are paragraph breaks in `remarks`/`Comment`). Keep repeated keys in order. `details_link` → `URL` if it parses and has scheme `https`, `http` or `mailto`.

**No-match marker:** a record whose first key starts with `No match found` (e.g. key `"No match found for + ! 2001"`, value `"4860:4860::8888."`), or starts with `%`, is a marker, not an object. A response whose only resource records are markers is `isNoMatch`.

#### 14.9.2 Classifying records (by first key)
| First key | Class |
|---|---|
| `NetRange`, `inetnum`, `inet6num` | network object |
| `ASNumber`, `aut-num` | AS object |
| `OrgName` | organisation (ARIN) |
| `OrgAbuseHandle`, `RAbuseHandle` | abuse contact (ARIN; `R…` = resource-level) |
| `OrgTechHandle`, `OrgNOCHandle`, `OrgRoutingHandle`, `RTechHandle`, `RNOCHandle` | other contact (ARIN) |
| `route`, `route6` (in `irr_records`) | IRR route object |
| anything else | other (raw view only) |

**Most specific network object:** ARIN often returns the parent chain (e.g. `ARIN-004 2001:4800::/23` then `GOOGLE-IPV6 2001:4860::/32`). Pick the object with the **longest prefix length** (from its CIDR, or the smallest range when only a range is given); ties → the later one. Same rule if a prefix query returns several.

**IRR records:** de-duplicate identical objects (RIPE often returns the same route twice, once with a privacy banner). Origins = distinct `origin` values as `UInt32`.

#### 14.9.3 Field mapping per RIR
| Summary field | ARIN | RIPE NCC / APNIC / AFRINIC (RPSL) | LACNIC (no records) | Fallback (any RIR) |
|---|---|---|---|---|
| CIDRs | `CIDR` (comma-separated list possible) | `inetnum`/`inet6num` if it is a CIDR; else computed from the range (minimal CIDR cover) | — | routed prefix from `network-info` / `prefix-overview` |
| Range | `NetRange` ("8.8.8.0 - 8.8.8.255") | `inetnum` if it is a range; else computed from the CIDR | — | from the routed prefix |
| Name | `NetName` | `netname` | — | — |
| Handle | `NetHandle` | (none; the inetnum is the key) | — | — |
| Descriptions | — | `descr` (all lines, max 3 on the card) | — | — |
| Organization (registry) | `Organization` "Google LLC (GOGL)" → name "Google LLC", handle "GOGL"; or `Customer` (reassignments, same format); else `OrgName` of the first org object | `org-name` if present; `owner` if present | — | **Holder** = first `descr` line that is not the netname and not a postal-looking line (contains a digit-only token of ≥ 4 digits or ends in a country name); then **Network operator** = `as-names` holder of the primary origin AS, with the handle part removed (`ASName` rule 1 only, legal suffix kept: "Hetzner Online GmbH") |
| Org handle | parenthetical of `Organization`/`Customer`, or `OrgId` | `org` | — | — |
| Country | `Country` of the organisation object whose `OrgId` equals the org handle (else the first org object) | `country` | — | `rir-stats-country` first `located_resources[].location` (caption "from RIR statistics") |
| RIR | `source` = ARIN | `source` (RIPE, RIPE-NONAUTH → RIPE NCC; APNIC; AFRINIC) | `authorities[0]` = lacnic | `abuse-contact-finder.authoritative_rir` |
| Status | `NetType` | `status` | — | — |
| Parent | `Parent` | `parent` (AFRINIC) | — | — |
| Origin AS (BGP) | — | — | — | `network-info.asns` / `prefix-overview.asns` (always BGP; never from whois) |
| Registered origins | `OriginAS` (often empty) | — | — | IRR `origin` values |
| Abuse e-mails | (fallback) `OrgAbuseEmail`, then `RAbuseEmail` | (fallback) `abuse-mailbox` | — | **Primary for all:** `abuse-contact-finder.abuse_contacts`. Last resort: first e-mail address in a `remarks`/`Comment`/`descr` line that contains "abuse" (APNIC 1.1.1.0/24: `resolver-abuse@cloudflare.com`) |
| Registered | `RegDate` (yyyy-MM-dd) | `created` (ISO 8601 Z) | — | — |
| Last modified | `Updated` | `last-modified` | — | — |
| Contacts (handles) | `OrgTechHandle`, `OrgNOCHandle`, `OrgAbuseHandle` | `admin-c`, `tech-c`, `abuse-c`, `mnt-by` | — | raw view only |
| **AS objects** | `ASNumber`, `ASName`, `ASHandle`, `RegDate`, `OrgName`/`Country` from the org object | `aut-num`, `as-name`, `descr`, `org`, `country`, `created`, `last-modified` | — | holder from `as-overview` / `as-names`; country from RIR stats; announcing from `as-overview.announced` |

**RIR display names:** AFRINIC, APNIC, ARIN, LACNIC, RIPE NCC.

**Not-found rule:** the summary is *empty* (→ "No registry record", §14.11) when there is no usable network/AS object (none, or only no-match markers), no IRR record, no routed prefix and no RIR-statistics country. **IANA catch-all rule:** a chosen network object with prefix length ≤ 8 (IPv4) or ≤ 12 (IPv6) **and** the low-confidence warning (e.g. `IANA-BLK 0.0.0.0/0`, returned for 10.0.0.1) counts as no object.

**Notes:** `registryRecordsUnavailable(rir)` (LACNIC, or any RIR with only markers after the retry) · `lowConfidence` · `notAnnounced` (registered but no BGP origin) · `missing(part)` for each helper call that failed.

#### 14.9.4 Golden expectations (from fixtures captured 2026-11-25)
| Fixture | Expected summary |
|---|---|
| `whois_8.8.8.8` + `network-info_8.8.8.8` + `abuse_8.8.8.8` | CIDR `8.8.8.0/24`, range `8.8.8.0 - 8.8.8.255`, name GOGL, handle NET-8-8-8-0-2, org "Google LLC" (registry, handle GOGL), country US (registry), ARIN, status "Direct Allocation", parent "NET8 (NET-8-0-0-0-0)", BGP origin 15169, registered origins [15169] (RADB), abuse [network-abuse@google.com], registered 2023-12-28 |
| `whois_2001-4860-4860--8888` (no-match) → retry `whois_2001-4860--32` | Retry happens; chosen object GOOGLE-IPV6 `2001:4860::/32` (not ARIN-004 /23), org Google LLC, country US from org object GOGL (not ARIN's), abuse from finder [arin-contact@google.com, network-abuse@google.com] |
| `whois_193.0.6.139` | CIDR `193.0.0.0/21`, name RIPE-NCC, descr ["RIPE Network Coordination Centre", "Amsterdam, Netherlands"], org **Holder** "RIPE Network Coordination Centre" (from description), handle ORG-RIEN1-RIPE, NL, RIPE NCC, "ASSIGNED PA", registered 2003-03-17, changed 2026-03-19, registered origins [3333] (duplicate IRR collapsed), abuse [abuse@ripe.net] from finder |
| `whois_1.1.1.1` | CIDR `1.1.1.0/24`, APNIC-LABS, Holder "APNIC and Cloudflare DNS Resolver project", AU, APNIC, "ASSIGNED PORTABLE", changed 2023-04-26, registered origins [13335]; finder → [helpdesk@apnic.net]; with the finder failed → remarks fallback [resolver-abuse@cloudflare.com] |
| `whois_196.216.2.1` | CIDR `196.216.2.0/23`, AFRINIC, Holder "AfriNIC - Internal Use", ZA, AFRINIC, "ASSIGNED PI", parent "196.0.0.0 - 196.255.255.255", registered origins [33764] |
| `whois_200.160.2.3` (LACNIC, records empty) + `network-info` + `rir-stats-country` + `as-names` | note `registryRecordsUnavailable(.lacnic)`, CIDR `200.160.0.0/20` (from BGP), **Network operator** "Nucleo de Inf. e Coord. do Ponto BR - NIC.BR" (from AS22548), country BR (from RIR statistics), LACNIC, origin 22548, registered origins [22548] |
| `whois_91.107.240.242` | CIDR `91.107.240.0/20`, CLOUD-NBG1, no descr → **Network operator** "Hetzner Online GmbH" (from AS24940), DE, RIPE NCC, "ASSIGNED PA" |
| `whois_10.0.0.1` | IANA catch-all rule → empty (never requested by the app, which rejects 10/8 locally; the test guards the rule) |
| `whois_AS13335` | AS, name CLOUDFLARENET, org "Cloudflare, Inc." (OrgName), US, ARIN, registered 2010-07-14, abuse [abuse@cloudflare.com] |
| `whois_AS3333` | AS, name RIPE-NCC-AS, Holder "Reseaux IP Europeens Network Coordination Centre (RIPE NCC)", RIPE NCC; the 80+ `remarks`/`import`/`export` lines stay raw-only |
| `whois_AS22548` (empty) | note LACNIC, org from `as-overview`/`as-names` holder, country from RIR stats |
| `whois_ORG-HOA1-RIPE` (HTTP 400, "unsupported resource type") | `RIPEstatError.api` with the message (guards the error path) |

### 14.10 Raw records view (`RawRecordsView`)

- Pushed on iPhone (title "Raw Records", inline; back button shows the query), inspector on iPad. Toolbar: Share (full record text) and Copy.
- **Section "Registry records"** (header: "ARIN · 4 objects" / "RIPE NCC · 1 object"), one card per object. **Section "Routing registry (IRR)"**, one card per de-duplicated route object, header "route 8.8.8.0/24 · RADB". Markers (no-match) appear as a single grey line "ARIN had no match for the address; showing the covering prefix 2001:4860::/32."
- **Object card header:** a friendly class name plus the primary value: "Network · 8.8.8.0/24" (NetRange/inetnum/inet6num), "AS · 13335", "Organization · Google LLC", "Abuse contact · ABUSE5250-ARIN", "Technical contact", "NOC contact", "Routing contact". Unknown classes use the first key. The **object chosen for the summary** gets a "Used in summary" tag.
- **Rows:** key in SF Mono footnote secondary (fixed 128 pt column, wraps), value in SF Mono footnote (selectable). Rows stack (key above value) at accessibility sizes.
- **Paragraph keys** (`remarks`, `Comment`, `descr` with > 3 lines): consecutive lines are joined into one block, blank values become line breaks, ASCII banners (lines made only of `+ - * = | #` and spaces) are kept as they are. Blocks over 6 lines collapse with "Show 34 more lines".
- **Links** (`details_link`): `https://stat.ripe.net/<resource>` → in-app Whois of that resource. Other `https`/`http` → Safari after a tap. `mailto:` → Mail. Plain e-mail addresses in values are detected (`NSDataDetector`) and become `mailto:` links.
- Long-press a row → *Copy Value* · *Copy "key: value"*. Header menu → *Copy Object*.
- Personal data (names, phone numbers in ARIN POCs; RIPE strips personal data at source) is shown exactly as RIPEstat returns it publicly. Nothing is stored.

### 14.11 States

**My IP**
| State | UI |
|---|---|
| Checking | Both rows "Checking…" with a small `ProgressView`; summary card skeleton (`redacted(.placeholder)`) |
| Both found | As §14.3.1; IPv4 selected |
| IPv4 only | IPv6 row: "No IPv6 on this network" (secondary, `network.slash` glyph). No segmented control |
| IPv6 only | IPv4 row: "IPv4 not available (IPv6-only network)". IPv6 selected |
| Mismatch (proxy/VPN) | IPv6 row: "No IPv6 through this connection" |
| One failed | That row: "Couldn't check" + **Retry**. The other works normally |
| Both failed, online | `ErrorStateView`: "Couldn't Find Your IP" · "RIPEstat didn't answer. Check your connection and try again." + Try Again. *This device* card still shown |
| RIPEstat busy (429/5xx) | "RIPEstat is busy. Try again in a moment." + Try Again (shared copy with §6.9) |
| Offline | Offline banner under the bar; rows "Connect to the Internet to see your public IP"; *This device* card still shown (Wi-Fi without Internet still has a local address); Look Up disabled |
| Network changed | Rows switch to "Checking…" automatically (debounced 2 s) |
| Whois of own IP failed | My IP rows stay; summary area shows the lookup error inline with Try Again |

**Lookup**
| State | UI |
|---|---|
| Resolving (host name) | Context line "Resolving apple.com…" with `ProgressView`; Stop available |
| Loading | Context line "Looking up 8.8.8.8 at RIPEstat…"; summary card skeleton; Stop |
| Loaded | §14.3.2 |
| Partial (whois failed, BGP worked) | Card with available rows + note "Registry record unavailable right now." + Try Again |
| LACNIC (no records) | Card with BGP/RIR-statistics rows + note "LACNIC doesn't share whois records through RIPEstat. Showing BGP and registry statistics." + "Open in RIPEstat" (Safari) |
| Low confidence | Note "RIPEstat couldn't identify the responsible registry; this is the best match." |
| Not announced | Origin row in orange "Not announced in BGP"; everything else normal (common for allocated but unused space) |
| Not found | `ContentUnavailableView("No Registry Record", systemImage: "questionmark.folder", description: "No registry has a record for 2001:db9::1. It may be unallocated.")` |
| Private / reserved / CGNAT / documentation / special ASN | Local verdict card (§14.3.4), no request |
| Mapped / NAT64 / 6to4 IPv6 | Local card + **Look up 8.8.8.8 instead** |
| Invalid input | Red footnote under the field (existing `TargetInputBar` behaviour); Look Up disabled |
| Resolve failed | §4.2 copy "Couldn't Resolve apple.cmo" + "Check the spelling or your DNS." |
| Rate-limited / 5xx (RIPEstat returned an nginx "502 Bad Gateway" HTML page on 2026-11-25) | "RIPEstat is busy. Try again in a moment." + Try Again |
| Timeout (> 30 s) | "RIPEstat didn't respond." + Try Again |
| Offline | Offline banner, Look Up disabled; a result already on screen stays |
| Backgrounded | Lookup cancelled; on return, "Stopped — app moved to background" + Try Again (only if nothing was shown yet) |

`WhoisFailure` mirrors `BGPFailure` (kinds `busy`, `timeout`, `offline`, `notFound`, `unresolved`, `invalid`, `other`) with the same titles, symbols and actions where they overlap.

### 14.12 Export text

Footer line and date format as the other tools (§4.6). **Share Summary** (also ⌘⇧C):
```
WHOIS 8.8.8.8 (dns.google)
Network     8.8.8.0/24  (8.8.8.0 - 8.8.8.255)
Name        GOGL  (NET-8-8-8-0-2)
Org         Google LLC  (GOGL)
Country     US
Registry    ARIN · Direct Allocation
Origin AS   AS15169 Google LLC  (BGP)
Abuse       network-abuse@google.com
Registered  2023-12-28
Source: ARIN whois via RIPEstat, 2026-11-25 13:40 UTC
— IP Tools for iOS, 2026-11-25 13:52 UTC
```
Provenance is kept in the text: `Org         Hetzner Online GmbH  (network operator, from AS24940)`, `Country     BR  (RIR statistics)`. A LACNIC lookup adds `Note: LACNIC doesn't share whois records through RIPEstat.` **The location row is never exported.**

**Share Full Record** = the summary, a blank line, then every object as `key:  value` lines (keys padded to the longest key in the object, as `whois` CLI output), objects separated by blank lines, then `--- routing registry (IRR) ---` and the route objects, then the footer.

**My IP** (toolbar Share in My IP mode):
```
My public IP — 2026-11-25 09:41 UTC
IPv4  193.0.6.139                 www.ripe.net
IPv6  2001:67c:2e8:22::c100:696
Network  193.0.0.0/21 · RIPE-NCC · AS3333 RIPE NCC · NL · RIPE NCC
Abuse    abuse@ripe.net
— IP Tools for iOS
```
Local device addresses are not included (copy them from the card if needed).

### 14.13 Accessibility

- **Order and headings:** "Your public IP", "Your network", "This device" and the raw-record object headers are `.isHeader`, so the headings rotor jumps between them.
- **Address rows:** one element each. Label: "IPv4 address, 193.0.6.139, www.ripe.net. Selected for whois." Actions (`accessibilityActions`): *Copy*, *Show whois* (when not selected), *Map in BGP*. IPv6 addresses get a speakable label built by `IPSpeech.label(_:)`: groups separated by pauses, `::` spoken as "double colon", hex letters spelled ("2001, 67c, 2e8, 22, double colon, c100, 696" with `speechSpellsOutCharacters` on letter groups).
- **Summary rows:** each row is one element "Organization, Google LLC" (`LabeledContent` semantics), provenance appended ("Network operator, Hetzner Online GmbH, from AS 24940"). ASNs spoken as "AS 15169" (as §6.11.10). The flag emoji is hidden; the country name is spoken.
- **Announcements:** when a lookup finishes, `.announcement` "Whois loaded: Google LLC, ARIN, United States". When My IP finishes: "Your IPv4 address is 193.0.6.139. IPv6 address found." Failures announce their title.
- **Dynamic Type up to AX5:** key–value rows switch to stacked layout from `.accessibility1`; the action row becomes a vertical list; IPv6 addresses wrap (never truncate).
- **Colour is never the only signal:** the selected address row has a tint bar *and* "Selected" in its label; "Not announced" is orange *and* says so; notes have text.
- **Raw view:** monospaced text is selectable; long paragraphs collapse with an explicit button ("Show 34 more lines", announced count); links have the hint "Opens in Safari" / "Looks up 193.0.0.0/21".
- **Keyboard:** everything is reachable with Tab; shortcuts in §14.2.1.
- **Reduce Motion:** skeleton shimmer off; rows appear without slide.

### 14.14 Privacy and store text

**App Privacy label: stays "Data Not Collected".** Lookups are sent to RIPEstat to serve the request the user made (the same basis as BGP Map today); the developer receives nothing; no identifiers; your public IP is kept in memory only. `PrivacyInfo.xcprivacy` is unchanged (`getifaddrs` and `NWConnection` are not required-reason APIs). `Info.plist` is unchanged: no new permission (reading local interface addresses and connecting to a public host don't trigger the Local Network prompt). No ATS exception (HTTPS only).

**PRIVACY.md, exact changes**
- Item 2 becomes: "**The system DNS resolver**, to turn host names into addresses and, in Whois, to look up the host name of an address."
- Item 3: append after the *your path* sentences:
  > **Whois and My IP.** The IP address, prefix or AS number you look up in Whois is sent to RIPEstat. If you enter a host name, it is resolved on your device and only the resulting address is sent. **My IP** asks RIPEstat which public address your connection uses, once over IPv4 and once over IPv6, and then looks that address up the same way. RIPEstat already sees that address on every request. The app keeps it in memory only, forgets it when your network changes, and never sends it anywhere else. The approximate location shown for an address is MaxMind GeoLite2 data delivered by RIPEstat; the app doesn't use your device's location. Links inside whois records, such as a registry web page or an e-mail address, open in Safari or Mail only when you tap them.
- New section after *Stored on your device*:
  > ## Your device's local addresses
  > The Whois tab shows this device's own network addresses (for example its Wi-Fi address) so you can compare them with your public IP. They are read on the device and are never sent anywhere.
- *Stored on your device*, first sentence becomes: "Recent targets (up to 20, including Whois lookups) and your settings are kept locally in `UserDefaults`."

(If D4 is declined, drop the location sentence. If D7 is declined, drop the new section.)

**About screen** (`AboutSections`), one new footnote under the *Your path* line:
"My IP & Whois: your public IP and the addresses, prefixes and AS numbers you look up are sent to RIPEstat. Your device's local addresses never leave it."
*Data sources* footer becomes: "BGP and whois data: RIPE NCC RIPEstat, built from RIPE RIS route collectors and the AFRINIC, APNIC, ARIN, LACNIC and RIPE NCC registries. Location data: GeoLite2 by MaxMind, via RIPEstat."

**README.md, exact changes**
- Title: "IP Tools: Ping, Traceroute, Whois & BGP Map for iPhone and iPad". Intro: "…**ping** any IP or hostname, **traceroute** hop by hop with ASN lookup, see **your public IP and whois** for any IP, prefix or AS, and explore a **visual BGP map**…".
- "**IP Tools** does three things" → "does four things". Table: new row "🔎 **Whois & My IP** | Your public IPv4 and IPv6 address and the network behind it. Whois for any IP, prefix or AS number across all five RIRs: organization, country, origin AS, abuse contact, plus the raw registry records."
- New features section "### Whois & My IP": your public IPv4 and IPv6 as the Internet sees them (both families checked separately), reverse DNS, your local addresses and NAT/CGNAT hint; whois for IPs, prefixes, AS numbers and host names; one clean summary across ARIN, RIPE NCC, APNIC, AFRINIC and LACNIC with the raw records; private, CGNAT and documentation ranges explained offline; one tap from a traceroute hop or a BGP network; share as text.
- *Made for iPhone and iPad*: "iPhone: four tabs"; "⌘1–4 to switch tools".
- *Privacy*: replace "Only BGP Map queries and the ASN lookup…" with "Only BGP Map, Whois and the ASN lookup for public traceroute hops contact **RIPEstat**…", and add "**My IP** asks RIPEstat for your public IPv4 and IPv6 address; it is kept in memory only. Your local addresses never leave the device."
- *Project structure*: "Sources/PingFeature, TraceFeature, BGPFeature, WhoisFeature   The four tools".
- FAQ, two new entries: "**Can it show my IP address?** Yes. The Whois tab shows your public IPv4 and IPv6 address, checked separately, the network and provider behind them, and your device's local addresses." · "**Does it look up domain names?** It looks up the network that hosts a domain's address. Domain registration whois (who registered example.com) isn't supported."
- *Contributing*: "keep the app focused on its four tools".
- Keywords footer: add "what is my IP, my IP address, IPv6 address, whois lookup, IP whois, ASN whois, abuse contact lookup".

**App Store metadata (§8 updates) [Confirm D8, D9]**
- **Name (27/30):** unchanged, `IP Tools: Ping & Traceroute`. Renaming would cost the "traceroute" title weight and the brand recognition of a shipped app.
- **Subtitle (27/30):** `Whois, BGP Map & ASN Lookup` (was `BGP Map, AS Path & ASN Lookup`). "whois" gets subtitle weight and pairs with "lookup" ("whois lookup", "ip lookup", "asn lookup"); "path" moves to keywords. Alternative: `My IP, Whois & BGP Map` (22/30), which loses "asn lookup".
- **Keywords (100/100):** `my,address,network,looking,glass,tracert,icmp,latency,ipv6,prefix,route,path,hop,jitter,ripe,isp,dns`
  Added: `my` ("my ip", "what is my ip"), `address` ("ip address"), `path` (moved from the subtitle). Dropped: `mtr` (the app has no mtr mode) and `peering` (lowest search value). No word repeats the name or subtitle (ip, tools, ping, traceroute, whois, bgp, map, asn, lookup).
- **Promotional text (162/170):** `New: see your public IPv4 and IPv6 address and the whois record of any IP, prefix or AS. Plus ping, traceroute and a live BGP map. Free, open source, no tracking.`
- **Description:** first sentence becomes "IP Tools is a fast, no-nonsense network toolkit for iPhone and iPad: ping, traceroute, whois and a visual BGP map that shows how the Internet reaches any IP address, prefix or ASN." New section after TRACEROUTE:
  ```
  MY IP & WHOIS
  • See your public IPv4 and IPv6 address, exactly as the Internet sees it
  • Who runs your network: provider, AS number, country and abuse contact
  • Whois any IP address, prefix or AS number, across ARIN, RIPE NCC, APNIC, AFRINIC and LACNIC
  • A clean summary card plus the full raw registry records
  • Private, CGNAT and documentation ranges explained instantly, offline
  • Whois any traceroute hop or BGP network with one tap
  ```
  TRACEROUTE gains "• Ping, map or whois any hop with one tap" (replacing "Ping or map any hop with one tap"). PRIVATE AND OPEN SOURCE: "• BGP, whois and ASN data comes from the public RIPEstat API by the RIPE NCC" and "• Your public IP is looked up only when you open Whois, and never stored".
- **Screenshots:** add "My IP & whois" ("Your IP and who runs it") as **#2** on 6.9", 6.3" and 13" iPad (whois is the highest-volume search term of the set). **Screenshot mode must not show the developer's real IP:** `-screenshotTool whois` makes `AppEnvironment` inject fixed My IP answers (193.0.6.139 / 2001:67c:2e8:22::c100:696, RIPE NCC, verified data) instead of calling `whats-my-ip`.

### 14.15 Architecture

#### 14.15.1 Modules
```
                 NetCore ─────────────┐        RIPEstat              BGPGraph
   (+ SpecialPurpose, LocalInterfaces)│   (+ whois, abuse, country,
                                      │      geo, pinned whats-my-ip,
                                      │      WhoisSummarizer)
                 SharedUI (+ Tool.whois, NetworkMonitor.supportsIPv4/6, interface kind)
        ┌────────────┬───────────────┬──────────────┬──────────────────┐
   PingFeature  TraceFeature     BGPFeature    WhoisFeature (new: NetCore, RIPEstat, SharedUI)
        └────────────┴───────────────┴──────────────┴──────────────────┘
                                   AppShell (+ WhoisFeature)
```
WhoisFeature must not depend on BGPFeature, TraceFeature or PingFeature; it reaches them only through `AppRouter`. Nothing depends on WhoisFeature except AppShell (and FeatureTests).

**`Package.swift` (coordinator, Step 0):**
```swift
.target(name: "WhoisFeature", dependencies: ["NetCore", "RIPEstat", "SharedUI"]),
// AppShell dependencies += "WhoisFeature"
// FeatureTests dependencies += "WhoisFeature"
```

#### 14.15.2 NetCore (new files only: `SpecialPurpose.swift`, `LocalInterfaces.swift`)
```swift
public struct SpecialPurposeRange: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case thisNetwork, privateUse, sharedCGNAT, loopback, linkLocal, protocolAssignments, documentation,
             relayAnycast, benchmarking, multicast, reserved, broadcast,
             unspecified, ipv4Mapped, nat64, discard, teredo, sixToFour, uniqueLocal
    }
    public let network: IPAddress
    public let length: Int
    public let kind: Kind
    public let name: String            // "Private use", "Shared address space (CGNAT)"
    public let rfc: String             // "RFC 1918"
    public var cidr: String { get }    // "192.168.0.0/16"
    public var allowsProbing: Bool { get }   // ping/trace sensible: private, CGNAT, link-local, loopback, ULA
    public static let ipv4: [SpecialPurposeRange]
    public static let ipv6: [SpecialPurposeRange]
    /// The range containing the whole prefix `network/length`, if any (most specific first).
    public static func containing(_ network: IPAddress, length: Int) -> SpecialPurposeRange?
}
public extension IPAddress {
    var specialPurpose: SpecialPurposeRange? { get }   // == SpecialPurposeRange.containing(self, length: 32|128)
    var embeddedIPv4: IPAddress? { get }               // ::ffff:a.b.c.d, 64:ff9b::a.b.c.d, 2002:aabb:ccdd::/48
    /// The network address of `self/length` (host bits cleared).
    func masked(to length: Int) -> IPAddress
}
public struct ReservedASN: Hashable, Sendable {
    public let range: ClosedRange<UInt32>
    public let name: String            // "Private use", "Documentation", "AS_TRANS"
    public let rfc: String
    public static func lookup(_ asn: UInt32) -> ReservedASN?
}
public struct LocalAddress: Hashable, Sendable, Identifiable {
    public enum Interface: Hashable, Sendable { case wifi, cellular, wired, vpn, other }
    public var id: String { get }      // "\(name)|\(address)"
    public let interface: Interface
    public let name: String            // BSD name, "en0"
    public let address: IPAddress
    public init(interface: Interface, name: String, address: IPAddress)
}
public enum LocalInterfaces {
    /// getifaddrs; up+running, non-loopback; IPv4 + global/ULA IPv6. Sorted Wi-Fi, cellular, wired, VPN, other; v4 before v6.
    public static func current() -> [LocalAddress]
    static func classify(name: String, hasNonLinkLocal: Bool) -> LocalAddress.Interface   // unit-tested
}
```

#### 14.15.3 RIPEstat (new files `Whois.swift`, `WhoisParsing.swift`, `WhoisSummary.swift`, `WhoisSummarizer.swift`, `WhoisRange.swift`, `PinnedHTTP.swift`; changed `RIPEstatClient.swift`, `MockRIPEstat.swift`, `DateParsing.swift`)
```swift
public enum IPVersion: String, Sendable, Hashable, CaseIterable { case v4, v6 }
public enum PublicIPError: Error, Sendable, Equatable {
    case noRoute(IPVersion), timeout(IPVersion), tls, badResponse(status: Int)
}
public struct WhoisField: Sendable, Hashable {
    public let key: String; public let value: String; public let link: URL?
    public init(key: String, value: String, link: URL?)
}
public struct WhoisRecord: Sendable, Hashable, Identifiable {
    public let id: Int                                  // index in the response
    public let fields: [WhoisField]
    public var primaryKey: String { get }               // first key
    public var primaryValue: String { get }
    public var source: String? { get }                  // "ARIN", "RIPE", "RADB"…
    public var isNoMatchMarker: Bool { get }
    public func first(_ key: String) -> String?         // case-sensitive (ARIN keys are CamelCase, RPSL lower-case)
    public func all(_ key: String) -> [String]
    public init(id: Int, fields: [WhoisField])
}
public struct WhoisResponse: Sendable, Hashable {
    public let resource: String
    public let authorities: [String]                    // lower-case RIR ids
    public let records: [WhoisRecord]
    public let irrRecords: [WhoisRecord]                // de-duplicated
    public let warnings: [String]
    public let queryTime: Date?
    public var isNoMatch: Bool { get }
    public var isLowConfidence: Bool { get }
    public init(resource: String, authorities: [String], records: [WhoisRecord], irrRecords: [WhoisRecord],
                warnings: [String], queryTime: Date?)
}
public struct AbuseContacts: Sendable, Hashable {
    public let emails: [String]; public let authoritativeRIR: String?
    public init(emails: [String], authoritativeRIR: String?)
}
public struct GeoLocation: Sendable, Hashable {
    public let country: String?; public let city: String?; public let coveredFraction: Double?
    public init(country: String?, city: String?, coveredFraction: Double?)
}

public protocol RIPEstatAPI: Sendable {
    // … existing …
    func whatsMyIP(over version: IPVersion) async throws -> WhatsMyIP     // NWConnection pinned family, never cached, 8 s
    func whois(_ resource: String) async throws -> WhoisResponse          // "8.8.8.8", "1.1.1.0/24", "AS13335"
    func abuseContacts(_ resource: String) async throws -> AbuseContacts  // abuse-contact-finder
    func registeredCountry(_ resource: String) async throws -> String?    // rir-stats-country, first location
    func geolocation(_ ip: String) async throws -> GeoLocation?           // maxmind-geo-lite, first location (D4)
}
public extension RIPEstatAPI {   // keeps existing fakes compiling (pattern of §12.7)
    func whatsMyIP(over version: IPVersion) async throws -> WhatsMyIP { throw RIPEstatError.api(messages: ["whats-my-ip(over:) not supported"]) }
    func whois(_ resource: String) async throws -> WhoisResponse { throw RIPEstatError.api(messages: ["whois not supported"]) }
    func abuseContacts(_ resource: String) async throws -> AbuseContacts { throw RIPEstatError.api(messages: ["abuse-contact-finder not supported"]) }
    func registeredCountry(_ resource: String) async throws -> String? { nil }
    func geolocation(_ ip: String) async throws -> GeoLocation? { nil }
}

public enum RIR: String, Sendable, Hashable, CaseIterable {
    case afrinic, apnic, arin, lacnic, ripe
    public init?(identifier: String)                  // "ARIN", "arin", "RIPE", "RIPE-NONAUTH", "RIPE NCC", "AfriNIC"…
    public var displayName: String { get }            // "AFRINIC", "APNIC", "ARIN", "LACNIC", "RIPE NCC"
}
public struct WhoisSummary: Sendable, Hashable {
    public enum Subject: Sendable, Hashable { case network, autonomousSystem(UInt32) }
    public enum Provenance: Sendable, Hashable { case registry, description, asHolder(UInt32), rirStatistics, bgp }
    public enum Part: Sendable, Hashable { case registry, routing, abuse, country, location, names }
    public enum Note: Sendable, Hashable { case registryRecordsUnavailable(RIR?), lowConfidence, notAnnounced, missing(Part) }
    public struct Contact: Sendable, Hashable { public let role: String; public let handle: String }
    public let subject: Subject
    public let query: String
    public let cidrs: [String]
    public let range: String?
    public let name: String?
    public let handle: String?
    public let descriptions: [String]
    public let organization: String?
    public let organizationProvenance: Provenance?
    public let orgHandle: String?
    public let country: String?                       // ISO 3166-1 alpha-2 or region code, upper-case
    public let countryProvenance: Provenance?
    public let rir: RIR?
    public let status: String?
    public let parent: String?
    public let routedPrefix: String?
    public let originASNs: [UInt32]                   // BGP
    public let registeredOrigins: [UInt32]            // IRR / ARIN OriginAS
    public let announced: Bool?
    public let abuseEmails: [String]
    public let abuseProvenance: Provenance?           // .registry (whois) or nil when from abuse-contact-finder
    public let registered: Date?
    public let lastModified: Date?
    public let contacts: [Contact]
    public let summaryRecordID: Int?                  // WhoisRecord.id used ("Used in summary" tag)
    public let notes: [Note]
    public var isEmpty: Bool { get }                  // not-found rule, §14.9.3
}
public struct WhoisInputs: Sendable {
    public var whois: WhoisResponse?
    public var network: NetworkInfo?
    public var prefixOverview: PrefixOverview?
    public var asOverview: ASOverview?
    public var abuse: AbuseContacts?
    public var country: String?
    public var names: [UInt32: String]
    public var failed: Set<WhoisSummary.Part>
    public init(whois: WhoisResponse? = nil, network: NetworkInfo? = nil, prefixOverview: PrefixOverview? = nil,
                asOverview: ASOverview? = nil, abuse: AbuseContacts? = nil, country: String? = nil,
                names: [UInt32: String] = [:], failed: Set<WhoisSummary.Part> = [])
}
public enum WhoisSummarizer {
    public static func summarize(query: String, subject: WhoisSummary.Subject, inputs: WhoisInputs) -> WhoisSummary
    /// §14.9.2 most-specific rule; nil when only markers.
    public static func summaryRecord(in records: [WhoisRecord]) -> WhoisRecord?
    /// "193.0.0.0 - 193.0.7.255" → ["193.0.0.0/21"]; minimal cover for non-aligned ranges.
    public static func cidrs(fromRange range: String) -> [String]
}
public extension ASName { static func holderName(_ holder: String) -> String }   // rule 1 only, suffix kept
```
- `RIPEstatClient.whois/abuseContacts/registeredCountry/geolocation` use the existing `fetch` (cached 5 min, 30 s timeout). `whois` for an IPv6 address does **not** retry by itself; the retry needs the `network-info` prefix and lives in the feature's plan (keeps the client a thin wrapper and the retry testable with fakes).
- `PinnedHTTP.swift` (internal): `struct PinnedHTTPGet { static func get(host:path:headers:version:timeout:) async throws -> (status: Int, body: Data) }` and `enum HTTP1Response { static func parse(_ raw: Data) throws -> (status: Int, headers: [String: String], body: Data) }` (status line, case-insensitive headers, `Content-Length`, `Transfer-Encoding: chunked`, body cap 64 KB).
- `DateParsing`: add `yyyy-MM-dd` and ISO 8601 with `Z`.
- `MockRIPEstat`: serves the new fixtures by key; `whatsMyIP(over: .v4)` → `whats-my-ip_v4.json` (193.0.6.139), `.v6` → `whats-my-ip_v6.json` (2001:67c:2e8:22::c100:696).

#### 14.15.4 SharedUI (changed `Tool.swift`, `NetworkMonitor.swift`)
```swift
public enum Tool: String, CaseIterable, Codable, Identifiable, Sendable {
    case ping, traceroute, bgp, whois                 // title "Whois", systemImage "person.text.rectangle"
}
// NetworkMonitor
public private(set) var supportsIPv4: Bool = true     // NWPath.supportsIPv4
public private(set) var supportsIPv6: Bool = true     // NWPath.supportsIPv6
public private(set) var usesVPN: Bool = false         // NWPath.usesInterfaceType(.other) while satisfied
```
`RecentTarget.lastTool` decodes the new raw value `"whois"` naturally; older builds never see it.

#### 14.15.5 WhoisFeature (new module)
Files: `WhoisModel.swift`, `WhoisSubject.swift`, `LocalVerdict.swift`, `MyIPLocator.swift`, `WhoisLoader.swift`, `WhoisFailure.swift`, `WhoisView.swift`, `WhoisPhoneLayout.swift`, `WhoisPadLayout.swift`, `MyIPCard.swift`, `DeviceAddressesCard.swift`, `WhoisSummaryCard.swift`, `WhoisRow.swift`, `WhoisActions.swift`, `LocalAddressCard.swift`, `RawRecordsView.swift`, `RawRecordCard.swift`, `IPSpeech.swift`, `WhoisExport.swift`, `WhoisPreviewData.swift`.
```swift
public enum WhoisSubject: Hashable, Sendable {
    case address(IPAddress, hostname: String?)
    case prefix(IPAddress, length: Int)
    case asn(UInt32)
    public var resource: String { get }               // "8.8.8.8", "1.1.1.0/24", "AS13335"
    public var canProbe: Bool { get }                 // Ping/Traceroute buttons
}
public struct LocalVerdict: Hashable, Sendable {
    public enum Reason: Hashable, Sendable { case address(SpecialPurposeRange), asn(ReservedASN) }
    public let input: String
    public let reason: Reason
    public let embeddedIPv4: IPAddress?               // "Look up 8.8.8.8 instead"
}
public struct WhoisResult: Hashable, Sendable {
    public let subject: WhoisSubject
    public let summary: WhoisSummary
    public let raw: WhoisResponse?
    public let retriedWith: String?                   // "2001:4860::/32" after the ARIN IPv6 retry
    public let reverseName: String?
    public let location: GeoLocation?
    public let fetchedAt: Date
}
public enum WhoisLoad: Hashable, Sendable { case loading, loaded(WhoisResult), failed(WhoisFailure) }
public struct MyIPSnapshot: Hashable, Sendable {
    public enum Slot: Hashable, Sendable {
        case checking
        case found(IPAddress, reverseName: String?)
        case unavailable(Unavailable)
        case failed(String)
    }
    public enum Unavailable: Hashable, Sendable { case noRoute, ipv6OnlyNetwork, mismatch, offline }
    public var v4: Slot
    public var v6: Slot
    public let viaVPN: Bool
    public let generation: Int
    public let fetchedAt: Date
}
actor MyIPLocator {                                   // §14.5.4
    init(api: any RIPEstatAPI, reverseName: @escaping @Sendable (IPAddress) async -> String?,
         now: @escaping @Sendable () -> Date = { Date() })
    func snapshot(generation: Int, supportsV4: Bool, supportsV6: Bool, viaVPN: Bool, force: Bool) -> AsyncStream<MyIPSnapshot>
}
struct WhoisLoader: Sendable {                        // §14.8 plans
    init(api: any RIPEstatAPI, reverseName: @escaping @Sendable (IPAddress) async -> String?, includeLocation: Bool)
    func load(_ subject: WhoisSubject) async throws -> WhoisResult      // throws WhoisFailure / CancellationError
}
@MainActor @Observable public final class WhoisModel {
    public enum Phase: Equatable {
        case myIP                                    // default; field empty or ‹ My IP tapped
        case resolving(String)
        case loading(WhoisSubject)
        case loaded(WhoisResult)
        case local(LocalVerdict)
        case failed(WhoisFailure)
    }
    public var targetText: String
    public private(set) var phase: Phase
    public private(set) var myIP: MyIPSnapshot?
    public var myFamily: IPVersion                   // selected own address; setting it loads that whois if needed
    public private(set) var myWhois: [IPVersion: WhoisLoad]
    public private(set) var localAddresses: [LocalAddress]
    public var inspectorShown: Bool                  // iPad, session only
    public init(api: any RIPEstatAPI, recents: RecentsStore, router: AppRouter, settings: SettingsStore,
                network: NetworkMonitor? = nil,
                resolve: @escaping @Sendable (String, AddressPreference) async throws -> ResolvedTarget = { try await Resolver.resolve($0, preference: $1) },
                reverseName: @escaping @Sendable (IPAddress) async -> String? = { await Resolver.reverseName(for: $0) },
                localAddresses: @escaping @Sendable () -> [LocalAddress] = { LocalInterfaces.current() },
                includeLocation: Bool = true)
    public func lookUp()                             // parses targetText (TargetParser .bgp)
    public func lookUp(_ resource: String)           // drill-down / raw link / embedded IPv4: sets targetText too
    public func cancel()
    public func showMyIP()                           // ‹ My IP: clears targetText, phase = .myIP
    public func appeared()                           // §14.5.4 triggers
    public func refreshMyIP()
    public func handle(_ request: ToolRequest)       // router: pre-fill, auto-start if requested
    public func ping()                               // router.open(.ping, …) for the current subject
    public func trace()
    public func map()
    public func stopForBackground()
    public var exportText: String { get }            // §14.12 summary or My IP text
    public var exportFullText: String { get }        // + raw records
    public enum Classified: Equatable { case subject(WhoisSubject), hostname(String), local(LocalVerdict) }
    public static func classify(_ text: String) -> Classified?   // pure, no network; nil = invalid input
}
public struct WhoisView: View { public init(model: WhoisModel) }   // AppShell wraps it in a NavigationStack, like the others
```
The view consumes router requests exactly like `BGPMapView` (`.onChange(of: router.requestTick)` → `router.takeRequest(for: .whois)` → `model.handle`).

#### 14.15.6 Cross-link changes in existing features
- **TraceFeature** (`TraceModel.swift`, `HopRow.swift`, `TraceView.swift`): `public func whoisHop(_ address: IPAddress)`, `public func whoisASN(_ asn: UInt32)`, `public func whoisTarget()`, `public var canWhoisTarget: Bool` (public target). Hop menu: "Whois this hop" after "Map in BGP" (public only); "Whois AS7922" when `hop.asn` exists. Header: icon-only button.
- **PingFeature** (`PingModel.swift`, `PingView.swift`): `public func whoisTarget()`, `canWhoisTarget`; header icon-only button.
- **BGPFeature** (`BGPMapModel.swift`, `ASDetailView.swift`, `BGPMapView.swift`): `public func whois(_ resource: String)` (→ `router.open(.whois, target:, autostart: true)`); "Whois AS3356" in AS details; "Whois 1.1.1.0/24" in the toolbar menu when a result is loaded.
- **AppShell:** `AppEnvironment.whois: WhoisModel` (live: `RIPEstatClient`, `settings`, `network`; preview: `MockRIPEstat` + fixed local addresses; screenshot mode: a fixed-answer API wrapper for `whatsMyIP(over:)`), fourth tab in `PhoneTabsView`, `case .whois` in `SplitRootView`, ⌘4 and the start/stop/copy cases in `RootView`, `environment.whois.stopForBackground()` on background, `ScreenshotMode` accepts `whois`, About text (§14.14).

#### 14.15.7 Fixtures to record (`Tests/RIPEstatTests/Fixtures/`, curl with `sourceapp=ahmadrezaei-iptools`)
`whois_8.8.8.8.json` · `whois_2001-4860-4860--8888.json` (no-match) · `whois_2001-4860--32.json` (parent chain, 12 objects) · `whois_193.0.6.139.json` · `whois_2001-67c-2e8-22--c100-696.json` · `whois_1.1.1.1.json` · `whois_1.1.1.0-24.json` · `whois_196.216.2.1.json` · `whois_200.160.2.3.json` (LACNIC empty) · `whois_91.107.240.242.json` · `whois_10.0.0.1.json` (IANA-BLK, warning) · `whois_AS13335.json` · `whois_AS3333.json` · `whois_AS22548.json` (empty) · `whois_ORG-HOA1-RIPE_error.json` (400) · `abuse-contact-finder_8.8.8.8.json` · `abuse-contact-finder_193.0.6.139.json` · `abuse-contact-finder_1.1.1.1.json` · `abuse-contact-finder_200.160.2.3_error.json` (backend error envelope) · `abuse-contact-finder_AS13335.json` · `rir-stats-country_8.8.8.8.json` · `rir-stats-country_200.160.2.3.json` · `rir-stats-country_AS13335.json` · `maxmind-geo-lite_193.0.6.139.json` (city empty) · `maxmind-geo-lite_91.107.240.242.json` (city Nuremberg) · `network-info_8.8.8.8.json` · `network-info_193.0.6.139.json` · `network-info_200.160.2.3.json` · `network-info_2001-4860-4860--8888.json` · `as-names_15169-3333-22548-24940.json` · `whats-my-ip_v4.json` · `whats-my-ip_v6.json` (hand-edited to the RIPE NCC addresses) · `http_whats-my-ip_content-length.bin`, `http_whats-my-ip_chunked.bin`, `http_429.bin`, `http_502_html.bin` (raw HTTP/1.1 responses for `HTTP1Response` tests; the 502 body is the nginx HTML page RIPEstat actually returned for `whois?resource=2606:4700:4700::1111` on 2026-11-25).

### 14.16 Work split: three parallel agents, no file overlap

**Step 0 (coordinator, before the agents start, ~20 min):** `Package.swift` (§14.15.1); compiling stubs for every public signature in §14.15 (`fatalError("TODO")` bodies, default protocol extensions, `Tool.whois` with its title and symbol, `NetworkMonitor` properties defaulting to `true`/`false`, a placeholder `WhoisView` and `WhoisModel`, and the `case .whois` branches in AppShell's switches so everything builds). Commit. After that the signatures are frozen and changes go through the coordinator. The coordinator also owns `docs/DESIGN.md`.

| Agent | Owns (exclusive) | Delivers | Tests |
|---|---|---|---|
| **D: Data** | `Sources/RIPEstat/**`, `Sources/NetCore/SpecialPurpose.swift`, `Sources/NetCore/LocalInterfaces.swift` (new files only; no edits to existing NetCore files), `Tests/RIPEstatTests/**` (+ all fixtures in §14.15.7), `Tests/NetCoreTests/SpecialPurposeTests.swift`, `Tests/NetCoreTests/LocalInterfacesTests.swift` | New client calls, `PinnedHTTPGet` + `HTTP1Response`, `whatsMyIP(over:)`, parsing, `WhoisSummarizer` (every rule in §14.9), `RIR`, `ASName.holderName`, date formats, mock + fixtures; special-purpose tables, `embeddedIPv4`, `masked(to:)`, `ReservedASN`, `LocalInterfaces` | Golden table §14.9.4 as one test per row; most-specific rule; IRR de-dup; no-match marker; IANA catch-all; range→CIDR cover (aligned, non-aligned, IPv6); HTTP parser (content-length, chunked, 429, 502 HTML, truncated); every special range boundary (first/last address in and just outside); embedded IPv4 for all three formats; ASN boundaries; interface classification table. A live test behind `IPTOOLS_NET_TESTS=1`: pinned v4 returns an IPv4 address; pinned v6 returns IPv6 or `noRoute` |
| **W: Whois UI** | `Sources/WhoisFeature/**`, `Tests/FeatureTests/Whois*.swift` (own `WhoisTestSupport.swift` with a recording fake API; not the shared `TestSupport.swift`) | All of §14.2–14.13 UI and model: both modes, iPhone and iPad layouts, inspector, raw view, local cards, actions, export, accessibility, previews for every state in §14.11 | Model tests with the fake API: request plans per subject (exact call list); ARIN IPv6 retry; partial (whois fails) vs failed (whois + BGP fail); every local verdict makes **no** API call; embedded-IPv4 offer; host-name resolution via injected resolver; recents recorded only on a successful start; My IP: both / v4-only / v6-only / mismatch / one failed / both failed / skip when `supportsIPv6 == false` / refresh on `pathGeneration` change / 30-min cache; default family IPv4; cancellation on new lookup and background; router calls for Ping/Trace/Map; export golden files (summary, full, My IP, LACNIC, operator provenance, location never exported) |
| **S: Shell, cross-links, docs** | `Sources/SharedUI/**`, `Sources/AppShell/**`, `Sources/TraceFeature/**`, `Sources/PingFeature/**`, `Sources/BGPFeature/{BGPMapModel,ASDetailView,BGPMapView}.swift`, `Tests/FeatureTests/{Ping,Trace,Shell,SharedUI,BGPMapModel}Tests.swift`, `Tests/FeatureTests/TestSupport.swift`, `PRIVACY.md`, `README.md` | `Tool.whois`, `NetworkMonitor.supportsIPv4/6/usesVPN`, AppEnvironment wiring (live, preview, screenshot fixed IP), tab, split view, sidebar, ⌘4 + start/stop/copy, background stop, ScreenshotMode `whois`, About text; all cross-links in §14.2.2 and §14.15.6; PRIVACY/README text from §14.14 | Router receives `.whois` with the right target for: hop, hop ASN, ping header, trace header, AS details, BGP toolbar; hop menu hides Whois for private hops; ⌘4 selects Whois; recents with `lastTool == .whois` reopen Whois; screenshot mode never calls the real `whatsMyIP` |

Merge order: **D → W → S** (W's previews and tests want D's fixtures; S's wiring replaces the placeholder with W's real view). Any order compiles thanks to Step 0.

**Phase 2 (one agent, devices):** dual-stack Wi-Fi; IPv4-only Wi-Fi; IPv6-only NAT64 (macOS Internet Sharing → "Create NAT64 Network", and a real carrier with 464XLAT if available); cellular with CGNAT (the CGNAT hint); VPN on/off; iCloud Private Relay on; offline; network change while the tab is visible; VoiceOver and AX5 pass; iPad landscape inspector; App Store screenshots in screenshot mode (fixed IP). Verify the `LocalInterfaces` BSD names on iPhone and iPad.

### 14.17 Testing notes
- The summarizer is pure and fixture-driven: it carries most of the correctness. Every row of §14.9.3 has at least one fixture-backed assertion.
- The pinned-family transport is split into a tiny `NWConnection` shell (live test only) and a pure HTTP parser (unit tests), so CI needs no network.
- Feature tests never touch the network: the fake API records calls, so "no request for private input" is asserted directly.
- Snapshot/preview coverage: every state row in §14.11 has a `#Preview`.

### 14.18 Open questions and risks

**Decisions for the owner (recommended pick first):**
- **D1. Placement:** a fourth tab named **Whois** (`person.text.rectangle`) whose default content is My IP. *Alternatives:* a tab named "My IP"; inside BGP Map. *Why:* one obvious home for both requests, consistent tool naming, keeps the search keyword visible.
- **D2. Data source:** **RIPEstat only** (no RDAP) for v1.2. *Alternative:* RDAP via rdap.org + RIR servers, or RDAP as an opt-in later. *Why:* the privacy promise stays "only RIPEstat"; gaps (LACNIC, RIPE org names, ARIN IPv6) have fallbacks.
- **D3. Both families, IPv4 selected by default:** check IPv4 and IPv6 separately with pinned-family connections and show whois for **IPv4** first when both exist. *Alternative:* one URLSession call (one family only), or IPv6 first. *Why:* phones are often dual-stack and the owner asked for "my IP"; IPv4 is what people quote.
- **D4. Approximate location row:** **include**, labelled "approx.", MaxMind GeoLite2 via RIPEstat, on screen only, not exported. *Alternative:* omit location entirely. *Why:* it's the most common thing a "my IP" user looks for, and it stays within RIPEstat.
- **D5. Accepted input:** IP, prefix, ASN **and host name** (resolved on device, with a "not domain whois" line). *Alternative:* IP only. *Why:* the same parser as BGP Map; users paste host names anyway.
- **D6. Auto-load My IP** when the Whois tab opens and when the network changes while it's visible. *Alternative:* a "Show my IP" button. *Why:* the user opened the tab to see it; RIPEstat already sees the address on every request.
- **D7. "This device" card** (local addresses + NAT/CGNAT hint, never sent). *Alternative:* omit. *Why:* it explains why the public IP differs from the Wi-Fi address, cheaply and offline.
- **D8. Store text:** keep the name; subtitle **`Whois, BGP Map & ASN Lookup`**; keywords as in §14.14. *Alternative:* subtitle `My IP, Whois & BGP Map`. *Why:* "whois lookup" and "asn lookup" both match; "my ip" comes from keywords.
- **D9. Screenshot:** add a My IP & Whois screenshot at **position 2** on all three device sizes. *Alternative:* position 5. *Why:* whois is the highest-volume term in the set.
- **D10. Cross-link entry points:** hop menu (Whois this hop / Whois ASn), Ping and Traceroute header icon buttons, BGP AS details and toolbar menu. *Alternative:* hop menu only. *Why:* every place an address or AS appears should reach its owner in one tap.

**Risks:**
- **RW1: RIPEstat whois gaps** (LACNIC empty, RIPE-style org names missing, ARIN bare IPv6 failing). *Mitigation:* specified fallbacks with visible provenance; RDAP opt-in as a v1.3 option.
- **RW2: Helper endpoints are flaky** (`abuse-contact-finder` returned a backend error for a LACNIC address; `rir` and `whois` each returned a 502 HTML page once during the 2026-11-25 checks). *Mitigation:* every helper is optional; only whois + BGP both failing is fatal; 5xx HTML maps to "busy".
- **RW3: Pinned-family `NWConnection` behaviour** on NAT64/CLAT, with VPNs and with proxies. *Mitigation:* `NWPath.supportsIPv4/6` pre-check, family-mismatch rule, URLSession fallback, Phase 2 device matrix.
- **RW4: Request budget.** Opening the tab costs 7–8 RIPEstat calls. *Mitigation:* 30-min per-network cache for My IP, 5-min URL cache for lookups, the other family loaded on demand, 4-request cap, `sourceapp` so RIPE can contact the project.
- **RW5: Users expecting domain whois.** *Mitigation:* the context line under host-name lookups and a README FAQ entry.
- **RW6: Personal data in raw records** (ARIN POC names/phones). *Mitigation:* displayed as published, never stored, only exported in *Full Record* on explicit share.
- **RW7: Screenshots or screen recordings revealing the owner's IP.** *Mitigation:* fixed answers in screenshot mode.
- **RW8: Schema drift** (keys vary by RIR and over time). *Mitigation:* the summary is best-effort and tolerant; the raw view always shows everything RIPEstat returns.
- **RW9: Hand-written HTTP/1.1 reader.** *Mitigation:* small surface (one GET, `Connection: close`), fixture tests for both framing modes, URLSession fallback.
