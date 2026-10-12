import AVFoundation
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Rummy_Calculator

/// Renders each shipping screen with representative state.
///
/// This is a smoke test: it proves every screen builds and draws without
/// trapping, which unit tests on the scoring engine cannot show. Rendered PNGs
/// are written into the test host's container so the screens can be eyeballed
/// during development — the directory is printed by the first test.
@MainActor
@Suite("Screens render")
struct ScreenRenderTests {

    private static let size = CGSize(width: 402, height: 874)

    private static let snapshotDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("rummy-snapshots", isDirectory: true)

    /// Renders a view through a real hosting controller and window.
    ///
    /// `ImageRenderer` never lays out `ScrollView` content, so it would report
    /// these screens as empty shells. Driving UIKit's own layout pass renders
    /// what the device actually shows.
    @discardableResult
    private func render(
        _ view: some View,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> UIImage? {
        let bounds = CGRect(origin: .zero, size: Self.size)

        // Light, on the app's canvas — as the app forces light mode and sheets
        // sit on that canvas.
        let controller = UIHostingController(rootView: AnyView(view))
        controller.overrideUserInterfaceStyle = .light
        controller.view.frame = bounds
        controller.view.backgroundColor = UIColor(Color.canvas)

        // Attaching to the host app's scene gives the hierarchy a real trait
        // environment, which lazy containers need before they materialise cells.
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene })
                as? UIWindowScene
        else {
            Issue.record("The render test host has no window scene", sourceLocation: sourceLocation)
            return nil
        }
        let window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // Give SwiftUI time to materialise lazy containers *and* to settle any
        // entrance animation — a shorter wait snapshots screens mid-fade.
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        controller.view.layoutIfNeeded()

        // `layer.render(in:)` works without the window being on a real screen,
        // unlike `drawHierarchy(afterScreenUpdates:)`.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            window.layer.render(in: context.cgContext)
        }

        #expect(image.size.width > 0 && image.size.height > 0, sourceLocation: sourceLocation)
        #expect(!isBlank(image), "\(name) rendered blank", sourceLocation: sourceLocation)

        if let data = image.pngData() {
            let directory = Self.snapshotDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent("\(name).png"))
        }

        window.isHidden = true
        return image
    }

    /// The colour at a fractional point in the image.
    private func colour(of image: UIImage, atX fx: CGFloat, y fy: CGFloat) -> (Int, Int, Int)? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(
            x: -CGFloat(cgImage.width) * fx,
            y: -CGFloat(cgImage.height) * (1 - fy)
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    /// True when every sampled pixel is the same colour — the screen drew nothing.
    private func isBlank(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }

        let width = 40, height = 80
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var seen = Set<UInt32>()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let packed = UInt32(pixels[index]) << 16
                | UInt32(pixels[index + 1]) << 8
                | UInt32(pixels[index + 2])
            seen.insert(packed)
            if seen.count > 12 { return false }
        }
        return true
    }

    // MARK: Fixtures

    /// A four-seat game with the given number of rounds already scored.
    private func game(roundsPlayed: Int) -> GameViewModel {
        let viewModel = GameViewModel(sessionStore: .ephemeral)
        viewModel.playerNames = ["Khalid", "Hamad", "Ali", "Saud"]
        viewModel.startGame()
        let types: [WinType] = [.normal, .color, .normal, .zata, .normal, .color, .normal, .normal, .zataJoker]
        for round in 0..<roundsPlayed {
            viewModel.selectWinner(playerIndex: round % 4, winType: types[round % types.count])
        }
        return viewModel
    }

    // MARK: Tests

    @Test("The start page renders with the table and name fields")
    func startPage() {
        print("RUMMY_SNAPSHOTS_AT \(Self.snapshotDirectory.path)")
        render(StartPageView(viewModel: GameViewModel(sessionStore: .ephemeral)), named: "01-start")
    }

    @Test("The board renders mid-game")
    func board() {
        let viewModel = game(roundsPlayed: 4)
        #expect(viewModel.isGameStarted)
        #expect(!viewModel.isGameOver)
        #expect(viewModel.currentRoundNumber == 5)
        let image = try! #require(render(GameScreenView(viewModel: viewModel), named: "02-board"))
        viewModel.stopTimer()

        // Controls over the aura carry ink glyphs: the pause chevron, top left.
        #expect(anyPixel(of: image, x: 0.05...0.15, y: 0.08...0.13, step: 0.004, where: isInk), "the pause button is white on white")
        // The leader's name stands at the left of the chart in black.
        #expect(anyPixel(of: image, x: 0.04...0.27, y: 0.26...0.46, step: 0.005, where: isInk), "no standings beside the chart")
    }

    @Test("The chart ranks names best first, level totals sharing a place")
    func chartStandings() {
        let standings = Standing.rank(totals: [400, 100, 400, -60], names: ["K", "H", "A", "S"], isRanked: true)
        #expect(standings.map(\.name) == ["S", "H", "K", "A"])
        #expect(standings.map(\.place) == [1, 2, 3, 3])
        #expect(Standing.rank(totals: [0, 0], names: ["K", "H"], isRanked: false).map(\.place) == [nil, nil])
    }

    @Test("The winner picker renders its seat-selection step")
    func winnerPicker() {
        let viewModel = game(roundsPlayed: 2)
        render(WinnerPickerView(viewModel: viewModel), named: "03-winner-picker")
        viewModel.stopTimer()
    }

    @Test("The celebration renders the first-place medal and the winner's name")
    func celebration() {
        render(
            WinnerCelebrationView(
                winnerName: "Khalid",
                winnerScore: -240,
                elapsed: "42:17",
                startsWithReveal: false,
                onDismiss: {}
            ),
            named: "04-celebration"
        )
    }

    @Test("The celebration renders a level finish with both names")
    func celebrationTie() {
        render(
            WinnerCelebrationView(
                winnerName: "Khalid • Hamad",
                winnerScore: 180,
                elapsed: "1:05:32",
                startsWithReveal: false,
                onDismiss: {}
            ),
            named: "05-celebration-tie"
        )
    }

    /// Whether any sampled pixel in the region passes `test`.
    private func anyPixel(
        of image: UIImage,
        x: ClosedRange<CGFloat>,
        y: ClosedRange<CGFloat>,
        step: CGFloat = 0.01,
        where test: ((Int, Int, Int)) -> Bool
    ) -> Bool {
        for fy in stride(from: y.lowerBound, through: y.upperBound, by: step) {
            for fx in stride(from: x.lowerBound, through: x.upperBound, by: step) {
                if let c = colour(of: image, atX: fx, y: fy), test(c) { return true }
            }
        }
        return false
    }

    private func isMoonYellow(_ c: (Int, Int, Int)) -> Bool { c.0 > 200 && c.1 > 170 && c.2 < 90 }
    private func isInk(_ c: (Int, Int, Int)) -> Bool { c.0 < 50 && c.1 < 50 && c.2 < 50 }

    /// A region of the Joker card, as fractions of a 402 × 874 screen.
    private func cardRegion(x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let screen = CGSize(width: 402, height: 874)
        let card = JokerWinnerReveal.cardFrame(in: screen)
        func sx(_ f: CGFloat) -> CGFloat { (card.minX + f * card.width) / screen.width }
        func sy(_ f: CGFloat) -> CGFloat { (card.minY + f * card.height) / screen.height }
        return (sx(x.lowerBound)...sx(x.upperBound), sy(y.lowerBound)...sy(y.upperBound))
    }

    /// The middle of the sign's panel, where the name is set.
    private var nameArea: (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let panel = JokerWinnerReveal.signPanel
        return cardRegion(
            x: (panel.minX + panel.width * 0.25)...(panel.maxX - panel.width * 0.25),
            y: (panel.minY + panel.height * 0.35)...(panel.maxY - panel.height * 0.1)
        )
    }

    @Test("The Joker reveal opens on the card, binoculars in hand and no name yet")
    func jokerRevealOpens() {
        let image = try! #require(render(JokerWinnerReveal(winnerName: "خالد", playing: false) {}, named: "16-joker-reveal"))
        #expect(anyPixel(of: image, x: 0.3...0.7, y: 0.3...0.75, where: isMoonYellow), "the card did not draw")
        let binoculars = cardRegion(x: 0.24...0.40, y: 0.40...0.50)
        #expect(anyPixel(of: image, x: binoculars.x, y: binoculars.y, step: 0.004, where: isInk), "no binoculars")
        #expect(!anyPixel(of: image, x: nameArea.x, y: nameArea.y, step: 0.004, where: isInk), "a name before the sign is up")
    }

    @Test("The Joker reveal ends on the sign with the winner's name set on it")
    func jokerRevealFinalFrame() {
        let image = try! #require(render(
            JokerWinnerReveal(winnerName: "خالد", startTime: JokerWinnerReveal.nameTime) {},
            named: "17-joker-reveal-final"
        ))
        #expect(anyPixel(of: image, x: 0.3...0.7, y: 0.3...0.75, where: isMoonYellow))
        // The sign in the clip is blank: ink on its panel is the overlaid name.
        #expect(anyPixel(of: image, x: nameArea.x, y: nameArea.y, step: 0.003, where: isInk), "the name is not on the sign")
    }

    @Test("The Joker clip ships with the app, long enough for the name to land")
    func jokerClipShips() async throws {
        let url = try #require(Bundle.main.url(forResource: "JokerReveal", withExtension: "mp4"))
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 3.79) < 0.1, "unexpected clip length \(duration)")
        #expect(duration > JokerWinnerReveal.nameTime + 0.3)
        let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(bytes < 3_000_000, "the clip has grown to \(bytes) bytes")
    }

    @Test("A board that is already finished raises the celebration on appear")
    func finishedBoard() {
        let viewModel = game(roundsPlayed: 9)
        #expect(viewModel.isGameOver)
        #expect(viewModel.gameWinnerName == "Khalid")

        let image = try! #require(render(GameScreenView(viewModel: viewModel), named: "06-board-finished"))
        viewModel.stopTimer()

        // The finish opens on the Joker reveal. Its moon is the only strong
        // yellow anywhere in the app, so finding it means the overlay is up.
        #expect(anyPixel(of: image, x: 0.3...0.7, y: 0.3...0.75, where: isMoonYellow), "no Joker reveal")
    }

    @Test("The predictions sheet renders once enough rounds are played")
    func predictions() {
        let viewModel = game(roundsPlayed: 6)
        viewModel.predictionsActive = true
        #expect(viewModel.canShowPredictions)
        render(PredictionView(viewModel: viewModel), named: "07-predictions")
        viewModel.stopTimer()
    }

    @Test("The calculator renders")
    func calculator() {
        render(MiniCalculatorView(), named: "08-calculator")
    }

    @Test("History renders its empty state")
    func history() {
        render(HistoryView(viewModel: GameViewModel(sessionStore: .ephemeral)), named: "09-history")
    }

    @Test("The rules sheet renders")
    func rules() {
        render(RulesView(viewModel: GameViewModel(sessionStore: .ephemeral)), named: "10-rules")
    }

    @Test("The start page offers to resume a paused game")
    func startPageWithPausedGame() {
        let viewModel = game(roundsPlayed: 3)
        viewModel.pauseGame()
        #expect(viewModel.hasPausedGame)
        render(StartPageView(viewModel: viewModel), named: "11-start-resume")
    }

    @Test("The nearby sheet renders with this phone's seat and its advice")
    func nearbySheet() {
        let savedName = PlayerIdentity.preferredName
        defer { PlayerIdentity.preferredName = savedName }

        let viewModel = game(roundsPlayed: 6)
        viewModel.setLocalSeat(1)
        #expect(viewModel.localSeatAdvice?.hasPlan == true)
        render(NearbyHostSheet(viewModel: viewModel), named: "12-nearby-host")
        viewModel.stopTimer()
    }

    @Test("The nearby players row renders waiting players, and its empty state")
    func nearbyPlayersRow() {
        let players = [
            LobbyPlayer(id: "1", name: "نايف"),
            LobbyPlayer(id: "2", name: "فهد"),
            LobbyPlayer(id: "3", name: "khalid 2"),
        ]
        render(
            VStack(spacing: 20) {
                NearbyPlayersRow(players: players, onSeat: { _ in })
                NearbyPlayersRow(players: [], onSeat: { _ in })
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top),
            named: "15-nearby-row"
        )
    }

    @Test("The manual score sheet renders")
    func manualEntry() {
        let viewModel = game(roundsPlayed: 2)
        viewModel.openManualEntry(roundIndex: 0, playerIndex: 1)
        render(ManualEntryView(viewModel: viewModel), named: "13-manual-entry")
        viewModel.stopTimer()
    }

    /// Ten games among seven friends, newest first.
    private var clubGames: [GameRecord] {
        [
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [-120, 660, 1_440, 1_180], roundWinners: ["Khalid", "Khalid", "Hamad"], daysAgo: 0),
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [900, 300, 1_200, 1_500], roundWinners: ["Hamad", "Hamad"], daysAgo: 1),
            standingsRecord(["Fahad", "Hamad", "Ali", "Khalid"], [1_100, 800, 400, 200], roundWinners: ["Khalid", "Ali"], daysAgo: 3),
            standingsRecord(["Khalid", "Hamad", "Nasser", "Saud"], [500, 520, 1_600, 260], roundWinners: ["Saud"], daysAgo: 4),
            standingsRecord(["Khalid", "Fahad", "Ali", "Nasser"], [140, 900, 980, 1_220], roundWinners: ["Khalid", "Fahad"], daysAgo: 6),
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [300, 300, 900, 1_000], daysAgo: 8),
            standingsRecord(["Hamad", "Ali", "Saud", "Yousef"], [100, 700, 860, 1_300], roundWinners: ["Hamad"], daysAgo: 9),
            standingsRecord(["Khalid", "Hamad", "Ali", "Saud"], [1_400, 200, 600, 900], daysAgo: 11),
            standingsRecord(["Khalid", "Nasser", "Ali", "Saud"], [60, 800, 640, 1_000], daysAgo: 12),
            standingsRecord(["Khalid", "Hamad", "Fahad", "Saud"], [700, 940, 220, 1_000], daysAgo: 14),
        ]
    }

    @Test("The standings render a podium and the leaderboard")
    func standingsLeaderboard() {
        let image = try! #require(render(StandingsView(games: clubGames), named: "19-standings"))
        // The leader's raised disc on the podium is ink.
        #expect(anyPixel(of: image, x: 0.35...0.65, y: 0.15...0.4, step: 0.005, where: isInk), "no leader on the podium")
    }

    @Test("The standings compare two chosen players head to head")
    func standingsHeadToHead() {
        render(StandingsView(games: clubGames, tab: .headToHead, first: "Khalid", second: "hamad"), named: "20-standings-h2h")
        render(StandingsView(games: clubGames, tab: .headToHead, first: "Nasser", second: "Yousef"), named: "21-standings-never-met")
    }

    @Test("The standings render their empty state")
    func standingsEmpty() {
        render(StandingsView(games: []), named: "22-standings-empty")
    }

    @Test("A finished game's details render")
    func historyDetail() {
        let viewModel = game(roundsPlayed: 9)
        let record = try! #require(viewModel.historyManager.games.first)
        render(NavigationStack { GameDetailView(record: record) }, named: "14-history-detail")
        viewModel.historyManager.deleteGame(at: IndexSet(integer: 0))
    }
}
