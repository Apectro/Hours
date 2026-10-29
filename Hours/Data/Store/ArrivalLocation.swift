import CoreLocation
import Foundation
import Observation
import SwiftData

/// What the app may do with the phone's location, in the four states the
/// site's settings tell apart.
enum LocationAccess: Hashable, Sendable {
    case notDetermined
    /// Denied, restricted, or Location Services off altogether.
    case denied
    case whenInUse
    case always
}

/// The opt-in arrival reminder's one door to CoreLocation (1.2).
///
/// Nothing else in the app touches location. It does two things, both only
/// for a site whose reminder the user turned on:
///
/// - **Saves where a site is.** "Use my current location" in the site's
///   settings asks for When In Use access and one fix
///   (`CLLocationManager.requestLocation`), which becomes the site's
///   latitude and longitude. Nothing else of the location is kept.
/// - **Watches those sites.** One `CLCircularRegion` per site with the
///   reminder on (at most 20, `ArrivalReminderPolicy.plan`), entry and exit
///   both, which needs Always access. iOS wakes the app when one is crossed;
///   the app then decides (`ArrivalReminders`) and may post a notification.
///   No background location mode, no continuous updates.
/// - **Turns a saved place into an address**, only when "Fill in from the
///   saved place" is tapped in the site's settings: `CLGeocoder` asks Apple
///   Maps about that one place, and what comes back becomes the site's
///   address text (`SiteAddress.compose`). Nothing is looked up otherwise.
///
/// **Why region monitoring rather than `CLMonitor`.** Both are on iOS 18.
/// `CLLocationManager` region monitoring hands an event to the delegate set
/// as the app launches — including the launch iOS makes in the background
/// for the event — with no monitor to reopen by name, no async event stream
/// to be iterating in time, and no `CLServiceSession` to hold; it has
/// delivered region events this way since iOS 7. `CLMonitor` would be the
/// newer spelling of the same thing with more lifecycle to get right in a
/// build nobody can run before CI. Apple has marked the older calls as to be
/// replaced, not removed.
///
/// Under UI tests no `CLLocationManager` is ever made: a fake gives the
/// access the launch arguments ask for and a fixed place in Zagreb, so the
/// flow can be walked without a real permission prompt.
@MainActor
@Observable
final class ArrivalLocation {
    private(set) var access: LocationAccess = .notDetermined
    /// Precise Location. Off, iOS hands out a fix kilometres wide and does
    /// not watch regions, so the reminder cannot work.
    private(set) var isPrecise = true

    /// The fake's place: Trg bana Jelačića, Zagreb.
    static let fakePlace = SitePlace(latitude: 45.81302, longitude: 15.97722)

    enum Failure: Error {
        case denied
        case noFix
    }

    private let isFake: Bool
    @ObservationIgnored private var bridge: LocationBridge?
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var placeWaiters: [CheckedContinuation<SitePlace, Error>] = []

    init(isFake: Bool) {
        self.isFake = isFake
        if isFake {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-hours-location-denied") {
                access = .denied
            } else if arguments.contains("-hours-location-always") {
                access = .always
            }
        }
    }

    /// Called as the app launches, from its `init`: a region crossed while
    /// the app was not running relaunches it in the background and hands
    /// the event to the delegate of the manager made now. Making the manager
    /// asks for nothing; it only reads the access already given.
    func start() {
        guard !isFake, bridge == nil else { return }
        let bridge = LocationBridge(owner: self)
        self.bridge = bridge
        read(bridge.manager)
    }

    // MARK: - Saving a site's place

    /// One fix of where the phone is now, asking for When In Use access
    /// first if it was never asked.
    func currentPlace() async throws -> SitePlace {
        if isFake {
            if access == .denied { throw Failure.denied }
            if access == .notDetermined { access = .whenInUse }
            return Self.fakePlace
        }
        start()
        guard let manager = bridge?.manager else { throw Failure.noFix }
        if access == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // The answer always comes back through the delegate when the
            // status was undetermined, so this cannot wait forever.
            await withCheckedContinuation { authorizationWaiters.append($0) }
        }
        guard access == .whenInUse || access == .always else { throw Failure.denied }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // `requestLocation` ends with exactly one fix or one error.
        return try await withCheckedThrowingContinuation { continuation in
            placeWaiters.append(continuation)
            if placeWaiters.count == 1 { manager.requestLocation() }
        }
    }

    // MARK: - The address of a saved place

    /// The street and number, postcode and city of a site's saved place, or
    /// nil when Apple Maps has none (or cannot be reached). Asked only when
    /// the user taps "Fill in from the saved place": this is the one call
    /// that sends a place off the phone, to Apple, for that answer.
    ///
    /// `CLGeocoder` rather than MapKit's `MKReverseGeocodingRequest`, which
    /// only arrives with iOS 26; the deployment target is iOS 18.
    func address(of place: SitePlace) async -> String? {
        if isFake {
            return SiteAddress.compose(street: "Trg bana Josipa Jelačića", number: "1", postcode: "10000", city: "Zagreb")
        }
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let text = SiteAddress.compose(
            street: placemark.thoroughfare,
            number: placemark.subThoroughfare,
            postcode: placemark.postalCode,
            city: placemark.locality
        )
        return text.isEmpty ? nil : text
    }

    // MARK: - Always

    /// Asks to upgrade to Always, which watching needs. iOS asks the user
    /// once; after that the answer is in Settings, and `access` follows it
    /// through the delegate, so nothing waits on a prompt that may never
    /// show.
    func requestAlways() {
        if isFake {
            if access != .denied, !ProcessInfo.processInfo.arguments.contains("-hours-location-no-always") {
                access = .always
            }
            return
        }
        start()
        guard access == .whenInUse || access == .notDetermined else { return }
        bridge?.manager.requestAlwaysAuthorization()
    }

    // MARK: - Watching

    /// Brings the watched regions in line with the sites: one for each site
    /// the plan watches, none for anything else, and none at all without
    /// Always access. Called on launch, on every return to the app, when a
    /// site is saved, after a restore, and when the access changes.
    func refresh(sites: [Site]) {
        guard !isFake, let manager = bridge?.manager else { return }
        let wanted = access == .always && isPrecise
            && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
            ? ArrivalReminderPolicy.plan(sites: sites).watched
            : []

        var regions: [String: CLCircularRegion] = [:]
        for site in wanted {
            guard let place = site.place else { continue }
            let identifier = ArrivalReminderPolicy.regionIdentifier(for: site.id)
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                radius: min(site.monitoredRadius, manager.maximumRegionMonitoringDistance),
                identifier: identifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            regions[identifier] = region
        }

        for case let region as CLCircularRegion in manager.monitoredRegions
        where ArrivalReminderPolicy.siteID(fromRegionIdentifier: region.identifier) != nil {
            if let replacement = regions[region.identifier], Self.same(region, replacement) {
                // Already watched as it should be; starting it again would
                // only reset what iOS knows about being inside it.
                regions[region.identifier] = nil
            } else {
                manager.stopMonitoring(for: region)
            }
        }
        for region in regions.values {
            manager.startMonitoring(for: region)
        }
    }

    /// The same as `refresh(sites:)`, reading the active sites from the store.
    func refresh() {
        guard !isFake, bridge != nil else { return }
        let sites = SiteRepository(context: HoursStack.container.mainContext).sites(includeArchived: false)
        refresh(sites: sites)
    }

    private static func same(_ a: CLCircularRegion, _ b: CLCircularRegion) -> Bool {
        abs(a.center.latitude - b.center.latitude) < 0.000_001
            && abs(a.center.longitude - b.center.longitude) < 0.000_001
            && abs(a.radius - b.radius) < 0.5
    }

    // MARK: - From the delegate

    fileprivate func read(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways: access = .always
        case .authorizedWhenInUse: access = .whenInUse
        case .notDetermined: access = .notDetermined
        case .denied, .restricted: access = .denied
        @unknown default: access = .denied
        }
        isPrecise = manager.accuracyAuthorization == .fullAccuracy
    }

    fileprivate func authorizationChanged(_ manager: CLLocationManager) {
        read(manager)
        if access != .notDetermined {
            let waiters = authorizationWaiters
            authorizationWaiters = []
            waiters.forEach { $0.resume() }
        }
        refresh()
    }

    fileprivate func located(_ location: CLLocation?) {
        let waiters = placeWaiters
        placeWaiters = []
        let place = location.flatMap {
            SitePlace(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        for waiter in waiters {
            if let place {
                waiter.resume(returning: place)
            } else {
                waiter.resume(throwing: Failure.noFix)
            }
        }
    }

    fileprivate func crossed(_ event: ArrivalEvent, region: CLRegion) {
        ArrivalReminders.handle(event, regionIdentifier: region.identifier, at: Date())
    }
}

/// CoreLocation's delegate. Not tied to an actor, since CoreLocation calls
/// it as it pleases (on the main thread, where the manager was made, in
/// practice); every call hops to the main actor before touching anything.
private final class LocationBridge: NSObject, CLLocationManagerDelegate {
    let manager: CLLocationManager
    private weak var owner: ArrivalLocation?

    @MainActor
    init(owner: ArrivalLocation) {
        self.owner = owner
        self.manager = CLLocationManager()
        super.init()
        manager.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.owner?.authorizationChanged(manager) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.owner?.located(last) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Region monitoring reports its own failures below; this is the
        // one-shot fix failing.
        Task { @MainActor in self.owner?.located(nil) }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in self.owner?.crossed(.arrived, region: region) }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in self.owner?.crossed(.left, region: region) }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Nothing to tell anyone: the site's settings already say when the
        // access or the precision rules watching out, and a refresh on the
        // next return to the app tries again.
    }
}
