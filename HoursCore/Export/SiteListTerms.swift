import Foundation

/// The words a site's defects list and a delivery's message write, in the
/// ten export languages (1.3).
///
/// The same mechanism as `ExportTerm` and `ExtraWorkTerm` — an enum and one
/// switch, so a term without every translation stops the build. What the
/// user typed (what's wrong, a floor, a room, an item) is never in here.
/// Terms with a `%@` or `%d` are formats, filled with `String(format:)`
/// because the value sits in a different place in some languages.
enum SiteListTerm: String, CaseIterable, Hashable, Sendable {
    /// "Trg Pravde Zagreb · Defects" and the PDF's eyebrow.
    case defects
    /// "4 open", after the date on the defects list.
    case openCount
    /// "since 3 Nov": how long an open defect has been there.
    case since
    /// "fixed 4 Nov".
    case fixedOn
    /// "Fixes: Ivan".
    case fixes
    /// "Fixes: nobody yet".
    case nobodyYet
    /// "Fixes: me", when the defect is yours and the sheets have no name.
    case me
    /// The sign-off's own page of them.
    case openDefects
    /// "Trg Pravde Zagreb · delivery, 4 Nov".
    case delivery
    // The defects PDF (1.4, Polish pages 22–24).
    /// "as of 4 Nov 2026", after the address and in the footer.
    case asOf
    /// A defect's status in the table: "Open", and "Open · 9 days".
    case statusOpen
    /// "Fixed 2 Nov", in the table.
    case statusFixed
    /// Under the figures on the first page: "4 open", "7 fixed".
    case figureOpen
    case figureFixed
    /// "oldest open (since 26 Oct)", under "9 days".
    case oldestOpen
    /// "most open (2)", under the floor's name.
    case mostOpen
    /// The table's columns.
    case columnNumber
    case columnWhat
    case columnWhere
    case columnSince
    case columnFixes
    case columnStatus
    /// The group of defects noted without a floor.
    case noFloor
    /// The line under the table: "…from page 2."
    case halfPageNote
    /// "Noted 3 Nov, 14:12 by Ivan", and without a name, "Noted 3 Nov, 14:12".
    case notedBy
    case notedOn
    /// "Open for 9 days", and noted the day of the list.
    case openFor
    case openSinceToday
    /// The boxes ticked on paper walking the site: Fixed, Date, Initials.
    case boxFixed
    case boxDate
    case boxInitials
    case stillMissing
    case cameAnyway
    case everythingCame
}

extension ExportLanguage {
    func callAsFunction(_ term: SiteListTerm) -> String {
        switch term {
        case .defects:
            return pick(en: "Defects", de: "Mängel", hr: "Nedostaci", sl: "Pomanjkljivosti", it: "Difetti",
                        fr: "Défauts", es: "Defectos", pt: "Defeitos", nl: "Gebreken", pl: "Usterki")
        case .openCount:
            return pick(en: "%d open", de: "%d offen", hr: "otvoreno: %d", sl: "odprto: %d", it: "%d aperti",
                        fr: "%d ouverts", es: "%d abiertos", pt: "%d em aberto", nl: "%d open", pl: "otwarte: %d")
        case .since:
            return pick(en: "since %@", de: "seit %@", hr: "od %@", sl: "od %@", it: "dal %@", fr: "depuis le %@",
                        es: "desde el %@", pt: "desde %@", nl: "sinds %@", pl: "od %@")
        case .fixedOn:
            return pick(en: "fixed %@", de: "behoben %@", hr: "popravljeno %@", sl: "odpravljeno %@",
                        it: "risolto il %@", fr: "corrigé le %@", es: "arreglado el %@", pt: "corrigido a %@",
                        nl: "verholpen %@", pl: "naprawione %@")
        case .fixes:
            return pick(en: "Fixes: %@", de: "Behebt: %@", hr: "Popravlja: %@", sl: "Odpravi: %@", it: "Risolve: %@",
                        fr: "Corrige : %@", es: "Arregla: %@", pt: "Corrige: %@", nl: "Verhelpt: %@", pl: "Naprawia: %@")
        case .nobodyYet:
            return pick(en: "nobody yet", de: "noch niemand", hr: "još nitko", sl: "še nihče", it: "ancora nessuno",
                        fr: "personne pour l’instant", es: "nadie todavía", pt: "ninguém ainda", nl: "nog niemand",
                        pl: "jeszcze nikt")
        case .me:
            return pick(en: "me", de: "ich", hr: "ja", sl: "jaz", it: "io", fr: "moi", es: "yo", pt: "eu", nl: "ik", pl: "ja")
        case .openDefects:
            return pick(en: "Open defects", de: "Offene Mängel", hr: "Otvoreni nedostaci", sl: "Odprte pomanjkljivosti",
                        it: "Difetti aperti", fr: "Défauts ouverts", es: "Defectos abiertos", pt: "Defeitos em aberto",
                        nl: "Openstaande gebreken", pl: "Otwarte usterki")
        case .delivery:
            // After the site's name and before the date: "· delivery, 4 Nov".
            return pick(en: "delivery", de: "Lieferung", hr: "isporuka", sl: "dobava", it: "consegna", fr: "livraison",
                        es: "entrega", pt: "entrega", nl: "levering", pl: "dostawa")
        case .asOf:
            return pick(en: "as of %@", de: "Stand %@", hr: "stanje na %@", sl: "stanje na dan %@", it: "al %@",
                        fr: "au %@", es: "a %@", pt: "em %@", nl: "per %@", pl: "stan na %@")
        case .statusOpen:
            return pick(en: "Open", de: "Offen", hr: "Otvoreno", sl: "Odprto", it: "Aperto", fr: "Ouvert",
                        es: "Abierto", pt: "Em aberto", nl: "Open", pl: "Otwarte")
        case .statusFixed:
            return pick(en: "Fixed %@", de: "Behoben %@", hr: "Popravljeno %@", sl: "Odpravljeno %@",
                        it: "Risolto il %@", fr: "Corrigé le %@", es: "Arreglado el %@", pt: "Corrigido a %@",
                        nl: "Verholpen %@", pl: "Naprawione %@")
        case .figureOpen:
            return pick(en: "open", de: "offen", hr: "otvoreno", sl: "odprto", it: "aperti", fr: "ouverts",
                        es: "abiertos", pt: "em aberto", nl: "open", pl: "otwarte")
        case .figureFixed:
            return pick(en: "fixed", de: "behoben", hr: "popravljeno", sl: "odpravljeno", it: "risolti",
                        fr: "corrigés", es: "arreglados", pt: "corrigidos", nl: "verholpen", pl: "naprawione")
        case .oldestOpen:
            return pick(en: "oldest open (since %@)", de: "am längsten offen (seit %@)", hr: "najdulje otvoreno (od %@)",
                        sl: "najdlje odprto (od %@)", it: "aperto da più tempo (dal %@)",
                        fr: "ouvert le plus ancien (depuis le %@)", es: "abierto más antiguo (desde el %@)",
                        pt: "em aberto há mais tempo (desde %@)", nl: "langst open (sinds %@)",
                        pl: "najdłużej otwarte (od %@)")
        case .mostOpen:
            return pick(en: "most open (%d)", de: "die meisten offenen (%d)", hr: "najviše otvorenih (%d)",
                        sl: "največ odprtih (%d)", it: "più aperti (%d)", fr: "le plus d’ouverts (%d)",
                        es: "más abiertos (%d)", pt: "mais em aberto (%d)", nl: "meeste open (%d)",
                        pl: "najwięcej otwartych (%d)")
        case .columnNumber:
            return pick(en: "No.", de: "Nr.", hr: "Br.", sl: "Št.", it: "N.", fr: "N°", es: "N.º", pt: "N.º",
                        nl: "Nr.", pl: "Nr")
        case .columnWhat:
            return pick(en: "What's wrong", de: "Mangel", hr: "Što ne valja", sl: "Kaj je narobe", it: "Cosa non va",
                        fr: "Problème", es: "Qué falla", pt: "O que está mal", nl: "Wat is er mis", pl: "Co jest nie tak")
        case .columnWhere:
            return pick(en: "Where", de: "Wo", hr: "Gdje", sl: "Kje", it: "Dove", fr: "Où", es: "Dónde", pt: "Onde",
                        nl: "Waar", pl: "Gdzie")
        case .columnSince:
            return pick(en: "Since", de: "Seit", hr: "Od", sl: "Od", it: "Dal", fr: "Depuis", es: "Desde", pt: "Desde",
                        nl: "Sinds", pl: "Od")
        case .columnFixes:
            return pick(en: "Fixes", de: "Behebt", hr: "Popravlja", sl: "Odpravi", it: "Risolve", fr: "Corrige",
                        es: "Arregla", pt: "Corrige", nl: "Verhelpt", pl: "Naprawia")
        case .columnStatus:
            return pick(en: "Status", de: "Status", hr: "Status", sl: "Stanje", it: "Stato", fr: "Statut",
                        es: "Estado", pt: "Estado", nl: "Status", pl: "Status")
        case .noFloor:
            return pick(en: "No floor", de: "Ohne Geschoss", hr: "Bez kata", sl: "Brez nadstropja", it: "Senza piano",
                        fr: "Sans étage", es: "Sin planta", pt: "Sem piso", nl: "Zonder verdieping", pl: "Bez piętra")
        case .halfPageNote:
            return pick(en: "Each open defect has its own half page with the photo, from page %d.",
                        de: "Jeder offene Mangel hat ab Seite %d eine eigene halbe Seite mit dem Foto.",
                        hr: "Svaki otvoreni nedostatak ima od stranice %d svoju pola stranice s fotografijom.",
                        sl: "Vsaka odprta pomanjkljivost ima od strani %d svojo polovico strani s fotografijo.",
                        it: "Ogni difetto aperto ha la sua mezza pagina con la foto, dalla pagina %d.",
                        fr: "Chaque défaut ouvert a sa demi-page avec la photo, à partir de la page %d.",
                        es: "Cada defecto abierto tiene su media página con la foto, desde la página %d.",
                        pt: "Cada defeito em aberto tem a sua meia página com a foto, a partir da página %d.",
                        nl: "Elk open gebrek heeft vanaf pagina %d een eigen halve pagina met de foto.",
                        pl: "Każda otwarta usterka ma od strony %d własne pół strony ze zdjęciem.")
        case .notedBy:
            return pick(en: "Noted %1$@ by %2$@", de: "Erfasst %1$@ von %2$@", hr: "Zabilježeno %1$@ (%2$@)",
                        sl: "Zabeleženo %1$@ (%2$@)", it: "Annotato il %1$@ da %2$@", fr: "Noté le %1$@ par %2$@",
                        es: "Anotado el %1$@ por %2$@", pt: "Registado a %1$@ por %2$@", nl: "Genoteerd %1$@ door %2$@",
                        pl: "Zgłoszone %1$@ (%2$@)")
        case .notedOn:
            return pick(en: "Noted %@", de: "Erfasst %@", hr: "Zabilježeno %@", sl: "Zabeleženo %@",
                        it: "Annotato il %@", fr: "Noté le %@", es: "Anotado el %@", pt: "Registado a %@",
                        nl: "Genoteerd %@", pl: "Zgłoszone %@")
        case .openFor:
            return pick(en: "Open for %@", de: "Offen: %@", hr: "Otvoreno: %@", sl: "Odprto: %@", it: "Aperto da %@",
                        fr: "Ouvert depuis %@", es: "Abierto desde hace %@", pt: "Em aberto há %@", nl: "Al %@ open",
                        pl: "Otwarte: %@")
        case .openSinceToday:
            return pick(en: "Open since today", de: "Offen seit heute", hr: "Otvoreno od danas", sl: "Odprto od danes",
                        it: "Aperto da oggi", fr: "Ouvert depuis aujourd’hui", es: "Abierto desde hoy",
                        pt: "Em aberto desde hoje", nl: "Sinds vandaag open", pl: "Otwarte od dziś")
        case .boxFixed:
            return pick(en: "Fixed", de: "Behoben", hr: "Popravljeno", sl: "Odpravljeno", it: "Risolto", fr: "Corrigé",
                        es: "Arreglado", pt: "Corrigido", nl: "Verholpen", pl: "Naprawione")
        case .boxDate:
            return pick(en: "Date", de: "Datum", hr: "Datum", sl: "Datum", it: "Data", fr: "Date", es: "Fecha",
                        pt: "Data", nl: "Datum", pl: "Data")
        case .boxInitials:
            return pick(en: "Initials", de: "Kürzel", hr: "Inicijali", sl: "Začetnice", it: "Iniziali", fr: "Initiales",
                        es: "Iniciales", pt: "Iniciais", nl: "Paraaf", pl: "Parafa")
        case .stillMissing:
            return pick(en: "Still missing:", de: "Fehlt noch:", hr: "Još nedostaje:", sl: "Še manjka:",
                        it: "Manca ancora:", fr: "Manque encore :", es: "Todavía falta:", pt: "Ainda falta:",
                        nl: "Ontbreekt nog:", pl: "Nadal brakuje:")
        case .cameAnyway:
            return pick(en: "Not ordered, came anyway:", de: "Nicht bestellt, trotzdem geliefert:",
                        hr: "Nije naručeno, a stiglo je:", sl: "Ni naročeno, pa je prispelo:",
                        it: "Non ordinato, arrivato comunque:", fr: "Non commandé, livré quand même :",
                        es: "No pedido, llegó igualmente:", pt: "Não encomendado, chegou na mesma:",
                        nl: "Niet besteld, toch geleverd:", pl: "Niezamówione, a dotarło:")
        case .everythingCame:
            return pick(en: "Everything ordered came.", de: "Alles Bestellte ist gekommen.", hr: "Stiglo je sve naručeno.",
                        sl: "Prispelo je vse naročeno.", it: "È arrivato tutto l’ordinato.",
                        fr: "Tout ce qui était commandé est arrivé.", es: "Llegó todo lo pedido.",
                        pt: "Chegou tudo o que foi encomendado.", nl: "Alles wat besteld was, is gekomen.",
                        pl: "Dotarło wszystko, co zamówiono.")
        }
    }

    /// A term that is a format, filled in.
    func callAsFunction(_ term: SiteListTerm, _ value: String) -> String {
        String(format: self(term), value)
    }

    func callAsFunction(_ term: SiteListTerm, count: Int) -> String {
        String(format: self(term), count)
    }
}

extension ExportLanguage {
    /// "1 day", "9 days": how long a defect has been open.
    func days(_ count: Int) -> String {
        let noun: String
        switch pluralCategory(count) {
        case .one:
            noun = pick(en: "day", de: "Tag", hr: "dan", sl: "dan", it: "giorno", fr: "jour", es: "día", pt: "dia",
                        nl: "dag", pl: "dzień")
        case .two:
            noun = pick(en: "days", de: "Tage", hr: "dana", sl: "dneva", it: "giorni", fr: "jours", es: "días",
                        pt: "dias", nl: "dagen", pl: "dni")
        case .few:
            noun = pick(en: "days", de: "Tage", hr: "dana", sl: "dnevi", it: "giorni", fr: "jours", es: "días",
                        pt: "dias", nl: "dagen", pl: "dni")
        case .many, .other:
            noun = pick(en: "days", de: "Tage", hr: "dana", sl: "dni", it: "giorni", fr: "jours", es: "días",
                        pt: "dias", nl: "dagen", pl: "dni")
        }
        return "\(count) \(noun)"
    }
}
