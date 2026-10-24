import Foundation

/// The words of the payslip check's note to payroll, in the ten export
/// languages.
///
/// The same mechanism as `ExportTerm` and `ExtraWorkTerm`: an enum and one
/// switch, so a term without every translation stops the build. The figures'
/// own names (Worked, Overtime, Sick leave, Vacation) are the timesheet's
/// `ExportTerm`s, so the note and the timesheet payroll already has use the
/// same words. Payroll is addressed formally, as a letter to an office is.
enum PayslipTerm: String, CaseIterable, Hashable, Sendable {
    case payslipCheck
    case myRecords, payslip, difference, matches
    case grossPay
    case pleaseCheck
}

extension ExportLanguage {
    func callAsFunction(_ term: PayslipTerm) -> String {
        switch term {
        case .payslipCheck:
            return pick(en: "Payslip check", de: "Kontrolle der Lohnabrechnung", hr: "Provjera platne liste",
                        sl: "Preverjanje plačilne liste", it: "Verifica della busta paga",
                        fr: "Vérification de la fiche de paie", es: "Comprobación de la nómina",
                        pt: "Verificação do recibo de vencimento", nl: "Controle van de loonstrook",
                        pl: "Sprawdzenie paska wypłaty")
        case .myRecords:
            return pick(en: "my records", de: "meine Aufzeichnungen", hr: "moja evidencija", sl: "moja evidenca",
                        it: "i miei dati", fr: "mes relevés", es: "mis registros", pt: "os meus registos",
                        nl: "mijn registratie", pl: "moje zapisy")
        case .payslip:
            return pick(en: "payslip", de: "Lohnabrechnung", hr: "platna lista", sl: "plačilna lista",
                        it: "busta paga", fr: "fiche de paie", es: "nómina", pt: "recibo", nl: "loonstrook",
                        pl: "pasek wypłaty")
        case .difference:
            return pick(en: "difference", de: "Differenz", hr: "razlika", sl: "razlika", it: "differenza",
                        fr: "écart", es: "diferencia", pt: "diferença", nl: "verschil", pl: "różnica")
        case .matches:
            return pick(en: "matches", de: "stimmt", hr: "odgovara", sl: "se ujema", it: "corrisponde",
                        fr: "concorde", es: "coincide", pt: "confere", nl: "klopt", pl: "zgadza się")
        case .grossPay:
            return pick(en: "Gross pay", de: "Bruttolohn", hr: "Bruto plaća", sl: "Bruto plača",
                        it: "Retribuzione lorda", fr: "Salaire brut", es: "Salario bruto", pt: "Salário bruto",
                        nl: "Brutoloon", pl: "Wynagrodzenie brutto")
        case .pleaseCheck:
            return pick(en: "Could you please check this? Thank you.",
                        de: "Könnten Sie das bitte prüfen? Danke.",
                        hr: "Možete li to, molim Vas, provjeriti? Hvala.",
                        sl: "Ali lahko to, prosim, preverite? Hvala.",
                        it: "Potreste verificarlo, per favore? Grazie.",
                        fr: "Pourriez-vous vérifier, s’il vous plaît ? Merci.",
                        es: "¿Podrían revisarlo, por favor? Gracias.",
                        pt: "Podem verificar, por favor? Obrigado.",
                        nl: "Kunt u dit nakijken? Dank u.",
                        pl: "Czy mogą Państwo to sprawdzić? Dziękuję.")
        }
    }
}
