# IP Tools: Ping & Traceroute — Design Spec (v1)

Status: **draft for approval**, no code written yet.
Companion files: [`mockup.html`](mockup.html) (visual mockups, open in a browser) and [`icon.svg`](icon.svg) (app icon).

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
2. Run header.
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
| Count | 5, 10, 20, 50, 100, Until stopped | **10** |
| Interval | 0.2, 0.5, 1, 2 s | **1 s** |
| Timeout | 1, 2, 5 s | **2 s** |
| Packet size (payload bytes) | 16, 56, 120, 512, 1024, 1472 (v4) / 1452 (v6) | **56** |
| IP version (shared with Traceroute) | Automatic, IPv4, IPv6 | **Automatic** |

Nothing else (no TTL, no DF bit, no QoS). "Automatic" uses the first address `getaddrinfo` returns with `AI_ADDRCONFIG`. That follows the system's RFC 6724 ordering, so it prefers IPv6 on IPv6-capable networks, just as Safari would.

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
Coordinates are in points, before zoom.
- Metrics: node 112 × 44, column gap 56, row gap 12, padding 24, header row 18.
- **Columns:** `x(layer) = padding + (maxLayer − layer) × (112 + 56)`. Layer 0 (origin) is the rightmost column. Above each column is a caption: "ORIGIN", "1 HOP", "2 HOPS"…
- **Order within a column (barycentre, deterministic):**
  1. Layer 0: origins sorted by `pathCount` descending.
  2. For layer `k = 1…max`: sort the nodes by the weighted mean index of their forward-edge targets in layer `k−1` (weights = edge `pathCount`). Ties go to higher score, then lower ASN.
  3. One refinement pass from `k = max−1` down to 1, using the mean index of incoming forward sources in layer `k+1`. Accept the new order only if the count of crossing forward edges does not increase.
  4. The `.more` bucket is always last (at the bottom) of its column.
- **Vertical:** each column is centred against the tallest column. `y = padding + header + (H − columnHeight)/2 + i × (44 + 12)`.
- **Edges:** forward edges are cubic Béziers from the source's right-mid to the target's left-mid, with control points at the horizontal midpoint (`c1 = (mx, y1)`, `c2 = (mx, y2)`). Lateral and backward edges loop out to the *left* of the source column: from the source's left-mid to the target's left-mid, with control points pulled left by `min(45, 20 + |Δy|·0.25)`. They are drawn **dashed**.
- **Stroke width** = `1.5 + 6 × √(edge.pathCount / totalPaths)`, so roughly 1.5–7.5 pt. Colour is `secondaryLabel` at 0.35 opacity. Edges are drawn in ascending count, so thick edges sit on top. Highlighted edges are drawn last.
- **Canvas size** = `(padding·2 + (L+1)·112 + L·56) × (padding·2 + header + H)`.

### 6.5 Rendering & interaction (`GraphCanvasView`)
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

---

## 13. Open questions & risks

**Decisions for you (the owner):**
1. **Hop ASN lookups default ON.** This sends public hop IPs to RIPEstat. It is privacy-friendly (no identifiers) but is network traffic you might prefer to be opt-in. *Recommendation: ON, with the clear footnote.*
2. **ASN input → prefix picker** (vs. an aggregated "upstreams of this AS" graph built from `asn-neighbours`). *Recommendation: picker for v1; it's simpler and exact.*
3. **Default column size K = 6** on both iPhone and iPad. iPad could default to 12. *Recommendation: 6 everywhere for a consistent first look; the menu is one tap away.*
4. **Ping default count: 10** — DECIDED by owner (stop after 10; "Until stopped" stays available in settings).
5. **Minimum iOS 17.** That gives `@Observable`, `ContentUnavailableView`, `.inspector` and `MagnifyGesture`. iOS 18's `.sidebarAdaptable` TabView would simplify navigation but would drop iOS 17 users. *Recommendation: keep 17 and the size-class switch.*
6. **Category:** Utilities vs Developer Tools as the primary. *Recommendation: Utilities, which has broader search traffic.*

**Risks:**
- **R1 (medium impact, low probability):** ICMP Time Exceeded may not reach DGRAM sockets on some iOS release, which would break traceroute. *Mitigation:* the day-1 device spike, before any UI work depends on it.
- **R2: RIPEstat availability, rate limits or schema drift.** *Mitigation:* tolerant decoding (unknown fields ignored, all optional except the core ones), clear error state, fixtures in tests, and `sourceapp` set so RIPE can contact the project.
- **R3: Graph readability for heavily peered origins** (Cloudflare has 240 neighbours). *Mitigation:* top-K collapsing with a "+N more" bucket, transit-weighted ranking, List mode. Verified on real data.
- **R4: Local Network prompt confusion.** *Mitigation:* the prompt appears only when the user targets a LAN address, and the denied state explains how to fix it.
- **R5: App Review.** Network utilities with ICMP are common and allowed. Make sure the description does not over-claim (no "speed test").
- **R6: Reverse DNS latency** slowing the traceroute UI. *Mitigation:* async enrichment that never blocks the probe loop.

**Out of scope for v1 (deliberately):** mtr-style continuous traceroute, TCP/UDP ping, whois, DNS lookup tool, history of past results, iCloud sync, widgets/Live Activities, Mac Catalyst, localisation beyond English.
