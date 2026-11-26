# Work Log — Mac 1 (Abhishek)

One entry for each piece of work, newest at the bottom. Times are IST. Where a time comes from a commit, it is when the work was committed. Add a new entry with each future change.

## 25 November 2026

| Time | Work | Result | Commit or evidence |
|---|---|---|---|
| 18:08 | Wrote TTL setting, backup resolver config, DNS scripts, DNS guide, report draft; tested both resolvers on Mac 1 on test ports | Local test passed. Earlier uncommitted Phase 2 files were found missing; the DNS files were restored from a copy | `5a458da`, `1c65165` |
| 18:19 | Merged pull request 1 | Merged | `5abb871` |
| about 18:25 | Set the four addresses in the env file, rendered configs, started primary DNS | `app` and `api` answer Mac 2 with TTL 30 | `f7c622a` |
| 19:03 | Tested the four-Mac path from Mac 1 | DNS, TLS, load balancing and 304 passed; backup DNS did not answer | `26b6efe` |
| about 19:10–19:40 | Mac 4 moved to a new address; found and fixed backup DNS and team CA trust on Mac 4 | Both resolvers answer; Mac 4 requests succeed | `7f37b8d` |
| 19:43 | Extension A: stopped primary DNS | Backup answered; Mac 2 client got HTTP 200 | `125308b`, `dbe2172` |
| 20:10–20:23 | Extension B: changed the record and restored it | Client kept the old address, then switched | `1322f43`, `3dba87d` |
| 20:26–20:49 | Extension C: checked from Mac 1 before and with the firewall | Backends blocked from Mac 1, edge working | `7458596` to `b8bb61e` |
| 20:54–21:06 | Extension E: tested standby, cut over and cut back | Client moved to the standby and back, HTTP 200 on the lines recorded | `a93a087` to `9f3de20` |
| 21:09 | Checked firewall rollback from Mac 1; recorded faults found during setup | Both ports open again | `8c95f77` |
| 21:59 | Wrote troubleshooting runbook and saved a healthy baseline | All layers healthy | `02f1346` |
| about 22:20 | Extension F, guided drill 1: wrong upstream port | Found and fixed | `44c9347` |
| 22:26 | Updated architecture, README and report; ran `demo.sh all` | 8 of 8 tests passed | `946649f` |
| 22:41 | Merged pull request 2 | Merged | `2392e46` |
| 22:59 | Extension B: manual cache flush test | Old address before the flush, new address right after | `d69a6e8` |
| 23:03 | Merged pull request 3; confirmed both backend ports open from Mac 1 | Merged | `ebc220a` |
| 23:12 | Added status tracker and this work log; saved Mac 1 network details and the DNS config in use; corrected an outdated line in the DNS guide | Tracker: 18 of 20 requirements done, 2 partly shown | this commit |
| 23:18 | Added the firewall copies sent from Mac 3 and Mac 4; updated tracker and report | Extension C requirements complete; tracker 19 of 20 | this commit |
| 23:31 | Extension E timing: changed the primary record at 23:25:12 with Mac 2 and Mac 4 as clients; diagnosed a connection failure on Mac 2 | Fresh lookup got the standby while the cached client stayed on the old edge; tracker 20 of 20 | this commit |
| 23:34 | Checked the restore from Mac 1 after the Extension E timing test | Both resolvers answer Mac 2 with TTL 30 and the standby is stopped; HTTPS fails because Mac 2 refuses connections on 8443 and 8080 | this commit |
| 23:37 | Mac 2 nginx started again; retested from Mac 1 | 8 of 8 requests returned 200, 4 from each backend; all 8 checks in `demo.sh all` passed | this commit |
| 23:43 | Added network details sent from Mac 2, 3 and 4 to the architecture document and evidence | All four Macs on `10.7.0.0/19`, gateway `10.7.0.1`, interface `en0` | this commit |
| 23:48 | Added a one-key control panel for Mac 1 (`scripts/mac1.sh`, `Mac1.command`) and a command guide | Tested with `sudo` simulated: command order correct, wrong-IP check works, status read live. Not yet run with real `sudo` | this commit |

## 26 November 2026

| Time | Work | Result | Commit or evidence |
|---|---|---|---|
| 02:38 | Wrote the Mac 1 viva guide: introduction, config, demonstrations, questions and answers | Added `docs/17-mac1-viva-guide.md` | this commit |
| 13:31 IST | Pre-demo full test on four Macs, using `mac1.sh demo` with real sudo. First run: 502 on all requests, Mac 2 log `no live upstreams` while Mac 1 reached both backends. Fixed after nginx on Mac 2 was stopped and started from Apple Terminal (cause not confirmed). | `demo.sh all` no FAIL or WARN; 8/8 requests 200 (4 A, 4 B); both DNS servers answer 10.7.29.185, TTL 30 | Terminal output, 26 Nov |
| 13:34 IST | Rechecked all four Macs before the demo. Mac 4 client ran `phase2-demo.sh lb 4`. | Four Macs answer ping; DNS, edge and backend ports open; `demo.sh all` no FAIL or WARN; 8/8 from Mac 1 and 4/4 from Mac 4 returned 200 | Terminal output, 26 Nov |
| 13:38 IST | Pre-demo retests. Backup DNS: stopped Mac 1 dnsmasq, flushed, sent 4 requests from Mac 1, restarted. Backend failure: stopped Backend A on Mac 3, then started it again. | Backup: 4/4 200 with primary stopped, primary running again. Backend failure: 6/6 200 from B with A stopped; after restart 8/8 200 (3 A, 5 B) | Terminal output, 26 Nov |
| 13:53 IST | Pre-demo retests. Isolation: pf enabled on Mac 3 and Mac 4, tested from Mac 1, then disabled on both. TTL and standby edge: standby checked directly, Mac 4 client on Mac 1 DNS only ran watch, `app` switched to Mac 3 at 13:49:34 and back at 13:52:40. | Isolation: both ports blocked, 8/8 via edge, block counters 3 (Mac 3) and 2 (Mac 4), rolled back, ports open. Cutover: standby 6/6 direct; fresh lookup new at 13:49:35; client old through 13:49:36, standby at 13:49:38. Cutback: Mac 1 and both DNS answer Mac 2, 6/6 200; client flush: reported as changed back, output not captured | Terminal output, 26 Nov |
