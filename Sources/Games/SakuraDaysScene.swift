import SwiftUI

// Sakura Days: a short visual novel. Pick a story, read, choose, and see which ending you reach.
//
// SakuraDaysStage paints one moment from a SakuraDaysLook: the painted background, the speaker's
// portrait, petals or lanterns, the dialogue box with its typewriter text, the choices, the hearts
// and the ending card. The playable game fills a look from its model every frame; the clip in the
// video feed builds one from a phase (0...1). Backgrounds and portraits are painted pictures in
// Resources/GameArt; every word and every heart is drawn in code.

public struct SakuraDaysScene: View {
    public var phase: Double
    public var showHUD: Bool

    public init(phase: Double, showHUD: Bool) {
        self.phase = phase
        self.showHUD = showHUD
    }

    public var body: some View {
        GeometryReader { geo in
            if geo.size.width > 8, geo.size.height > 8 {
                SakuraDaysStage(look: SakuraDaysClip.look(at: phase), size: geo.size, showHUD: showHUD)
            }
        }
    }
}

// MARK: - One moment

struct SakuraDaysMeter {
    let name: String
    /// 0...10, two points to a heart.
    let value: Int
    let color: Color
    /// 1 right after a change, falling to 0.
    let pulse: Double
}

struct SakuraDaysFloater {
    /// In fractions of the screen.
    var x: Double
    var y: Double
    var age: Double
    var up: Bool
    var color: Color
}

struct SakuraDaysCard {
    let kicker: String
    let title: String
    let line: String
    let score: Int
    let age: Double
}

struct SakuraDaysLook {
    var serif = true
    var bg = ""
    var prevBg = ""
    var bgMix = 1.0
    var night = false
    var time = 0.0
    var portrait: String? = nil
    var portraitIn = 1.0
    var bounce = 0.0
    var shake = 0.0
    var blush = 0.0
    var sparkle = 0.0
    var speaker: String? = nil
    var tag = Color.pink
    var shown = ""
    var hidden = ""
    var narration = false
    var showBox = true
    var waiting = false
    var choices: [String] = []
    var choiceIn = 0.0
    var pressed: Int? = nil
    var meter: [SakuraDaysMeter] = []
    var floaters: [SakuraDaysFloater] = []
    var card: SakuraDaysCard? = nil
}

enum SakuraDaysInk {
    static let ink = Color(red: 0.20, green: 0.13, blue: 0.20)
    static let paper = Color(red: 1.0, green: 0.98, blue: 0.96)
    static let rose = Color(red: 0.93, green: 0.40, blue: 0.58)
    static let petal = Color(red: 1.0, green: 0.80, blue: 0.86)
    static let glow = Color(red: 1.0, green: 0.72, blue: 0.36)

    static func ease(_ t: Double) -> Double {
        let x = Swift.min(Swift.max(t, 0), 1)
        return 1 - (1 - x) * (1 - x) * (1 - x)
    }

    static func hearts(_ value: Int, _ k: Int) -> Double {
        Swift.min(Swift.max(Double(value - k * 2) / 2, 0), 1)
    }
}

// MARK: - The clip for covers and the Videos feed

enum SakuraDaysClip {
    private static let ask = Array("Want to try the ring toss with me? I have never landed one.")
    private static let reply = Array("I landed one. It was on the wrong peg, but I landed one.")
    private static let choices = ["Let her throw first and cheer", "Throw all the rings at once", "Wave Ren over to join"]
    private static let hana = Color(red: 0.92, green: 0.38, blue: 0.55)
    private static let ren = Color(red: 0.32, green: 0.36, blue: 0.66)

    static func look(at phase: Double) -> SakuraDaysLook {
        let p = phase - floor(phase)
        var look = SakuraDaysLook()
        look.serif = true
        look.bg = "sakura-days-shrine"
        look.night = true
        look.time = p * 8
        look.speaker = "Hana"
        look.tag = hana
        look.portraitIn = SakuraDaysInk.ease(p / 0.1) * (1 - SakuraDaysInk.ease((p - 0.95) / 0.05))

        let answered = p >= 0.76
        let text = answered ? reply : ask
        let typed = answered ? (p - 0.78) / 0.14 : (p - 0.08) / 0.34
        let count = Int(Double(text.count) * Swift.min(Swift.max(typed, 0), 1))
        look.shown = String(text[0..<count])
        look.hidden = String(text[count...])
        look.waiting = count == text.count

        look.portrait = answered ? "sakura-days-hana-happy" : "sakura-days-hana"
        if answered {
            let since = p - 0.76
            look.bounce = -sin(Swift.min(since / 0.06, 1) * .pi) * 10
            look.sparkle = Swift.max(0, 1 - since / 0.2)
        }
        if p >= 0.5 && p < 0.76 {
            look.choices = choices
            look.choiceIn = SakuraDaysInk.ease((p - 0.5) / 0.06)
            if p >= 0.68 { look.pressed = 0 }
        }
        let pulse = answered ? Swift.max(0, 1 - (p - 0.76) / 0.1) : 0
        look.meter = [
            SakuraDaysMeter(name: "Hana", value: answered ? 7 : 5, color: hana, pulse: pulse),
            SakuraDaysMeter(name: "Ren", value: 4, color: ren, pulse: 0),
        ]
        if answered && p < 0.94 {
            let age = (p - 0.76) * 8
            look.floaters = [
                SakuraDaysFloater(x: 0.42, y: 0.42, age: age, up: true, color: hana),
                SakuraDaysFloater(x: 0.58, y: 0.46, age: age - 0.15, up: true, color: hana),
                SakuraDaysFloater(x: 0.50, y: 0.38, age: age - 0.3, up: true, color: hana),
            ]
        }
        return look
    }
}

// MARK: - Painting

struct SakuraDaysHeart: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.32),
                   control1: CGPoint(x: r.midX - w * 0.12, y: r.maxY - h * 0.16),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.62))
        p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.3), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.3), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.62),
                   control2: CGPoint(x: r.midX + w * 0.12, y: r.maxY - h * 0.16))
        p.closeSubpath()
        return p
    }

    /// A heart one unit wide around the origin, kept for the canvases.
    static let unit = SakuraDaysHeart().path(in: CGRect(x: -0.5, y: -0.45, width: 1, height: 0.9))
}

struct SakuraDaysHeartIcon: View {
    let fill: Double
    let color: Color
    let side: CGFloat

    var body: some View {
        ZStack {
            SakuraDaysHeart().fill(Color.black.opacity(0.16))
            SakuraDaysHeart().fill(color)
                .mask(alignment: .leading) { Rectangle().frame(width: side * fill) }
        }
        .frame(width: side, height: side * 0.9)
    }
}

/// Petals by day, rising lantern glows by night. Every drift loops in 8 seconds, so the clip loops too.
struct SakuraDaysParticles: View {
    let time: Double
    let night: Bool

    private struct Seed {
        let x: Double, y: Double, laps: Double, sway: Double, turn: Double, size: Double
    }

    private static let seeds: [Seed] = (0..<26).map { i in
        func hash(_ k: Double) -> Double {
            let s = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
            return s - floor(s)
        }
        return Seed(x: hash(1), y: hash(2), laps: Double(1 + i % 2), sway: Double(1 + i % 3),
                    turn: hash(3), size: 0.6 + hash(4) * 0.8)
    }

    private static let petal = Path(ellipseIn: CGRect(x: -1, y: -0.55, width: 2, height: 1.1))
    private static let dot = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let u = size.width / 393
            let loop = time / 8
            for seed in Self.seeds {
                let f = loop * seed.laps + seed.y
                let fy = f - floor(f)
                let wave = sin((loop * seed.sway + seed.turn) * 2 * .pi)
                var c = context
                if night {
                    let x = seed.x * size.width + wave * 10 * u
                    let y = size.height * (1.05 - fy * 1.1)
                    let r = (3 + seed.size * 4) * u
                    let fade = Swift.min(fy * 4, 1) * Swift.min((1 - fy) * 3, 1)
                    c.translateBy(x: x, y: y)
                    c.scaleBy(x: r * 2.4, y: r * 2.4)
                    c.fill(Self.dot, with: .color(SakuraDaysInk.glow.opacity(0.18 * fade)))
                    c.scaleBy(x: 1 / 2.4, y: 1 / 2.4)
                    c.fill(Self.dot, with: .color(SakuraDaysInk.glow.opacity(0.75 * fade)))
                } else {
                    let across = seed.x + fy * 0.25
                    let x = (across - floor(across)) * (size.width + 40 * u) - 20 * u + wave * 18 * u
                    let y = fy * (size.height + 40 * u) - 20 * u
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(wave * 1.2 + seed.turn * 6))
                    c.scaleBy(x: 5 * seed.size * u, y: 5 * seed.size * u)
                    c.fill(Self.petal, with: .color(SakuraDaysInk.petal.opacity(0.9)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Hearts that float up when affection rises and sink when it falls.
struct SakuraDaysFloaters: View {
    let floaters: [SakuraDaysFloater]

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let u = size.width / 393
            for f in floaters where f.age >= 0 && f.age < 1.2 {
                let t = f.age / 1.2
                let fade = Swift.min(f.age * 6, 1) * (1 - t)
                let x = f.x * size.width + sin(f.age * 7) * 8 * u
                let y = f.y * size.height + (f.up ? -1 : 1) * t * 120 * u
                let side = (f.up ? 30 : 22) * u * (0.7 + 0.3 * Swift.min(f.age * 5, 1))
                var c = context
                c.translateBy(x: x, y: y)
                c.scaleBy(x: side, y: side)
                c.fill(SakuraDaysHeart.unit, with: .color(.white.opacity(0.9 * fade)))
                c.scaleBy(x: 0.8, y: 0.8)
                c.fill(SakuraDaysHeart.unit, with: .color((f.up ? f.color : Color.gray).opacity(fade)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Little marks beside the head: sparkles when happy, blush lines when flustered.
struct SakuraDaysEmote: View {
    let sparkle: Double
    let blush: Double
    let time: Double

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let u = size.height / 520
            let head = CGPoint(x: size.width * 0.5, y: size.height * 0.17)
            if blush > 0 {
                let a = blush * (0.75 + 0.25 * sin(time * 9))
                for k in 0..<3 {
                    let x = head.x + 72 * u + Double(k) * 9 * u
                    let y = head.y - 30 * u + Double(k) * 3 * u
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: y))
                    line.addLine(to: CGPoint(x: x + 7 * u, y: y - 13 * u))
                    context.stroke(line, with: .color(SakuraDaysInk.rose.opacity(a)),
                                   style: StrokeStyle(lineWidth: 3.2 * u, lineCap: .round))
                }
            }
            if sparkle > 0 {
                for k in 0..<4 {
                    let angle = Double(k) * 1.7 + 0.4
                    let x = head.x + cos(angle) * 95 * u
                    let y = head.y - 10 * u + sin(angle) * 55 * u
                    let r = (7 + 4 * sin(time * 8 + Double(k))) * u * sparkle
                    var star = Path()
                    star.move(to: CGPoint(x: x, y: y - r))
                    star.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y))
                    star.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x, y: y))
                    context.fill(star, with: .color(Color.white.opacity(sparkle)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SakuraDaysStage: View {
    let look: SakuraDaysLook
    let size: CGSize
    let showHUD: Bool
    var onTap: (() -> Void)? = nil
    var onChoose: ((Int) -> Void)? = nil

    private var u: CGFloat { size.width / 393 }
    private var boxHeight: CGFloat { 136 * u }
    private var boxTop: CGFloat { size.height - GameLayout.bottomInset * u - boxHeight }

    private func font(_ points: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: points * u, weight: weight, design: look.serif ? .serif : .rounded)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            SakuraDaysParticles(time: look.time, night: look.night)
            portrait
            LinearGradient(colors: [.clear, Color.black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .frame(width: size.width, height: size.height * 0.4)
                .offset(y: size.height * 0.6)
                .allowsHitTesting(false)
            if let card = look.card {
                cardView(card)
            } else {
                if !look.choices.isEmpty { choiceStack }
                if look.showBox { dialogue }
            }
            if showHUD && !look.meter.isEmpty && look.card == nil { meter }
            SakuraDaysFloaters(floaters: look.floaters)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .allowsHitTesting(onTap != nil)
    }

    private var backdrop: some View {
        ZStack {
            if !look.prevBg.isEmpty && look.bgMix < 1 {
                Image(look.prevBg).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
            }
            if !look.bg.isEmpty {
                Image(look.bg).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
                    .opacity(look.bgMix)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color(red: 0.98, green: 0.86, blue: 0.90))
        .allowsHitTesting(false)
    }

    @ViewBuilder private var portrait: some View {
        if let name = look.portrait {
            let height = Swift.min(size.height * 0.62, size.width * 1.45)
            let slide = (1 - look.portraitIn) * 60 * u
            ZStack {
                Image(name).resizable().scaledToFit()
                    .frame(width: size.width, height: height, alignment: .bottom)
                SakuraDaysEmote(sparkle: look.sparkle, blush: look.blush, time: look.time)
                    .frame(width: height * 0.66, height: height)
            }
            .frame(width: size.width, height: height)
            .offset(x: slide + look.shake * u, y: boxTop + boxHeight * 0.4 - height + look.bounce * u)
            .opacity(look.portraitIn)
            .allowsHitTesting(false)
        }
    }

    private var dialogue: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
                .fill(SakuraDaysInk.paper.opacity(0.94))
            RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
                .strokeBorder(look.narration ? Color.white.opacity(0.7) : look.tag.opacity(0.8), lineWidth: 2.5 * u)
            (Text(look.shown).foregroundStyle(SakuraDaysInk.ink) + Text(look.hidden).foregroundStyle(Color.clear))
                .font(look.narration ? font(17).italic() : font(18, .medium))
                .lineSpacing(4 * u)
                .padding(.horizontal, 20 * u)
                .padding(.top, 26 * u)
                .frame(width: size.width - 28 * u, alignment: .leading)
            if look.waiting {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 11 * u))
                    .foregroundStyle(look.narration ? SakuraDaysInk.rose : look.tag)
                    .opacity(0.5 + 0.5 * sin(look.time * 6))
                    .offset(x: size.width - 58 * u, y: boxHeight - 24 * u + sin(look.time * 6) * 2 * u)
            }
        }
        .frame(width: size.width - 28 * u, height: boxHeight)
        .overlay(alignment: .topLeading) {
            if let name = look.speaker, !look.narration {
                Text(name)
                    .font(font(16, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16 * u)
                    .padding(.vertical, 6 * u)
                    .background(Capsule().fill(look.tag))
                    .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2 * u))
                    .offset(x: 18 * u, y: -16 * u)
            }
        }
        .offset(x: 14 * u, y: boxTop)
    }

    private var choiceStack: some View {
        VStack(spacing: 11 * u) {
            ForEach(look.choices.indices, id: \.self) { i in
                choiceButton(i)
            }
        }
        .frame(width: size.width * 0.86)
        .frame(width: size.width, height: boxTop - 18 * u, alignment: .bottom)
        .opacity(look.choiceIn)
        .offset(y: (1 - look.choiceIn) * 16 * u)
    }

    private func choiceButton(_ i: Int) -> some View {
        let picked = look.pressed == i
        let dim = look.pressed != nil && !picked
        return Button {
            onChoose?(i)
        } label: {
            HStack(spacing: 10 * u) {
                SakuraDaysHeartIcon(fill: picked ? 1 : 0, color: .white, side: 15 * u)
                Text(look.choices[i])
                    .font(font(16, .semibold))
                    .foregroundStyle(picked ? Color.white : SakuraDaysInk.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18 * u)
            .padding(.vertical, 13 * u)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16 * u, style: .continuous)
                    .fill(picked ? look.tag : SakuraDaysInk.paper.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16 * u, style: .continuous)
                    .strokeBorder(look.tag.opacity(picked ? 0 : 0.7), lineWidth: 2 * u)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 6 * u, y: 3 * u)
        }
        .buttonStyle(.plain)
        .scaleEffect(picked ? 1.04 : 1)
        .opacity(dim ? 0.45 : 1)
        .disabled(look.pressed != nil || onChoose == nil)
    }

    private func hearts(_ m: SakuraDaysMeter, side: CGFloat, nameWidth: CGFloat, nameSize: CGFloat) -> some View {
        HStack(spacing: 4 * u) {
            Text(m.name)
                .font(font(nameSize, .bold))
                .foregroundStyle(m.color)
                .frame(width: nameWidth, alignment: .leading)
            ForEach(0..<5, id: \.self) { k in
                SakuraDaysHeartIcon(fill: SakuraDaysInk.hearts(m.value, k), color: m.color, side: side)
            }
        }
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 6 * u) {
            ForEach(look.meter.indices, id: \.self) { i in
                hearts(look.meter[i], side: 15 * u, nameWidth: 46 * u, nameSize: 12)
                    .padding(.horizontal, 10 * u)
                    .padding(.vertical, 5 * u)
                    .background(Capsule().fill(Color.white.opacity(0.88)))
                    .scaleEffect(1 + 0.12 * look.meter[i].pulse, anchor: .leading)
            }
        }
        .offset(x: 14 * u, y: GameLayout.topBand * u + 4 * u)
        .allowsHitTesting(false)
    }

    private func cardView(_ card: SakuraDaysCard) -> some View {
        let show = SakuraDaysInk.ease(card.age / 0.5)
        return ZStack {
            Color.black.opacity(0.35 * show)
            VStack(spacing: 12 * u) {
                Text(card.kicker)
                    .font(font(13, .bold))
                    .tracking(3 * u)
                    .foregroundStyle(SakuraDaysInk.rose)
                Text(card.title)
                    .font(font(30, .bold))
                    .foregroundStyle(SakuraDaysInk.ink)
                    .multilineTextAlignment(.center)
                Text(card.line)
                    .font(font(16))
                    .foregroundStyle(SakuraDaysInk.ink.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8 * u) {
                    ForEach(look.meter.indices, id: \.self) { i in
                        hearts(look.meter[i], side: 20 * u, nameWidth: 56 * u, nameSize: 14)
                    }
                }
                .padding(.vertical, 6 * u)
                Text("\(card.score) points")
                    .font(font(24, .heavy))
                    .foregroundStyle(SakuraDaysInk.rose)
                Text("Tap to finish")
                    .font(font(14, .semibold))
                    .foregroundStyle(SakuraDaysInk.ink.opacity(0.55))
                    .opacity(card.age > 1.2 ? 0.6 + 0.4 * sin(look.time * 4) : 0)
            }
            .padding(.horizontal, 24 * u)
            .padding(.vertical, 26 * u)
            .frame(width: size.width * 0.84)
            .background(
                RoundedRectangle(cornerRadius: 26 * u, style: .continuous)
                    .fill(SakuraDaysInk.paper.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26 * u, style: .continuous)
                    .strokeBorder(SakuraDaysInk.rose.opacity(0.6), lineWidth: 2.5 * u)
            )
            .scaleEffect(0.9 + 0.1 * show)
            .opacity(show)
        }
        .frame(width: size.width, height: size.height)
    }
}
