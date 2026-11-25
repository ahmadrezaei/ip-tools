Captured from https://stat.ripe.net/data/ on 2026-11-07 with `sourceapp=ahmadrezaei-iptools`.

Real `bgp-state` captures (the endpoint the client falls back to when `looking-glass` is empty):
`bgp-state_1.1.1.0-24.json` (365 routes, 23 collectors, origin AS13335), `bgp-state_80.249.208.0-21.json` (2 routes),
`bgp-state_2606-4700-4700---48.json` (IPv6), `bgp-state_10.0.0.0-8.json` (genuine empty answer for a private prefix).
`as-names_bgp-state_1.1.1.0-24.json` names every ASN seen in the 1.1.1.0/24 capture (297 ASNs, one call).
`MockRIPEstat` file naming: `/` and `:` in a resource become `-`.

Two files are SYNTHETIC because RIPEstat's RIS-backed calls returned empty data at capture time
(`looking-glass` gave `rrcs: []`, `routing-status` gave HTTP 500): 
`looking-glass_1.1.1.0-24.json` and `routing-status_1.1.1.0-24.json`. They follow the verified schema
(DESIGN section 11) and the verified shape of the live response (23 collectors, 360 peers, path lengths 1-4,
layer sizes 1/240/48/7, origin AS13335). Re-capture them when the API recovers (the routing-status one was also edited to status ok/200). Both carry a message saying so.

`looking-glass_10.0.0.0-8.json` (empty `rrcs`) is a genuine response for a private prefix.
`*_AS13335_error.json` are genuine 400-style error envelopes for an ASN passed to an IP/prefix call.

## My IP & Whois fixtures (captured 2026-11-25, `sourceapp=ahmadrezaei-iptools`)

Real responses of `whois`, `abuse-contact-finder`, `rir-stats-country`, `maxmind-geo-lite`, `network-info`,
`as-overview` and `as-names` (`as-names_15169-3333-22548-24940.json`). File names follow the `MockRIPEstat` rule
(`/` and `:` in a resource become `-`), so the prefix `2001:4860::/32` is `whois_2001-4860---32.json`.
`whois_2001-4860-4860--8888.json` is ARIN's "No match found" answer for a bare IPv6 address (the retry uses the prefix).
`whois_200.160.2.3.json` and `whois_AS22548.json` have empty `records` (LACNIC). `whois_10.0.0.1.json` is the IANA
catch-all with the low-confidence warning. `*_error.json` are genuine error envelopes (HTTP 400 / backend error 500).
The Hetzner examples use 116.203.0.1 (no `descr`, operator comes from the AS) and 88.198.0.1 (`descr` holder).

`whats-my-ip_v4.json` / `whats-my-ip_v6.json` are hand-written in the live shape and carry the RIPE NCC addresses
(193.0.6.139 and 2001:67c:2e8:22::c100:696), never a real client address.
`http_*.bin` are hand-built HTTP/1.1 responses for the `HTTP1Response` tests (content-length, chunked with an
extension, 429 JSON, and an nginx 502 HTML page like the one RIPEstat returned on 2026-11-25).
`announced-prefixes_AS13335.json` is the full live response (5,748 prefixes).
