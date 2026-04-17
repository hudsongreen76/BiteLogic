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
                Map(position: $cameraPosition, interactionModes: .all) {
                    if let pin = pinCoordinate {
                        Annotation("", coordinate: pin) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundColor(.red)
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
                    // MapKit tap handling - use MapReader for coordinate conversion
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("Tap search to place pin")
                        .font(.caption2)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(8)
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
        let _ = spotManager.createSpot(
            name: spotName,
            latitude: pin.latitude,
            longitude: pin.longitude,
            noaaStationId: station.id,
            timezone: tz
        )
        isSaving = false
        dismiss()
    }
}
