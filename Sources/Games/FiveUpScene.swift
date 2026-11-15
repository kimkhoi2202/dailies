import SwiftUI

// Five Up: find a hidden five-letter word in six tries.
//
// Letterpress tiles and typewriter keys on cream paper, painted by FiveUpPainter. The paper, slots,
// tiles and solved stamp are images from Resources/GameArt; letters and keys are drawn in code.
// Teal: the letter is in the right place. Coral: it is in the word, somewhere else. Ink: it is not
// in the word. The clip in the video feed makes a board from a phase (0...1) and a fixed script;
// the playable game makes one from its model.

public struct FiveUpScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            if size.width <= 2 || size.height <= 2 { return }
            FiveUpPainter(board: FiveUpClip.board(at: phase), showHUD: showHUD, size: size).paint(&context)
        }
    }
}

// MARK: - Colours and curves

enum FiveUpInk {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    static let paper = hex(0xF5E9D4)
    static let cream = hex(0xFFF7E8)

    static let ink = hex(0x211D33)
    static let inkHi = hex(0x3A3553)
    static let inkLo = hex(0x100E1B)

    static let teal = hex(0x17B3A3)
    static let tealHi = hex(0x38D2C0)
    static let tealLo = hex(0x0A7268)

    static let coral = hex(0xFF6B4F)
    static let coralHi = hex(0xFF8E72)
    static let coralLo = hex(0xC23D26)

    static let mint = hex(0xBDEBE2)
    static let blush = hex(0xFFD4C7)
}

enum FiveUpEase {
    static func unit(_ v: Double) -> Double { min(max(v, 0), 1) }

    static func smooth(_ edge0: Double, _ edge1: Double, _ v: Double) -> Double {
        let k = unit((v - edge0) / (edge1 - edge0))
        return k * k * (3 - 2 * k)
    }

    static func outCubic(_ v: Double) -> Double {
        let rest = 1 - unit(v)
        return 1 - rest * rest * rest
    }

    /// Overshoots a little before it settles on 1.
    static func outBack(_ v: Double) -> Double {
        let x = unit(v) - 1
        let spring = 1.9
        return 1 + (spring + 1) * x * x * x + spring * x * x
    }
}

/// SplitMix64, for the speckles and the confetti.
struct FiveUpNoise {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03 }

    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var v = state
        v = (v ^ (v >> 30)) &* 0xBF58476D1CE4E5B9
        v = (v ^ (v >> 27)) &* 0x94D049BB133111EB
        v ^= v >> 31
        return Double(v >> 11) / 9007199254740992.0
    }

    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}

// MARK: - The board

enum FiveUpMark {
    case absent, present, exact

    var rank: Int {
        switch self {
        case .absent: return 1
        case .present: return 2
        case .exact: return 3
        }
    }

    /// Marks for a guess. Placed letters are settled first, so a letter is never marked more often
    /// than the answer holds it.
    static func grade(_ guess: [Character], against answer: [Character]) -> [FiveUpMark] {
        var marks = [FiveUpMark](repeating: .absent, count: guess.count)
        var spare: [Character: Int] = [:]
        for k in guess.indices {
            if guess[k] == answer[k] { marks[k] = .exact } else { spare[answer[k], default: 0] += 1 }
        }
        for k in guess.indices where marks[k] != .exact {
            let left = spare[guess[k]] ?? 0
            if left > 0 {
                marks[k] = .present
                spare[guess[k]] = left - 1
            }
        }
        return marks
    }
}

/// One letter tile on the board.
struct FiveUpTile {
    var letter: Character
    var mark = FiveUpMark.absent
    /// 0: the typed face is up. 1: turned over, showing its mark.
    var flip = 0.0
    /// 0...1 while it pops in after being typed.
    var pop: Double?
    /// 0...1 while it settles after turning over.
    var land: Double?
}

/// Everything the painter needs for one frame.
struct FiveUpBoard {
    var rows: [[FiveUpTile]] = []
    var activeRow: Int? = 0
    /// Letters typed on the active row. -1 when no row is open.
    var cursor = 0
    /// By letter, A = 0.
    var keyMarks = [FiveUpMark?](repeating: nil, count: 26)
    var keyPress = [Double?](repeating: nil, count: 26)
    var enterPress: Double?
    var deletePress: Double?

    var score = 0
    var seconds = 0
    var urgent = false

    /// 0...1 through the solved flourish. 0 = not solved.
    var win = 0.0
    var winRow = 4
    var stampRow = 5
    var stampText = "SOLVED"
    var bonusText = "+500"

    var shakeRow: Int?
    /// Sideways offset of the shaking row, in board units.
    var shakeDX: CGFloat = 0

    static func keyIndex(_ letter: Character) -> Int? {
        guard let code = letter.asciiValue, code >= 65, code <= 90 else { return nil }
        return Int(code) - 65
    }
}

/// The round the clip shows: five guesses that close in on PRINT.
enum FiveUpClip {
    static let answer: [Character] = Array("PRINT")
    static let guesses: [[Character]] = ["STORM", "TRIAL", "WRITE", "DRIFT", "PRINT"].map { Array($0) }
    static let marks: [[FiveUpMark]] = guesses.map { FiveUpMark.grade($0, against: answer) }

    /// When each row is typed and when it turns over, in phase.
    private static let beats: [(type0: Double, type1: Double, flip0: Double, flip1: Double)] = [
        (-0.060, -0.010, 0.000, 0.050),
        (0.058, 0.092, 0.097, 0.137),
        (0.1445, 0.2125, 0.218, 0.262),
        (0.275, 0.335, 0.341, 0.386),
        (0.391, 0.551, 0.565, 0.655)
    ]
    private static let points: [Double] = [20, 50, 50, 70, 500]
    private static let winStart = 0.66

    static func board(at phase: Double) -> FiveUpBoard {
        let p = phase.isFinite ? FiveUpEase.unit(phase) : 0
        var board = FiveUpBoard()
        var open: Int?
        var total = 2480.0
        for (r, beat) in beats.enumerated() {
            let typing = (p - beat.type0) / (beat.type1 - beat.type0)
            let span = beat.flip1 - beat.flip0
            var tiles: [FiveUpTile] = []
            for c in 0..<5 {
                let letter = guesses[r][c]
                let mark = marks[r][c]
                let shownAt = (Double(c) + 0.15) / 5
                let turnAt = beat.flip0 + Double(c) * 0.16 * span
                let flip = FiveUpEase.unit((p - turnAt) / (0.36 * span))
                if typing >= shownAt {
                    var tile = FiveUpTile(letter: letter, mark: mark, flip: flip)
                    let pop = (typing - shownAt) / 0.17
                    if pop > 0, pop < 1 { tile.pop = pop }
                    let land = (p - turnAt - 0.36 * span) / (0.6 * span)
                    if land > 0, land < 1 { tile.land = land }
                    tiles.append(tile)
                }
                guard let key = FiveUpBoard.keyIndex(letter) else { continue }
                if flip >= 0.5, mark.rank > (board.keyMarks[key]?.rank ?? 0) { board.keyMarks[key] = mark }
                if board.keyPress[key] == nil, typing > -0.1, typing < 1.2 {
                    let press = (typing - (shownAt - 0.035)) / 0.165
                    if press > 0, press < 1 { board.keyPress[key] = press }
                }
            }
            board.rows.append(tiles)

            if r > 0, board.enterPress == nil {
                let press = (p - (beat.flip0 - 0.007)) / 0.013
                if press > 0, press < 1 { board.enterPress = press }
            }
            if open == nil, p < beat.flip0 {
                open = r
                board.cursor = tiles.count
            }
            let roll = r == beats.count - 1 ? 0.09 : 0.03
            total += points[r] * FiveUpEase.smooth(beat.flip1 - 0.012, beat.flip1 + roll, p)
        }
        board.activeRow = open
        if open == nil { board.cursor = -1 }
        board.score = Int((total / 5).rounded()) * 5
        let stop = beats[beats.count - 1].flip1
        board.seconds = Int((90 - 75 * min(p, stop) / stop).rounded())
        board.win = FiveUpEase.unit((p - winStart) / (1 - winStart))
        board.winRow = guesses.count - 1
        return board
    }
}

// MARK: - Layout

/// Where things sit. From the top: room for the app's two buttons, a slim header row, the grid,
/// the keyboard.
struct FiveUpLayout {
    /// The app's close button and gold counter end at this y on a full-screen phone.
    static let appButtonsBottom: CGFloat = 114
    // In screen units.
    static let headerHeight: CGFloat = 44
    static let keyCapHeight: CGFloat = 50
    static let keyRowStep: CGFloat = 59.5
    static let keyDepth: CGFloat = 4.6
    // In board units: five tiles across, six rows of slots.
    static let gridWidth: CGFloat = 294
    static let gridHeight: CGFloat = 357

    let w: CGFloat
    let h: CGFloat
    /// Screen unit, for type, the header and the keys: 1 on a 402 x 874 screen.
    let u: CGFloat
    /// Board unit: a tile is 54 of these and tiles sit 60 apart.
    let b: CGFloat
    let midX: CGFloat
    let headerTop: CGFloat
    /// Top of the first row of slots.
    let gridTop: CGFloat
    /// Middle of the first row of key caps.
    let keysY: CGFloat
    /// From one letter key to the next, and from one row of keys to the next.
    let keyPitch: CGFloat
    let keyRowPitch: CGFloat
    let keyWidth: CGFloat
    let keyHeight: CGFloat
    /// false in thumbnails too short for the keyboard.
    let showsKeys: Bool
    /// The solved flourish stays below this line.
    let ceiling: CGFloat

    init(size: CGSize, showHUD: Bool = true) {
        typealias K = FiveUpLayout
        w = max(size.width, 1)
        h = max(size.height, 1)
        midX = w / 2
        let keyboard = 2 * K.keyRowStep + K.keyCapHeight + K.keyDepth
        let unit: CGFloat
        if h / w >= 1.8 {
            // A full-screen phone. The header hangs under the app's buttons, the keyboard stands on
            // the home indicator's inset, and the grid gets the room between them.
            unit = min(w / 402, h / 874)
            headerTop = K.appButtonsBottom + 16 * unit
            keysY = h - GameLayout.bottomInset - (2 + keyboard - K.keyCapHeight / 2) * unit
            let roomTop = headerTop + (K.headerHeight + 12) * unit
            let roomBottom = keysY - (K.keyCapHeight / 2 + 16) * unit
            let fit = min((w - 28 * unit) / K.gridWidth, (roomBottom - roomTop) / K.gridHeight)
            b = max(min(fit, 1.45 * unit), 0.2 * unit)
            gridTop = roomTop + max((roomBottom - roomTop - K.gridHeight * b) / 2, 0)
            showsKeys = true
            ceiling = headerTop
        } else {
            // Thumbnails and crops: header (when shown) and grid, centred. A frame that is tall
            // enough gets the keyboard too.
            let tall = h / w >= 1.5
            let head: CGFloat = showHUD ? K.headerHeight + 12 : 0
            let grid = K.gridHeight * 1.25
            let block = head + grid + (tall ? 16 + keyboard : 0)
            unit = min(w / 402, h / (block + 40))
            b = 1.25 * unit
            headerTop = (h - block * unit) / 2
            gridTop = headerTop + head * unit
            keysY = gridTop + (grid + 16 + K.keyCapHeight / 2) * unit
            showsKeys = tall
            ceiling = -.greatestFiniteMagnitude
        }
        u = unit
        keyPitch = 39.2 * unit
        keyRowPitch = K.keyRowStep * unit
        keyWidth = keyPitch - 4 * unit
        keyHeight = K.keyCapHeight * unit
    }
}

// MARK: - Tile faces

struct FiveUpFace {
    /// The painted tile, letter-free, with its thickness along the bottom.
    let art: String
    let top: Color
    let side: Color
    let letter: Color
    let letterShade: Color

    /// Typed, not yet turned over.
    static let blank = FiveUpFace(art: "five-up-tile-blank", top: FiveUpInk.hex(0xFFFDF6), side: FiveUpInk.ink,
                                  letter: FiveUpInk.ink, letterShade: Color.white.opacity(0))
    static let absent = FiveUpFace(art: "five-up-tile-absent", top: FiveUpInk.hex(0x3D3857), side: FiveUpInk.hex(0x0F0D1A),
                                   letter: FiveUpInk.hex(0xC9C0D6), letterShade: FiveUpInk.hex(0x0F0D1A, 0.55))
    static let present = FiveUpFace(art: "five-up-tile-present", top: FiveUpInk.hex(0xFF8B6E), side: FiveUpInk.coralLo,
                                    letter: FiveUpInk.cream, letterShade: FiveUpInk.hex(0xA42E1A, 0.55))
    static let exact = FiveUpFace(art: "five-up-tile-exact", top: FiveUpInk.hex(0x35D0BE), side: FiveUpInk.tealLo,
                                  letter: FiveUpInk.cream, letterShade: FiveUpInk.hex(0x075E56, 0.55))

    static func of(_ mark: FiveUpMark) -> FiveUpFace {
        switch mark {
        case .absent: return absent
        case .present: return present
        case .exact: return exact
        }
    }
}

/// The four painted tile faces, resolved once a frame.
struct FiveUpTileArt {
    private let blank: GraphicsContext.ResolvedImage
    private let absent: GraphicsContext.ResolvedImage
    private let present: GraphicsContext.ResolvedImage
    private let exact: GraphicsContext.ResolvedImage

    init(_ ctx: GraphicsContext) {
        blank = ctx.resolve(Image(FiveUpFace.blank.art))
        absent = ctx.resolve(Image(FiveUpFace.absent.art))
        present = ctx.resolve(Image(FiveUpFace.present.art))
        exact = ctx.resolve(Image(FiveUpFace.exact.art))
    }

    func image(for face: FiveUpFace) -> GraphicsContext.ResolvedImage {
        switch face.art {
        case FiveUpFace.absent.art: return absent
        case FiveUpFace.present.art: return present
        case FiveUpFace.exact.art: return exact
        default: return blank
        }
    }
}

// MARK: - Painter

struct FiveUpPainter {
    typealias Ink = FiveUpInk
    typealias Ease = FiveUpEase

    /// The clip paints everything at once. The playable game paints what never changes once
    /// (still) and the rest every frame (live).
    enum Pass { case all, still, live }

    static let keyRows: [[Character]] = ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"].map { Array($0) }

    let board: FiveUpBoard
    let showHUD: Bool
    let layout: FiveUpLayout

    init(board: FiveUpBoard, showHUD: Bool, size: CGSize) {
        self.board = board
        self.showHUD = showHUD
        layout = FiveUpLayout(size: size, showHUD: showHUD)
    }

    var u: CGFloat { layout.u }
    var b: CGFloat { layout.b }

    /// The six rows of slots.
    var gridRect: CGRect {
        CGRect(x: layout.midX - FiveUpLayout.gridWidth / 2 * b, y: layout.gridTop,
               width: FiveUpLayout.gridWidth * b, height: FiveUpLayout.gridHeight * b)
    }

    func tileCenter(_ row: Int, _ column: Int) -> CGPoint {
        CGPoint(x: layout.midX + CGFloat(column - 2) * 60 * b, y: layout.gridTop + (25 + CGFloat(row) * 60) * b)
    }

    func keyCenter(_ row: Int, _ index: Int) -> CGPoint {
        let middle = CGFloat(Self.keyRows[row].count - 1) / 2
        return CGPoint(x: layout.midX + (CGFloat(index) - middle) * layout.keyPitch,
                       y: layout.keysY + CGFloat(row) * layout.keyRowPitch)
    }

    /// ENTER and delete fill the two ends of the bottom row, each one and a half letter keys wide.
    var wideKeyWidth: CGFloat { 1.5 * layout.keyPitch - 4 * u }
    var enterKeyCenter: CGPoint { CGPoint(x: layout.midX - 4.25 * layout.keyPitch, y: layout.keysY + 2 * layout.keyRowPitch) }
    var deleteKeyCenter: CGPoint { CGPoint(x: layout.midX + 4.25 * layout.keyPitch, y: layout.keysY + 2 * layout.keyRowPitch) }

    /// The cap of a key at rest.
    func keyCap(center: CGPoint, width: CGFloat) -> CGRect {
        CGRect(x: center.x - width / 2, y: center.y - layout.keyHeight / 2, width: width, height: layout.keyHeight)
    }

    var keyCorner: CGFloat { min(layout.keyWidth * 0.4, layout.keyHeight / 2) }

    func paint(_ ctx: inout GraphicsContext, pass: Pass = .all) {
        if pass != .live {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: layout.w, height: layout.h)), with: .color(Ink.paper))
            let cover = max(layout.w / 2, layout.h / 3)
            ctx.draw(ctx.resolve(Image("five-up-paper")),
                     in: CGRect(x: (layout.w - 2 * cover) / 2, y: (layout.h - 3 * cover) / 2, width: 2 * cover, height: 3 * cover))
        }
        if pass == .still { return }
        if showHUD { paintHeader(&ctx) }
        paintSlots(&ctx)
        paintTiles(&ctx)
        paintStamp(&ctx)
        if layout.showsKeys { paintKeys(&ctx) }
        paintFlourish(&ctx)
    }

    // MARK: Helpers

    func styled(_ words: String, size: CGFloat, weight: Font.Weight, design: Font.Design = .default,
                expanded: Bool = false, tracking: CGFloat = 0, color: Color) -> Text {
        let font = Font.system(size: size, weight: weight, design: design)
        return Text(words).font(expanded ? font.width(.expanded) : font).tracking(tracking).foregroundColor(color)
    }

    func label(_ ctx: inout GraphicsContext, _ words: String, size: CGFloat, weight: Font.Weight,
               design: Font.Design = .default, expanded: Bool = false, tracking: CGFloat = 0,
               color: Color, at point: CGPoint, anchor: UnitPoint = .center) {
        ctx.draw(ctx.resolve(styled(words, size: size, weight: weight, design: design, expanded: expanded,
                                    tracking: tracking, color: color)), at: point, anchor: anchor)
    }

    func soft(_ rect: CGRect, _ radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }

    func pill(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .circular)
    }

    /// A four-pointed star with curved sides.
    func star(_ center: CGPoint, radius: CGFloat, waist: CGFloat = 0.16) -> Path {
        func point(_ angle: Double, _ reach: CGFloat) -> CGPoint {
            CGPoint(x: center.x + CGFloat(cos(angle)) * reach, y: center.y + CGFloat(sin(angle)) * reach)
        }
        var path = Path()
        path.move(to: point(-.pi / 2, radius))
        for k in 0..<4 {
            let angle = Double(k) * .pi / 2 - .pi / 2
            path.addQuadCurve(to: point(angle + .pi / 2, radius), control: point(angle + .pi / 4, radius * waist))
        }
        path.closeSubpath()
        return path
    }

    static func grouped(_ value: Int) -> String {
        let digits = Array(String(max(value, 0)))
        var out = ""
        for (k, digit) in digits.enumerated() {
            if k > 0, (digits.count - k) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }

    /// A raised pill: the clock, a toast.
    func paintChip(_ ctx: inout GraphicsContext, rect: CGRect, top: Color, bottom: Color, side: Color) {
        ctx.fill(pill(rect.offsetBy(dx: 0, dy: 5.5 * u).insetBy(dx: u, dy: u)), with: .color(Ink.hex(0x6E4F22, 0.18)))
        ctx.fill(pill(rect.offsetBy(dx: 0, dy: 3 * u)), with: .color(side))
        ctx.fill(pill(rect), with: .linearGradient(Gradient(colors: [top, bottom]),
                                                    startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        var gloss = Path()
        gloss.move(to: CGPoint(x: rect.minX + rect.height * 0.45, y: rect.minY + 2.4 * u))
        gloss.addLine(to: CGPoint(x: rect.maxX - rect.height * 0.45, y: rect.minY + 2.4 * u))
        ctx.stroke(gloss, with: .color(Color.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1.3 * u, lineCap: .round))
    }

    // MARK: Header: score on the left, clock in the middle

    private var scoreCaption: Text {
        styled("SCORE", size: 9 * u, weight: .heavy, expanded: true, tracking: 2.4 * u, color: Ink.hex(0x211D33, 0.6))
    }

    private func paintHeader(_ ctx: inout GraphicsContext) {
        let left = gridRect.minX
        let top = layout.headerTop

        ctx.draw(ctx.resolve(scoreCaption), at: CGPoint(x: left + u, y: top + 6.5 * u), anchor: .leading)
        // The number swells for a moment when the word is solved.
        let swell = board.win > 0 ? CGFloat(sin(.pi * Ease.unit(board.win / 0.3))) * 0.06 : 0
        label(&ctx, Self.grouped(board.score), size: 30 * u * (1 + swell), weight: .black, design: .serif, tracking: -0.4 * u,
              color: Ink.ink, at: CGPoint(x: left - 0.5 * u, y: top + 30 * u), anchor: .leading)

        let chip = CGRect(x: layout.w / 2 - 38 * u, y: top + 7 * u, width: 76 * u, height: 30 * u)
        if board.urgent {
            paintChip(&ctx, rect: chip, top: Ink.coralHi, bottom: Ink.coral, side: Ink.coralLo)
        } else {
            paintChip(&ctx, rect: chip, top: Ink.inkHi, bottom: Ink.ink, side: Ink.inkLo)
        }
        let dial = CGPoint(x: chip.minX + 17 * u, y: chip.midY)
        ctx.stroke(Path(ellipseIn: CGRect(x: dial.x - 6.6 * u, y: dial.y - 6.6 * u, width: 13.2 * u, height: 13.2 * u)),
                   with: .color(Ink.cream), lineWidth: 1.8 * u)
        var hands = Path()
        hands.move(to: CGPoint(x: dial.x, y: dial.y - 3.8 * u))
        hands.addLine(to: dial)
        hands.addLine(to: CGPoint(x: dial.x + 3.0 * u, y: dial.y + 1.6 * u))
        ctx.stroke(hands, with: .color(Ink.cream), style: StrokeStyle(lineWidth: 1.7 * u, lineCap: .round, lineJoin: .round))
        let seconds = board.seconds % 60
        label(&ctx, "\(board.seconds / 60):\(seconds < 10 ? "0" : "")\(seconds)", size: 15.5 * u, weight: .heavy,
              design: .rounded, color: Ink.cream, at: CGPoint(x: chip.minX + 47 * u, y: chip.midY))
    }

    // MARK: Slots

    private func paintSlots(_ ctx: inout GraphicsContext) {
        let u = b
        let radius = 11.5 * u
        let slot = ctx.resolve(Image("five-up-slot"))
        for row in 0..<6 {
            let open = board.activeRow == row
            for column in 0..<5 {
                let centre = tileCenter(row, column)
                let rect = CGRect(x: centre.x - 27 * u, y: centre.y - 25 * u, width: 54 * u, height: 57 * u)
                ctx.draw(slot, in: rect)
                if open { ctx.fill(soft(rect, radius), with: .color(Color.white.opacity(0.22))) }

                if open, column == board.cursor {
                    let inner = soft(rect.insetBy(dx: 1.6 * u, dy: 1.6 * u), radius - 1.6 * u)
                    ctx.fill(inner, with: .color(Ink.hex(0xFFF9EC, 0.9)))
                    ctx.stroke(inner, with: .color(Ink.coral), lineWidth: 2.6 * u)
                    ctx.fill(pill(CGRect(x: centre.x - 9 * u, y: rect.maxY - 13 * u, width: 18 * u, height: 3.4 * u)),
                             with: .color(Ink.coral))
                }
            }
        }
    }

    // MARK: Tiles

    /// How one tile is drawn this frame.
    struct TilePose {
        var center: CGPoint
        var face: FiveUpFace
        var letter: Character
        /// 1 = face on, 0 = edge on, half way through a turn.
        var squash: CGFloat = 1
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var rotation = 0.0
        var lift: CGFloat = 0
        var mark: FiveUpMark?
        /// x of the passing glint, from the tile's middle.
        var shine: CGFloat?
        var burst: Double?
        var ring: Double?
    }

    private func paintTiles(_ ctx: inout GraphicsContext) {
        let u = b
        let grid = gridRect
        let win = board.win
        // Tiles at rest go down first so the moving ones pass over them.
        var resting: [TilePose] = []
        var moving: [TilePose] = []
        for (r, row) in board.rows.prefix(6).enumerated() {
            for (c, tile) in row.prefix(5).enumerated() {
                var pose = TilePose(center: tileCenter(r, c), face: .blank, letter: tile.letter)
                if board.shakeRow == r { pose.center.x += board.shakeDX * u }
                var busy = false

                if tile.flip > 0 {
                    pose.squash = CGFloat(abs(cos(.pi * tile.flip)))
                    pose.lift = CGFloat(sin(.pi * tile.flip)) * 5 * u
                    if tile.flip >= 0.5 {
                        pose.face = FiveUpFace.of(tile.mark)
                        pose.mark = tile.mark
                    }
                    if tile.flip < 1 { busy = true }
                }
                if let pop = tile.pop {
                    let kick = sin(.pi * pop) * (1 - 0.35 * pop)
                    pose.scaleX = 1 + CGFloat(0.2 * kick)
                    pose.scaleY = pose.scaleX
                    pose.rotation = -0.07 * kick
                    pose.lift += CGFloat(kick) * 3 * u
                    pose.burst = pop
                    busy = true
                }
                if let land = tile.land {
                    let kick = sin(.pi * land) * (1 - land)
                    pose.scaleX = 1 + CGFloat(0.12 * kick)
                    pose.scaleY = 1 - CGFloat(0.10 * kick)
                    if pose.mark != .absent { pose.ring = land }
                    busy = true
                }
                if r == board.winRow, win > 0 {
                    // The solved row hops, one tile after the other, while a glint runs across it.
                    let beat = win * 4.4 - Double(c) * 0.22
                    if beat > 0 {
                        let strength = max(0.4, 1 - 0.16 * beat)
                        let hop = abs(sin(.pi * beat))
                        let flat = pow(1 - hop, 3) * strength
                        pose.lift += CGFloat(hop * strength) * 17 * u
                        pose.scaleX *= 1 + CGFloat(0.10 * flat - 0.03 * hop)
                        pose.scaleY *= 1 - CGFloat(0.10 * flat - 0.05 * hop)
                        pose.rotation += sin(.pi * beat + Double(c)) * 0.06 * hop
                        busy = true
                    }
                    let sweep = (win * 1.55).truncatingRemainder(dividingBy: 1.3) - 0.15
                    pose.shine = grid.minX + CGFloat(sweep) * grid.width - pose.center.x
                }
                if busy { moving.append(pose) } else { resting.append(pose) }
            }
        }
        let art = FiveUpTileArt(ctx)
        for pose in resting { paintTile(&ctx, pose, art: art) }
        for pose in moving { paintTile(&ctx, pose, art: art) }
    }

    func paintTile(_ ctx: inout GraphicsContext, _ pose: TilePose, art: FiveUpTileArt) {
        let u = b
        let side = 54 * u
        let depth = 5.5 * u
        let c = pose.center

        // Ticks fly out from a tile that was just typed.
        if let burst = pose.burst {
            let from = side * (0.66 + 0.26 * CGFloat(Ease.outCubic(burst)))
            let to = from + 6.5 * u * CGFloat(1 - burst * 0.7)
            var ticks = Path()
            for k in 0..<8 {
                let angle = Double(k) * .pi / 4 + 0.39
                let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
                ticks.move(to: CGPoint(x: c.x + dx * from, y: c.y + dy * from))
                ticks.addLine(to: CGPoint(x: c.x + dx * to, y: c.y + dy * to))
            }
            ctx.stroke(ticks, with: .color(Ink.hex(0xFF6B4F, 1 - burst * 0.8)), style: StrokeStyle(lineWidth: 2.6 * u, lineCap: .round))
        }
        // A ring puffs out when a coloured tile lands.
        if let ring = pose.ring, let mark = pose.mark {
            let half = side / 2 + 3 * u + 12 * u * CGFloat(Ease.outCubic(ring))
            ctx.stroke(soft(CGRect(x: c.x - half, y: c.y - half + 2 * u, width: half * 2, height: half * 2), 12 * u + (half - side / 2)),
                       with: .color((mark == .exact ? Ink.teal : Ink.coral).opacity(0.75 * (1 - ring))),
                       lineWidth: 3 * u * CGFloat(1 - ring) + 0.6 * u)
        }

        // The shadow stays down in the slot while the tile lifts.
        let shrink = 1 - min(pose.lift / (side * 1.6), 0.3)
        let shadowW = side * pose.scaleX * shrink
        let shadowH = max(side * pose.squash, side * 0.2) * pose.scaleY * shrink
        for k in 0..<3 {
            let spread = CGFloat(k) * 1.5 * u
            let rect = CGRect(x: c.x - shadowW / 2 - spread + u,
                              y: c.y - shadowH / 2 + depth + 1.6 * u - spread * 0.3 + pose.lift * 0.12,
                              width: shadowW + spread * 2, height: shadowH + spread * 1.3)
            ctx.fill(soft(rect, 12 * u + spread), with: .color(Ink.hex(0x3C2A10, 0.11)))
        }

        var g = ctx
        g.translateBy(x: c.x, y: c.y - pose.lift)
        g.rotate(by: .radians(pose.rotation))
        g.scaleBy(x: pose.scaleX, y: pose.scaleY)

        let height = max(side * pose.squash, side * 0.07)
        let radius = min(side * 0.215, height / 2)
        let rect = CGRect(x: -side / 2, y: -height / 2, width: side, height: height)
        let front = soft(rect, radius)

        g.draw(art.image(for: pose.face), in: CGRect(x: -side / 2, y: -height / 2, width: side, height: height + depth))
        if let x = pose.shine, pose.mark != nil, height > side * 0.5 {
            let half = 15 * u
            let slant = 12 * u
            var band = Path()
            band.addLines([CGPoint(x: x - half + slant, y: rect.minY), CGPoint(x: x + half + slant, y: rect.minY),
                           CGPoint(x: x + half - slant, y: rect.maxY), CGPoint(x: x - half - slant, y: rect.maxY)])
            band.closeSubpath()
            var glint = g
            glint.clip(to: front)
            glint.fill(band, with: .color(Color.white.opacity(0.26)))
        }
        if pose.squash > 0.14 {
            var type = g
            type.scaleBy(x: 1, y: pose.squash)
            let glyph = Text(String(pose.letter)).font(.system(size: side * 0.63, weight: .black, design: .serif))
            type.draw(type.resolve(glyph.foregroundColor(pose.face.letterShade)), at: CGPoint(x: 0, y: side * 0.035), anchor: .center)
            type.draw(type.resolve(glyph.foregroundColor(pose.face.letter)), at: CGPoint(x: 0, y: -side * 0.005), anchor: .center)
        }
    }

    // MARK: Solved stamp

    private func paintStamp(_ ctx: inout GraphicsContext) {
        let u = b
        let win = board.win
        if win <= 0.10 { return }
        // It slams down, then gives a little.
        let arrive = Ease.unit((win - 0.10) / 0.09)
        let slam = 1 + CGFloat(pow(1 - arrive, 2)) * 1.3
        let give = arrive >= 1 ? 1 + CGFloat(sin(.pi * Ease.unit((win - 0.19) / 0.08))) * 0.05 : 1

        var g = ctx
        g.translateBy(x: layout.midX + 6 * u, y: tileCenter(board.stampRow, 0).y + 2 * u)
        g.rotate(by: .degrees(-6.5))
        g.scaleBy(x: slam * give, y: slam * give)
        g.opacity = arrive

        let w = 226 * u, h = 50 * u
        let frame = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let red = Ink.hex(0xF0502F)
        g.draw(g.resolve(Image("five-up-stamp")), in: frame)
        label(&g, board.stampText, size: 24 * u, weight: .black, expanded: true, tracking: 3.2 * u, color: red,
              at: CGPoint(x: 2 * u, y: 0))

        // Gaps where the ink did not take.
        var noise = FiveUpNoise(seed: 77)
        var gaps = Path()
        for _ in 0..<70 {
            let x = CGFloat(noise.range(-0.5, 0.5)) * w
            let y = CGFloat(noise.range(-0.5, 0.5)) * h
            let r = CGFloat(noise.range(0.4, 1.3)) * u
            gaps.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        g.fill(gaps, with: .color(Ink.hex(0xFFF3E2, 0.85)))
    }

    // MARK: Keys

    private struct KeyLook {
        let top: Color
        let bottom: Color
        let side: Color
        let ring: Color
        let letter: Color
        let gloss: Double
        let depth: CGFloat
    }

    private static let plainKey = KeyLook(top: FiveUpInk.hex(0xFFFDF5), bottom: FiveUpInk.hex(0xEFE0C3), side: FiveUpInk.hex(0x8F7A58),
                                          ring: FiveUpInk.hex(0xD3BE98), letter: FiveUpInk.ink, gloss: 0.9, depth: FiveUpLayout.keyDepth)
    private static let exactKey = KeyLook(top: FiveUpInk.hex(0x3DD6C4), bottom: FiveUpInk.hex(0x0FA291), side: FiveUpInk.hex(0x075B53),
                                          ring: FiveUpInk.hex(0x0C8679), letter: FiveUpInk.cream, gloss: 0.5, depth: FiveUpLayout.keyDepth)
    private static let presentKey = KeyLook(top: FiveUpInk.hex(0xFF9377), bottom: FiveUpInk.hex(0xF75A3D), side: FiveUpInk.hex(0x9C2F1C),
                                            ring: FiveUpInk.hex(0xD9472D), letter: FiveUpInk.cream, gloss: 0.5, depth: FiveUpLayout.keyDepth)
    /// A letter that is not in the word sits low and dark.
    private static let absentKey = KeyLook(top: FiveUpInk.hex(0x353050), bottom: FiveUpInk.hex(0x272338), side: FiveUpInk.hex(0x0A0812),
                                           ring: FiveUpInk.hex(0x443E63), letter: FiveUpInk.hex(0x8D86A6), gloss: 0.12, depth: 2.0)

    private func look(_ mark: FiveUpMark?) -> KeyLook {
        switch mark {
        case .none: return Self.plainKey
        case .some(.exact): return Self.exactKey
        case .some(.present): return Self.presentKey
        case .some(.absent): return Self.absentKey
        }
    }

    private func paintKeys(_ ctx: inout GraphicsContext) {
        var ripples: [(at: CGPoint, age: Double)] = []
        for (row, letters) in Self.keyRows.enumerated() {
            for (k, letter) in letters.enumerated() {
                let centre = keyCenter(row, k)
                let index = FiveUpBoard.keyIndex(letter) ?? 0
                let look = look(board.keyMarks[index])
                let at = paintCap(&ctx, center: centre, width: layout.keyWidth, look: look, press: board.keyPress[index])
                label(&ctx, String(letter), size: 19 * u, weight: .black, design: .serif, color: look.letter, at: at)
                if let age = board.keyPress[index] { ripples.append((centre, age)) }
            }
        }

        let enter = paintCap(&ctx, center: enterKeyCenter, width: wideKeyWidth, look: Self.plainKey, press: board.enterPress)
        label(&ctx, "ENTER", size: 9 * u, weight: .black, expanded: true, tracking: 0.3 * u, color: Ink.ink, at: enter)
        if let age = board.enterPress { ripples.append((enterKeyCenter, age)) }

        let c = paintCap(&ctx, center: deleteKeyCenter, width: wideKeyWidth, look: Self.plainKey, press: board.deletePress)
        var arrow = Path()
        arrow.addLines([CGPoint(x: c.x - 11 * u, y: c.y), CGPoint(x: c.x - 4.5 * u, y: c.y - 6.5 * u),
                        CGPoint(x: c.x + 10 * u, y: c.y - 6.5 * u), CGPoint(x: c.x + 10 * u, y: c.y + 6.5 * u),
                        CGPoint(x: c.x - 4.5 * u, y: c.y + 6.5 * u)])
        arrow.closeSubpath()
        ctx.stroke(arrow, with: .color(Ink.ink), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round, lineJoin: .round))
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - 0.5 * u, y: c.y - 2.8 * u))
        cross.addLine(to: CGPoint(x: c.x + 5.1 * u, y: c.y + 2.8 * u))
        cross.move(to: CGPoint(x: c.x + 5.1 * u, y: c.y - 2.8 * u))
        cross.addLine(to: CGPoint(x: c.x - 0.5 * u, y: c.y + 2.8 * u))
        ctx.stroke(cross, with: .color(Ink.ink), style: StrokeStyle(lineWidth: 1.9 * u, lineCap: .round))
        if let age = board.deletePress { ripples.append((deleteKeyCenter, age)) }

        // Tap ripples go over all the keys.
        for ripple in ripples {
            let grow = CGFloat(Ease.outCubic(ripple.age))
            let inner = (21 + 15 * grow) * u
            ctx.stroke(Path(ellipseIn: CGRect(x: ripple.at.x - inner, y: ripple.at.y - inner + 2 * u, width: inner * 2, height: inner * 2)),
                       with: .color(Ink.hex(0x211D33, 0.3 * (1 - ripple.age))), lineWidth: (3.2 - 2.2 * grow) * u)
            let outer = (21 + 28 * grow) * u
            ctx.stroke(Path(ellipseIn: CGRect(x: ripple.at.x - outer, y: ripple.at.y - outer + 2 * u, width: outer * 2, height: outer * 2)),
                       with: .color(Ink.hex(0xFF8E72, 0.6 * (1 - ripple.age))), lineWidth: (2.2 - 1.6 * grow) * u)
        }
    }

    /// One key cap, raised, sinking when pressed. Returns where its legend goes.
    private func paintCap(_ ctx: inout GraphicsContext, center: CGPoint, width: CGFloat, look: KeyLook, press: Double?) -> CGPoint {
        let radius = keyCorner
        let depth = look.depth * u
        let sunk: CGFloat = press.map { CGFloat(sin(.pi * min($0 * 1.5, 1))) } ?? 0
        let foot = keyCap(center: center, width: width).offsetBy(dx: 0, dy: depth)
        let cap = foot.offsetBy(dx: 0, dy: -depth * (1 - 0.85 * sunk))

        ctx.fill(soft(foot.offsetBy(dx: 0, dy: 2.2 * u).insetBy(dx: -0.6 * u, dy: 0), radius), with: .color(Ink.hex(0x3C2A10, 0.2)))
        ctx.fill(soft(foot, radius), with: .color(look.side))
        ctx.fill(Path(CGRect(x: cap.minX, y: cap.midY, width: width, height: foot.midY - cap.midY)), with: .color(look.side))
        ctx.fill(soft(cap, radius), with: .linearGradient(Gradient(colors: [look.top, look.bottom]),
                                                          startPoint: CGPoint(x: 0, y: cap.minY), endPoint: CGPoint(x: 0, y: cap.maxY)))
        ctx.stroke(soft(cap.insetBy(dx: 1.3 * u, dy: 1.3 * u), radius - 1.3 * u), with: .color(look.ring), lineWidth: 1.7 * u)
        let inset = 3.8 * u
        var gloss = Path()
        gloss.move(to: CGPoint(x: cap.minX + inset, y: cap.minY + radius * 1.1))
        gloss.addQuadCurve(to: CGPoint(x: cap.minX + radius * 1.1, y: cap.minY + inset),
                           control: CGPoint(x: cap.minX + inset, y: cap.minY + inset))
        gloss.addLine(to: CGPoint(x: cap.maxX - radius * 1.2, y: cap.minY + inset))
        ctx.stroke(gloss, with: .color(Color.white.opacity(look.gloss)), style: StrokeStyle(lineWidth: 1.5 * u, lineCap: .round))
        return CGPoint(x: cap.midX, y: cap.midY + 0.2 * u)
    }

    // MARK: Solved flourish

    private static let twinkles: [(dx: Double, dy: Double, size: Double, offset: Double, kind: Int)] = [
        (-168, -34, 15, 0.00, 0), (-104, -52, 9, 0.35, 1), (-38, 40, 8, 0.62, 2),
        (30, -50, 13, 0.18, 0), (96, 36, 9, 0.80, 1), (160, -40, 16, 0.48, 0),
        (176, 18, 8, 0.10, 2), (-176, 22, 8, 0.70, 1), (-70, -8, 7, 0.90, 2), (128, -4, 7, 0.28, 2)
    ]

    private func paintFlourish(_ ctx: inout GraphicsContext) {
        let win = board.win
        if win <= 0 { return }
        let hud = layout.u
        let u = b
        let rowY = tileCenter(board.winRow, 0).y
        let cx = layout.midX

        // Confetti: paper offcuts thrown up from the solved row. A row near the top throws lower,
        // so nothing reaches the room kept for the app's buttons.
        let reach = min(max((rowY - layout.ceiling - 14 * hud) / (215 * u), 0.15), 1)
        let colors = [Ink.teal, Ink.coral, Ink.ink, Ink.mint, Ink.blush, Ink.tealHi, Ink.coralHi, Ink.cream]
        var noise = FiveUpNoise(seed: 2027)
        for k in 0..<46 {
            let x0 = noise.range(-150, 150)
            let push = (x0 >= 0 ? 1.0 : -1.0) * noise.range(10, 150)
            let vx = push + noise.range(-40, 40)
            let vy = noise.range(-430, -170)
            let delay = noise.range(0, 0.07)
            let spin = noise.range(-9, 9)
            let size = CGFloat(noise.range(4.5, 8.5)) * u
            let kind = Int(noise.next() * 3)
            let age = (win - delay) * 1.5
            if age <= 0 { continue }
            let alpha = 1 - Ease.smooth(1.05, 1.42, age)
            if alpha <= 0.01 { continue }
            let x = cx + CGFloat(x0 + vx * age) * u
            let y = rowY + CGFloat(vy * age + 215 * age * age) * u * reach
            let turn = Angle.radians(spin * age)
            let flat = CGFloat(0.35 + 0.65 * abs(cos(spin * age * 0.8 + Double(k))))

            var scrap: Path
            switch kind {
            case 0:
                scrap = Path(roundedRect: CGRect(x: -size * 0.75, y: -size * 0.42 * flat, width: size * 1.5, height: size * 0.84 * flat),
                             cornerRadius: size * 0.14)
            case 1:
                scrap = Path(ellipseIn: CGRect(x: -size * 0.48, y: -size * 0.48 * flat, width: size * 0.96, height: size * 0.96 * flat))
            default:
                scrap = Path()
                scrap.addLines([CGPoint(x: 0, y: -size * 0.62 * flat), CGPoint(x: size * 0.6, y: size * 0.46 * flat),
                                CGPoint(x: -size * 0.6, y: size * 0.46 * flat)])
                scrap.closeSubpath()
            }
            var shade = ctx
            shade.translateBy(x: x + 1.4 * u, y: y + 2.6 * u)
            shade.rotate(by: turn)
            shade.fill(scrap, with: .color(Ink.hex(0x2A1B08, 0.2 * alpha)))
            var g = ctx
            g.opacity = alpha
            g.translateBy(x: x, y: y)
            g.rotate(by: turn)
            g.fill(scrap, with: .color(colors[k % colors.count]))
            if k % colors.count == 7 { g.stroke(scrap, with: .color(Ink.ink), lineWidth: 1.1 * u) }
        }

        // Stars twinkle around the solved row. Sideways they use the screen's unit, so the outer
        // ones stay on screen; up and down they follow the rows.
        let appear = Ease.smooth(0, 0.08, win)
        for spot in Self.twinkles {
            let glow = pow(abs(sin(.pi * (win * 2.7 + spot.offset))), 1.4)
            let r = CGFloat(spot.size * (0.35 + 0.75 * glow) * appear) * hud
            if r <= 1.2 * hud { continue }
            let rim = spot.kind == 0 ? Ink.ink : (spot.kind == 1 ? Ink.coralLo : Ink.tealLo)
            var g = ctx
            g.translateBy(x: cx + CGFloat(spot.dx) * hud, y: rowY + CGFloat(spot.dy) * u)
            g.rotate(by: .radians(0.25 * sin(win * 9 + spot.offset * 6)))
            g.fill(star(CGPoint(x: 1.0 * hud, y: 1.8 * hud), radius: r + 2.4 * hud), with: .color(rim.opacity(0.9)))
            g.fill(star(.zero, radius: r + 2.0 * hud), with: .color(rim))
            g.fill(star(.zero, radius: r), with: .color(Color.white))
        }

        // The points for solving, on a chip beside the score's caption.
        guard showHUD else { return }
        let pop = Ease.outBack(win / 0.12)
        let fade = 1 - Ease.smooth(0.86, 0.98, win)
        if pop <= 0.01 || fade <= 0.01 { return }
        let caption = ctx.resolve(scoreCaption).measure(in: CGSize(width: 400 * hud, height: 40 * hud)).width
        // Wider than the clip's "+500" when the text is longer.
        let half = max(22, CGFloat(board.bonusText.count) * 4.0 + 7.5) * hud
        let rise = CGFloat(Ease.outCubic(win / 0.6)) * 8 * hud
        var g = ctx
        g.opacity = fade
        g.translateBy(x: gridRect.minX + caption + 9 * hud + half, y: layout.headerTop + 13.5 * hud - rise)
        g.rotate(by: .degrees(-4))
        g.scaleBy(x: CGFloat(pop), y: CGFloat(pop))
        let chip = CGRect(x: -half, y: -8.5 * hud, width: half * 2, height: 17 * hud)
        g.fill(pill(chip.offsetBy(dx: 0, dy: 2.2 * hud)), with: .color(Ink.tealLo))
        g.fill(pill(chip), with: .linearGradient(Gradient(colors: [Ink.tealHi, Ink.teal]),
                                                 startPoint: CGPoint(x: 0, y: chip.minY), endPoint: CGPoint(x: 0, y: chip.maxY)))
        label(&g, board.bonusText, size: 11.5 * hud, weight: .black, design: .rounded, color: Ink.cream, at: .zero)
    }
}
