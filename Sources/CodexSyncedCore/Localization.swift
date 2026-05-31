import Foundation

public struct L10n {
    public var language: Language

    public init(language: Language) {
        self.language = language
    }

    public func text(_ zh: String, _ en: String) -> String {
        language == .zh ? zh : en
    }
}
