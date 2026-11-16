import SwiftUI

// Sakura Days, playable.
//
// SakuraDaysStories  the two stories: Old Kyoto and Campus, their cast, lines, choices and endings.
// SakuraDaysModel    the rules in plain Swift: where the reader is, the typing, affection, the ending.
// SakuraDaysRunner   keeps the clock, plays the scripted reader, fires haptics, reports the result.
// SakuraDaysPicker   the opening screen where the player picks a story.
// SakuraDaysGame     the view the app shows.

// MARK: - Stories

enum SakuraDaysMood: Int {
    case neutral, happy, flustered
}

struct SakuraDaysCast {
    let name: String
    let color: Color
    /// Portrait names by mood.
    let images: [String]

    init(_ name: String, art: String, color: Color) {
        self.name = name
        self.color = color
        images = ["sakura-days-\(art)", "sakura-days-\(art)-happy", "sakura-days-\(art)-flustered"]
    }
}

struct SakuraDaysLine {
    /// -1 is the narrator, otherwise an index into the cast.
    let who: Int
    let mood: SakuraDaysMood
    let text: String
}

struct SakuraDaysOption {
    let text: String
    /// Affection change for each member of the cast.
    let delta: [Int]
    /// Set on the last choice: the cast member the player spends the night with, -1 for nobody.
    var path: Int? = nil
    let reply: [SakuraDaysLine]
}

enum SakuraDaysBeat {
    case place(String)
    case line(SakuraDaysLine)
    case choice([SakuraDaysOption])
}

enum SakuraDaysEndingKind {
    case good, sweet, comic
}

struct SakuraDaysEnding {
    let kind: SakuraDaysEndingKind
    let title: String
    let line: String
    let lines: [SakuraDaysLine]
}

struct SakuraDaysStory {
    let title: String
    let blurb: String
    let serif: Bool
    let cast: [SakuraDaysCast]
    let beats: [SakuraDaysBeat]
    let finale: String
    let good: [SakuraDaysEnding]
    let sweet: [SakuraDaysEnding]
    let comic: SakuraDaysEnding
    /// Affection with the chosen partner needed for the good ending.
    let goodAt: Int
}

private func say(_ who: Int, _ mood: SakuraDaysMood, _ text: String) -> SakuraDaysLine {
    SakuraDaysLine(who: who, mood: mood, text: text)
}

private func beat(_ who: Int, _ mood: SakuraDaysMood, _ text: String) -> SakuraDaysBeat {
    .line(SakuraDaysLine(who: who, mood: mood, text: text))
}

private func option(_ text: String, _ delta: [Int], path: Int? = nil, _ reply: SakuraDaysLine...) -> SakuraDaysOption {
    SakuraDaysOption(text: text, delta: delta, path: path, reply: reply)
}

enum SakuraDaysStories {
    static let nightPlaces: Set<String> = ["sakura-days-shrine", "sakura-days-bridge"]

    static let all: [SakuraDaysStory] = [kyoto, campus]

    private static let n = -1

    static let kyoto: SakuraDaysStory = {
        let hana = 0, ren = 1
        return SakuraDaysStory(
            title: "Old Kyoto",
            blurb: "Tea, lanterns and one very dramatic swordsman.",
            serif: true,
            cast: [
                SakuraDaysCast("Hana", art: "hana", color: Color(red: 0.92, green: 0.38, blue: 0.55)),
                SakuraDaysCast("Ren", art: "ren", color: Color(red: 0.32, green: 0.36, blue: 0.66)),
            ],
            beats: [
                .place("sakura-days-street"),
                beat(n, .neutral, "Kyoto, in spring. You arrive with one bag and no plan at all."),
                beat(n, .neutral, "A wooden sword clatters onto the stones in front of you."),
                beat(ren, .neutral, "Halt, traveller. This road is guarded by Ren of the Nameless Blade."),
                beat(ren, .flustered, "Could you pass me the blade, please? It slipped."),
                .choice([
                    option("Hand it over with a polite bow", [0, 2],
                           say(ren, .happy, "A true warrior's manners. I will remember your face. Probably.")),
                    option("Ask why the blade has no name", [0, 1],
                           say(ren, .flustered, "I have not thought of a good one yet. Please stop smiling like that.")),
                    option("Step over it and keep walking", [0, -1],
                           say(ren, .flustered, "Wait. The guarding part was the best part.")),
                ]),
                .place("sakura-days-teahouse"),
                beat(n, .neutral, "Rain chases you into a small teahouse with a crooked sign."),
                beat(hana, .neutral, "Welcome to the Sakura teahouse. Sit anywhere that is not dripping."),
                beat(hana, .happy, "We have green tea, roasted tea, and a sweet I invented this morning."),
                .choice([
                    option("The new sweet, please", [2, 0],
                           say(hana, .happy, "Brave. It is red bean, plum, and a little bit of hope.")),
                    option("Plain green tea", [1, 0],
                           say(hana, .happy, "A classic. My grandmother would like you.")),
                    option("Whatever is fastest", [-1, 0],
                           say(hana, .flustered, "Tea is not a race. Please breathe. I will bring it slowly.")),
                ]),
                beat(ren, .neutral, "Hana. Three dango, and tell no one I was here."),
                beat(hana, .happy, "He says that every day. Everyone always knows he is here."),
                beat(hana, .neutral, "So, are you in town for the lantern festival tonight?"),
                .choice([
                    option("I came to see the lanterns", [1, 1],
                           say(hana, .happy, "Then you picked the best night of the year.")),
                    option("I came to find myself", [0, 2],
                           say(ren, .happy, "Same. I have been looking for three years. Nothing yet.")),
                    option("Honestly, for the snacks", [2, 0],
                           say(hana, .happy, "An honest guest. I will pack you extra for the road.")),
                ]),
                .place("sakura-days-street"),
                beat(n, .neutral, "Later, a fat orange cat trots past with Ren's dango in its mouth."),
                beat(ren, .flustered, "Thief. Stop. That was my lunch and also my dinner."),
                .choice([
                    option("Chase the cat with Ren", [0, 2],
                           say(ren, .happy, "Together we are unstoppable. The cat disagrees, but still.")),
                    option("Buy Ren new dango", [1, 1],
                           say(ren, .flustered, "You would do that? For a stranger with a wooden sword?"),
                           say(hana, .happy, "Three more dango. He will pay me back in about ten years.")),
                    option("Cheer for the cat", [0, -1],
                           say(ren, .flustered, "Whose side are you on?")),
                ]),
                .place("sakura-days-shrine"),
                beat(n, .neutral, "Evening. The shrine glows with a thousand paper lanterns."),
                beat(hana, .happy, "I am working the tea stall tonight, but I have a short break."),
                beat(hana, .neutral, "Want to try the ring toss with me? I have never landed one."),
                .choice([
                    option("Let her throw first and cheer", [2, 0],
                           say(hana, .happy, "I landed one. It was on the wrong peg, but I landed one.")),
                    option("Throw all the rings at once", [-1, 0],
                           say(hana, .flustered, "You hit the stall keeper. Twice. We should go.")),
                    option("Wave Ren over to join", [1, 1],
                           say(ren, .happy, "A worthy challenge. I accept."),
                           say(n, .neutral, "He misses every single ring with great dignity.")),
                ]),
                beat(ren, .neutral, "The fireworks start soon. I know a bridge with the best view in Kyoto."),
                beat(hana, .flustered, "Oh. I was going to show them that bridge."),
                beat(n, .neutral, "They both look at you. The lanterns sway. Somewhere, a drum starts."),
                .choice([
                    option("Go with Hana", [3, 0], path: hana,
                           say(hana, .happy, "Then hurry. I know a shortcut past the noodle stall.")),
                    option("Go with Ren", [0, 3], path: ren,
                           say(ren, .happy, "Follow me. Stay close. Mind my sleeves, they are very long.")),
                    option("Get in line for noodles", [-1, -1], path: -1,
                           say(n, .neutral, "The noodle line is long. The noodles smell amazing. You stay.")),
                ]),
            ],
            finale: "sakura-days-bridge",
            good: [
                SakuraDaysEnding(kind: .good, title: "Lantern Promise", line: "Hana asked you to come back next spring.", lines: [
                    say(n, .neutral, "Fireworks bloom over the river, gold and pink."),
                    say(hana, .happy, "Come back next spring. I will invent a sweet just for you."),
                    say(hana, .flustered, "I already have a name for it. Do not ask. It is embarrassing."),
                ]),
                SakuraDaysEnding(kind: .good, title: "The Named Blade", line: "Ren finally named his sword.", lines: [
                    say(n, .neutral, "Fireworks bloom over the river, gold and pink."),
                    say(ren, .flustered, "I have decided. My blade is named after you."),
                    say(ren, .happy, "It is a wooden sword, so it is mostly an honour."),
                ]),
            ],
            sweet: [
                SakuraDaysEnding(kind: .sweet, title: "Next Spring", line: "A nice night with Hana. Maybe more next year.", lines: [
                    say(n, .neutral, "You watch the fireworks with Hana, side by side."),
                    say(hana, .happy, "That was nice. Maybe next year it can be more than nice."),
                ]),
                SakuraDaysEnding(kind: .sweet, title: "Sword Buddies", line: "Ren thinks you are a fine companion.", lines: [
                    say(n, .neutral, "You watch the fireworks with Ren, side by side."),
                    say(ren, .happy, "You are a fine companion. Like a dango with legs."),
                ]),
            ],
            comic: SakuraDaysEnding(kind: .comic, title: "Noodle Ending", line: "The noodles were excellent, at least.", lines: [
                say(n, .neutral, "By the time you get your noodles, the fireworks are over."),
                say(n, .neutral, "Across the river, Hana and Ren wave. You wave back with a noodle."),
                say(ren, .happy, "Save us some next year?"),
            ]),
            goodAt: 7)
    }()

    static let campus: SakuraDaysStory = {
        let mei = 0, kaito = 1
        return SakuraDaysStory(
            title: "Campus",
            blurb: "Paint, coffee and a rooftop festival.",
            serif: false,
            cast: [
                SakuraDaysCast("Mei", art: "mei", color: Color(red: 0.93, green: 0.52, blue: 0.22)),
                SakuraDaysCast("Kaito", art: "kaito", color: Color(red: 0.18, green: 0.48, blue: 0.58)),
            ],
            beats: [
                .place("sakura-days-campus"),
                beat(n, .neutral, "First week at Sakura University. You are already lost."),
                beat(n, .neutral, "Someone runs into you. A jar of blue paint goes everywhere."),
                beat(mei, .flustered, "Sorry, sorry. That blue looks great on your shirt, though."),
                .choice([
                    option("Laugh it off", [2, 0],
                           say(mei, .happy, "A good sport. I am Mei. I owe you one shirt.")),
                    option("Say it is modern art now", [1, 0],
                           say(mei, .happy, "Finally, someone who gets it.")),
                    option("Sigh very loudly", [-1, 0],
                           say(mei, .flustered, "I will pay you back. In snacks. Probably.")),
                ]),
                .place("sakura-days-library"),
                beat(n, .neutral, "You hide in the library to find your class list."),
                beat(kaito, .neutral, "This is a quiet zone. Your shirt is very loud."),
                beat(kaito, .neutral, "Do you need help finding something?"),
                .choice([
                    option("The best study spot", [0, 2],
                           say(kaito, .happy, "Third floor, by the big clock. Nobody knows. Now you do.")),
                    option("Ask what he is reading", [0, 1],
                           say(kaito, .flustered, "A cookbook for people who only own a kettle. It is research.")),
                    option("Ask where the snacks are", [0, 0],
                           say(kaito, .neutral, "No snacks in the library. I have six in my bag, for emergencies.")),
                ]),
                .place("sakura-days-studio"),
                beat(n, .neutral, "That afternoon, Mei pulls you into the art club room."),
                beat(mei, .happy, "We need a model for the spring painting. You have a great face for it."),
                beat(mei, .neutral, "Just sit still for ten minutes. Maybe an hour. Maybe two."),
                .choice([
                    option("Strike a heroic pose", [2, 0],
                           say(mei, .happy, "Yes. Hold it. Look into the future.")),
                    option("Offer to paint her instead", [1, 0],
                           say(mei, .flustered, "Me? Nobody asks that. Okay, but paint my good side.")),
                    option("Fall asleep in the chair", [0, 0],
                           say(mei, .flustered, "I painted you asleep. It is my best work. Please do not be mad.")),
                ]),
                .place("sakura-days-library"),
                beat(n, .neutral, "Evening. You return a book and find Kaito asleep on a pile of essays."),
                beat(kaito, .flustered, "I was not asleep. I was resting my glasses."),
                .choice([
                    option("Bring him a coffee", [0, 2],
                           say(kaito, .happy, "Black, two sugars. How did you know? That is a little scary.")),
                    option("Help sort the essays", [0, 1],
                           say(kaito, .happy, "You sorted them by colour. That is wrong. It does look nice.")),
                    option("Take a photo", [0, -1],
                           say(kaito, .flustered, "Delete that. Or at least send it to me.")),
                ]),
                .place("sakura-days-rooftop"),
                beat(n, .neutral, "Friday. The campus festival ends with fireworks seen from the roof."),
                beat(mei, .happy, "Kaito and I are on the roof crew. Come help us hang the lights."),
                beat(kaito, .neutral, "She means I hang the lights and she points."),
                .choice([
                    option("Help Mei plan the lights", [2, 0],
                           say(mei, .happy, "A heart shape. No, a cat. No, a cat holding a heart.")),
                    option("Hold the ladder for Kaito", [0, 2],
                           say(kaito, .happy, "Thank you. You are the first person to hold it still.")),
                    option("Hang them all upside down", [1, 1],
                           say(n, .neutral, "Somehow, it looks better."),
                           say(mei, .happy, "We are leaving it like that.")),
                ]),
                beat(n, .neutral, "The sky turns pink. The first firework goes up."),
                beat(mei, .flustered, "Hey. Want to watch from the good corner with me?"),
                beat(kaito, .flustered, "I saved two seats. By accident. One is free."),
                .choice([
                    option("The good corner with Mei", [3, 0], path: mei,
                           say(mei, .happy, "Come on, before Kaito takes it.")),
                    option("The free seat by Kaito", [0, 3], path: kaito,
                           say(kaito, .happy, "Oh. Good. I mean, okay. Sit.")),
                    option("Run down for festival crepes", [-1, -1], path: -1,
                           say(n, .neutral, "You will be quick. You are sure of it.")),
                ]),
            ],
            finale: "sakura-days-rooftop",
            good: [
                SakuraDaysEnding(kind: .good, title: "Spring Painting", line: "Mei is painting you for the spring show.", lines: [
                    say(n, .neutral, "The sky fills with colour, like paint on a wet page."),
                    say(mei, .happy, "I know what the spring painting is now. It is you, up here, tonight."),
                    say(mei, .flustered, "Do not look at it too long when it is done. I will get shy."),
                ]),
                SakuraDaysEnding(kind: .good, title: "Third Floor Clock", line: "Kaito asked you to study with him.", lines: [
                    say(n, .neutral, "The sky fills with colour over the city."),
                    say(kaito, .flustered, "Monday. Third floor, by the clock. I will bring two coffees."),
                    say(kaito, .happy, "That was a question. I am bad at questions."),
                ]),
            ],
            sweet: [
                SakuraDaysEnding(kind: .sweet, title: "Paint Pals", line: "A good night with Mei. Same time next year.", lines: [
                    say(n, .neutral, "You watch the fireworks with Mei."),
                    say(mei, .happy, "Same time next year? I am holding you to it."),
                ]),
                SakuraDaysEnding(kind: .sweet, title: "Study Buddies", line: "Kaito liked it more than his essays.", lines: [
                    say(n, .neutral, "You watch the fireworks with Kaito."),
                    say(kaito, .happy, "This was nice. Better than essays. Do not tell the essays."),
                ]),
            ],
            comic: SakuraDaysEnding(kind: .comic, title: "Crepe Ending", line: "Three crepes, zero fireworks.", lines: [
                say(n, .neutral, "You come back with three crepes. The fireworks ended four minutes ago."),
                say(n, .neutral, "Mei and Kaito are asleep on the bench."),
                say(mei, .happy, "We saved you a sparkler. It is a little bent."),
            ]),
            goodAt: 6)
    }()
}

// MARK: - Model

enum SakuraDaysStep {
    case pick, story, card, done
}

enum SakuraDaysEvent {
    case advance, choose, up, down, end
}

final class SakuraDaysModel {
    static let typeSpeed = 46.0
    static let pressTime = 0.4

    private(set) var stage = SakuraDaysStep.pick
    private(set) var storyIndex = 0
    private(set) var affection: [Int] = [0, 0]
    private(set) var time = 0.0
    private(set) var ending: SakuraDaysEnding?
    private(set) var feedback: [SakuraDaysEvent] = []

    private var pos = 0
    private var pending: [SakuraDaysLine] = []
    private var path: Int?

    private var bg = ""
    private var prevBg = ""
    private var bgAge = 9.0
    private var line: SakuraDaysLine?
    private var chars: [Character] = []
    private var typed = 0.0
    private var shownCount = -1
    private var shown = ""
    private var hidden = ""
    private var portraitWho = -1
    private var portraitAge = 9.0
    private var moodAge = 9.0
    private var mood = SakuraDaysMood.neutral
    private(set) var choices: [SakuraDaysOption] = []
    private var choiceTexts: [String] = []
    private var choiceAge = 0.0
    private(set) var pressed: Int?
    private var pressAge = 0.0
    private var lineAge = 0.0
    private var pulse: [Double] = [0, 0]
    private var floaters: [SakuraDaysFloater] = []
    private var cardAge = 0.0

    var story: SakuraDaysStory { SakuraDaysStories.all[storyIndex] }
    var lineDone: Bool { typed >= Double(chars.count) }
    var waitingForChoice: Bool { !choices.isEmpty && pressed == nil }
    /// Seconds the current line has been fully shown, or the choices have been up.
    var idle: Double { stage == .card ? cardAge : (waitingForChoice ? choiceAge : (lineDone ? lineAge : 0)) }

    func clearFeedback() { feedback.removeAll(keepingCapacity: true) }

    func pick(_ index: Int) {
        guard stage == .pick else { return }
        storyIndex = index
        affection = Array(repeating: 0, count: story.cast.count)
        pulse = Array(repeating: 0, count: story.cast.count)
        stage = .story
        feedback.append(.advance)
        next()
    }

    /// A tap anywhere: finish the typing, or move on.
    func tap() {
        switch stage {
        case .pick, .done:
            return
        case .card:
            if cardAge > 1.0 {
                stage = .done
                feedback.append(.end)
            }
        case .story:
            if !choices.isEmpty { return }
            if !lineDone {
                typed = Double(chars.count)
                return
            }
            feedback.append(.advance)
            next()
        }
    }

    func choose(_ index: Int) {
        guard stage == .story, pressed == nil, choices.indices.contains(index), lineDone else { return }
        pressed = index
        pressAge = 0
        feedback.append(.choose)
    }

    func step(dt: Double) {
        time += dt
        bgAge += dt
        portraitAge += dt
        moodAge += dt
        choiceAge += dt
        for i in pulse.indices { pulse[i] = Swift.max(0, pulse[i] - dt * 2.5) }
        for i in floaters.indices { floaters[i].age += dt }
        if floaters.count > 0, floaters.allSatisfy({ $0.age > 1.3 }) { floaters.removeAll(keepingCapacity: true) }
        switch stage {
        case .story:
            if !lineDone {
                typed = Swift.min(typed + dt * Self.typeSpeed, Double(chars.count))
            } else {
                lineAge += dt
            }
            if let index = pressed {
                pressAge += dt
                if pressAge >= Self.pressTime { apply(choices[index]) }
            }
        case .card:
            cardAge += dt
        default:
            break
        }
    }

    private func apply(_ option: SakuraDaysOption) {
        for (i, d) in option.delta.enumerated() where d != 0 && affection.indices.contains(i) {
            affection[i] = Swift.max(0, Swift.min(10, affection[i] + d))
            pulse[i] = 1
            let color = story.cast[i].color
            let count = d > 0 ? d + 1 : 1
            for k in 0..<count {
                floaters.append(SakuraDaysFloater(x: 0.36 + 0.28 * Double(k) / Double(Swift.max(count - 1, 1)),
                                                  y: d > 0 ? 0.42 : 0.3, age: -0.12 * Double(k), up: d > 0, color: color))
            }
            feedback.append(d > 0 ? .up : .down)
        }
        if let p = option.path { path = p }
        pending.append(contentsOf: option.reply)
        choices = []
        choiceTexts = []
        pressed = nil
        next()
    }

    private func next() {
        while true {
            if !pending.isEmpty {
                show(pending.removeFirst())
                return
            }
            if ending != nil {
                stage = .card
                cardAge = 0
                feedback.append(.end)
                return
            }
            if pos >= story.beats.count {
                let chosen = pickEnding()
                ending = chosen
                place(story.finale)
                pending = chosen.lines
                continue
            }
            let item = story.beats[pos]
            pos += 1
            switch item {
            case .place(let name):
                place(name)
            case .line(let l):
                show(l)
                return
            case .choice(let options):
                choices = options
                choiceTexts = options.map(\.text)
                choiceAge = 0
                return
            }
        }
    }

    private func pickEnding() -> SakuraDaysEnding {
        let partner = path ?? (affection.indices.max { affection[$0] < affection[$1] } ?? 0)
        if partner < 0 { return story.comic }
        return affection[partner] >= story.goodAt ? story.good[partner] : story.sweet[partner]
    }

    private func place(_ name: String) {
        guard name != bg else { return }
        prevBg = bg
        bg = name
        bgAge = 0
        portraitWho = -1
    }

    private func show(_ next: SakuraDaysLine) {
        if next.who >= 0 {
            if next.who != portraitWho {
                portraitWho = next.who
                portraitAge = 0
                moodAge = 9
            } else if next.mood != mood {
                moodAge = 0
            }
            mood = next.mood
        }
        line = next
        chars = Array(next.text)
        typed = 0
        lineAge = 0
        shownCount = -1
    }

    var score: Int {
        let hearts = affection.reduce(0, +) * 20
        switch ending?.kind {
        case .good: return hearts + 300
        case .sweet: return hearts + 150
        case .comic: return hearts + 60
        case nil: return hearts
        }
    }

    var result: GameResult {
        let title = ending?.title ?? "Sakura Days"
        return GameResult(score: score, unit: "points", detail: "Reached the \(title) ending in \(story.title).")
    }

    /// The picture for this moment.
    func look() -> SakuraDaysLook {
        var look = SakuraDaysLook()
        let story = self.story
        look.serif = story.serif
        look.time = time
        look.bg = bg
        look.prevBg = prevBg
        look.bgMix = SakuraDaysInk.ease(bgAge / 0.6)
        look.night = SakuraDaysStories.nightPlaces.contains(bg)
        look.meter = affection.indices.map {
            SakuraDaysMeter(name: story.cast[$0].name, value: affection[$0], color: story.cast[$0].color, pulse: pulse[$0])
        }
        look.floaters = floaters

        if portraitWho >= 0 {
            let cast = story.cast[portraitWho]
            look.portrait = cast.images[mood.rawValue]
            look.portraitIn = SakuraDaysInk.ease(portraitAge / 0.35)
            if moodAge < 0.5 {
                if mood == .happy { look.bounce = -sin(Swift.min(moodAge / 0.3, 1) * .pi) * 12 }
                if mood == .flustered { look.shake = sin(moodAge * 50) * 5 * (1 - moodAge / 0.5) }
            }
            if mood == .flustered { look.blush = 1 }
            if mood == .happy { look.sparkle = Swift.max(0, 1 - moodAge / 1.2) }
        }

        if let line {
            let count = Int(typed)
            if count != shownCount {
                shownCount = count
                shown = String(chars[0..<count])
                hidden = String(chars[count...])
            }
            look.shown = shown
            look.hidden = hidden
            look.narration = line.who < 0
            if line.who >= 0 {
                look.speaker = story.cast[line.who].name
                look.tag = story.cast[line.who].color
            }
            look.waiting = lineDone && choices.isEmpty
        } else {
            look.showBox = false
        }

        look.choices = choiceTexts
        look.choiceIn = choices.isEmpty ? 0 : SakuraDaysInk.ease(choiceAge / 0.3)
        look.pressed = pressed
        if !choices.isEmpty, let line, line.who >= 0 { look.tag = story.cast[line.who].color }
        if !choices.isEmpty, line?.who ?? -1 < 0 { look.tag = SakuraDaysInk.rose }

        if stage == .card || stage == .done, let ending {
            let kicker: String
            switch ending.kind {
            case .good: kicker = "TRUE ENDING"
            case .sweet: kicker = "SWEET ENDING"
            case .comic: kicker = "SILLY ENDING"
            }
            look.card = SakuraDaysCard(kicker: kicker, title: ending.title, line: ending.line, score: score, age: cardAge)
        }
        return look
    }
}

// MARK: - Runner

/// Holds the round between frames. Nothing is published: the timeline repaints every frame anyway.
final class SakuraDaysRunner: ObservableObject {
    let model = SakuraDaysModel()
    private let seed: UInt64
    private var lastDate: Date?
    private var frame = 0
    private var reported = false

    init(options: GameOptions) {
        seed = options.seed
    }

    func advance(to date: Date, link: GameLink) -> Int {
        if link.paused {
            lastDate = nil
            return frame
        }
        defer { lastDate = date }
        guard let before = lastDate else { return frame }
        let dt = Swift.min(Swift.max(date.timeIntervalSince(before), 0), 0.1)
        if dt <= 0 { return frame }
        model.step(dt: dt)
        if GameDemo.autopilot { pilot() }
        settle(link)
        frame &+= 1
        return frame
    }

    /// The scripted reader: picks a story, reads at a steady pace, takes the warm choices, or the
    /// silly ones once GameDemo.loseAfter has passed.
    private func pilot() {
        switch model.stage {
        case .pick:
            if model.time > 1.0 { model.pick(Int(seed % 2)) }
        case .story:
            if model.waitingForChoice {
                if model.idle > 1.1 {
                    let silly = GameDemo.loseAfter.map { model.time > $0 } ?? false
                    model.choose(silly ? model.choices.count - 1 : 0)
                }
            } else if model.pressed == nil, model.idle > 0.9 {
                model.tap()
            }
        case .card:
            if model.idle > 2.5 { model.tap() }
        case .done:
            break
        }
    }

    func pick(_ index: Int, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.pick(index)
        settle(link)
    }

    func tap(link: GameLink) {
        if link.paused || link.isFinished { return }
        model.tap()
        settle(link)
    }

    func choose(_ index: Int, link: GameLink) {
        if link.paused || link.isFinished { return }
        model.choose(index)
        settle(link)
    }

    private func settle(_ link: GameLink) {
        for event in model.feedback {
            switch event {
            case .advance: GameHaptics.tap()
            case .choose: GameHaptics.thud()
            case .up: GameHaptics.success()
            case .down: GameHaptics.tap()
            case .end: GameHaptics.thud()
            }
        }
        model.clearFeedback()
        if model.stage == .done, !reported {
            reported = true
            let result = model.result
            DispatchQueue.main.async { link.finish(result) }
        }
    }
}

// MARK: - Views

/// The opening screen: the logo and one card per story.
struct SakuraDaysPicker: View {
    let size: CGSize
    let time: Double
    var onPick: (Int) -> Void

    private var u: CGFloat { size.width / 393 }

    var body: some View {
        ZStack(alignment: .top) {
            Image("sakura-days-street").resizable().scaledToFill()
                .frame(width: size.width, height: size.height).clipped()
            LinearGradient(colors: [Color.white.opacity(0.1), Color(red: 1, green: 0.9, blue: 0.93).opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
            SakuraDaysParticles(time: time, night: false)
            VStack(spacing: 14 * u) {
                Spacer().frame(height: GameLayout.topBand * u + 30 * u)
                VStack(spacing: -6 * u) {
                    Text("SAKURA")
                        .font(.system(size: 54 * u, weight: .black, design: .serif))
                    Text("DAYS")
                        .font(.system(size: 54 * u, weight: .black, design: .serif))
                }
                .foregroundStyle(LinearGradient(colors: [SakuraDaysInk.rose, Color(red: 0.62, green: 0.22, blue: 0.48)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .white, radius: 0, x: 2 * u, y: 2 * u)
                .shadow(color: .white.opacity(0.9), radius: 10 * u)
                .offset(y: sin(time * 1.6) * 3 * u)
                Text("Pick a story")
                    .font(.system(size: 17 * u, weight: .semibold, design: .serif))
                    .foregroundStyle(SakuraDaysInk.ink)
                    .padding(.horizontal, 16 * u)
                    .padding(.vertical, 6 * u)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
                Spacer()
                ForEach(SakuraDaysStories.all.indices, id: \.self) { i in
                    storyCard(i)
                }
                Spacer().frame(height: GameLayout.bottomInset * u + 6 * u)
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
    }

    private func storyCard(_ i: Int) -> some View {
        let story = SakuraDaysStories.all[i]
        let cover = i == 0 ? "sakura-days-teahouse" : "sakura-days-campus"
        return Button {
            onPick(i)
        } label: {
            HStack(spacing: 14 * u) {
                ZStack(alignment: .bottom) {
                    Image(cover).resizable().scaledToFill()
                        .frame(width: 100 * u, height: 120 * u).clipped()
                    HStack(spacing: -34 * u) {
                        ForEach(story.cast.indices, id: \.self) { k in
                            Image(story.cast[k].images[1]).resizable().scaledToFit()
                                .frame(height: 104 * u)
                        }
                    }
                    .frame(width: 100 * u, height: 120 * u, alignment: .bottom)
                    .clipped()
                }
                .frame(width: 100 * u, height: 120 * u)
                .clipShape(RoundedRectangle(cornerRadius: 14 * u, style: .continuous))
                VStack(alignment: .leading, spacing: 6 * u) {
                    Text(story.title)
                        .font(.system(size: 22 * u, weight: .bold, design: story.serif ? .serif : .rounded))
                        .foregroundStyle(SakuraDaysInk.ink)
                    Text(story.blurb)
                        .font(.system(size: 15 * u, weight: .medium, design: story.serif ? .serif : .rounded))
                        .foregroundStyle(SakuraDaysInk.ink.opacity(0.75))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6 * u) {
                        ForEach(story.cast.indices, id: \.self) { k in
                            Text(story.cast[k].name)
                                .font(.system(size: 12 * u, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9 * u)
                                .padding(.vertical, 3 * u)
                                .background(Capsule().fill(story.cast[k].color))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10 * u)
            .background(
                RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
                    .fill(SakuraDaysInk.paper.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20 * u, style: .continuous)
                    .strokeBorder(story.cast[0].color.opacity(0.6), lineWidth: 2 * u)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8 * u, y: 4 * u)
        }
        .buttonStyle(.plain)
        .frame(width: size.width - 32 * u)
    }
}

public struct SakuraDaysGame: View {
    private let options: GameOptions
    private let link: GameLink

    public init(options: GameOptions, link: GameLink) {
        self.options = options
        self.link = link
    }

    public var body: some View {
        // A new link is a new round, so the round's state lives and dies with the link.
        SakuraDaysRound(options: options, link: link)
            .id(ObjectIdentifier(link))
    }
}

private struct SakuraDaysRound: View {
    @ObservedObject var link: GameLink
    @StateObject private var runner: SakuraDaysRunner

    init(options: GameOptions, link: GameLink) {
        self.link = link
        _runner = StateObject(wrappedValue: SakuraDaysRunner(options: options))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: link.paused)) { timeline in
                let frame = runner.advance(to: timeline.date, link: link)
                screen(size: geo.size, frame: frame)
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Sakura Days. Read the story and pick what to say.")
    }

    @ViewBuilder private func screen(size: CGSize, frame: Int) -> some View {
        if size.width > 8, size.height > 8, frame >= 0 {
            if runner.model.stage == .pick {
                SakuraDaysPicker(size: size, time: runner.model.time) { index in
                    runner.pick(index, link: link)
                }
            } else {
                SakuraDaysStage(look: runner.model.look(), size: size, showHUD: true,
                                onTap: { runner.tap(link: link) },
                                onChoose: { index in runner.choose(index, link: link) })
            }
        }
    }
}
