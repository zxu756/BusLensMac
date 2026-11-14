=== BusLens Mac README Command Replay & Honesty Gate ===
Date (UTC): 2026-11-14T08:49:28Z
App Binary: <REPO_ROOT>/build/BusLensMac.app/Contents/MacOS/BusLensMac

[PASS] Documentation honesty & Unreleased (after v0.2.0) disclosures verified in README.md, README.zh-CN.md, and docs/SPEC.md
[PASS] Extracted all fenced bash commands with 100% EN/ZH parity (README.md=20, README.zh-CN.md=20)
[SKIP] [README.md #01] `brew install --cask zxu756/tap/buslens-mac` -> reason: external Homebrew cask install requires network/Homebrew tap; out of offline test scope
[SKIP] [README.md #02] `git clone https://github.com/zxu756/BusLensMac.git` -> reason: network clone from GitHub remote; local git clone independence is verified via /tmp clone test
[SKIP] [README.md #03] `cd BusLensMac` -> reason: shell directory change builtin; replay already runs inside repository root
[PASS] [README.md #04] `./Scripts/test.sh scope Diagnoser Collector CLI` -> rc=0 (Swift Testing scoped suites (Diagnoser, Collector, CLI) passed)
[SKIP] [README.md #05] `./Scripts/test.sh milestone 0` -> reason: already executing inside parent './Scripts/test.sh milestone 0' gate (prevents infinite recursion)
[PASS] [README.md #06] `./Scripts/build-app.sh` -> rc=0 (Built and codesigned build/BusLensMac.app)
[SKIP] [README.md #07] `open build/BusLensMac.app` -> reason: launches macOS GUI window; skipped to enforce zero-GUI headless test policy
[PASS] [README.md #08] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --lang en` -> rc=0 (Power: AC Line Power (Low Power Mode: No) | Peak Negotiated Link: 40 Gb/s)
[PASS] [README.md #09] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --lang zh` -> rc=0 (供电状态：交流电源（低电量模式：否） | 最高协商链路：40 Gb/s)
[PASS] [README.md #10] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --json --lang en` -> rc=0 (JSON valid (language=en, isDemo=false, devices=3))
[PASS] [README.md #11] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --json --lang zh` -> rc=0 (JSON valid (language=zh-Hans, isDemo=false, devices=3))
[PASS] [README.md #12] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang en` -> rc=0 (Verified TBU405Pro + Indeterminate + [Low-speed peripheral])
[PASS] [README.md #13] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang zh` -> rc=0 (Verified TBU405Pro + 无法判断是否被限速 + 低速外设（USB 1.x）)
[PASS] [README.md #14] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --demo --lang en` -> rc=0 ([DEMO] Synthetic preview topology (BusLensMonitor.preview))
[PASS] [README.md #15] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --demo --lang zh` -> rc=0 ([演示数据] 内置合成演示拓扑 (BusLensMonitor.preview))
[PASS] [README.md #16] `build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots .build/demo-shots --lang en` -> rc=0 (Exported 2x Retina [DEMO] screenshots (en) to .build/demo-shots)
[PASS] [README.md #17] `build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots .build/demo-shots --lang zh` -> rc=0 (已导出 2x Retina [演示数据] 截图（zh-Hans）至 .build/demo-shots)
[PASS] [README.md #18] `build/BusLensMac.app/Contents/MacOS/BusLensMac --help --lang en` -> rc=0 (BusLens Mac 0.2.0 — Thunderbolt, USB4 & USB-C negotiated link-speed inspector)
[PASS] [README.md #19] `build/BusLensMac.app/Contents/MacOS/BusLensMac --help --lang zh` -> rc=0 (BusLens Mac 0.2.0 — 雷雳、USB4 与 USB-C 协商速率检视工具)
[PASS] [README.md #20] `build/BusLensMac.app/Contents/MacOS/BusLensMac --version` -> rc=0 (BusLens Mac 0.2.0)
[SKIP] [README.zh-CN.md #01] `brew install --cask zxu756/tap/buslens-mac` -> reason: external Homebrew cask install requires network/Homebrew tap; out of offline test scope
[SKIP] [README.zh-CN.md #02] `git clone https://github.com/zxu756/BusLensMac.git` -> reason: network clone from GitHub remote; local git clone independence is verified via /tmp clone test
[SKIP] [README.zh-CN.md #03] `cd BusLensMac` -> reason: shell directory change builtin; replay already runs inside repository root
[PASS] [README.zh-CN.md #04] `./Scripts/test.sh scope Diagnoser Collector CLI` -> rc=0 (Swift Testing scoped suites (Diagnoser, Collector, CLI) passed)
[SKIP] [README.zh-CN.md #05] `./Scripts/test.sh milestone 0` -> reason: already executing inside parent './Scripts/test.sh milestone 0' gate (prevents infinite recursion)
[PASS] [README.zh-CN.md #06] `./Scripts/build-app.sh` -> rc=0 (Built and codesigned build/BusLensMac.app)
[SKIP] [README.zh-CN.md #07] `open build/BusLensMac.app` -> reason: launches macOS GUI window; skipped to enforce zero-GUI headless test policy
[PASS] [README.zh-CN.md #08] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --lang en` -> rc=0 (Power: AC Line Power (Low Power Mode: No) | Peak Negotiated Link: 40 Gb/s)
[PASS] [README.zh-CN.md #09] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --lang zh` -> rc=0 (供电状态：交流电源（低电量模式：否） | 最高协商链路：40 Gb/s)
[PASS] [README.zh-CN.md #10] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --json --lang en` -> rc=0 (JSON valid (language=en, isDemo=false, devices=3))
[PASS] [README.zh-CN.md #11] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --json --lang zh` -> rc=0 (JSON valid (language=zh-Hans, isDemo=false, devices=3))
[PASS] [README.zh-CN.md #12] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang en` -> rc=0 (Verified TBU405Pro + Indeterminate + [Low-speed peripheral])
[PASS] [README.zh-CN.md #13] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang zh` -> rc=0 (Verified TBU405Pro + 无法判断是否被限速 + 低速外设（USB 1.x）)
[PASS] [README.zh-CN.md #14] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --demo --lang en` -> rc=0 ([DEMO] Synthetic preview topology (BusLensMonitor.preview))
[PASS] [README.zh-CN.md #15] `build/BusLensMac.app/Contents/MacOS/BusLensMac --cli topology --demo --lang zh` -> rc=0 ([演示数据] 内置合成演示拓扑 (BusLensMonitor.preview))
[PASS] [README.zh-CN.md #16] `build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots .build/demo-shots --lang en` -> rc=0 (Exported 2x Retina [DEMO] screenshots (en) to .build/demo-shots)
[PASS] [README.zh-CN.md #17] `build/BusLensMac.app/Contents/MacOS/BusLensMac --export-screenshots .build/demo-shots --lang zh` -> rc=0 (已导出 2x Retina [演示数据] 截图（zh-Hans）至 .build/demo-shots)
[PASS] [README.zh-CN.md #18] `build/BusLensMac.app/Contents/MacOS/BusLensMac --help --lang en` -> rc=0 (BusLens Mac 0.2.0 — Thunderbolt, USB4 & USB-C negotiated link-speed inspector)
[PASS] [README.zh-CN.md #19] `build/BusLensMac.app/Contents/MacOS/BusLensMac --help --lang zh` -> rc=0 (BusLens Mac 0.2.0 — 雷雳、USB4 与 USB-C 协商速率检视工具)
[PASS] [README.zh-CN.md #20] `build/BusLensMac.app/Contents/MacOS/BusLensMac --version` -> rc=0 (BusLens Mac 0.2.0)

=== ALL README COMMANDS VERIFIED (executed=30, skipped=10) ===
