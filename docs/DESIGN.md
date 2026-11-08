# IP Tools: Ping & Traceroute — Design Spec (v1)

Status: **draft for approval**, no code written yet.
Companion files: [`mockup.html`](mockup.html) (visual mockups, open in a browser), [`mockup-your-route.html`](mockup-your-route.html) (v1.1 mockups: BGP "Your route", clearer "All routes", Ping count control) and [`icon.svg`](icon.svg) (app icon).

**v1.1 addendum (draft for approval, 2026-11-08):** BGP Map gets a new default view, **Your route** (§6.11), the existing graph becomes **All routes (worldwide)** with a plain-English summary and legend (§6.12), and Ping gets a visible count control (§4.3). Privacy wording changes are in §9; types, signatures and the parallel work split are in §12.7.

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
6. Toolbar menu (`ellipsis.circle` on iPhone; "Top 6 ▾" on iPad): **Show per column:** Top 6 (default) · Top 12 · Top 30. **Share as text / Share as image**.

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
- **Orientation and opening view:** vertical (§6.4). The opening view fits the graph if the scale is at least 0.7; otherwise it scales to the view width (0.7–1.0×), centres horizontally on the origin node and anchors the origin row at the bottom, and the rest is reached by panning. The Fit button lives in the header row, not over the canvas, so it never covers a node.
- **Header:** collapsed by default to one compact line (prefix, origin, your-path status, Graph/List, Fit, an info button). The info button or the line expands the full card (prefix, origin, chips, your-path chip). The state is kept for the session only.
- **Edges:** one SwiftUI `Canvas`, drawing the paths from `EdgeGeometry`. **Nodes:** real SwiftUI `Button`s positioned with `.position()` in a `ZStack` of the canvas size, so hit testing and VoiceOver come for free. The whole stack gets one `.scaleEffect(scale, anchor: .topLeading)` + `.offset(pan)`.
- **Gestures:** `MagnifyGesture` (scale 0.3…3.0, anchored at the pinch location) running simultaneously with `DragGesture` (pan, clamped so at least 80 pt of graph stays visible). Double-tap on empty space toggles between "fit" and 1.0× at that point. The Fit button animates to fit.
- **Initial view:** `fitScale = min(viewW/canvasW, viewH/canvasH)`. If `fitScale ≥ 0.7`, the graph is centred at that scale (the iPad usually fits). Otherwise the graph opens at **0.7×**, vertically centred, with the **origin column anchored to the right edge**. The user pans left toward the peers. The mockup shows this.
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
The canvas is `.accessibilityElement(children: .contain)` with the label "AS path graph, 22 networks, 4 columns". Nodes are ordered column by column from the origin outward (`.accessibilitySortPriority`). Each node is a button with the same label as its List row, plus the hint "Double-tap to highlight its paths". A rotor action switches to List.

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
