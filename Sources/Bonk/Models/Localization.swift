import Foundation

enum Lang {
    case nl
    case en
}

/// Kies de tekst op basis van de actieve taal.
func L(_ nl: String, _ en: String, _ lang: Lang) -> String {
    lang == .en ? en : nl
}
