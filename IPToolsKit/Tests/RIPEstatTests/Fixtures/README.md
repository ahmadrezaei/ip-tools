Captured from https://stat.ripe.net/data/ on 2026-11-07 with `sourceapp=ip-tools-ios`.

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
`announced-prefixes_AS13335.json` is the full live response (5,748 prefixes).
