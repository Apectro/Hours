import SwiftUI

/// A colour per site (2026-11-24), the same on every screen: the site's
/// palette index (`SitePalette`), stored nowhere. Your own hours are the
/// neutral ink colour, `Color.primary`.
///
/// System colours, so each has its Light and Dark value. None of them is
/// one the colour rule gives a meaning to (blue: tap it, green: done,
/// orange: look at this, red: missing), and colour is never the only
/// sign: the calendar's VoiceOver label names the site and its hours, and
/// the day card writes the name beside the dot.
struct SiteColors: Equatable {
    private let indexes: [UUID: Int]

    init(sites: [Site] = []) {
        self.indexes = SitePalette.indexes(of: sites)
    }

    /// As many as `SitePalette.count`.
    static let palette: [Color] = [.teal, .purple, .pink, .brown, .mint, .indigo]

    func color(for siteID: UUID) -> Color {
        let index = indexes[siteID] ?? SitePalette.fallbackIndex(for: siteID)
        return Self.palette[index % Self.palette.count]
    }
}

/// The thin bar on a worked day's tile: one segment per source, the sites
/// that day in the order worked, then your own hours. Under a filter, that
/// source's segment alone. Decoration: the tile's label says it in words.
struct SourceBar: View {
    let sources: DaySources
    let colors: SiteColors
    var filter: SourceFilter = .all
    /// On today's filled tile: a white backing, and your own hours dark, so
    /// every segment reads on the accent.
    var isOnAccent = false

    private var siteParts: [DaySources.SitePart] {
        switch filter {
        case .all: return sources.sites
        case let .site(id): return sources.sites.filter { $0.siteID == id }
        case .own: return []
        }
    }

    private var showsOwn: Bool {
        guard sources.ownMinutes > 0 else { return false }
        switch filter {
        case .all, .own: return true
        case .site: return false
        }
    }

    var body: some View {
        let parts = siteParts
        if !parts.isEmpty || showsOwn {
            HStack(spacing: 2) {
                ForEach(parts, id: \.siteID) { part in
                    Capsule().fill(colors.color(for: part.siteID))
                }
                if showsOwn {
                    Capsule().fill(isOnAccent ? Color.black.opacity(0.75) : Color.primary)
                }
            }
            .frame(height: 3)
            .padding(isOnAccent ? 1.5 : 0)
            .background {
                if isOnAccent {
                    Capsule().fill(Color.white.opacity(0.92))
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// A source's dot, beside its name: on a chip, a day card row, the Write
/// today sheet. Nil is your own hours.
struct SourceDot: View {
    let color: Color?

    var body: some View {
        Circle()
            .fill(color ?? Color.primary)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// The chips above the month: All · a chip per active site with hours in
/// the period · Own. The legend is the filter: a site's chip carries its
/// colour. Shown only when there is at least one site; the choice is the
/// screen's, and is not kept across launches.
struct SourceFilterChips: View {
    let filters: [SourceFilter]
    let selected: SourceFilter
    let siteNames: [UUID: String]
    let colors: SiteColors
    let onSelect: (SourceFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.small) {
                ForEach(Array(filters.enumerated()), id: \.element) { index, filter in
                    chip(filter, index: index)
                }
            }
            .padding(.horizontal, Metrics.medium)
        }
    }

    private func chip(_ filter: SourceFilter, index: Int) -> some View {
        let isOn = filter == selected
        return Button {
            onSelect(filter)
        } label: {
            HStack(spacing: 6) {
                switch filter {
                case .all:
                    EmptyView()
                case let .site(id):
                    SourceDot(color: colors.color(for: id))
                case .own:
                    SourceDot(color: isOn ? Color.white : nil)
                }
                Text(verbatim: title(filter))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, Metrics.medium)
            .frame(minHeight: 34)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: Capsule())
            // The chip is drawn 34 points high and taken on 44.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityHint(Text("Shows only these hours in the calendar"))
        .accessibilityIdentifier(identifier(filter, index: index))
    }

    private func title(_ filter: SourceFilter) -> String {
        switch filter {
        case .all: return String(localized: "All", comment: "Calendar filter chip: every source of hours")
        case let .site(id): return siteNames[id] ?? String(localized: "Site")
        case .own: return String(localized: "Own", comment: "Calendar filter chip: hours that are on no site")
        }
    }

    /// "calendar-filter-all", "calendar-filter-site-0" (the first site
    /// chip), "calendar-filter-own".
    private func identifier(_ filter: SourceFilter, index: Int) -> String {
        switch filter {
        case .all: return "calendar-filter-all"
        case .site: return "calendar-filter-site-\(index - 1)"
        case .own: return "calendar-filter-own"
        }
    }
}
