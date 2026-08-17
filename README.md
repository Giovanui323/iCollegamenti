# iCollegamenti 🔌

**iCollegamenti** è un'applicazione nativa per macOS (SwiftUI & IOKit) per la diagnostica avanzata di collegamenti hardware, cavi USB/Thunderbolt, prestazioni delle unità di archiviazione, display HDMI/video, telemetria di ricarica e salute SMART dei dischi.

---

## ✨ Funzionalità Principali

- 🔗 **Diagnostica Collegamenti & Cavi USB/Thunderbolt:**
  - Rilevamento in tempo reale della velocità negoziata di link (480 Mb/s, 5 Gb/s, 10 Gb/s, 20 Gb/s, 40 Gb/s).
  - Identificazione di colli di bottiglia causati da cavi lenti, hub USB sovrascritti o controller intermedi.
  - Riconoscimento automatico del produttore e modello tramite database Vendor ID / Product ID e descrittori IOKit.
- ⚡ **Telemetria di Ricarica:**
  - Monitoraggio in tempo reale di tensione (V), corrente (A) e potenza (W) fornita da alimentatori esterni o porte USB-C/PD.
  - Calcolo della salute e stato della batteria.
- 💾 **Unità e Benchmark:**
  - Test sequenziali e ad alto carico (stress, IOPS casuali, integrità, scrittura sostenuta per video editing).
  - Confronto intelligente tra velocità misurate, limiti fisici del link e velocità attese per categoria di disco (NVMe, SATA SSD, HDD, chiavetta USB).
  - Storico persistente e dedicato dei test effettuati per ciascuna unità con data, ora, tipologia e resa.
- 🩺 **Salute Unità (SMART):**
  - Lettura accurata dello stato SMART, temperatura operativa, percentuale di vita residua, ore di accensione e cicli di alimentazione.
- 🖥️ **Diagnostica Display & Cavi Video (HDMI / DisplayPort):**
  - Parsing a basso livello dei metadati EDID del monitor (risoluzione nativa, refresh rate, profondità colore, formati audio).
  - Calcolo della banda dati video richiesta e matrice di compatibilità (4K60, 4K120, 8K).
- 📜 **Cronologia ed Esportazione:**
  - Registro cronologico dei test e log eventi hardware in tempo reale (collegamento, scollegamento, rinegoziazione velocità).
  - Esportazione completa dei dati in formati **Markdown**, **PDF**, **CSV** e **JSON diagnostico**.

---

## 🛠 Requisiti di Sistema

- **macOS:** 14.0 (Sonoma) o versioni successive
- **Architettura:** Apple Silicon (M1/M2/M3/M4) e Intel 64-bit

---

## 🚀 Installazione

Scarica l'ultima versione di **`iCollegamenti.dmg`** dalla sezione [Releases](https://github.com/Giovanui323/iCollegamenti/releases), aprilo e trascina l'icona dell'app nella cartella **Applicazioni**.

---

## 🔨 Compilazione dal Codice Sorgente

Per compilare ed eseguire il progetto localmente:

```bash
# Clona il repository
git clone https://github.com/Giovanui323/iCollegamenti.git
cd iCollegamenti

# Esegui la suite di test di sicurezza e logica
swift run SafetyTestRunner

# Compila il bundle dell'applicazione
./build_app.sh

# Crea l'immagine disco .dmg
./create_dmg.sh
```

---

## 🛡️ Sicurezza e Riservatezza

- L'applicazione esegue i test di velocità creando esclusivamente un file temporaneo isolato all'interno del percorso del volume, che viene eliminato automaticamente al termine o in caso di annullamento.
- Nessun file personale dell'utente viene mai letto o modificato durante i benchmark.
- I report esportati anonimizzano gli identificativi univoci dei percorsi hardware locali.

---

## 📄 Licenza

Distribuito sotto licenza MIT.
