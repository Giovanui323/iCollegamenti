import SwiftUI
import Charts
import CAVICore

struct ChargingSpeedView: View {
    @Environment(DeviceDiscoveryService.self) private var discovery
    @Environment(MacChargingService.self) private var macCharging
    @Environment(ChargerProfileStore.self) private var chargers
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(LanguageManager.self) private var languageManager

    @State private var brand = ""
    @State private var label = ""
    @State private var watts = 0
    @State private var chargingCableLabel = ""
    @State private var selectedCableID: UUID?
    @State private var showSaved = false

    var body: some View {
        Form {
            Section(languageManager.t("This Mac", "Questo Mac")) {
                LabeledContent(languageManager.t("Model", "Modello"), value: macCharging.snapshot.modelIdentifier)
                LabeledContent(languageManager.t("State", "Stato"), value: macCharging.snapshot.batteryState)
                if let percentage = macCharging.snapshot.batteryPercent {
                    LabeledContent(languageManager.t("Battery", "Batteria"), value: "\(percentage)%")
                }
                if let adapterWatts = macCharging.snapshot.adapterWatts {
                    LabeledContent(languageManager.t("Power Adapter", "Alimentatore"), value: "\(adapterWatts) W")
                }
                LabeledContent(languageManager.t("Observed Power", "Potenza osservata")) {
                    Text(macCharging.snapshot.observedWatts.map { String(format: "%.1f W", $0) } ?? languageManager.t("Not available", "Non disponibile"))
                        .monospacedDigit()
                }
                if let voltage = macCharging.snapshot.batteryVoltageVolts {
                    LabeledContent(languageManager.t("Battery voltage", "Tensione batteria"), value: String(format: "%.2f V", voltage))
                }
                if let current = macCharging.snapshot.batteryCurrentAmps {
                    LabeledContent(languageManager.t("Battery current", "Corrente batteria"), value: String(format: "%+.2f A", current))
                }
                LabeledContent(languageManager.t("Assessment", "Valutazione")) {
                    Text(macCharging.snapshot.assessment)
                        .foregroundStyle(macCharging.snapshot.isOnExternalPower ? .green : .secondary)
                }
                Text(macCharging.snapshot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let sourceLimit = PowerSourceDisclosure.message(isOnExternalPower: macCharging.snapshot.isOnExternalPower) {
                    Label(sourceLimit, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 20) {
                    VStack {
                        Gauge(value: macCharging.snapshot.batteryVoltageVolts ?? 0, in: 0...20) {
                            Text("V")
                        } currentValueLabel: {
                            Text(String(format: "%.1f", macCharging.snapshot.batteryVoltageVolts ?? 0))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(.blue)
                        Text(languageManager.t("Voltage", "Tensione")).font(.caption2).foregroundStyle(.secondary)
                    }
                    
                    VStack {
                        Gauge(value: abs(macCharging.snapshot.batteryCurrentAmps ?? 0), in: 0...5) {
                            Text("A")
                        } currentValueLabel: {
                            Text(String(format: "%.1f", abs(macCharging.snapshot.batteryCurrentAmps ?? 0)))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(.purple)
                        Text(languageManager.t("Current", "Corrente")).font(.caption2).foregroundStyle(.secondary)
                    }
                    
                    VStack {
                        Gauge(value: macCharging.snapshot.observedWatts ?? 0, in: 0...140) {
                            Text("W")
                        } currentValueLabel: {
                            Text(String(format: "%.0f", macCharging.snapshot.observedWatts ?? 0))
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(.orange)
                        Text(languageManager.t("Power", "Potenza")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }

            if !macCharging.recentSamples.isEmpty {
                Section(languageManager.t("Live Power", "Potenza in tempo reale")) {
                    Chart(macCharging.recentSamples) { sample in
                        LineMark(
                            x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                            y: .value(languageManager.t("Watts", "Watt"), sample.watts)
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                            y: .value(languageManager.t("Watts", "Watt"), sample.watts)
                        )
                        .foregroundStyle(.orange.opacity(0.12))
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 160)
                    Text(languageManager.t(
                        "Updated every two seconds. Values reflect the active Mac power source or the battery-side measurement exposed by macOS, not a direct USB‑C PD contract.",
                        "Aggiornata ogni due secondi. I valori riflettono la fonte di alimentazione attiva del Mac o la misura lato batteria esposta da macOS, non un contratto USB‑C PD diretto."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section(languageManager.t("Charger Diagnostics", "Diagnosi caricatore")) {
                if !chargers.chargers.isEmpty {
                    Picker(languageManager.t("Charger", "Caricatore"), selection: Bindable(chargers).selectedChargerID) {
                        Text(languageManager.t("No charger selected", "Nessun caricatore selezionato")).tag(UUID?.none)
                        ForEach(chargers.chargers) { charger in
                            Text(charger.displayName).tag(Optional(charger.id))
                        }
                    }
                    if let selected = chargers.selectedCharger {
                        Button("\(languageManager.t("Remove", "Rimuovi")) \(selected.displayName)", role: .destructive) {
                            chargers.remove(selected)
                        }
                    }
                }

                if let charger = chargers.selectedCharger {
                    diagnostic(for: charger)
                } else {
                    Text(languageManager.t(
                        "Select or add a certified charger to compare nominal power with observed power.",
                        "Scegli o aggiungi un caricatore certificato per confrontare la potenza nominale con quella osservata."
                    ))
                    .foregroundStyle(.secondary)
                }
            }

            Section(languageManager.t("Add Charger", "Aggiungi caricatore")) {
                TextField(languageManager.t("Brand", "Marca"), text: $brand, prompt: Text("Apple, Anker, Baseus"))
                TextField(languageManager.t("Model or label", "Modello o etichetta"), text: $label, prompt: Text("Dual USB-C 35W Compact"))
                TextField(languageManager.t("Nominal power (W)", "Potenza nominale (W)"), value: $watts, format: .number)
                Button(languageManager.t("Save Charger", "Salva caricatore")) {
                    chargers.add(brand: brand, label: label, watts: watts)
                    brand = ""
                    label = ""
                    watts = 0
                }
                .disabled(brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || watts <= 0)
            }

            Section(languageManager.t("Power Measurement", "Misurazione alimentazione")) {
                Text(languageManager.t(
                    "This saves the active Mac power-source measurement. Select a cable only when you want to manually associate the measurement; macOS cannot verify that association.",
                    "Questa salva la misurazione della fonte di alimentazione attiva del Mac. Seleziona un cavo solo se vuoi associare manualmente la misura: macOS non può verificarne l'associazione."
                ))
                .font(.caption).foregroundStyle(.secondary)
                CableCatalogSelection(
                    selectedCableID: $selectedCableID,
                    cableName: $chargingCableLabel,
                    prompt: languageManager.t("Cable name (e.g. USB-C 240W)", "Nome del cavo (es. USB-C 240 W)")
                )
                Button(languageManager.t("Save to History", "Salva in Cronologia"), action: saveChargingCable)
                    .disabled(chargingCableLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || macCharging.snapshot.observedWatts == nil)
                if showSaved {
                    Text(languageManager.t("Measurement saved to History.", "Misurazione salvata in Cronologia."))
                        .foregroundStyle(.green)
                }
            }

            Section {
                DisclosureGroup(languageManager.t("Technical Notes", "Note tecniche")) {
                    Text(languageManager.t(
                        "Power intake varies depending on battery level, temperature, cable capacity, and port/hub capability. macOS manages Power Delivery negotiation automatically.",
                        "La potenza assorbita varia in base alla batteria, alla temperatura, al cavo e alla capacità della porta o dell’hub. macOS gestisce automaticamente la negoziazione Power Delivery."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(languageManager.t("Power & Charging", "Ricarica"))
    }

    @ViewBuilder
    private func diagnostic(for charger: CertifiedCharger) -> some View {
        LabeledContent(languageManager.t("Nominal power", "Potenza nominale"), value: "\(charger.certifiedWatts) W")
        if let observed = macCharging.snapshot.observedWatts {
            let ratio = observed / Double(charger.certifiedWatts)
            let percent = Int(min(ratio * 100, 100))
            LabeledContent(languageManager.t("Observed power", "Potenza osservata"), value: String(format: "%.1f W", observed))
            ProgressView(value: min(observed, Double(charger.certifiedWatts)), total: Double(charger.certifiedWatts))
                .tint(ratio >= 0.8 ? .green : .orange)
            Text(ratio >= 0.8 
                 ? "\(languageManager.t("Power matches charger specifications", "Potenza in linea con il caricatore")) (\(percent)% \(languageManager.t("of nominal", "del nominale")))." 
                 : "\(languageManager.t("Power below nominal", "Potenza inferiore al nominale")) (\(percent)%): \(languageManager.t("may depend on battery level, cable, hub, or thermal throttling.", "può dipendere da batteria, cavo, hub o temperatura."))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(languageManager.t("Awaiting observed power from macOS.", "In attesa che macOS comunichi la potenza osservata."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chargingContent(_ assessment: ChargingAssessment) -> some View {
        switch assessment {
        case .observed(let watts):
            LabeledContent(languageManager.t("Device power", "Potenza del dispositivo"), value: String(format: "%.1f W", watts))
        case .unavailable:
            Text(assessment.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func saveChargingCable() {
        guard let cable = resolvedCableProfile() else { return }
        let observedWatts = macCharging.snapshot.observedWatts ?? 0
        let adapterWatts = macCharging.snapshot.adapterWatts ?? 0
        let notes = languageManager.t(
            "Active power source: \(String(format: "%.1f W", observedWatts)) (Adapter \(adapterWatts) W). Not attributable to an individual cable.",
            "Fonte di alimentazione attiva: \(String(format: "%.1f W", observedWatts)) (Alimentatore \(adapterWatts) W). Non attribuibile a un singolo cavo."
        )
        let topology = languageManager.t(
            "Active Mac power source (\(adapterWatts) W)",
            "Fonte di alimentazione Mac attiva (\(adapterWatts) W)"
        )
        let result = CableTestResult(
            cableLabel: cable.name,
            deviceName: macCharging.snapshot.modelIdentifier,
            linkSpeedBps: UInt64(observedWatts * 1_000_000),
            userNotes: notes,
            topologyDescription: topology,
            cableID: cable.id,
            category: .charging
        )
        historyStore.saveTestResult(result)
        chargingCableLabel = ""
        showSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { showSaved = false }
    }

    private func resolvedCableProfile() -> CableProfile? {
        let name = chargingCableLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let selectedCableID, let existing = historyStore.cableProfile(id: selectedCableID) {
            historyStore.renameCable(id: existing.id, newName: name)
            return historyStore.cableProfile(id: existing.id) ?? existing
        }
        let cable = historyStore.createCable(named: name)
        selectedCableID = cable.id
        return cable
    }
}
