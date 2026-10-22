import Foundation

/// Everything the extra-work report writes in its own words, in the ten
/// export languages.
///
/// The same mechanism as `ExportTerm` — an enum and one switch, so a term
/// without every translation stops the build — kept in a file of its own so
/// the feature's vocabulary does not have to be threaded through the
/// timesheet's. `language(.extraWork)` reads exactly as `language(.total)`
/// does. Whatever the user typed (a job, an item, a custom unit) is never
/// in here: it is printed as it was written.
enum ExtraWorkTerm: String, CaseIterable, Hashable, Sendable {
    case extraWork, extraWorkReport
    case jobs, items, clientSigned
    case materialInTotal, item, quantity, unit
    case jobsDayByDay, job, workAndMaterial, photos, client
    case confirmed, notConfirmed
    case legend, legendWithoutHours
    case clientSignatureLine, supervisorSignature
    case unitPieces, unitSets
}

extension ExportLanguage {
    func callAsFunction(_ term: ExtraWorkTerm) -> String {
        switch term {
        case .extraWork:
            return pick(en: "Extra work", de: "Regiearbeiten", hr: "Izvanugovorni radovi", sl: "Dodatna dela",
                        it: "Lavori extra", fr: "Travaux supplémentaires", es: "Trabajos adicionales",
                        pt: "Trabalhos adicionais", nl: "Meerwerk", pl: "Prace dodatkowe")
        case .extraWorkReport:
            return pick(en: "Extra work report", de: "Regiebericht", hr: "Izvješće o izvanugovornim radovima",
                        sl: "Poročilo o dodatnih delih", it: "Rapporto lavori extra",
                        fr: "Rapport de travaux supplémentaires", es: "Informe de trabajos adicionales",
                        pt: "Relatório de trabalhos adicionais", nl: "Meerwerkrapport", pl: "Raport prac dodatkowych")
        case .jobs:
            return pick(en: "Jobs", de: "Arbeiten", hr: "Radovi", sl: "Dela", it: "Lavori", fr: "Travaux",
                        es: "Trabajos", pt: "Trabalhos", nl: "Werkzaamheden", pl: "Prace")
        case .items:
            return pick(en: "Items", de: "Positionen", hr: "Stavke", sl: "Postavke", it: "Voci", fr: "Articles",
                        es: "Artículos", pt: "Artigos", nl: "Artikelen", pl: "Pozycje")
        case .clientSigned:
            return pick(en: "Client signed", de: "Unterschrieben", hr: "Potpisano", sl: "Podpisano", it: "Firmati",
                        fr: "Signés", es: "Firmados", pt: "Assinados", nl: "Getekend", pl: "Podpisane")
        case .materialInTotal:
            return pick(en: "Material in total", de: "Material gesamt", hr: "Ukupno materijala", sl: "Material skupaj",
                        it: "Materiale totale", fr: "Total du matériel", es: "Material total", pt: "Material total",
                        nl: "Materiaal totaal", pl: "Materiał łącznie")
        case .item:
            return pick(en: "Item", de: "Artikel", hr: "Stavka", sl: "Postavka", it: "Voce", fr: "Article",
                        es: "Artículo", pt: "Artigo", nl: "Artikel", pl: "Pozycja")
        case .quantity:
            return pick(en: "Quantity", de: "Menge", hr: "Količina", sl: "Količina", it: "Quantità", fr: "Quantité",
                        es: "Cantidad", pt: "Quantidade", nl: "Aantal", pl: "Ilość")
        case .unit:
            return pick(en: "Unit", de: "Einheit", hr: "Jedinica", sl: "Enota", it: "Unità", fr: "Unité",
                        es: "Unidad", pt: "Unidade", nl: "Eenheid", pl: "Jednostka")
        case .jobsDayByDay:
            return pick(en: "Jobs, day by day", de: "Arbeiten, Tag für Tag", hr: "Radovi po danima",
                        sl: "Dela po dnevih", it: "Lavori, giorno per giorno", fr: "Travaux, jour par jour",
                        es: "Trabajos, día a día", pt: "Trabalhos, dia a dia", nl: "Werkzaamheden per dag",
                        pl: "Prace dzień po dniu")
        case .job:
            return pick(en: "Job", de: "Arbeit", hr: "Rad", sl: "Delo", it: "Lavoro", fr: "Travail", es: "Trabajo",
                        pt: "Trabalho", nl: "Werk", pl: "Praca")
        case .workAndMaterial:
            return pick(en: "Work and material", de: "Arbeit und Material", hr: "Rad i materijal",
                        sl: "Delo in material", it: "Lavoro e materiale", fr: "Travail et matériel",
                        es: "Trabajo y material", pt: "Trabalho e material", nl: "Werk en materiaal",
                        pl: "Praca i materiał")
        case .photos:
            return pick(en: "Photos", de: "Fotos", hr: "Fotografije", sl: "Fotografije", it: "Foto", fr: "Photos",
                        es: "Fotos", pt: "Fotos", nl: "Foto’s", pl: "Zdjęcia")
        case .client:
            return pick(en: "Client", de: "Auftraggeber", hr: "Naručitelj", sl: "Naročnik", it: "Committente",
                        fr: "Client", es: "Cliente", pt: "Cliente", nl: "Opdrachtgever", pl: "Zleceniodawca")
        case .confirmed:
            return pick(en: "signed", de: "unterschrieben", hr: "potpisano", sl: "podpisano", it: "firmato",
                        fr: "signé", es: "firmado", pt: "assinado", nl: "getekend", pl: "podpisano")
        case .notConfirmed:
            return pick(en: "open", de: "offen", hr: "otvoreno", sl: "odprto", it: "aperto", fr: "ouvert",
                        es: "abierto", pt: "aberto", nl: "open", pl: "otwarte")
        case .legend:
            return pick(
                en: "Quantities as fitted on site. Hours are listed only where they were noted. "
                    + "Orange = not yet confirmed by the client.",
                de: "Mengen wie auf der Baustelle eingebaut. Stunden nur, wo sie notiert wurden. "
                    + "Orange = vom Auftraggeber noch nicht bestätigt.",
                hr: "Količine kako su ugrađene na gradilištu. Sati su navedeni samo gdje su zabilježeni. "
                    + "Narančasto = naručitelj još nije potvrdio.",
                sl: "Količine, kot so bile vgrajene na gradbišču. Ure so navedene le, kjer so bile zapisane. "
                    + "Oranžno = naročnik še ni potrdil.",
                it: "Quantità come posate in cantiere. Le ore sono indicate solo dove sono state annotate. "
                    + "Arancione = non ancora confermato dal committente.",
                fr: "Quantités telles que posées sur le chantier. Les heures ne figurent que là où elles ont été "
                    + "notées. Orange = pas encore confirmé par le client.",
                es: "Cantidades tal como se colocaron en obra. Las horas figuran solo donde se anotaron. "
                    + "Naranja = aún no confirmado por el cliente.",
                pt: "Quantidades tal como aplicadas em obra. As horas só aparecem onde foram anotadas. "
                    + "Laranja = ainda não confirmado pelo cliente.",
                nl: "Hoeveelheden zoals op de bouwplaats aangebracht. Uren staan er alleen waar ze zijn genoteerd. "
                    + "Oranje = nog niet bevestigd door de opdrachtgever.",
                pl: "Ilości według montażu na budowie. Godziny podano tylko tam, gdzie je zapisano. "
                    + "Pomarańczowy = jeszcze niepotwierdzone przez zleceniodawcę."
            )
        case .legendWithoutHours:
            return pick(
                en: "Quantities as fitted on site. Orange = not yet confirmed by the client.",
                de: "Mengen wie auf der Baustelle eingebaut. Orange = vom Auftraggeber noch nicht bestätigt.",
                hr: "Količine kako su ugrađene na gradilištu. Narančasto = naručitelj još nije potvrdio.",
                sl: "Količine, kot so bile vgrajene na gradbišču. Oranžno = naročnik še ni potrdil.",
                it: "Quantità come posate in cantiere. Arancione = non ancora confermato dal committente.",
                fr: "Quantités telles que posées sur le chantier. Orange = pas encore confirmé par le client.",
                es: "Cantidades tal como se colocaron en obra. Naranja = aún no confirmado por el cliente.",
                pt: "Quantidades tal como aplicadas em obra. Laranja = ainda não confirmado pelo cliente.",
                nl: "Hoeveelheden zoals op de bouwplaats aangebracht. Oranje = nog niet bevestigd door de "
                    + "opdrachtgever.",
                pl: "Ilości według montażu na budowie. Pomarańczowy = jeszcze niepotwierdzone przez zleceniodawcę."
            )
        case .clientSignatureLine:
            return pick(en: "Client · date, signature", de: "Auftraggeber · Datum, Unterschrift",
                        hr: "Naručitelj · datum, potpis", sl: "Naročnik · datum, podpis",
                        it: "Committente · data, firma", fr: "Client · date, signature",
                        es: "Cliente · fecha, firma", pt: "Cliente · data, assinatura",
                        nl: "Opdrachtgever · datum, handtekening", pl: "Zleceniodawca · data, podpis")
        case .supervisorSignature:
            return pick(en: "Supervisor · date, signature", de: "Bauleiter · Datum, Unterschrift",
                        hr: "Voditelj radova · datum, potpis", sl: "Vodja del · datum, podpis",
                        it: "Capocantiere · data, firma", fr: "Chef de chantier · date, signature",
                        es: "Encargado · fecha, firma", pt: "Encarregado · data, assinatura",
                        nl: "Uitvoerder · datum, handtekening", pl: "Kierownik robót · data, podpis")
        case .unitPieces:
            return pick(en: "pcs", de: "Stk", hr: "kom", sl: "kos", it: "pz", fr: "pce", es: "ud", pt: "un",
                        nl: "st", pl: "szt")
        case .unitSets:
            return pick(en: "set", de: "Satz", hr: "kompl.", sl: "kpl.", it: "set", fr: "lot", es: "juego",
                        pt: "conj.", nl: "set", pl: "kpl.")
        }
    }
}
