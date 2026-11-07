Captured from https://stat.ripe.net/data/ on 2026-11-07 with `sourceapp=ip-tools-ios`.

Two files are SYNTHETIC because RIPEstat's RIS-backed calls returned empty data at capture time
(`looking-glass` gave `rrcs: []`, `routing-status` gave `data: {}`): 
`looking-glass_1.1.1.0-24.json` and `routing-status_1.1.1.0-24.json`. They follow the verified schema
(DESIGN section 11) and the verified shape of the live response (23 collectors, 360 peers, path lengths 1-4,
layer sizes 1/240/48/7, origin AS13335). Re-capture them when the API recovers. Both carry a message saying so.

`looking-glass_10.0.0.0-8.json` (empty `rrcs`) is a genuine response for a private prefix.
`*_AS13335_error.json` are genuine 400-style error envelopes for an ASN passed to an IP/prefix call.
`announced-prefixes_AS13335.json` is the full live response (5,748 prefixes).
