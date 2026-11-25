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
