import SwiftUI
import MapKit
import CoreData

struct SpotPickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var spotManager: SpotManager

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.76, longitude: -80.19),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    )
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var spotName = ""
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []

    @State private var detectedStation: NOAAStationService.StationResult?
    @State private var isDetectingStation = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingSetup = false
    @State private var newSpotId: UUID?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search location...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { performSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = ""; searchResults = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)

                // Search results
                if !searchResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(searchResults, id: \.self) { item in
                                Button {
                                    selectSearchResult(item)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(item.name ?? "Unknown")
                                                .font(.subheadline.weight(.medium))
                                            if let locality = item.placemark.locality {
                                                Text(locality)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "mappin")
                                            .foregroundColor(.accentColor)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                                .foregroundColor(.primary)
                                Divider().padding(.leading)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // Map
                MapReader { proxy in
                    Map(position: $cameraPosition, interactionModes: .all) {
                        if let pin = pinCoordinate {
                            Annotation("", coordinate: pin) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.red)
                                    .shadow(radius: 3)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if let coord = proxy.convert(value.location, from: .local) {
                                                    pinCoordinate = coord
                                                }
                                            }
                                            .onEnded { value in
                                                if let coord = proxy.convert(value.location, from: .local) {
                                                    pinCoordinate = coord
                                                    detectStation(at: coord)
                                                }
                                            }
                                    )
                            }
                        }
                        if let station = detectedStation {
                            Annotation("NOAA: \(station.name)", coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(4)
                                    .background(Circle().fill(.white))
                            }
                        }
                    }
                    .onTapGesture { position in
                        if let coord = proxy.convert(position, from: .local) {
                            pinCoordinate = coord
                            if spotName.isEmpty {
                                spotName = String(format: "Spot %.3f, %.3f", coord.latitude, coord.longitude)
                            }
                            detectStation(at: coord)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(pinCoordinate == nil ? "Tap map to place pin" : "Drag pin to adjust")
                            .font(.caption2)
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .padding(8)
                    }
                }
                .frame(maxHeight: .infinity)

                // Bottom panel
                VStack(spacing: 12) {
                    if let pin = pinCoordinate {
                        Text(String(format: "%.4f, %.4f", pin.latitude, pin.longitude))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isDetectingStation {
                        HStack {
                            ProgressView()
                            Text("Finding nearest NOAA tide station...")
                                .font(.caption)
                        }
                    } else if let station = detectedStation {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("NOAA Station: \(station.name)")
                                    .font(.caption.weight(.medium))
                                Text(String(format: "ID: %@ (%.1f km away)", station.id, station.distance))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    TextField("Spot Name", text: $spotName)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        saveSpot()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Create Spot")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canSave ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canSave || isSaving)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Add Fishing Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSetup) {
                SpotSetupView(spotId: newSpotId) {
                    dismiss()
                }
                .interactiveDismissDisabled()
            }
        }
    }

    private var canSave: Bool {
        pinCoordinate != nil && !spotName.isEmpty && detectedStation != nil
    }

    private func performSearch() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            searchResults = response?.mapItems ?? []
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        pinCoordinate = coord
        spotName = item.name ?? ""
        searchResults = []
        searchText = ""

        cameraPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))

        detectStation(at: coord)
    }

    private func detectStation(at coord: CLLocationCoordinate2D) {
        isDetectingStation = true
        detectedStation = nil
        errorMessage = nil

        Task {
            do {
                let station = try await NOAAStationService.shared.findNearestStation(
                    lat: coord.latitude, lon: coord.longitude
                )
                detectedStation = station
                if station.distance > 100 {
                    errorMessage = "Nearest station is \(Int(station.distance))km away - tide data may be inaccurate"
                }
            } catch {
                errorMessage = "Could not find NOAA station: \(error.localizedDescription)"
            }
            isDetectingStation = false
        }
    }

    private func saveSpot() {
        guard let pin = pinCoordinate, let station = detectedStation else { return }
        isSaving = true

        let tz = TimeZone.current.identifier
        let newSpot = spotManager.createSpot(
            name: spotName,
            latitude: pin.latitude,
            longitude: pin.longitude,
            noaaStationId: station.id,
            timezone: tz
        )
        newSpotId = newSpot?.id
        isSaving = false
        showingSetup = true
    }
}

// MARK: - Spot Setup View (shown after creating a new spot)

struct SpotSetupView: View {
    @Environment(\.dismiss) private var dismiss

    let spotId: UUID?
    let onDone: () -> Void

    @State private var prefs: HeuristicPreferences = .defaultPreferences
    @State private var weights: [Double] = HeuristicEngine().weights

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "tuningfork")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Configure Your Preferences")
                                .font(.subheadline.bold())
                            Text("Set your optional fishing preferences. These help the prediction engine understand what conditions you think are better. You can change these anytime in Settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Tide Movement
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tide Movement")
                            .font(.subheadline.weight(.medium))
                        Picker("Preference", selection: $prefs.tideMovementEnabled) {
                            Text("No Effect").tag(false)
                            Text("More = Better").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: prefs.tideMovementEnabled) { _, enabled in
                            if !enabled { weights[1] = 0.0 } else if weights[1] == 0 { weights[1] = 0.25 }
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Turn off for landlocked spots without tides. Leave on for coastal/tidal fishing.")
                }

                // Tide Stage
                Section {
                    optionalFactorRow(
                        title: "Tide Stage",
                        weightIndex: 6,
                        binding: Binding(
                            get: { prefs.tideStagePreference ?? "none" },
                            set: {
                                prefs.tideStagePreference = $0 == "none" ? nil : $0
                                if $0 == "none" { weights[6] = 0.0 } else if weights[6] == 0 { weights[6] = 0.10 }
                            }
                        ),
                        options: [("none", "No Effect"), ("incoming", "Incoming Better"), ("outgoing", "Outgoing Better")]
                    )
                } footer: {
                    Text("Does incoming or outgoing tide produce better fishing?")
                }

                // Time of Day
                Section {
                    optionalFactorRow(
                        title: "Time of Day",
                        weightIndex: 2,
                        binding: Binding(
                            get: { prefs.timePreference ?? "none" },
                            set: {
                                prefs.timePreference = $0 == "none" ? nil : $0
                                if $0 == "none" { weights[2] = 0.0 } else if weights[2] == 0 { weights[2] = 0.15 }
                            }
                        ),
                        options: [("none", "No Effect"), ("night", "Night Better"), ("day", "Day Better")]
                    )
                } footer: {
                    Text("Do fish bite better during the day or at night at your spot?")
                }

                // Moon Phase
                Section {
                    optionalFactorRow(
                        title: "Moon Phase",
                        weightIndex: 4,
                        binding: Binding(
                            get: { prefs.moonPreference ?? "none" },
                            set: {
                                prefs.moonPreference = $0 == "none" ? nil : $0
                                if $0 == "none" { weights[4] = 0.0 } else if weights[4] == 0 { weights[4] = 0.10 }
                            }
                        ),
                        options: [("none", "No Effect"), ("new", "New Moon Better"), ("full", "Full Moon Better")]
                    )
                } footer: {
                    Text("Does the moon phase affect the bite at your spot?")
                }

            }
            .navigationTitle("Spot Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func optionalFactorRow(title: String, weightIndex: Int, binding: Binding<String>, options: [(value: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Picker("Preference", selection: binding) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }

    private func saveAndDismiss() {
        if !prefs.tideMovementEnabled { weights[1] = 0 }
        if prefs.timePreference == nil { weights[2] = 0 }
        if prefs.moonPreference == nil { weights[4] = 0 }
        if prefs.tideStagePreference == nil { weights[6] = 0 }

        prefs.save(spotId: spotId)
        HeuristicPreferences.saveWeights(weights, spotId: spotId)

        if let spotId {
            PredictionManager.shared.updateHeuristicPreferences(prefs, spotId: spotId)
        }
        onDone()
    }
}
