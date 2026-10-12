import CoreBluetooth
import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "KHALID.Rummy-Calculator", category: "NearbyHost")

/// The scorekeeper's side: advertises the table over Bluetooth LE — the lobby
/// while players are being seated, then the board — and hears each phone
/// introduce itself.
///
/// Callbacks arrive on the main queue. The `bluetooth-peripheral` background
/// mode keeps the service up while the scorekeeper's phone is locked.
@Observable
final class NearbyHost: NSObject {

    enum Status: Equatable {
        case off, starting, live, poweredOff, unauthorized, unsupported
    }

    private(set) var status: Status = .off
    /// Phones subscribed to updates, by their Bluetooth identifier.
    private(set) var followerIDs: Set<UUID> = []

    /// A phone introduced itself (again, after a reconnect, with the same ID).
    @ObservationIgnored var onPlayerJoined: ((LobbyPlayer) -> Void)?
    /// The last connection from a player's phone went away.
    @ObservationIgnored var onPlayerLeft: ((String) -> Void)?
    /// Bluetooth went off or sharing stopped: every player is gone at once.
    @ObservationIgnored var onAllPlayersLeft: (() -> Void)?

    var followerCount: Int { followerIDs.count }

    /// Whether the player wants the board shared; remembered between games.
    var isEnabled: Bool {
        get {
            access(keyPath: \.isEnabled)
            return UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set {
            withMutation(keyPath: \.isEnabled) {
                UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            }
        }
    }

    /// Identifies this phone as a scorekeeper across games and relaunches.
    static let hostID: UUID = {
        let key = "nearbyHostID"
        if let stored = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: stored) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }()

    private static let enabledKey = "shareNearby"

    @ObservationIgnored private var manager: CBPeripheralManager?
    @ObservationIgnored private var revisionCharacteristic: CBMutableCharacteristic?
    /// The player ID each connected phone introduced itself with.
    @ObservationIgnored private var playerIDs: [UUID: String] = [:]
    @ObservationIgnored private var serviceAdded = false
    @ObservationIgnored private var snapshotData = Data()
    @ObservationIgnored private var revision: UInt32 = 0
    @ObservationIgnored private var notifyPending = false
    /// The board as it was when each follower started reading it, so a long
    /// read spanning several packets never mixes two versions.
    @ObservationIgnored private var readCache: [UUID: Data] = [:]

    // MARK: - Control

    /// Brings the service up. The first call asks for Bluetooth permission.
    func start() {
        guard manager == nil else { return }
        status = .starting
        manager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
        )
    }

    func stop() {
        guard let manager else { return }
        manager.stopAdvertising()
        manager.removeAllServices()
        manager.delegate = nil
        self.manager = nil
        revisionCharacteristic = nil
        serviceAdded = false
        followerIDs = []
        playerIDs = [:]
        readCache = [:]
        status = .off
        onAllPlayersLeft?()
    }

    /// Makes `snapshot` the board followers see, and tells them it changed.
    func publish(_ snapshot: TableSnapshot) {
        guard let data = snapshot.encoded() else {
            logger.error("Board too large to share")
            return
        }
        guard data != snapshotData else { return }
        snapshotData = data
        revision &+= 1
        notifyFollowers()
    }

    // MARK: - Internals

    private var revisionData: Data {
        withUnsafeBytes(of: revision.littleEndian) { Data($0) }
    }

    private func notifyFollowers() {
        guard let manager, let revisionCharacteristic, !followerIDs.isEmpty else { return }
        // `false` means the transmit queue is full; retried when it drains.
        notifyPending = !manager.updateValue(revisionData, for: revisionCharacteristic, onSubscribedCentrals: nil)
    }

    private func addService() {
        guard let manager, !serviceAdded else { return }
        let revision = CBMutableCharacteristic(
            type: NearbyService.revision,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        let snapshot = CBMutableCharacteristic(
            type: NearbyService.snapshot,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        let profile = CBMutableCharacteristic(
            type: NearbyService.profile,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: NearbyService.service, primary: true)
        service.characteristics = [revision, snapshot, profile]
        revisionCharacteristic = revision
        serviceAdded = true
        manager.add(service)
    }

    /// Forgets a connection; the player leaves only when it was their last.
    private func dropConnection(_ central: UUID) {
        followerIDs.remove(central)
        readCache[central] = nil
        guard let playerID = playerIDs.removeValue(forKey: central) else { return }
        if !playerIDs.values.contains(playerID) {
            onPlayerLeft?(playerID)
        }
    }

    private func respond(_ request: CBATTRequest, with data: Data, on manager: CBPeripheralManager) {
        guard request.offset <= data.count else {
            manager.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        manager.respond(to: request, withResult: .success)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension NearbyHost: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            addService()
        case .poweredOff:
            // Turning Bluetooth off drops the service and every connection.
            serviceAdded = false
            followerIDs = []
            playerIDs = [:]
            status = .poweredOff
            onAllPlayersLeft?()
        case .unauthorized:
            status = .unauthorized
        case .unsupported:
            status = .unsupported
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            logger.error("Could not add the service: \(error)")
            serviceAdded = false
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [NearbyService.service],
            CBAdvertisementDataLocalNameKey: "Hand",
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            logger.error("Could not advertise: \(error)")
            return
        }
        status = .live
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        followerIDs.insert(central.identifier)
    }

    /// Also called when a follower disconnects.
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        dropConnection(central.identifier)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        if notifyPending {
            notifyFollowers()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        switch request.characteristic.uuid {
        case NearbyService.snapshot:
            let reader = request.central.identifier
            if request.offset == 0 || readCache[reader] == nil {
                readCache[reader] = snapshotData
            }
            respond(request, with: readCache[reader] ?? snapshotData, on: peripheral)
        case NearbyService.revision:
            respond(request, with: revisionData, on: peripheral)
        default:
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        var joined: [LobbyPlayer] = []
        for request in requests where request.characteristic.uuid == NearbyService.profile {
            guard let data = request.value, let player = LobbyPlayer.decode(data) else {
                peripheral.respond(to: first, withResult: .invalidAttributeValueLength)
                return
            }
            let central = request.central.identifier
            if let previous = playerIDs[central], previous != player.id, !playerIDs.contains(where: { $0.key != central && $0.value == previous }) {
                onPlayerLeft?(previous)
            }
            playerIDs[central] = player.id
            joined.append(player)
        }
        // One response answers the whole batch.
        peripheral.respond(to: first, withResult: .success)
        joined.forEach { onPlayerJoined?($0) }
    }
}
