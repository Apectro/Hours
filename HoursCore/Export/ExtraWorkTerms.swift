import Foundation

/// Everything the extra-work report writes in its own words, in the ten
/// export languages.
///
/// The same mechanism as `ExportTerm` — an enum and one switch, so a term
/// without every translation stops the build — kept in a file of its own so
/// the feature's vocabulary does not have to be threaded through the
/// timesheet's. `language(.extraWorkDone)` reads exactly as
/// `language(.total)` does. Whatever the user typed (a job, an item, a custom
/// unit) is never in here: it is printed as it was written.
///
/// The report tells the boss what is done. It is not a bill, so none of these
/// words is one of invoicing (no Regie, no Rechnung, no račun), and there are
/// no lines left empty for anyone to sign on.
enum ExtraWorkTerm: String, CaseIterable, Hashable, Sendable {
    case extraWorkDone
    case jobs, jobsDone, inProgress, photos
    case workDoneDayByDay, stillInProgress, job, workAndMaterial
    case materialUsed, item, quantity, unit
    case who
    case progress, progressDone, progressInProgress
    case confirmedOnSite, confirmedOnSiteBy
    case legend, legendWithoutHours
    case unitPieces, unitSets
}

extension ExportLanguage {
    func callAsFunction(_ term: ExtraWorkTerm) -> String {
        switch term {
        case .extraWorkDone:
            return pick(en: "Extra work done", de: "Erledigte Zusatzarbeiten", hr: "Izvršeni dodatni radovi",
                        sl: "Opravljena dodatna dela", it: "Lavori extra eseguiti",
                        fr: "Travaux supplémentaires réalisés", es: "Trabajos adicionales realizados",
                        pt: "Trabalhos adicionais realizados", nl: "Uitgevoerd meerwerk",
                        pl: "Wykonane prace dodatkowe")
        case .jobs:
            return pick(en: "Jobs", de: "Arbeiten", hr: "Radovi", sl: "Dela", it: "Lavori", fr: "Travaux",
                        es: "Trabajos", pt: "Trabalhos", nl: "Werkzaamheden", pl: "Prace")
        case .jobsDone:
            return pick(en: "Jobs done", de: "Erledigt", hr: "Završeno", sl: "Končano", it: "Finiti",
                        fr: "Terminés", es: "Terminados", pt: "Concluídos", nl: "Klaar", pl: "Ukończone")
        case .inProgress:
            return pick(en: "In progress", de: "In Arbeit", hr: "U tijeku", sl: "V teku", it: "In corso",
                        fr: "En cours", es: "En curso", pt: "Em curso", nl: "Bezig", pl: "W toku")
        case .photos:
            return pick(en: "Photos", de: "Fotos", hr: "Fotografije", sl: "Fotografije", it: "Foto", fr: "Photos",
                        es: "Fotos", pt: "Fotos", nl: "Foto’s", pl: "Zdjęcia")
        case .workDoneDayByDay:
            return pick(en: "Work done, day by day", de: "Erledigte Arbeiten, Tag für Tag",
                        hr: "Izvršeni radovi po danima", sl: "Opravljena dela po dnevih",
                        it: "Lavori eseguiti, giorno per giorno", fr: "Travaux réalisés, jour par jour",
                        es: "Trabajos realizados, día a día", pt: "Trabalhos realizados, dia a dia",
                        nl: "Uitgevoerd werk per dag", pl: "Wykonane prace dzień po dniu")
        case .stillInProgress:
            return pick(en: "Still in progress", de: "Noch in Arbeit", hr: "Još u tijeku", sl: "Še v teku",
                        it: "Ancora in corso", fr: "Toujours en cours", es: "Todavía en curso",
                        pt: "Ainda em curso", nl: "Nog bezig", pl: "Wciąż w toku")
        case .job:
            return pick(en: "Job", de: "Arbeit", hr: "Rad", sl: "Delo", it: "Lavoro", fr: "Travail", es: "Trabajo",
                        pt: "Trabalho", nl: "Werk", pl: "Praca")
        case .workAndMaterial:
            return pick(en: "Work and material", de: "Arbeit und Material", hr: "Rad i materijal",
                        sl: "Delo in material", it: "Lavoro e materiale", fr: "Travail et matériel",
                        es: "Trabajo y material", pt: "Trabalho e material", nl: "Werk en materiaal",
                        pl: "Praca i materiał")
        case .materialUsed:
            return pick(en: "Material used", de: "Verwendetes Material", hr: "Utrošeni materijal",
                        sl: "Porabljen material", it: "Materiale utilizzato", fr: "Matériel utilisé",
                        es: "Material utilizado", pt: "Material utilizado", nl: "Gebruikt materiaal",
                        pl: "Zużyty materiał")
        case .item:
            return pick(en: "Item", de: "Artikel", hr: "Stavka", sl: "Postavka", it: "Voce", fr: "Article",
                        es: "Artículo", pt: "Artigo", nl: "Artikel", pl: "Pozycja")
        case .quantity:
            return pick(en: "Quantity", de: "Menge", hr: "Količina", sl: "Količina", it: "Quantità", fr: "Quantité",
                        es: "Cantidad", pt: "Quantidade", nl: "Aantal", pl: "Ilość")
        case .unit:
            return pick(en: "Unit", de: "Einheit", hr: "Jedinica", sl: "Enota", it: "Unità", fr: "Unité",
                        es: "Unidad", pt: "Unidade", nl: "Eenheid", pl: "Jednostka")
        case .who:
            // The column of who was on a job, beside how long it took.
            return pick(en: "Who", de: "Wer", hr: "Tko", sl: "Kdo", it: "Chi", fr: "Qui", es: "Quién", pt: "Quem",
                        nl: "Wie", pl: "Kto")
        case .progress:
            return pick(en: "Status", de: "Stand", hr: "Stanje", sl: "Stanje", it: "Stato", fr: "État",
                        es: "Estado", pt: "Estado", nl: "Stand", pl: "Stan")
        case .progressDone:
            return pick(en: "done", de: "erledigt", hr: "završeno", sl: "končano", it: "finito", fr: "terminé",
                        es: "terminado", pt: "concluído", nl: "klaar", pl: "ukończone")
        case .progressInProgress:
            return pick(en: "in progress", de: "in Arbeit", hr: "u tijeku", sl: "v teku", it: "in corso",
                        fr: "en cours", es: "en curso", pt: "em curso", nl: "bezig", pl: "w toku")
        case .confirmedOnSite:
            return pick(en: "Confirmed on site", de: "Vor Ort bestätigt", hr: "Potvrđeno na gradilištu",
                        sl: "Potrjeno na gradbišču", it: "Confermato in cantiere", fr: "Confirmé sur le chantier",
                        es: "Confirmado en obra", pt: "Confirmado em obra", nl: "Bevestigd op de bouwplaats",
                        pl: "Potwierdzone na budowie")
        case .confirmedOnSiteBy:
            // Followed by a name. Where "by" would have to agree with the
            // signer, a colon says the same thing.
            return pick(en: "Confirmed on site by", de: "Vor Ort bestätigt von", hr: "Potvrđeno na gradilištu:",
                        sl: "Potrjeno na gradbišču:", it: "Confermato in cantiere da",
                        fr: "Confirmé sur le chantier par", es: "Confirmado en obra por",
                        pt: "Confirmado em obra por", nl: "Bevestigd op de bouwplaats door",
                        pl: "Potwierdzone na budowie przez")
        case .legend:
            return pick(
                en: "Quantities as fitted on site. Hours are listed only where they were noted.",
                de: "Mengen wie auf der Baustelle eingebaut. Stunden nur, wo sie notiert wurden.",
                hr: "Količine kako su ugrađene na gradilištu. Sati su navedeni samo gdje su zabilježeni.",
                sl: "Količine, kot so bile vgrajene na gradbišču. Ure so navedene le, kjer so bile zapisane.",
                it: "Quantità come posate in cantiere. Le ore sono indicate solo dove sono state annotate.",
                fr: "Quantités telles que posées sur le chantier. Les heures ne figurent que là où elles ont été "
                    + "notées.",
                es: "Cantidades tal como se colocaron en obra. Las horas figuran solo donde se anotaron.",
                pt: "Quantidades tal como aplicadas em obra. As horas só aparecem onde foram anotadas.",
                nl: "Hoeveelheden zoals op de bouwplaats aangebracht. Uren staan er alleen waar ze zijn genoteerd.",
                pl: "Ilości według montażu na budowie. Godziny podano tylko tam, gdzie je zapisano."
            )
        case .legendWithoutHours:
            return pick(
                en: "Quantities as fitted on site.",
                de: "Mengen wie auf der Baustelle eingebaut.",
                hr: "Količine kako su ugrađene na gradilištu.",
                sl: "Količine, kot so bile vgrajene na gradbišču.",
                it: "Quantità come posate in cantiere.",
                fr: "Quantités telles que posées sur le chantier.",
                es: "Cantidades tal como se colocaron en obra.",
                pt: "Quantidades tal como aplicadas em obra.",
                nl: "Hoeveelheden zoals op de bouwplaats aangebracht.",
                pl: "Ilości według montażu na budowie."
            )
        case .unitPieces:
            return pick(en: "pcs", de: "Stk", hr: "kom", sl: "kos", it: "pz", fr: "pce", es: "ud", pt: "un",
                        nl: "st", pl: "szt")
        case .unitSets:
            return pick(en: "set", de: "Satz", hr: "kompl.", sl: "kpl.", it: "set", fr: "lot", es: "juego",
                        pt: "conj.", nl: "set", pl: "kpl.")
        }
    }
}
