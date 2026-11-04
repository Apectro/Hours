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
