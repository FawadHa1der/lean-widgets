| arm | browser | runs | crashed | V2 | variants | crashed runs | quiet at launch |
|---|---|---|---|---|---|---|---|
| ctl (current gallery) | headed | 24 | **8/24** | 8 | V2 8 | v01-ctl-hd, v03-ctl-hd, v04-ctl-hd, v05-ctl-hd, v10-ctl-hd, v14-ctl-hd, v16-ctl-hd, v24-ctl-hd | 24/24 |
| mit (pagehide teardown) | headed | 24 | **10/24** | 10 | V2 10 | v04-mit-hd, v09-mit-hd, v11-mit-hd, v12-mit-hd, v14-mit-hd, v16-mit-hd, v17-mit-hd, v20-mit-hd, v22-mit-hd, v23-mit-hd | 24/24 |
| ctl (current gallery) | headless-shell | 12 | **0/12** | 0 | - | - | 12/12 |
| mit (pagehide teardown) | headless-shell | 12 | **0/12** | 0 | - | - | 12/12 |
| ctl (current gallery) | **both** | 36 | **8/36** | 8 | V2 8 | v01-ctl-hd, v03-ctl-hd, v04-ctl-hd, v05-ctl-hd, v10-ctl-hd, v14-ctl-hd, v16-ctl-hd, v24-ctl-hd | 36/36 |
| mit (pagehide teardown) | **both** | 36 | **10/36** | 10 | V2 10 | v04-mit-hd, v09-mit-hd, v11-mit-hd, v12-mit-hd, v14-mit-hd, v16-mit-hd, v17-mit-hd, v20-mit-hd, v22-mit-hd, v23-mit-hd | 36/36 |

* V2 headed: ctl 8/24, mit 10/24; Fisher exact two-sided p = 0.766
* V2 headless-shell: ctl 0/12, mit 0/12; Fisher exact two-sided p = 1.000
* V2 both browsers: ctl 8/36, mit 10/36; Fisher exact two-sided p = 0.786

| tag | utc | arm | mode | recl | swap | swapDelta | foreign | quiet | waited | result | variant | crashAt | oomLines | firstReadyMs | readyAfterMs | rssPeak | workers |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v01-ctl-hd | 22:37:44 | ctl | headed | 22.8 | 605.81 | None | - | True | waited=0s | CRASH | V2 | reload 2 +2041 ms | 1 | 13252 | None | 11710 | 106/106 |
| v01-mit-hd | 22:38:15 | mit | headed | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13278 | 6188 | 11843 | 158/132 |
| v01-mit-hs | 22:38:56 | mit | headless-shell | 22.9 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13267 | 6140 | 11837 | 158/132 |
| v01-ctl-hs | 22:39:36 | ctl | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13250 | 6059 | 11796 | 158/132 |
| v02-ctl-hs | 22:40:17 | ctl | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13272 | 6080 | 11719 | 158/132 |
| v02-mit-hs | 22:40:57 | mit | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13514 | 6103 | 12002 | 158/132 |
| v02-mit-hd | 22:41:37 | mit | headed | 22.8 | 605.81 | 0.0 | - | True | waited=1s | no crash | - | - | 0 | 13720 | 6199 | 12058 | 158/132 |
| v02-ctl-hd | 22:42:19 | ctl | headed | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13612 | 6102 | 12184 | 158/132 |
| v03-mit-hd | 22:43:00 | mit | headed | 22.6 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13660 | 6237 | 11771 | 158/132 |
| v03-ctl-hd | 22:43:41 | ctl | headed | 22.8 | 605.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2089 ms | 1 | 13587 | None | 12214 | 132/132 |
| v03-ctl-hs | 22:44:16 | ctl | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13320 | 6149 | 11897 | 158/132 |
| v03-mit-hs | 22:44:56 | mit | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13495 | 6097 | 11677 | 158/132 |
| v04-mit-hs | 22:46:07 | mit | headless-shell | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13223 | 6112 | 11726 | 158/132 |
| v04-ctl-hs | 22:46:47 | ctl | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13294 | 5978 | 11664 | 158/132 |
| v04-ctl-hd | 22:47:27 | ctl | headed | 22.8 | 605.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2081 ms | 1 | 13715 | None | 12161 | 158/158 |
| v04-mit-hd | 22:48:04 | mit | headed | 22.6 | 605.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2026 ms | 1 | 13406 | None | 11863 | 158/158 |
| v05-ctl-hd | 22:48:41 | ctl | headed | 22.8 | 605.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2066 ms | 2 | 13660 | None | 12246 | 158/158 |
| v05-mit-hd | 22:49:18 | mit | headed | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13564 | 6257 | 11937 | 158/132 |
| v05-mit-hs | 22:50:00 | mit | headless-shell | 22.6 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13210 | 6151 | 11902 | 158/132 |
| v05-ctl-hs | 22:50:40 | ctl | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13339 | 6113 | 11857 | 158/132 |
| v06-ctl-hs | 22:51:20 | ctl | headless-shell | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13539 | 5981 | 11672 | 158/132 |
| v06-mit-hs | 22:52:01 | mit | headless-shell | 22.5 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13323 | 6110 | 11870 | 158/132 |
| v06-mit-hd | 22:52:41 | mit | headed | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13667 | 6102 | 12217 | 158/132 |
| v06-ctl-hd | 22:53:22 | ctl | headed | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13705 | 6323 | 11820 | 158/132 |
| v07-mit-hd | 22:54:34 | mit | headed | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13583 | 6292 | 12009 | 158/132 |
| v07-ctl-hd | 22:55:15 | ctl | headed | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13603 | 6248 | 12089 | 158/132 |
| v07-ctl-hs | 22:55:56 | ctl | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13312 | 6024 | 11713 | 158/132 |
| v07-mit-hs | 22:56:36 | mit | headless-shell | 22.8 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13349 | 6069 | 11970 | 158/132 |
| v08-mit-hs | 22:57:16 | mit | headless-shell | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13517 | 6180 | 11797 | 158/132 |
| v08-ctl-hs | 22:57:57 | ctl | headless-shell | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13457 | 6184 | 11821 | 158/132 |
| v08-ctl-hd | 22:58:38 | ctl | headed | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13729 | 6302 | 11992 | 158/132 |
| v08-mit-hd | 22:59:19 | mit | headed | 22.7 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13550 | 6267 | 12417 | 158/132 |
| v09-ctl-hd | 23:00:00 | ctl | headed | 22.5 | 605.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13612 | 6302 | 12099 | 158/132 |
| v09-mit-hd | 23:00:41 | mit | headed | 22.7 | 605.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2132 ms | 1 | 13656 | None | 12001 | 158/158 |
| v09-mit-hs | 23:01:19 | mit | headless-shell | 22.7 | 597.81 | -8.0 | - | True | waited=0s | no crash | - | - | 0 | 13289 | 6064 | 11775 | 158/132 |
| v09-ctl-hs | 23:01:59 | ctl | headless-shell | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13511 | 6158 | 11806 | 158/132 |
| v10-ctl-hs | 23:03:10 | ctl | headless-shell | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13280 | 6150 | 11726 | 158/132 |
| v10-mit-hs | 23:03:50 | mit | headless-shell | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13423 | 6039 | 11866 | 158/132 |
| v10-mit-hd | 23:04:30 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13686 | 6245 | 11729 | 158/132 |
| v10-ctl-hd | 23:05:11 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=1s | CRASH | V2 | reload 4 +2097 ms | 1 | 13620 | None | 11918 | 158/158 |
| v11-mit-hd | 23:05:49 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2041 ms | 2 | 13635 | None | 11743 | 158/158 |
| v11-ctl-hd | 23:06:26 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13425 | 6280 | 11922 | 158/132 |
| v11-ctl-hs | 23:07:07 | ctl | headless-shell | 22.6 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13283 | 6087 | 11810 | 158/132 |
| v11-mit-hs | 23:07:47 | mit | headless-shell | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13306 | 6033 | 11673 | 158/132 |
| v12-mit-hs | 23:08:27 | mit | headless-shell | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13207 | 6107 | 11816 | 158/132 |
| v12-ctl-hs | 23:09:08 | ctl | headless-shell | 22.6 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13321 | 6040 | 11645 | 158/132 |
| v12-ctl-hd | 23:09:48 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13407 | 6303 | 11983 | 158/132 |
| v12-mit-hd | 23:10:29 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2047 ms | 1 | 13435 | None | 11902 | 158/158 |
| v13-ctl-hd | 23:16:42 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13368 | 5993 | 11891 | 158/132 |
| v13-mit-hd | 23:17:23 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13596 | 6254 | 11914 | 158/132 |
| v14-mit-hd | 23:18:04 | mit | headed | 22.5 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2024 ms | 1 | 13449 | None | 12152 | 158/158 |
| v14-ctl-hd | 23:18:41 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2056 ms | 1 | 13402 | None | 12315 | 158/158 |
| v15-ctl-hd | 23:19:18 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13654 | 6305 | 11754 | 158/132 |
| v15-mit-hd | 23:19:59 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13653 | 6241 | 11755 | 158/132 |
| v16-mit-hd | 23:20:40 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 2 +2086 ms | 2 | 13445 | None | 11988 | 106/106 |
| v16-ctl-hd | 23:21:12 | ctl | headed | 22.6 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 4 +2132 ms | 1 | 13426 | None | 12022 | 158/158 |
| v17-ctl-hd | 23:21:49 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13647 | 6272 | 11967 | 158/132 |
| v17-mit-hd | 23:22:30 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2135 ms | 1 | 13666 | None | 11864 | 132/132 |
| v18-mit-hd | 23:23:05 | mit | headed | 22.6 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13688 | 6222 | 11996 | 158/132 |
| v18-ctl-hd | 23:23:46 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13696 | 6303 | 11612 | 158/132 |
| v19-ctl-hd | 23:24:57 | ctl | headed | 22.5 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13654 | 6276 | 11980 | 158/132 |
| v19-mit-hd | 23:25:39 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13426 | 6322 | 11797 | 158/132 |
| v20-mit-hd | 23:26:20 | mit | headed | 22.5 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2061 ms | 1 | 13637 | None | 12132 | 132/132 |
| v20-ctl-hd | 23:26:55 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13731 | 6240 | 12116 | 158/132 |
| v21-ctl-hd | 23:27:36 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13659 | 6306 | 12009 | 158/132 |
| v21-mit-hd | 23:28:17 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13684 | 6321 | 11858 | 158/132 |
| v22-mit-hd | 23:28:58 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2067 ms | 1 | 13474 | None | 11844 | 132/132 |
| v22-ctl-hd | 23:29:33 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13642 | 6295 | 11742 | 158/132 |
| v23-ctl-hd | 23:30:14 | ctl | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13507 | 6299 | 11869 | 158/132 |
| v23-mit-hd | 23:30:55 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | CRASH | V2 | reload 3 +2161 ms | 1 | 13675 | None | 12072 | 132/132 |
| v24-mit-hd | 23:31:30 | mit | headed | 22.7 | 597.81 | 0.0 | - | True | waited=0s | no crash | - | - | 0 | 13659 | 6292 | 11967 | 158/132 |
| v24-ctl-hd | 23:32:11 | ctl | headed | 22.6 | 597.81 | 0.0 | - | True | waited=1s | CRASH | V2 | reload 3 +2111 ms | 1 | 13579 | None | 11990 | 132/132 |
