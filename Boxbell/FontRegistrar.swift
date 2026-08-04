import CoreText
import Foundation

enum FontRegistrar {
    static func registerBundledFonts() {
        registerFont(named: "DS-DIGIB", extension: "TTF")
    }

    private static func registerFont(named name: String, extension fileExtension: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return
        }

        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
