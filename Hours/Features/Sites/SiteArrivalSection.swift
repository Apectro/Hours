import MapKit
import SwiftUI
import UIKit

/// The site's arrival reminder (1.2), a section of the site's settings.
///
/// Off unless turned on. Turning it on explains first — what it does, that
/// it needs location "Always", that nothing leaves the phone — and only
/// then asks: When In Use for one fix of where the site is (stand at the
/// site), notifications, then Always. The place is shown as coordinates and
/// a small map that cannot be moved; "Clear location" forgets it. Without
/// Always, or without Precise Location, the switch stays on and the section
/// says the reminder cannot work, with a way to Settings.
struct SiteArrivalSection: View {
    @Binding var site: Site
    let isReadOnly: Bool
    /// The other active sites, to say when this one is past the twenty iOS
    /// lets an app watch.
    let otherSites: [Site]

    @Environment(\.openURL) var openURL

    @State private var showsExplanation = false
    @State private var isLocating = false
    @State private var problem: Problem?

    private var arrivals: ArrivalLocation { HoursStack.arrivals }

    private enum Problem {
        case denied
        case noFix
    }

    var body: some View {
        Section {
            Toggle("Remind me when I arrive", isOn: toggleBinding)
                .accessibilityIdentifier("site-editor-arrival")
                .disabled(isReadOnly || isLocating)
                // On the row, not on the Section: a Form hands a Section's
                // modifiers to its rows, and a sheet there never showed.
                .sheet(isPresented: $showsExplanation) {
                    ArrivalExplanationSheet(
                        needsPlace: site.place == nil,
                        onContinue: {
                            showsExplanation = false
                            Task { await turnOn() }
                        },
                        onCancel: { showsExplanation = false }
                    )
                }

            if isLocating {
                HStack(spacing: Metrics.small) {
                    ProgressView()
                    Text("Finding your location…")
                        .foregroundStyle(.secondary)
                }
            }

            if let place = site.place {
                SitePlaceMap(place: place, radius: site.monitoredRadius, name: site.name)
                // One element for VoiceOver and the UI tests: "Place, 45.81302, 15.97722".
                HStack {
                    Text("Place")
                    Spacer(minLength: Metrics.medium)
                    Text(Self.coordinates(place))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("site-arrival-coordinates")
                Picker("Counts as arrived within", selection: $site.arrivalRadius) {
                    ForEach(Site.arrivalRadii, id: \.self) { radius in
                        Text(Self.metres(radius)).tag(radius)
                    }
                }
                .accessibilityIdentifier("site-arrival-radius")
                .disabled(isReadOnly)
                Button("Use my current location") {
                    Task { _ = await locate() }
                }
                .accessibilityIdentifier("site-arrival-use-location")
                .disabled(isReadOnly || isLocating)
                Button("Clear location", role: .destructive) {
                    site.place = nil
                    site.remindsOnArrival = false
                    problem = nil
                }
                .accessibilityIdentifier("site-arrival-clear")
                .disabled(isReadOnly)
            }

            if needsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("site-arrival-settings")
            }
        } header: {
            Text("Arrival reminder")
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.small) {
                ForEach(notices, id: \.self) { Text($0) }
            }
        }
    }

    // MARK: - Turning it on

    /// On, straight away, when everything it needs is already there; the
    /// explanation first otherwise. Off keeps the place for next time.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { site.remindsOnArrival },
            set: { on in
                guard on else {
                    site.remindsOnArrival = false
                    return
                }
                if site.place != nil, arrivals.access == .always {
                    site.remindsOnArrival = true
                } else {
                    showsExplanation = true
                }
            }
        )
    }

    private func turnOn() async {
        problem = nil
        if site.place == nil {
            guard await locate() else { return }
        }
        site.remindsOnArrival = true
        // One system question at a time: the notification's answer first,
        // then the upgrade to Always.
        if !HoursStack.isRunningUITests {
            _ = await ReminderScheduler().requestAuthorization()
        }
        arrivals.requestAlways()
    }

    /// One fix of where the phone is, saved as the site's place.
    private func locate() async -> Bool {
        isLocating = true
        defer { isLocating = false }
        do {
            site.place = try await arrivals.currentPlace()
            problem = nil
            return true
        } catch ArrivalLocation.Failure.denied {
            problem = .denied
        } catch {
            problem = .noFix
        }
        return false
    }

    // MARK: - What the footer says

    private var cannotWatch: Bool {
        site.remindsOnArrival && site.place != nil && (arrivals.access != .always || !arrivals.isPrecise)
    }

    private var needsSettings: Bool {
        problem == .denied || cannotWatch
    }

    private var isPastTheLimit: Bool {
        guard site.monitorsArrival else { return false }
        let others = otherSites.filter { $0.id != site.id }
        return ArrivalReminderPolicy.plan(sites: others + [site]).leftOut.contains { $0.id == site.id }
    }

    private var notices: [String] {
        var lines = [String(localized: "When you reach this site, Zeitkonto asks whether to start the clock, and when you leave with the clock running, whether to stop it. Your location never leaves your phone.")]
        switch problem {
        case .denied:
            lines.append(String(localized: "Location is off for Zeitkonto, so the site's place can't be saved. Turn it on in Settings."))
        case .noFix:
            lines.append(String(localized: "Your location couldn't be found. Try again outdoors."))
        case nil:
            break
        }
        if site.remindsOnArrival, site.place != nil {
            if arrivals.access != .always {
                lines.append(String(localized: "Reminders only work when Zeitkonto may use your location “Always”. Change it in Settings › Zeitkonto › Location."))
            } else if !arrivals.isPrecise {
                lines.append(String(localized: "Precise Location is off for Zeitkonto, so arriving can't be noticed. Turn it on in Settings › Zeitkonto › Location."))
            }
        }
        if isPastTheLimit {
            lines.append(String(localized: "iPhone watches at most 20 sites for one app. This one is past the first 20 sites with a reminder, so it isn't watched."))
        }
        return lines
    }

    // MARK: - Formatting

    /// `45.81302, 15.97722`: the same digits in every language, as a map
    /// app would take them.
    static func coordinates(_ place: SitePlace) -> String {
        String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), place.latitude, place.longitude)
    }

    static func metres(_ radius: Double) -> String {
        Measurement(value: radius, unit: UnitLength.meters).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }
}

/// The site's place on a small map with the reminder's circle. It cannot be
/// moved or zoomed: it shows what was saved, nothing more. The map is drawn
/// by MapKit, which loads Apple's map tiles for that area; the app itself
/// makes no network call.
struct SitePlaceMap: View {
    let place: SitePlace
    let radius: Double
    let name: String

    var body: some View {
        let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        Map(
            initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: radius * 3, longitudinalMeters: radius * 3)),
            interactionModes: []
        ) {
            MapCircle(center: center, radius: radius)
                .foregroundStyle(Color.accentColor.opacity(0.18))
                .stroke(Color.accentColor, lineWidth: 2)
            Marker(name, coordinate: center)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        // A new place or radius is a new picture rather than a camera move.
        .id(SiteArrivalSection.coordinates(place) + "/\(Int(radius))")
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius))
        .allowsHitTesting(false)
        .listRowInsets(EdgeInsets(top: Metrics.small, leading: Metrics.small, bottom: Metrics.small, trailing: Metrics.small))
        .accessibilityElement()
        .accessibilityLabel(Text("Map of the site's place"))
        .accessibilityIdentifier("site-arrival-map")
    }
}

/// What the arrival reminder does and what it needs, before anything is
/// asked of iOS.
struct ArrivalExplanationSheet: View {
    /// No place saved yet, so Continue also takes the current location.
    let needsPlace: Bool
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.large) {
                    Image(systemName: "location.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Remind me when I arrive")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("When you reach this site, Zeitkonto asks whether to start the clock. When you leave with the clock running, it asks whether to stop it. Not on days off, and not twice within two hours.")
                        .accessibilityIdentifier("site-arrival-explanation")
                    if needsPlace {
                        Text("First it saves where the site is, from your current location — so do this standing at the site.")
                    }
                    Text("To notice you arriving while the app is closed, iPhone has to let Zeitkonto use your location “Always”. iPhone asks next: allow it while using the app, then change it to Always.")
                    Text("Your location never leaves your phone. Zeitkonto keeps only the site's saved place, and nothing is sent anywhere.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.large)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onContinue) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("site-arrival-continue")
                .padding(Metrics.large)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now", action: onCancel)
                        .accessibilityIdentifier("site-arrival-cancel")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}
