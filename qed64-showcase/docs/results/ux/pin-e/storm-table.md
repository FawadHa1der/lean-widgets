| arm | runs | V2 | rate (Wilson 95 %) | other crashes | not ready after storm | V2 runs | quiet at launch | document as intended | first ready (median s) | ready again (median s) |
|---|---|---|---|---|---|---|---|---|---|---|
| E 33b0967, headed | 20 | **0/20** | 0 % (0–16 %) | - | 0 | - | 19/20 | 20/20 | 14.64 | 7.40 |
| C 5ac5d00, headed | 20 | **0/20** | 0 % (0–16 %) | - | 0 | - | 18/20 | 20/20 | 14.57 | 7.24 |
| E 33b0967, headless-shell | 8 | **0/8** | 0 % (0–32 %) | - | 0 | - | 8/8 | 8/8 | 14.29 | 7.25 |
| C 5ac5d00, headless-shell | 8 | **1/8** | 12 % (2–47 %) | - | 0 | e08-C-hs | 8/8 | 8/8 | 14.15 | 7.17 |

Fisher exact, E vs C (one-sided direction: C > E):
* hd V2: E 0/20 vs C 0/20; two-sided p = 1.0000, one-sided (C > E) p = 1.0000
* hd any crash: E 0/20 vs C 0/20; two-sided p = 1.0000, one-sided (C > E) p = 1.0000
* hs V2: E 0/8 vs C 1/8; two-sided p = 1.0000, one-sided (C > E) p = 0.5000
* hs any crash: E 0/8 vs C 1/8; two-sided p = 1.0000, one-sided (C > E) p = 0.5000
* pooled any crash: E 0/28 vs C 1/28; two-sided p = 1.0000
* headed reps 1-10: E 0/10, C 0/10 (V2)
* headed reps 11-20: E 0/10, C 0/10 (V2)
Crashes by position in the rep: hd C first: 0/10, hd C second: 0/10, hd E first: 0/10, hd E second: 0/10, hs C first: 1/4, hs C second: 0/4, hs E first: 0/4, hs E second: 0/4

| tag | utc | arm | recl | swap | swapDelta | foreign | quiet | waited | result | variant | crashAt | oomLines | firstReadyMs | readyAfterMs | rssPeak | workers | doc | docOk | dsf1 | chromeForTesting | headlessShell | version |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| e01-E-hd | 02:52:42 | E-hd | 14.8 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 15092 | 7567 | 9759 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e01-C-hd | 02:53:27 | C-hd | 16.3 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14862 | 7192 | 9707 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e02-C-hd | 02:54:10 | C-hd | 16.0 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14470 | 7263 | 9827 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e02-E-hd | 02:54:53 | E-hd | 16.0 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14708 | 7329 | 10006 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e03-E-hd | 02:55:37 | E-hd | 16.2 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14696 | 7632 | 9690 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e03-C-hd | 02:56:21 | C-hd | 16.3 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14401 | 7264 | 9780 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e04-C-hd | 02:57:04 | C-hd | 16.0 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14538 | 7289 | 9758 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e04-E-hd | 02:57:47 | E-hd | 16.0 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 15306 | 7830 | 9504 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e05-E-hd | 03:03:32 | E-hd | 15.8 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14299 | 7605 | 9434 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e05-C-hd | 03:04:16 | C-hd | 16.1 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14623 | 7368 | 9504 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e06-C-hd | 03:04:59 | C-hd | 16.0 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14489 | 7207 | 9734 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e06-E-hd | 03:05:42 | E-hd | 16.2 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14720 | 7578 | 9836 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e07-E-hd | 03:06:26 | E-hd | 16.2 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14622 | 7593 | 9823 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e07-C-hd | 03:07:10 | C-hd | 16.1 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14626 | 7118 | 9808 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e08-C-hd | 03:07:53 | C-hd | 16.3 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14650 | 7526 | 9509 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e08-E-hd | 03:08:36 | E-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14743 | 7434 | 9773 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e09-E-hd | 03:14:21 | E-hd | 16.3 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14342 | 7359 | 9720 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e09-C-hd | 03:15:04 | C-hd | 14.8 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 15492 | 7324 | 11118 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e10-C-hd | 03:15:48 | C-hd | 16.3 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14592 | 7275 | 10781 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e10-E-hd | 03:16:32 | E-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14505 | 7478 | 10067 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e11-E-hd | 03:17:15 | E-hd | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14466 | 7410 | 10012 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e11-C-hd | 03:17:58 | C-hd | 16.4 | 509.75 | 0.0 | lv-live4r2-boot-D4.mjs(23593) lv-live4r2-offline(23971) | False | waited=0s | no crash | - | - | 0 | 14626 | 7169 | 10043 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e12-C-hd | 03:18:41 | C-hd | 16.4 | 509.75 | 0.0 | lv-live4r2-boot-D4.mjs(23593) lv-live4r2-slow.mjs(25269) | False | waited=0s | no crash | - | - | 0 | 14541 | 7178 | 9997 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e12-E-hd | 03:19:24 | E-hd | 16.3 | 509.75 | 0.0 | lv-live4r2-boot-D4.mjs(23593) lv-live4r2-slow.mjs(25269) lv-live4r2b-offline.mjs(26103) | False | waited=1s | no crash | - | - | 0 | 14753 | 7323 | 10100 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e13-E-hd | 04:39:24 | E-hd | 15.9 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14405 | 7272 | 9696 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e13-C-hd | 04:40:07 | C-hd | 16.7 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14355 | 7103 | 9829 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e14-C-hd | 04:40:50 | C-hd | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14638 | 7449 | 10540 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e14-E-hd | 04:41:34 | E-hd | 16.4 | 509.75 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 14648 | 7373 | 9971 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e15-E-hd | 04:42:17 | E-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14674 | 7205 | 10217 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e15-C-hd | 04:43:00 | C-hd | 16.2 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14728 | 7156 | 10482 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e16-C-hd | 04:43:44 | C-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14922 | 7266 | 10256 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e16-E-hd | 04:44:27 | E-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14426 | 7538 | 10093 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e17-E-hd | 04:50:12 | E-hd | 16.6 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14107 | 7346 | 9889 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e17-C-hd | 04:50:55 | C-hd | 16.7 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14498 | 7215 | 9977 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e18-C-hd | 04:51:38 | C-hd | 16.6 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14440 | 6995 | 9973 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e18-E-hd | 04:52:21 | E-hd | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14582 | 7341 | 10048 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e19-E-hd | 04:53:04 | E-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14679 | 7280 | 10010 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e19-C-hd | 04:53:48 | C-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14437 | 7219 | 10312 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e20-C-hd | 04:54:31 | C-hd | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14544 | 7426 | 10439 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e20-E-hd | 04:55:14 | E-hd | 16.4 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14637 | 7396 | 10063 | 158/132 | b474a9cc8345 | True | True | True | False | 151.0.7922.34 |
| e01-E-hs | 05:00:59 | E-hs | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13955 | 7037 | 9729 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e01-C-hs | 05:01:41 | C-hs | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14145 | 7093 | 10413 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e02-C-hs | 05:02:23 | C-hs | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14176 | 7169 | 11129 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e02-E-hs | 05:03:06 | E-hs | 17.1 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14181 | 7302 | 10893 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e03-E-hs | 05:03:48 | E-hs | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14452 | 7096 | 10699 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e03-C-hs | 05:04:31 | C-hs | 16.6 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14234 | 7213 | 11422 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e04-C-hs | 05:05:13 | C-hs | 17.1 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14264 | 7147 | 10622 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e04-E-hs | 05:05:56 | E-hs | 16.9 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14369 | 7337 | 10097 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e05-E-hs | 05:11:40 | E-hs | 16.6 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13701 | 7046 | 9818 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e05-C-hs | 05:12:22 | C-hs | 16.6 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14035 | 7287 | 10811 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e06-C-hs | 05:13:04 | C-hs | 17.0 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14120 | 7151 | 11104 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e06-E-hs | 05:13:46 | E-hs | 16.6 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14295 | 7193 | 9897 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e07-E-hs | 05:14:29 | E-hs | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14408 | 7352 | 10918 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e07-C-hs | 05:15:12 | C-hs | 16.6 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14159 | 7259 | 11300 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e08-C-hs | 05:15:54 | C-hs | 17.1 | 509.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +1885 ms | 1 | 14119 | None | 11550 | 132/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
| e08-E-hs | 05:16:29 | E-hs | 16.5 | 509.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14279 | 7332 | 11056 | 158/132 | b474a9cc8345 | True | False | False | True | 151.0.7922.34 |
