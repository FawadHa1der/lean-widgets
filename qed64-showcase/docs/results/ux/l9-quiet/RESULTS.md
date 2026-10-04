# L9 quiet-host slot (2026-10-02, 11:03–11:21 UTC)

The QED64 owner's session opened a quiet window (nothing of theirs running from 11:02 UTC). Both sequences ran inside ONE
browser-lock hold each (so our own pin-D bake could not start), headed Chrome for Testing (Playwright `launch`, headed),
`DEBUG=pw:browser` for the V8 OOM line, renderer RSS sampled by a separate process. Host state per run is in
`explore/host-state.tsv` (reclaimable 20.1–26.1 GB, swap flat or falling, no foreign heavy process in any run).
Tools: `$W/l9-desktop/quiet-seq.sh` (widgets8 overlay, storm-desktop2.mjs) and `quiet-seq-stock.sh`
(QED64's stock page `/`, storm-desktop3.mjs = storm-desktop2 with `--path`). Servers: serve.mjs with SHOWCASE_PIN on
:5201 (A 1859b83), :5202 (C 5ac5d00), :5203 (B 9fdf9b8), :5204 (D 3b42714).

| set | pin | runs | crashed | variant | where |
|---|---|---|---|---|---|
| widgets8 overlay | A 1859b83 (4b025db7, old worker) | 5 | 1 (qA2) | V2 `MarkCompactCollector: young object promotion failed` | 2026 ms after reload 4 |
| widgets8 overlay | C 5ac5d00 (4b025db7, new worker) | 5 | 0 | – | – |
| widgets8 overlay | B 9fdf9b8 (2c18773e, parked threads) | 2 | 1 (qB1) | V1 `Scavenger: semi-space copy` | 2127 ms after reload 0 |
| stock page `/` | C 5ac5d00 | 5 | 2 (sC4, sC5) | V2 | 2171 ms after reload 2; 2052 ms after reload 3 |
| stock page `/` | D 3b42714 (3ab1c6a9, 0035b, parking off) | 5 | 0 | – | – |
| stock page `/` | A 1859b83 | 3 | 0 | – | – |

**Reading.** V2 happens on a quiet host too, on runtime 4b025db7 with either worker (A 1/8, C 2/10 across both sets),
so host pressure is not required for it; it is a background rate of headed Chrome 151 on these pins (~10–20 % per
5-reload storm). D showed 0/5 (not yet significant against C's 2/10). V1 reproduces on B as the positive control.
