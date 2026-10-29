import Foundation

/// Where a site is: a point on the globe, saved once from "Use my current
/// location" for the opt-in arrival reminder (1.2). Plain numbers, so the
/// engine needs no CoreLocation and the backup writes two keys.
struct SitePlace: Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    /// A point that exists: finite, latitude within ±90 and longitude within
    /// ±180. Anything else — a damaged backup, half a pair — is no place.
    init?(latitude: Double?, longitude: Double?) {
        guard
            let latitude, let longitude,
            latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension Site {
    /// What "how close counts as arrived" offers, in metres. Region
    /// monitoring is not reliable much below 100 m, and beyond 500 m the
    /// reminder comes from the next street.
    static let arrivalRadii: [Double] = [100, 150, 300, 500]
    static let defaultArrivalRadius: Double = 150

    /// The site's place, when both coordinates are there and on the globe.
    /// Setting it writes both; `nil` clears both ("Clear location").
    var place: SitePlace? {
        get { SitePlace(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue?.latitude
            longitude = newValue?.longitude
        }
    }

    /// The radius actually watched: the stored one held to the choices'
    /// range, and the default when none was ever stored.
    var monitoredRadius: Double {
        guard arrivalRadius.isFinite, arrivalRadius > 0 else { return Site.defaultArrivalRadius }
        let smallest = Site.arrivalRadii.first ?? Site.defaultArrivalRadius
        let largest = Site.arrivalRadii.last ?? Site.defaultArrivalRadius
        return min(largest, max(smallest, arrivalRadius))
    }

    /// Whether the phone should watch for this site: the switch on, a place
    /// saved, and the site still active. The switch alone watches nothing.
    var monitorsArrival: Bool {
        remindsOnArrival && place != nil && !isArchived
    }
}
