import SwiftUI

struct SpotSwitcherView: View {
    @ObservedObject var spotManager: SpotManager
    @State private var showingPicker = false
    @State private var showingAddSpot = false
    @State private var spotToDelete: FishingSpotEntity?

    var body: some View {
        Menu {
            Section("Switch Spot") {
                ForEach(spotManager.spots, id: \.id) { spot in
                    Button {
                        spotManager.setActiveSpot(spot)
                    } label: {
                        HStack {
                            Text(spot.name ?? "Unnamed")
                            if spot == spotManager.activeSpot {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                showingAddSpot = true
            } label: {
                Label("Add New Spot", systemImage: "plus")
            }

            if let active = spotManager.activeSpot, spotManager.spots.count > 1 {
                Button(role: .destructive) {
                    spotToDelete = active
                } label: {
                    Label("Delete \(active.name ?? "Spot")", systemImage: "trash")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.accentColor)
                Text(spotManager.activeSpot?.name ?? "No Spot")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingAddSpot) {
            SpotPickerView(spotManager: spotManager)
        }
        .alert("Delete Spot?", isPresented: Binding(
            get: { spotToDelete != nil },
            set: { if !$0 { spotToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { spotToDelete = nil }
            Button("Delete", role: .destructive) {
                if let spot = spotToDelete {
                    spotManager.deleteSpot(spot)
                    spotToDelete = nil
                }
            }
        } message: {
            Text("This will delete all logs and predictions for this spot.")
        }
    }
}
