import AppKit

class BottleView: NSView {

    // MARK: - Public
    var waterLevel: Double = 0.5 { didSet { needsDisplay = true } }

    // MARK: - State machine
    private enum FlipState {
        case idle
        case charging(since: Date)
        case flipping
        case landing(success: Bool, countdown: Double)
        case tipping          // gravity pulls it over after a miss
        case fallen           // lying on its side, waiting for a tap
        case risingUp         // spring-back to upright after the tap
    }
    private var state: FlipState = .idle

    // Physics
    private var angle: Double = 0
    private var angVel: Double = 0
    private var flipElapsed: Double = 0
    private let flipDuration = 0.80

    // Water simulation
    private var wavePhase: Double = 0
    private var waveAmp: Double = 0.5

    // Landing flash
    private var flashAlpha: Double = 0
    private var flashSuccess = false

    // Haptics — escalating beat, no visual indicator
    private var lastHapticFire: Date = .distantPast

    // Timer
    private var timer: Timer?
    private var lastTick = Date()

    // Bottle PNG
    private var bottleImage: NSImage?

    // MARK: - Geometry (bottle-local, y-up, origin = rotation pivot)
    //
    // The bottle.png is 6464×6464 with alpha. We draw it in a 20×20 pt square
    // (local rect x:−10..10, y:−9..11). The bottle silhouette occupies roughly
    // x: 25%..73%  →  local −5..4.6   (≈ centered, half-width ~4.8)
    // y: 4%..96%   →  local 10.2..−8.2
    //
    // Interior clip path is traced slightly inside the thick outline.
    // Image drawn as a full 22×22 pt square — fills the entire menu-bar slot.
    // The bottle silhouette occupies ~48 % of the width and ~92 % of the height
    // inside that square, so expanding to 22 × 22 gives the maximum feasible size.
    private let imgRect  = CGRect(x: -11, y: -11, width: 22, height: 22)
    private let waveHW: CGFloat = 5.3   // widest body half-width (scaled ×1.1)
    private let fillBottom: CGFloat = -9.4  // bottom of bottle bumps (scaled ×1.1)
    private let fillTop:    CGFloat =  6.9  // just below neck shoulder (scaled ×1.1)

    // MARK: - Init
    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    deinit { timer?.invalidate() }

    private func setup() {
        loadImage()
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func loadImage() {
        guard let url = Bundle.main.url(forResource: "bottle", withExtension: "png") else { return }
        bottleImage = NSImage(contentsOf: url)
        bottleImage?.isTemplate = true
    }

    // MARK: - Physics tick

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.033)
        lastTick = now

        switch state {
        case .idle:
            wavePhase += dt * 1.1
            waveAmp  += (0.35 - waveAmp) * dt * 3.0

        case .charging(let since):
            wavePhase += dt * 2.6
            waveAmp  += (1.2 - waveAmp) * dt * 6.0
            fireEscalatingHaptic(held: Date().timeIntervalSince(since))

        case .flipping:
            flipElapsed += dt
            angle      += angVel * dt
            wavePhase  += dt * 8.5
            let target  = min(abs(angVel) * 0.11 * (0.4 + waterLevel), 1.8)
            waveAmp    += (target - waveAmp) * dt * 12.0
            if flipElapsed >= flipDuration { land() }

        case .landing(let success, let countdown):
            wavePhase  += dt * 1.8
            waveAmp     = max(waveAmp - dt * 2.5, 0.3)
            flashAlpha  = max(flashAlpha - dt * 0.9, 0)
            let rem     = countdown - dt
            if rem <= 0 {
                if success {
                    state = .idle; angle = 0; waveAmp = 0.35
                } else {
                    // Brief pause over — start tipping
                    angVel = (angle > 0 ? 1.0 : -1.0) * 0.6
                    state  = .tipping
                }
            } else {
                state = .landing(success: success, countdown: rem)
            }

        case .tipping:
            // Gravity torque: accelerates toward π/2 like a rod falling under gravity
            angVel    += 9.0 * sin(angle) * dt
            angle     += angVel * dt
            wavePhase += dt * (2.5 + abs(angVel) * 0.6)
            waveAmp   += (3.0 - waveAmp) * dt * 5.0

            let limit: Double = .pi / 2
            if abs(angle) >= limit {
                angle  = angle > 0 ? limit : -limit
                angVel = 0
                waveAmp = 4.0          // water crashes to one end on impact
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                state  = .fallen
            }

        case .fallen:
            // Settle the slosh; stay here until the user taps
            wavePhase += dt * 1.4
            waveAmp    = max(waveAmp - dt * 1.5, 0.5)

        case .risingUp:
            // Overdamped spring back to vertical
            let k = 48.0, d = 12.0
            angVel += (-k * angle - d * angVel) * dt
            angle  += angVel * dt
            wavePhase += dt * 2.2
            waveAmp   += (0.4 - waveAmp) * dt * 3.0
            if abs(angle) < 0.04 && abs(angVel) < 0.15 {
                angle = 0; angVel = 0; state = .idle
            }
        }

        if wavePhase > .pi * 2 { wavePhase -= .pi * 2 }
        needsDisplay = true
    }

    // MARK: - Haptics (escalating beat, no visual)

    private func sweetSpot() -> Double {
        // 25 % water is the real-world optimum; difficulty increases toward 0 % / 100 %
        let dist = abs(waterLevel - 0.25)
        return 0.55 + dist * 0.45
    }

    private func fireEscalatingHaptic(held: Double) {
        let perfect  = sweetSpot()
        let progress = held / perfect     // 0 → start, 1 → sweet spot

        // Interval shrinks from 0.5 s down to 0.07 s as the sweet spot approaches,
        // then widens again so the player feels they've passed it.
        let interval: Double
        if progress < 1.0 {
            interval = max(0.07, 0.50 - progress * 0.43)
        } else {
            interval = min(0.07 + (progress - 1.0) * 0.28, 0.45)
        }

        guard Date().timeIntervalSince(lastHapticFire) >= interval else { return }
        lastHapticFire = Date()

        // Alignment (stronger "click") right at the sweet spot window; generic taps elsewhere
        let pattern: NSHapticFeedbackManager.FeedbackPattern =
            progress >= 0.92 && progress <= 1.08 ? .alignment : .generic
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    // MARK: - Land

    private func land() {
        var norm = angle.truncatingRemainder(dividingBy: .pi * 2)
        if norm < 0 { norm += .pi * 2 }
        let deg = norm * 180 / .pi
        let success = deg < 22 || deg > 338

        if success {
            angle = 0; waveAmp = 2.0
            flashSuccess = true
            flashAlpha   = 0.45
            state = .landing(success: true, countdown: 1.6)
        } else {
            // Land at a slight lean — then tip over after a short beat
            let lean = norm < .pi ? min(norm, .pi / 5) : max(norm - .pi * 2, -.pi / 5)
            angle = lean; angVel = 0; waveAmp = 1.2
            flashSuccess = false
            flashAlpha   = 0.28
            state = .landing(success: false, countdown: 0.30)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        switch state {
        case .idle:
            lastHapticFire = .distantPast
            state = .charging(since: Date())
        case .fallen:
            // Pick it back up
            angVel = 0
            state  = .risingUp
        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard case .charging(let since) = state else { return }
        let held = min(Date().timeIntervalSince(since), 2.4)
        doFlip(chargeTime: held)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Bottle Flip",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func doFlip(chargeTime: Double) {
        let ratio  = chargeTime / sweetSpot()
        angVel     = ratio * ((2 * .pi) / flipDuration)
        angle      = 0; flipElapsed = 0
        waveAmp    = 1.8 + waterLevel * 2.0
        state      = .flipping
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Success / fail flash
        if flashAlpha > 0 {
            let fc = flashSuccess
                ? NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.3, alpha: flashAlpha)
                : NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.1, alpha: flashAlpha)
            ctx.setFillColor(fc.cgColor)
            ctx.fill(bounds)
        }

        let cx = bounds.midX

        ctx.saveGState()

        let visualAngle: Double
        switch state {
        case .charging(let since):
            let t = min(Date().timeIntervalSince(since) / 2.4, 1.0)
            visualAngle = t * 0.18
        default:
            visualAngle = angle
        }

        // ── Pivot strategy ─────────────────────────────────────────────────────
        // Spinning in the air  →  rotate around the body centre (cx, 11).
        // At rest / tipping / fallen / rising  →  keep the bottle BASE on the
        // menubar floor by deriving the pivot from the current tilt angle.
        //
        //   baseLen  = distance from body centre to bottle base in local coords.
        //   floorY   = view-y where the base rests (bottom of the 22-pt slot).
        //
        //   pivot_x = cx + sin(θ) * baseLen   (base stays at cx in view)
        //   pivot_y = floorY + cos(θ) * baseLen
        //
        // At θ = 0 this collapses to (cx, 11) — identical to the air pivot —
        // so the idle/success/risingUp→idle transitions are seamless.
        // ───────────────────────────────────────────────────────────────────────
        let baseLen: CGFloat = 10.12   // local-coord distance, centre → base
        let floorY:  CGFloat =  0.88   // view-y of bottle base when upright

        let pivotX: CGFloat
        let pivotY: CGFloat
        switch state {
        case .flipping, .charging:
            pivotX = cx
            pivotY = 11.0
        default:
            pivotX = cx + CGFloat(sin(visualAngle)) * baseLen
            pivotY = floorY + CGFloat(cos(visualAngle)) * baseLen
        }

        ctx.translateBy(x: pivotX, y: pivotY)
        ctx.rotate(by: CGFloat(-visualAngle))
        renderWater(ctx: ctx, tiltAngle: visualAngle)
        renderBottleImage()

        ctx.restoreGState()
    }

    // MARK: - Water (drawn first, clipped to bottle interior)

    private func renderWater(ctx: CGContext, tiltAngle: Double) {
        let totalH  = fillTop - fillBottom
        let surfaceY = fillBottom + CGFloat(waterLevel) * totalH

        // Water tilts with bottle lean.  During the fall the water piles hard to
        // one end (large multiplier); during normal rest/charge it's subtle.
        let tilt: CGFloat
        switch state {
        case .flipping:
            tilt = 0
        case .tipping, .fallen, .risingUp:
            tilt = CGFloat(sin(tiltAngle)) * waveHW * 0.95
        default:
            tilt = CGFloat(sin(tiltAngle)) * waveHW * 0.28
        }

        // Wave path: from bottom up to animated surface
        let steps = 18
        let wPath = CGMutablePath()
        wPath.move(to: CGPoint(x: -waveHW, y: fillBottom - 1))
        wPath.addLine(to: CGPoint(x:  waveHW, y: fillBottom - 1))
        wPath.addLine(to: CGPoint(x:  waveHW, y: surfaceY + tilt))

        for i in 0...steps {
            let t  = CGFloat(i) / CGFloat(steps)
            let x  = waveHW - t * (waveHW * 2)
            let ty = x * (tilt / max(waveHW, 0.001))
            let wy = surfaceY + ty +
                     CGFloat(waveAmp) * CGFloat(sin(wavePhase + Double(t) * 2 * .pi))
            wPath.addLine(to: CGPoint(x: x, y: wy))
        }
        wPath.closeSubpath()

        // Clip to bottle interior so water never bleeds outside the outline
        ctx.saveGState()
        ctx.addPath(bottleInteriorPath())
        ctx.clip()

        // Gradient fill
        let (topC, botC) = waterColors()
        let cs = CGColorSpaceCreateDeviceRGB()
        if let g = CGGradient(colorsSpace: cs,
                              colors: [topC, botC] as CFArray,
                              locations: [0, 1] as [CGFloat]) {
            ctx.saveGState()
            ctx.addPath(wPath); ctx.clip()
            ctx.drawLinearGradient(g,
                start: CGPoint(x: 0, y: surfaceY),
                end:   CGPoint(x: 0, y: fillBottom),
                options: [])
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }

    // MARK: - Bottle PNG overlay (drawn on top of water)

    private func renderBottleImage() {
        bottleImage?.draw(in: imgRect, from: .zero,
                          operation: .sourceOver, fraction: 1.0)
    }

    // MARK: - Interior clip path
    //
    // Traced from bottle.png with the image mapped to imgRect (−10..10, −9..11).
    // Bottle silhouette within that rect:
    //   x ≈ −5 .. 4.6   (we symmetrise to ±4.8, centred at −0.2 ≈ 0)
    //   y ≈ −8.2 .. 10.2
    // Path is inset ~0.8 pt from the visible stroke to stay inside the thick outline.

    private func bottleInteriorPath() -> CGPath {
        // Path defined at the original 20 pt scale, then uniformly scaled ×1.1
        // to match the expanded 22 pt imgRect.
        let p = CGMutablePath()

        // ── Bottom scallops (3 bumps) ──
        p.move(to: CGPoint(x: -4.0, y: -6.8))
        p.addQuadCurve(to: CGPoint(x: -1.6, y: -6.8),
                       control: CGPoint(x: -2.9, y: -8.3))
        p.addQuadCurve(to: CGPoint(x:  1.6, y: -6.8),
                       control: CGPoint(x:  0.0, y: -8.3))
        p.addQuadCurve(to: CGPoint(x:  4.0, y: -6.8),
                       control: CGPoint(x:  2.9, y: -8.3))

        // ── Right body: barrel shape then shoulder ──
        p.addCurve(to:       CGPoint(x:  4.8, y:  0.5),
                   control1: CGPoint(x:  5.1, y: -4.5),
                   control2: CGPoint(x:  5.1, y: -1.8))
        p.addCurve(to:       CGPoint(x:  2.5, y:  6.3),
                   control1: CGPoint(x:  4.8, y:  4.2),
                   control2: CGPoint(x:  4.1, y:  6.3))

        // ── Right neck ──
        p.addLine(to: CGPoint(x:  2.5, y:  7.3))

        // ── Cap right ──
        p.addLine(to: CGPoint(x:  3.5, y:  7.3))
        p.addLine(to: CGPoint(x:  3.5, y: 10.0))

        // ── Cap top ──
        p.addLine(to: CGPoint(x: -3.5, y: 10.0))

        // ── Cap left ──
        p.addLine(to: CGPoint(x: -3.5, y:  7.3))
        p.addLine(to: CGPoint(x: -2.5, y:  7.3))

        // ── Left neck ──
        p.addLine(to: CGPoint(x: -2.5, y:  6.3))

        // ── Left shoulder + body ──
        p.addCurve(to:       CGPoint(x: -4.8, y:  0.5),
                   control1: CGPoint(x: -4.1, y:  6.3),
                   control2: CGPoint(x: -4.8, y:  4.2))
        p.addCurve(to:       CGPoint(x: -4.0, y: -6.8),
                   control1: CGPoint(x: -5.1, y: -1.8),
                   control2: CGPoint(x: -5.1, y: -4.5))

        p.closeSubpath()

        // Scale up to match the 22 × 22 imgRect (was 20 × 20)
        var t = CGAffineTransform(scaleX: 1.1, y: 1.1)
        return p.copy(using: &t) ?? p
    }

    // MARK: - Water colours

    private func waterColors() -> (CGColor, CGColor) {
        switch waterLevel {
        case 0.5...:
            return (NSColor(calibratedRed: 0.15, green: 0.62, blue: 1.00, alpha: 0.90).cgColor,
                    NSColor(calibratedRed: 0.00, green: 0.30, blue: 0.78, alpha: 0.95).cgColor)
        case 0.2..<0.5:
            return (NSColor(calibratedRed: 0.10, green: 0.52, blue: 0.95, alpha: 0.90).cgColor,
                    NSColor(calibratedRed: 0.00, green: 0.24, blue: 0.65, alpha: 0.95).cgColor)
        default:
            return (NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.10, alpha: 0.90).cgColor,
                    NSColor(calibratedRed: 0.60, green: 0.08, blue: 0.00, alpha: 0.95).cgColor)
        }
    }
}
