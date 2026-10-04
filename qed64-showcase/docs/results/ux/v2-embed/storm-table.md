| arm | runs | V2 | rate (Wilson 95 %) | other crashes | V2 runs | quiet at launch | document as intended |
|---|---|---|---|---|---|---|---|
| S: gallery /showcase/#hasse-view | 24 | **15/24** | 62 % (43–79 %) | other: CALL_AND_RETRY_LAST 1 | e02-S, e04-S, e05-S, e06-S, e07-S, e08-S, e09-S, e10-S, e12-S, e14-S, e16-S, e19-S, e20-S, e21-S, e24-S | 24/24 | 24/24 |
| P: stock page, default document | 24 | **2/24** | 8 % (2–26 %) | - | e19-P, e23-P | 24/24 | 24/24 |
| I: test page iframing the stock page, default document | 24 | **6/24** | 25 % (12–45 %) | - | e01-I, e05-I, e06-I, e09-I, e14-I, e17-I | 24/24 | 24/24 |
| Is: I with the hasse-view document seeded | 24 | **10/24** | 42 % (24–61 %) | - | e05-Is, e06-Is, e11-Is, e12-Is, e14-Is, e15-Is, e16-Is, e17-Is, e20-Is, e22-Is | 24/24 | 24/24 |
| Ps: P with the hasse-view document seeded | 24 | **2/24** | 8 % (2–26 %) | - | e10-Ps, e22-Ps | 24/24 | 24/24 |

Pairwise V2 (Fisher exact):
* S vs P: 15/24 vs 2/24; Fisher two-sided p = 0.000, one-sided (S > P) p = 0.000
* I vs P: 6/24 vs 2/24; Fisher two-sided p = 0.245, one-sided (I > P) p = 0.122
* S vs I: 15/24 vs 6/24; Fisher two-sided p = 0.019, one-sided (S > I) p = 0.009
* Is vs Ps: 10/24 vs 2/24; Fisher two-sided p = 0.017, one-sided (Is > Ps) p = 0.009
* S vs Is: 15/24 vs 10/24; Fisher two-sided p = 0.248, one-sided (S > Is) p = 0.124
* Ps vs P: 2/24 vs 2/24; Fisher two-sided p = 1.000, one-sided (Ps > P) p = 0.696
* Is vs I: 10/24 vs 6/24; Fisher two-sided p = 0.359, one-sided (Is > I) p = 0.179
* S vs Ps: 15/24 vs 2/24; Fisher two-sided p = 0.000, one-sided (S > Ps) p = 0.000
* embedded (I+Is) vs top-level (P+Ps): 16/48 vs 4/48; Fisher two-sided p = 0.005, one-sided (embedded (I+Is) > top-level (P+Ps)) p = 0.002
* hasse document (Is+Ps) vs default document (I+P): 12/48 vs 8/48; Fisher two-sided p = 0.452, one-sided (hasse document (Is+Ps) > default document (I+P)) p = 0.226

Any renderer crash (V2 plus any other OOM variant), Fisher exact:
* S vs P: 16/24 vs 2/24; two-sided p = 0.000, one-sided p = 0.000
* I vs P: 6/24 vs 2/24; two-sided p = 0.245, one-sided p = 0.122
* S vs I: 16/24 vs 6/24; two-sided p = 0.008, one-sided p = 0.004
* S vs Is: 16/24 vs 10/24; two-sided p = 0.147, one-sided p = 0.073
* Is vs Ps: 10/24 vs 2/24; two-sided p = 0.017, one-sided p = 0.009
* V2, S vs embedded test page (I+Is): 15/24 vs 16/48; two-sided p = 0.024, one-sided p = 0.018
* any crash, S vs embedded test page (I+Is): 16/24 vs 16/48; two-sided p = 0.011, one-sided p = 0.007
* reps 1-12: S 9/12, P 0/12, I 4/12, Is 4/12, Ps 1/12 (V2)
* reps 13-24: S 6/12, P 2/12, I 2/12, Is 6/12, Ps 1/12 (V2)

V2 by position of the run within its rep (0 = first of the 5 arms): 0: 5/24, 1: 6/24, 2: 6/24, 3: 9/24, 4: 9/24

| tag | utc | arm | recl | swap | swapDelta | foreign | quiet | waited | result | variant | crashAt | oomLines | firstReadyMs | readyAfterMs | rssPeak | workers | doc | docOk | dsf1 | chromeForTesting |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| e01-S | 06:55:48 | S | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14044 | 6796 | 12063 | 158/132 | b474a9cc8345 | True | True | True |
| e01-P | 06:56:30 | P | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13629 | 6438 | 11579 | 158/132 | 9f943fb19cbe | True | True | True |
| e01-I | 06:57:12 | I | 22.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +1998 ms | 4 | 13714 | None | 12167 | 158/158 | 9f943fb19cbe | True | True | True |
| e01-Is | 06:57:49 | Is | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14190 | 6746 | 11965 | 158/132 | b474a9cc8345 | True | True | True |
| e01-Ps | 06:58:31 | Ps | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13811 | 6775 | 11981 | 158/132 | b474a9cc8345 | True | True | True |
| e02-S | 06:59:13 | S | 22.9 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2152 ms | 1 | 14536 | None | 12215 | 132/132 | b474a9cc8345 | True | True | True |
| e02-P | 06:59:49 | P | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13647 | 6175 | 11812 | 158/132 | 9f943fb19cbe | True | True | True |
| e02-I | 07:00:30 | I | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13877 | 6449 | 11832 | 158/132 | 9f943fb19cbe | True | True | True |
| e02-Is | 07:01:12 | Is | 22.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14190 | 6765 | 12063 | 158/132 | b474a9cc8345 | True | True | True |
| e02-Ps | 07:01:54 | Ps | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14108 | 6682 | 11696 | 158/132 | b474a9cc8345 | True | True | True |
| e03-I | 07:07:37 | I | 22.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13126 | 6410 | 12169 | 158/132 | 9f943fb19cbe | True | True | True |
| e03-Is | 07:08:18 | Is | 22.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14073 | 6753 | 12067 | 158/132 | b474a9cc8345 | True | True | True |
| e03-Ps | 07:09:00 | Ps | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13837 | 6652 | 11987 | 158/132 | b474a9cc8345 | True | True | True |
| e03-S | 07:09:42 | S | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14475 | 7146 | 11863 | 158/132 | b474a9cc8345 | True | True | True |
| e03-P | 07:10:25 | P | 22.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13630 | 6223 | 11793 | 158/132 | 9f943fb19cbe | True | True | True |
| e04-I | 07:11:06 | I | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13814 | 6651 | 12335 | 158/132 | 9f943fb19cbe | True | True | True |
| e04-Is | 07:11:48 | Is | 22.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14233 | 6907 | 12019 | 158/132 | b474a9cc8345 | True | True | True |
| e04-Ps | 07:12:30 | Ps | 22.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13971 | 6696 | 11881 | 158/132 | b474a9cc8345 | True | True | True |
| e04-S | 07:13:12 | S | 22.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2056 ms | 1 | 14386 | None | 12054 | 158/158 | b474a9cc8345 | True | True | True |
| e04-P | 07:13:50 | P | 22.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13641 | 6298 | 11760 | 158/132 | 9f943fb19cbe | True | True | True |
| e05-Ps | 07:19:32 | Ps | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13587 | 6646 | 12033 | 158/132 | b474a9cc8345 | True | True | True |
| e05-S | 07:20:14 | S | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 2 +2050 ms | 1 | 14129 | None | 11748 | 106/106 | b474a9cc8345 | True | True | True |
| e05-P | 07:20:46 | P | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13422 | 6435 | 11765 | 158/132 | 9f943fb19cbe | True | True | True |
| e05-I | 07:21:28 | I | 22.7 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2023 ms | 2 | 13846 | None | 12017 | 132/132 | 9f943fb19cbe | True | True | True |
| e05-Is | 07:22:03 | Is | 22.4 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2055 ms | 1 | 14167 | None | 12203 | 158/158 | b474a9cc8345 | True | True | True |
| e06-Ps | 07:22:40 | Ps | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14122 | 6739 | 11792 | 158/132 | b474a9cc8345 | True | True | True |
| e06-S | 07:23:23 | S | 22.7 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2063 ms | 1 | 14360 | None | 11901 | 132/132 | b474a9cc8345 | True | True | True |
| e06-P | 07:23:58 | P | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13680 | 6411 | 11853 | 158/132 | 9f943fb19cbe | True | True | True |
| e06-I | 07:24:40 | I | 22.7 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2054 ms | 2 | 13640 | None | 11844 | 132/132 | 9f943fb19cbe | True | True | True |
| e06-Is | 07:25:15 | Is | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 2 +2069 ms | 1 | 14171 | None | 12081 | 106/106 | b474a9cc8345 | True | True | True |
| e07-P | 07:30:48 | P | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13217 | 6338 | 11941 | 158/132 | 9f943fb19cbe | True | True | True |
| e07-I | 07:31:29 | I | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13536 | 6523 | 12228 | 158/132 | 9f943fb19cbe | True | True | True |
| e07-Is | 07:32:10 | Is | 22.5 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14217 | 6826 | 12216 | 158/132 | b474a9cc8345 | True | True | True |
| e07-Ps | 07:32:52 | Ps | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14229 | 6634 | 12066 | 158/132 | b474a9cc8345 | True | True | True |
| e07-S | 07:33:35 | S | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2217 ms | 1 | 14475 | None | 11920 | 132/132 | b474a9cc8345 | True | True | True |
| e08-P | 07:34:10 | P | 22.5 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13552 | 6200 | 11706 | 158/132 | 9f943fb19cbe | True | True | True |
| e08-I | 07:34:52 | I | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13772 | 6357 | 12015 | 158/132 | 9f943fb19cbe | True | True | True |
| e08-Is | 07:35:33 | Is | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14172 | 6769 | 12201 | 158/132 | b474a9cc8345 | True | True | True |
| e08-Ps | 07:36:15 | Ps | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14167 | 6757 | 12130 | 158/132 | b474a9cc8345 | True | True | True |
| e08-S | 07:36:58 | S | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2123 ms | 1 | 14434 | None | 11883 | 132/132 | b474a9cc8345 | True | True | True |
| e09-Is | 07:42:34 | Is | 22.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13700 | 6625 | 11931 | 158/132 | b474a9cc8345 | True | True | True |
| e09-Ps | 07:43:16 | Ps | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14076 | 6678 | 11943 | 158/132 | b474a9cc8345 | True | True | True |
| e09-S | 07:43:58 | S | 22.5 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2060 ms | 1 | 14458 | None | 11979 | 158/158 | b474a9cc8345 | True | True | True |
| e09-P | 07:44:36 | P | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13668 | 6431 | 12068 | 158/132 | 9f943fb19cbe | True | True | True |
| e09-I | 07:45:17 | I | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2073 ms | 1 | 13708 | None | 11988 | 158/158 | 9f943fb19cbe | True | True | True |
| e10-Is | 07:45:54 | Is | 22.6 | 533.75 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 14411 | 6903 | 12104 | 158/132 | b474a9cc8345 | True | True | True |
| e10-Ps | 07:46:37 | Ps | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2009 ms | 1 | 13966 | None | 11804 | 132/132 | b474a9cc8345 | True | True | True |
| e10-S | 07:47:12 | S | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2167 ms | 2 | 14342 | None | 12090 | 132/132 | b474a9cc8345 | True | True | True |
| e10-P | 07:47:48 | P | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13637 | 6379 | 11782 | 158/132 | 9f943fb19cbe | True | True | True |
| e10-I | 07:48:29 | I | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13765 | 6496 | 11921 | 158/132 | 9f943fb19cbe | True | True | True |
| e11-S | 07:54:12 | S | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | other: CALL_AND_RETRY_LAST | reload 4 +2125 ms | 1 | 14105 | None | 12338 | 158/158 | b474a9cc8345 | True | True | True |
| e11-P | 07:54:49 | P | 22.5 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13544 | 6167 | 11857 | 158/132 | 9f943fb19cbe | True | True | True |
| e11-I | 07:55:31 | I | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13790 | 6527 | 11925 | 158/132 | 9f943fb19cbe | True | True | True |
| e11-Is | 07:56:12 | Is | 22.5 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2089 ms | 1 | 14324 | None | 12138 | 132/132 | b474a9cc8345 | True | True | True |
| e11-Ps | 07:56:48 | Ps | 22.5 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13955 | 6664 | 12126 | 158/132 | b474a9cc8345 | True | True | True |
| e12-S | 07:57:30 | S | 22.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2085 ms | 1 | 14429 | None | 11909 | 132/132 | b474a9cc8345 | True | True | True |
| e12-P | 07:58:05 | P | 22.4 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13631 | 6342 | 12137 | 158/132 | 9f943fb19cbe | True | True | True |
| e12-I | 07:58:47 | I | 22.5 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13731 | 6271 | 11986 | 158/132 | 9f943fb19cbe | True | True | True |
| e12-Is | 07:59:28 | Is | 22.5 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2101 ms | 2 | 14126 | None | 12016 | 158/158 | b474a9cc8345 | True | True | True |
| e12-Ps | 08:00:06 | Ps | 22.3 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14124 | 6701 | 11970 | 158/132 | b474a9cc8345 | True | True | True |
| e13-I | 08:06:21 | I | 22.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13402 | 6271 | 11953 | 158/132 | 9f943fb19cbe | True | True | True |
| e13-Is | 08:07:02 | Is | 22.2 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14012 | 6818 | 12029 | 158/132 | b474a9cc8345 | True | True | True |
| e13-Ps | 08:07:44 | Ps | 22.4 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13849 | 6713 | 11941 | 158/132 | b474a9cc8345 | True | True | True |
| e13-S | 08:08:26 | S | 22.3 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14540 | 7009 | 11813 | 158/132 | b474a9cc8345 | True | True | True |
| e13-P | 08:09:09 | P | 22.4 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13427 | 6243 | 11646 | 158/132 | 9f943fb19cbe | True | True | True |
| e14-I | 08:09:50 | I | 22.4 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2047 ms | 1 | 13947 | None | 12181 | 158/158 | 9f943fb19cbe | True | True | True |
| e14-Is | 08:10:27 | Is | 22.5 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2010 ms | 1 | 14206 | None | 11890 | 158/158 | b474a9cc8345 | True | True | True |
| e14-Ps | 08:11:05 | Ps | 22.3 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14134 | 6791 | 11823 | 158/132 | b474a9cc8345 | True | True | True |
| e14-S | 08:11:47 | S | 22.4 | 533.75 | 0.0 | - | True | waited=1s | CRASH | V2 | reload 2 +2108 ms | 1 | 14433 | None | 11761 | 106/106 | b474a9cc8345 | True | True | True |
| e14-P | 08:12:20 | P | 22.4 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13654 | 6361 | 11951 | 158/132 | 9f943fb19cbe | True | True | True |
| e15-Ps | 08:18:02 | Ps | 21.6 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13465 | 6576 | 11715 | 158/132 | b474a9cc8345 | True | True | True |
| e15-S | 08:18:44 | S | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14407 | 7143 | 11972 | 158/132 | b474a9cc8345 | True | True | True |
| e15-P | 08:19:27 | P | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13734 | 6237 | 11958 | 158/132 | 9f943fb19cbe | True | True | True |
| e15-I | 08:20:08 | I | 21.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13664 | 6321 | 12332 | 158/132 | 9f943fb19cbe | True | True | True |
| e15-Is | 08:20:50 | Is | 21.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2014 ms | 1 | 14392 | None | 11984 | 158/158 | b474a9cc8345 | True | True | True |
| e16-Ps | 08:21:27 | Ps | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14364 | 6867 | 11767 | 158/132 | b474a9cc8345 | True | True | True |
| e16-S | 08:22:10 | S | 21.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2138 ms | 1 | 14452 | None | 11787 | 132/132 | b474a9cc8345 | True | True | True |
| e16-P | 08:22:46 | P | 21.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13824 | 6409 | 12057 | 158/132 | 9f943fb19cbe | True | True | True |
| e16-I | 08:23:27 | I | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13883 | 6514 | 12128 | 158/132 | 9f943fb19cbe | True | True | True |
| e16-Is | 08:24:09 | Is | 21.7 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2054 ms | 1 | 14416 | None | 11753 | 132/132 | b474a9cc8345 | True | True | True |
| e17-P | 08:29:46 | P | 21.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13359 | 6326 | 11690 | 158/132 | 9f943fb19cbe | True | True | True |
| e17-I | 08:30:27 | I | 21.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2089 ms | 1 | 13686 | None | 12278 | 158/158 | 9f943fb19cbe | True | True | True |
| e17-Is | 08:31:04 | Is | 21.7 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2037 ms | 1 | 14245 | None | 12098 | 158/158 | b474a9cc8345 | True | True | True |
| e17-Ps | 08:31:42 | Ps | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13992 | 6777 | 12008 | 158/132 | b474a9cc8345 | True | True | True |
| e17-S | 08:32:24 | S | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14569 | 7095 | 11717 | 158/132 | b474a9cc8345 | True | True | True |
| e18-P | 08:33:07 | P | 21.7 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13532 | 6176 | 11836 | 158/132 | 9f943fb19cbe | True | True | True |
| e18-I | 08:33:48 | I | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13929 | 6430 | 12178 | 158/132 | 9f943fb19cbe | True | True | True |
| e18-Is | 08:34:30 | Is | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14429 | 6783 | 12339 | 158/132 | b474a9cc8345 | True | True | True |
| e18-Ps | 08:35:12 | Ps | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14068 | 6787 | 12011 | 158/132 | b474a9cc8345 | True | True | True |
| e18-S | 08:35:55 | S | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14470 | 7237 | 11998 | 158/132 | b474a9cc8345 | True | True | True |
| e19-Is | 08:41:38 | Is | 21.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14028 | 6834 | 12450 | 158/132 | b474a9cc8345 | True | True | True |
| e19-Ps | 08:42:21 | Ps | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14010 | 6766 | 11656 | 158/132 | b474a9cc8345 | True | True | True |
| e19-S | 08:43:03 | S | 21.6 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2099 ms | 2 | 14362 | None | 12082 | 132/132 | b474a9cc8345 | True | True | True |
| e19-P | 08:43:38 | P | 21.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +1999 ms | 1 | 13623 | None | 11835 | 132/132 | 9f943fb19cbe | True | True | True |
| e19-I | 08:44:13 | I | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13699 | 6644 | 12541 | 158/132 | 9f943fb19cbe | True | True | True |
| e20-Is | 08:44:55 | Is | 21.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2047 ms | 1 | 14387 | None | 12040 | 132/132 | b474a9cc8345 | True | True | True |
| e20-Ps | 08:45:30 | Ps | 21.8 | 533.75 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 14068 | 6896 | 11818 | 158/132 | b474a9cc8345 | True | True | True |
| e20-S | 08:46:13 | S | 21.8 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2083 ms | 1 | 14337 | None | 12056 | 158/158 | b474a9cc8345 | True | True | True |
| e20-P | 08:46:51 | P | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13828 | 6384 | 12055 | 158/132 | 9f943fb19cbe | True | True | True |
| e20-I | 08:47:32 | I | 21.8 | 533.75 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 13922 | 6532 | 12337 | 158/132 | 9f943fb19cbe | True | True | True |
| e21-S | 08:53:15 | S | 22.0 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2158 ms | 1 | 13925 | None | 12000 | 158/158 | b474a9cc8345 | True | True | True |
| e21-P | 08:53:53 | P | 21.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13431 | 6127 | 11647 | 158/132 | 9f943fb19cbe | True | True | True |
| e21-I | 08:54:33 | I | 21.9 | 533.75 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 13865 | 6512 | 12137 | 158/132 | 9f943fb19cbe | True | True | True |
| e21-Is | 08:55:15 | Is | 21.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14323 | 6745 | 12235 | 158/132 | b474a9cc8345 | True | True | True |
| e21-Ps | 08:55:57 | Ps | 21.9 | 533.75 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 14031 | 6816 | 11772 | 158/132 | b474a9cc8345 | True | True | True |
| e22-S | 08:56:40 | S | 21.9 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14440 | 6962 | 11536 | 158/132 | b474a9cc8345 | True | True | True |
| e22-P | 08:57:23 | P | 21.9 | 533.75 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 13823 | 6257 | 11736 | 158/132 | 9f943fb19cbe | True | True | True |
| e22-I | 08:58:04 | I | 21.8 | 533.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13872 | 6521 | 12205 | 158/132 | 9f943fb19cbe | True | True | True |
| e22-Is | 08:58:46 | Is | 22.0 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2018 ms | 1 | 14327 | None | 12187 | 158/158 | b474a9cc8345 | True | True | True |
| e22-Ps | 08:59:24 | Ps | 21.9 | 533.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2043 ms | 1 | 14149 | None | 12045 | 158/158 | b474a9cc8345 | True | True | True |
| e23-I | 09:05:02 | I | 20.7 | 517.75 | -16.0 | - | True | waited=0s | no crash | - | - | 0 | 14781 | 6854 | 11773 | 158/132 | 9f943fb19cbe | True | True | True |
| e23-Is | 09:05:45 | Is | 21.2 | 517.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 15375 | 7698 | 10128 | 158/132 | b474a9cc8345 | True | True | True |
| e23-Ps | 09:06:30 | Ps | 20.8 | 517.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14628 | 7408 | 11461 | 158/132 | b474a9cc8345 | True | True | True |
| e23-S | 09:07:13 | S | 21.3 | 517.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 15505 | 7510 | 10119 | 158/132 | b474a9cc8345 | True | True | True |
| e23-P | 09:07:58 | P | 21.1 | 517.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 1 +2360 ms | 1 | 14619 | None | 12066 | 80/80 | 9f943fb19cbe | True | True | True |
| e24-I | 09:08:28 | I | 22.0 | 517.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14672 | 6816 | 11767 | 158/132 | 9f943fb19cbe | True | True | True |
| e24-Is | 09:09:11 | Is | 21.4 | 517.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 14481 | 7725 | 11499 | 158/132 | b474a9cc8345 | True | True | True |
| e24-Ps | 09:09:55 | Ps | 21.1 | 517.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 15093 | 6635 | 11970 | 158/132 | b474a9cc8345 | True | True | True |
| e24-S | 09:10:38 | S | 21.8 | 517.75 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 2 +2197 ms | 1 | 14453 | None | 11999 | 106/106 | b474a9cc8345 | True | True | True |
| e24-P | 09:11:11 | P | 21.8 | 517.75 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13799 | 6313 | 11948 | 158/132 | 9f943fb19cbe | True | True | True |
