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
        render(GameScreenView(viewModel: viewModel), named: "02-board")
        viewModel.stopTimer()
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

    @Test("The Joker reveal renders the card before the camera moves in")
    func jokerReveal() {
        let image = try! #require(render(JokerWinnerReveal(winnerName: "خالد") {}, named: "16-joker-reveal"))
        // The card art sits in the middle; red and yellow in it show the image
        // loaded from the asset catalogue rather than a blank white canvas.
        var sawColour = false
        for fy in stride(from: 0.3, through: 0.7, by: 0.05) {
            for fx in stride(from: 0.3, through: 0.7, by: 0.05) {
                if let (r, g, b) = colour(of: image, atX: fx, y: fy), max(r, g, b) - min(r, g, b) > 80 {
                    sawColour = true
                }
            }
        }
        #expect(sawColour, "the Joker card did not draw")
    }

    @Test("The Joker reveal ends on the winner's name inside the lens")
    func jokerRevealFinalFrame() {
        let image = try! #require(render(
            JokerWinnerReveal(winnerName: "خالد", startTime: 4.6) {},
            named: "17-joker-reveal-final"
        ))
        // Inside the lens the screen is deep green-black, not the white card.
        let (r, g, b) = try! #require(colour(of: image, atX: 0.12, y: 0.3))
        #expect(r < 90 && g < 90 && b < 90, "not inside the lens — got (\(r), \(g), \(b))")
    }

    @Test("A board that is already finished raises the celebration on appear")
    func finishedBoard() {
        let viewModel = game(roundsPlayed: 9)
        #expect(viewModel.isGameOver)
        #expect(viewModel.gameWinnerName == "Khalid")

        let image = try! #require(render(GameScreenView(viewModel: viewModel), named: "06-board-finished"))
        viewModel.stopTimer()

        // The finish opens on the Joker reveal, drawn on white. Beside the card
        // at mid-height is pure white when it is up; without it this point is
        // the board's mauve-and-sage gradient.
        let (r, g, b) = try! #require(colour(of: image, atX: 0.04, y: 0.5))
        #expect(r > 245 && g > 245 && b > 245, "no Joker reveal — got (\(r), \(g), \(b))")
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

    @Test("A finished game's details render")
    func historyDetail() {
        let viewModel = game(roundsPlayed: 9)
        let record = try! #require(viewModel.historyManager.games.first)
        render(NavigationStack { GameDetailView(record: record) }, named: "14-history-detail")
        viewModel.historyManager.deleteGame(at: IndexSet(integer: 0))
    }
}
