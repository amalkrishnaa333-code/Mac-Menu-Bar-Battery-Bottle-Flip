<p align="center">
  <img src="bottle.png" width="120" alt="Bottle Flip" />
</p>

<h1 align="center">Bottle Flip</h1>

<p align="center">
  A bottle flip game that lives entirely in your macOS menu bar.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-Attribution--NonCommercial-blue" alt="License: Attribution NonCommercial" />
</p>

---

## How it works

| | |
|---|---|
| **Water level** | Matches your battery percentage in real time. Water shifts blue → red as your battery drains, and affects the physics — a fuller bottle is harder to land. |
| **Flip** | Hold the menu bar icon. The longer you hold, the more spin you give the bottle. |
| **Haptic feedback** | Your trackpad pulses faster as you approach the sweet spot. Release when the beat peaks. No on-screen indicator — feel it. |
| **Failed flip** | The bottle tips and falls over right there in the menu bar. Tap it to pick it back up. |

## Install

**Requirements:** macOS 12+, Xcode Command Line Tools

```bash
git clone https://github.com/amalkrishnaa333-code/Mac-Menu-Bar-Battery-Bottle-Flip.git
cd Mac-Menu-Bar-Battery-Bottle-Flip
bash build.sh
open BottleFlip.app
```

Or download the pre-built app from [Releases](https://github.com/amalkrishnaa333-code/Mac-Menu-Bar-Battery-Bottle-Flip/releases).

## Kill it

```bash
pkill BottleFlip
```

## Built with

Swift · AppKit · CoreGraphics · IOKit

## License

Copyright © 2026 **Amal Krishna A**

Free to fork and build on — with two rules:
1. **Credit me.** Any public fork or derivative must link back to this repo and name Amal Krishna A as the original author.
2. **No selling.** You can't sell this or bundle it into a paid product without my written permission.

See [LICENSE](LICENSE) for the full terms.
