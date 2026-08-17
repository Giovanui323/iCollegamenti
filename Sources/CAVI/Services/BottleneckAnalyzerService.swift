import Foundation
import CAVICore

// MARK: - BottleneckAnalysis

public struct BottleneckAnalysis: Sendable {
    public let currentSpeedBps: UInt64?
    public let referenceMaxSpeedBps: UInt64?
    public let topologyBottleneck: BottleneckInfo?
    public let diagnosis: ConnectionDiagnosis
    public let orderedCauses: [ConnectionCauseAssessment]
    public let headline: String
    public let detailedMessage: String
    public let possibleCauses: [String]
    public let severity: Severity

}

// MARK: - BottleneckAnalyzerService

@Observable
@MainActor
public final class BottleneckAnalyzerService {
    public var currentAnalysis: BottleneckAnalysis?
    
    public init() {}
    
    /// Diagnoses the observed connection without attributing an unobserved
    /// limitation to the physical cable.
    public func analyze(device: DriveDevice, referenceDevice: ReferenceDevice?, language: AppLanguage = .english) -> BottleneckAnalysis {
        let currentSpeed = device.negotiatedSpeedBps
        let referenceSpeed = referenceDevice?.maxObservedSpeedBps
        let hubBottleneck = USBTopologyService.findBottleneck(in: device.usbTopology)
        let diagnosis = ConnectionDiagnosisEngine.analyze(
            currentLinkSpeedBps: currentSpeed,
            referenceMaxSpeedBps: referenceSpeed,
            constraints: USBTopologyService.connectionConstraints(for: device.usbTopology)
        )
        let narrative = makeNarrative(
            diagnosis: diagnosis,
            observedHub: hubBottleneck,
            language: language
        )
        
        let analysis = BottleneckAnalysis(
            currentSpeedBps: currentSpeed,
            referenceMaxSpeedBps: referenceSpeed,
            topologyBottleneck: hubBottleneck,
            diagnosis: diagnosis,
            orderedCauses: diagnosis.causes,
            headline: narrative.headline,
            detailedMessage: narrative.message,
            possibleCauses: narrative.possibleCauses,
            severity: narrative.severity
        )
        self.currentAnalysis = analysis
        return analysis
    }

    private func makeNarrative(
        diagnosis: ConnectionDiagnosis,
        observedHub: BottleneckInfo?,
        language: AppLanguage
    ) -> (headline: String, message: String, possibleCauses: [String], severity: Severity) {
        let current = diagnosis.currentLinkSpeedBps.map(LinkSpeedService.formatSpeed) ?? unavailable(language)
        let reference = diagnosis.referenceMaxSpeedBps.map(LinkSpeedService.formatSpeed)

        switch diagnosis.primaryCause {
        case .hub:
            let hub = observedHub?.nodeName ?? (language == .english ? "an observed USB hub" : "un hub USB osservato")
            let hubSpeed = observedHub.map { LinkSpeedService.formatSpeed($0.nodeSpeed) } ?? current
            return (
                language == .english ? "Observed hub limitation" : "Limitazione dell’hub osservata",
                language == .english
                    ? "The connection negotiated at \(current); \(hub) exposes an observed \(hubSpeed) link while this device was previously measured at \(reference ?? unavailable(language))."
                    : "La connessione è negoziata a \(current); \(hub) espone un link osservato a \(hubSpeed), mentre questo dispositivo è stato misurato in precedenza a \(reference ?? unavailable(language)).",
                language == .english
                    ? ["Observed hub link: \(hubSpeed)", "Try a hub or direct port compatible with the desired speed."]
                    : ["Link dell’hub osservato: \(hubSpeed)", "Prova un hub o una porta diretta compatibile con la velocità desiderata."],
                .critical
            )

        case .connectionChain:
            return (
                language == .english ? "Possible connection-chain limitation" : "Possibile limitazione nella catena",
                language == .english
                    ? "This device was previously measured at \(reference ?? unavailable(language)), but this connection negotiated at \(current). macOS cannot attribute the difference to the cable alone."
                    : "Questo dispositivo è stato misurato in precedenza a \(reference ?? unavailable(language)), ma questa connessione è negoziata a \(current). macOS non può attribuire la differenza al solo cavo.",
                language == .english
                    ? ["Cable, port, adapter, intermediate hub, or link negotiation.", "Repeat the comparison with one component changed at a time."]
                    : ["Cavo, porta, adattatore, hub intermedio o negoziazione del link.", "Ripeti il confronto cambiando un solo componente alla volta."],
                .warning
            )

        case .bridge:
            let bridge = observedHub?.nodeName ?? (language == .english ? "the bridge controller" : "il controller bridge")
            let bridgeSpeed = observedHub.map { LinkSpeedService.formatSpeed($0.nodeSpeed) } ?? current
            return (
                language == .english ? "Bridge controller limitation" : "Limitazione del controller bridge",
                language == .english
                    ? "The USB-NVMe bridge controller (\(bridge)) supports up to \(bridgeSpeed), limiting the connection."
                    : "Il controller bridge USB-NVMe (\(bridge)) supporta fino a \(bridgeSpeed), limitando la connessione.",
                [],
                .critical
            )

        case .cable, .port:
            return (
                language == .english ? "Cable limitation" : "Limitazione del cavo",
                language == .english
                    ? "The cable or port is likely limiting the connection to \(current). The device has been observed at \(reference ?? unavailable(language)) previously."
                    : "Il cavo o la porta sta probabilmente limitando la connessione a \(current). Il dispositivo è stato osservato a \(reference ?? unavailable(language)) in precedenza.",
                [],
                .warning
            )

        case .device:
            return (
                language == .english ? "Device limitation" : "Limitazione del dispositivo",
                language == .english
                    ? "The SSD/device itself is the performance-limiting component. The connection is operating at its maximum capability."
                    : "L'SSD/dispositivo stesso è il componente che limita le prestazioni. La connessione sta operando alla sua massima capacità.",
                [],
                .none
            )

        case .unknown:
            if diagnosis.referenceMaxSpeedBps == nil && diagnosis.currentLinkSpeedBps != nil {
                return (
                    language == .english ? "Missing reference measurement" : "Misurazione di riferimento mancante",
                    language == .english
                        ? "Connected at \(current). Connect the device with a known-good cable to establish a reference measurement."
                        : "Connesso a \(current). Connetti il dispositivo con un cavo sicuramente funzionante per stabilire una misurazione di riferimento.",
                    [],
                    .none
                )
            }
            return (
                language == .english ? "Link speed unavailable" : "Velocità del link non disponibile",
                language == .english
                    ? "macOS did not expose a negotiated link speed for this connection."
                    : "macOS non ha esposto una velocità di link negoziata per questa connessione.",
                [],
                .none
            )

        case .none:
            return (
                language == .english ? "Connection consistent with available evidence" : "Connessione coerente con le evidenze disponibili",
                language == .english
                    ? "The observed negotiated link is \(current)."
                    : "Il link negoziato osservato è \(current).",
                [],
                .none
            )
        }
    }

    private func unavailable(_ language: AppLanguage) -> String {
        language == .english ? "unavailable" : "non disponibile"
    }
}
