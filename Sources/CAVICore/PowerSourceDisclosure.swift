import Foundation

public enum PowerSourceDisclosure {
    public static func message(isOnExternalPower: Bool) -> String? {
        guard isOnExternalPower else { return nil }
        return "macOS mostra una sola fonte di alimentazione attiva; eventuali alimentatori collegati contemporaneamente non sono sommati né attribuibili a un singolo cavo."
    }
}
