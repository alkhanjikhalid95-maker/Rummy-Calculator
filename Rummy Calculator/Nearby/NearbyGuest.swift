import ActivityKit
import CoreBluetooth
import Foundation
import Observation
import OSLog
import WidgetKit

private let logger = Logger(subsystem: "KHALID.Rummy-Calculator", category: "NearbyGuest")

/// A player's side: finds the scorekeeper's phone over Bluetooth LE, mirrors
/// its board, and keeps this phone's Live Activity and lock-screen widgets
/// showing the game — with advice for this player's own seat from round 7.
///
/// The `bluetooth-central` background mode lets updates land while this phone
/// is locked; state restoration brings the app back if iOS closed it.
@Observable
final class NearbyGuest: NSObject {

    static let shared = NearbyGuest()

    enum Phase: Equatable {
        case idle, browsing, following
    }

    enum Radio: Equatable {
        case unknown, ready, poweredOff, unauthorized, unsupported
    }

    /// A scorekeeper found while browsing.
    struct Table: Identifiable, Equatable {
        let id: UUID
        var snapshot: TableSnapshot
    }

    private(set) var phase: Phase = .idle
    private(set) var radio: Radio = .unknown
    private(set) var tables: [Table] = []
    /// The followed board, as last received.
    private(set) var snapshot: TableSnapshot?
    private(set) var isConnected = false
    private(set) var mySeat: Int?
    /// True when the host seated this phone from the lobby, rather than the
    /// player tapping a seat or being matched by name.
    private(set) var seatFromHost = false

    /// Whether the host has this phone in its lobby or a seat yet.
    var isKnownToHost: Bool {
        snapshot?.knows(playerID: PlayerIdentity.playerID) ?? false
    }

    /// This seat's standing and, from round 7, the wins it needs.
    var advice: SeatAdvice? {
        guard let snapshot, !snapshot.isLobby, let mySeat else { return nil }
        return PredictionEngine.advice(
            forSeat: mySeat,
            totals: snapshot.totals,
            currentRound: snapshot.round,
            maxRounds: snapshot.maxRounds,
            isGameOver: snapshot.isOver
        )
    }

    static let restoreIdentifier = "KHALID.Rummy-Calculator.follower"

    private static let hostKey = "followHostID"
    private static let peripheralKey = "followPeripheralID"
    private static let seatKey = "followSeat"
    private static let seatFromHostKey = "followSeatFromHost"
    /// Connections opened at once while looking for tables.
    private static let browseLimit = 6

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var characteristics: [UUID: [CBUUID: CBCharacteristic]] = [:]
    @ObservationIgnored private var activity: Activity<GameActivityAttributes>?

    /// The scorekeeper's phone as Core Bluetooth knows it — remembered so a
    /// relaunch can reconnect without waiting for a scan.
    @ObservationIgnored private var followedPeripheralID: UUID? {
        didSet { UserDefaults.standard.set(followedPeripheralID?.uuidString, forKey: Self.peripheralKey) }
    }

    private var followedHostID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.hostKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.hostKey) }
    }

    override init() {
        super.init()
        followedPeripheralID = UserDefaults.standard.string(forKey: Self.peripheralKey).flatMap(UUID.init(uuidString:))
        if UserDefaults.standard.object(forKey: Self.seatKey) != nil {
            let stored = UserDefaults.standard.integer(forKey: Self.seatKey)
            mySeat = stored >= 0 ? stored : nil
        }
        seatFromHost = UserDefaults.standard.bool(forKey: Self.seatFromHostKey)
    }

    // MARK: - Control

    /// Picks up a table this phone was following before the app was closed.
    func resumeIfNeeded() {
        guard followedHostID != nil, phase == .idle else { return }
        phase = .following
        activity = Activity<GameActivityAttributes>.activities.first { $0.attributes.isFollowing }
        makeCentral()
        reconnect()
    }

    /// Starts looking for scorekeepers nearby. The first call asks for
    /// Bluetooth permission.
    func startBrowsing() {
        guard phase != .following else { return }
        phase = .browsing
        tables = []
        makeCentral()
        scanIfReady()
    }

    func stopBrowsing() {
        guard phase == .browsing else { return }
        central?.stopScan()
        dropAllPeripherals()
        tables = []
        phase = .idle
    }

    /// Follows `table` and works out which seat is this phone's owner.
    func follow(_ table: Table) {
        followedHostID = table.snapshot.hostID
        followedPeripheralID = table.id
        phase = .following
        tables = []
        central?.stopScan()
        dropAllPeripherals(except: table.id)

        // A new table: whatever seat this phone had elsewhere does not apply.
        snapshot = nil
        setSeat(nil, fromHost: false)
        apply(table.snapshot)
        if let peripheral = peripherals[table.id] {
            subscribe(to: peripheral)
        }
    }

    /// The player tapped their seat — the fallback when the host typed names
    /// by hand instead of seating phones from the lobby. Stays on this phone.
    func chooseSeat(_ seat: Int?) {
        setSeat(seat, fromHost: false)
        refreshLockScreen()
    }

    /// Re-introduces this phone to the host, after the player changed their name.
    func refreshProfile() {
        sendProfile()
    }

    /// Stops following and clears this phone's lock screen. The scorekeeper
    /// frees the seat when the connection drops.
    func leave() {
        followedHostID = nil
        followedPeripheralID = nil
        snapshot = nil
        isConnected = false
        phase = .idle
        central?.stopScan()
        dropAllPeripherals()
        endActivity()
        WidgetGameState.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Internals

    private var followedPeripheral: CBPeripheral? {
        followedPeripheralID.flatMap { peripherals[$0] }
    }

    private func setSeat(_ seat: Int?, fromHost: Bool) {
        mySeat = seat
        seatFromHost = fromHost
        UserDefaults.standard.set(seat ?? -1, forKey: Self.seatKey)
        UserDefaults.standard.set(fromHost, forKey: Self.seatFromHostKey)
    }

    private func makeCentral() {
        guard central == nil else { return }
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
            ]
        )
    }

    private func scanIfReady() {
        guard let central, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(withServices: [NearbyService.service])
    }

    /// Reaches the followed scorekeeper again: directly if Core Bluetooth
    /// still knows the phone, and by scanning in case its address has rotated.
    private func reconnect() {
        guard let central, central.state == .poweredOn else { return }
        if let id = followedPeripheralID,
           let peripheral = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first {
            track(peripheral)
            if peripheral.state == .connected {
                peripheral.discoverServices([NearbyService.service])
            } else {
                central.connect(peripheral)
            }
        }
        scanIfReady()
    }

    private func track(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripherals[peripheral.identifier] = peripheral
    }

    private func dropAllPeripherals(except keep: UUID? = nil) {
        for (id, peripheral) in peripherals where id != keep {
            central?.cancelPeripheralConnection(peripheral)
            peripherals[id] = nil
            characteristics[id] = nil
        }
    }

    private func subscribe(to peripheral: CBPeripheral) {
        guard let found = characteristics[peripheral.identifier] else { return }
        if let revision = found[NearbyService.revision], !revision.isNotifying {
            peripheral.setNotifyValue(true, for: revision)
        }
        sendProfile()
    }

    /// Tells the host who this phone is: its player ID and its owner's name.
    /// Sent on every (re)connection, so a returning player gets their seat back.
    private func sendProfile() {
        guard let peripheral = followedPeripheral,
              let profile = characteristics[peripheral.identifier]?[NearbyService.profile],
              let data = LobbyPlayer(id: PlayerIdentity.playerID, name: PlayerIdentity.preferredName ?? "").encoded()
        else { return }
        peripheral.writeValue(data, for: profile, type: .withResponse)
    }

    private func readSnapshot(from peripheral: CBPeripheral) {
        guard let characteristic = characteristics[peripheral.identifier]?[NearbyService.snapshot] else { return }
        peripheral.readValue(for: characteristic)
    }

    private func received(_ incoming: TableSnapshot, from peripheral: CBPeripheral) {
        switch phase {
        case .browsing:
            if let index = tables.firstIndex(where: { $0.id == peripheral.identifier }) {
                tables[index].snapshot = incoming
            } else {
                tables.append(Table(id: peripheral.identifier, snapshot: incoming))
            }

        case .following:
            if peripheral.identifier != followedPeripheralID {
                // Someone else's table, or our scorekeeper under a new address.
                guard incoming.hostID == followedHostID else {
                    central?.cancelPeripheralConnection(peripheral)
                    peripherals[peripheral.identifier] = nil
                    return
                }
                followedPeripheralID = peripheral.identifier
                central?.stopScan()
                dropAllPeripherals(except: peripheral.identifier)
                subscribe(to: peripheral)
            }
            isConnected = true
            apply(incoming)

        case .idle:
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    private func apply(_ incoming: TableSnapshot) {
        let previous = snapshot
        snapshot = incoming

        var resolver = SeatResolver(seat: mySeat, fromHost: seatFromHost)
        resolver.update(
            with: incoming,
            previousNames: previous?.names,
            playerID: PlayerIdentity.playerID,
            name: { PlayerIdentity.seat(in: $0) }
        )
        if resolver.seat != mySeat || resolver.fromHost != seatFromHost {
            setSeat(resolver.seat, fromHost: resolver.fromHost)
        }
        refreshLockScreen()
    }

    // MARK: - Lock screen

    private func refreshLockScreen() {
        guard phase == .following, let snapshot else { return }

        if snapshot.isLobby {
            // No board yet: the widgets have nothing to show.
            WidgetGameState.clear()
        } else {
            refreshWidgets(snapshot)
        }

        let state = GameActivityAttributes.ContentState(
            playerNames: snapshot.names,
            scores: snapshot.totals,
            currentRound: snapshot.round,
            isGameOver: snapshot.isOver,
            leaderIndex: snapshot.leaderIndex,
            elapsedSeconds: snapshot.elapsed,
            startDate: snapshot.startedAt,
            mySeat: mySeat,
            advice: advice,
            isConnected: isConnected,
            isLobby: snapshot.isLobby
        )
        // Out of touch with the scorekeeper: let iOS grey it out after a while.
        let content = ActivityContent(
            state: state,
            staleDate: isConnected ? nil : Date().addingTimeInterval(30 * 60)
        )

        if activity == nil {
            // Survives the app being closed and relaunched by Bluetooth.
            activity = Activity<GameActivityAttributes>.activities.first {
                $0.attributes.isFollowing && $0.activityState == .active
            }
        }
        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        // Starting one only works in the foreground — which is why it starts
        // in the lobby, while the player is still looking at the app. Once
        // the game begins the updates land with the phone locked.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(
                attributes: GameActivityAttributes(isFollowing: true),
                content: content,
                pushType: nil
            )
        } catch {
            logger.info("Live Activity not started: \(error)")
        }
    }

    private func refreshWidgets(_ snapshot: TableSnapshot) {
        var widget = WidgetGameState(
            playerNames: snapshot.names,
            scores: snapshot.totals,
            currentRound: snapshot.round,
            isGameOver: snapshot.isOver,
            leaderIndex: snapshot.leaderIndex,
            lastUpdated: Date()
        )
        widget.startDate = snapshot.startedAt
        widget.elapsedSeconds = snapshot.elapsed
        widget.mySeat = mySeat
        widget.advice = advice
        widget.isFollowing = true
        widget.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func endActivity() {
        let following = Activity<GameActivityAttributes>.activities.filter { $0.attributes.isFollowing }
        for activity in following {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension NearbyGuest: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            radio = .ready
            switch phase {
            case .browsing: scanIfReady()
            case .following: reconnect()
            case .idle: break
            }
        case .poweredOff:
            radio = .poweredOff
            if isConnected {
                isConnected = false
                refreshLockScreen()
            }
        case .unauthorized:
            radio = .unauthorized
        case .unsupported:
            radio = .unsupported
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            track(peripheral)
        }
        if followedHostID != nil {
            phase = .following
            followedPeripheralID = restored.first?.identifier
            activity = Activity<GameActivityAttributes>.activities.first { $0.attributes.isFollowing }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard peripherals[peripheral.identifier] == nil else { return }
        if phase == .browsing, peripherals.count >= Self.browseLimit { return }
        track(peripheral)
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([NearbyService.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == followedPeripheralID {
            central.connect(peripheral)
        } else {
            peripherals[peripheral.identifier] = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        characteristics[peripheral.identifier] = nil

        if phase == .following, peripheral.identifier == followedPeripheralID {
            isConnected = false
            refreshLockScreen()
            // A pending connect has no timeout: it completes whenever the
            // scorekeeper is back in range, even with this phone locked.
            central.connect(peripheral)
            scanIfReady()
            return
        }
        peripherals[peripheral.identifier] = nil
        tables.removeAll { $0.id == peripheral.identifier }
    }
}

// MARK: - CBPeripheralDelegate

extension NearbyGuest: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == NearbyService.service }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics(
            [NearbyService.revision, NearbyService.snapshot, NearbyService.profile],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        var found: [CBUUID: CBCharacteristic] = [:]
        for characteristic in service.characteristics ?? [] {
            found[characteristic.uuid] = characteristic
        }
        characteristics[peripheral.identifier] = found

        if peripheral.identifier == followedPeripheralID {
            subscribe(to: peripheral)
        }
        readSnapshot(from: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.error("Read failed: \(error)")
            return
        }
        switch characteristic.uuid {
        case NearbyService.revision:
            readSnapshot(from: peripheral)
        case NearbyService.snapshot:
            guard let data = characteristic.value, let incoming = TableSnapshot.decode(data) else { return }
            received(incoming, from: peripheral)
        default:
            break
        }
    }
}
