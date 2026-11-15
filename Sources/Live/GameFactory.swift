import SwiftUI

/// The playable view for each game.
enum GameFactory {
    @ViewBuilder static func view(for kind: GameKind, options: GameOptions, link: GameLink) -> some View {
        switch kind {
        case .fiveUp: FiveUpGame(options: options, link: link)
        case .tippyTower: TippyTowerGame(options: options, link: link)
        case .spiralDrop: SpiralDropGame(options: options, link: link)
        case .laneDash: LaneDashGame(options: options, link: link)
        case .gulpCity: GulpCityGame(options: options, link: link)
        case .inkland: InklandGame(options: options, link: link)
        case .slipOut: SlipOutGame(options: options, link: link)
        case .blockParty: BlockPartyGame(options: options, link: link)
        case .wildEights: WildEightsGame(options: options, link: link)
        case .brickOut: BrickOutGame(options: options, link: link)
        case .dailyGrid: DailyGridGame(options: options, link: link)
        case .letterRush: LetterRushGame(options: options, link: link)
        case .pourParty: PourPartyGame(options: options, link: link)
        case .deepEnd: DeepEndGame(options: options, link: link)
        case .jamSlide: JamSlideGame(options: options, link: link)
        case .busRush: BusRushGame(options: options, link: link)
        }
    }
}
