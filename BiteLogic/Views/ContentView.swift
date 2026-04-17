import SwiftUI
import CoreData

struct ContentView: View {
    @StateObject private var vm = FishingViewModel()
    @StateObject private var spotManager = SpotManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingAddSpot = false

    var body: some View {
        Group {
            if spotManager.spots.isEmpty {
                onboardingView
            } else {
                mainTabView
            }
        }
        // Sheet lives on the Group (ContentView level), not inside onboardingView.
        // This prevents it from being destroyed when spots becomes non-empty
        // and the view switches from onboarding → main.
        .sheet(isPresented: $showingAddSpot) {
            SpotPickerView(spotManager: spotManager)
        }
        .onAppear {
            spotManager.loadSpots(context: viewContext)
        }
        .onChange(of: spotManager.activeSpot) { _, newSpot in
            vm.activeSpot = newSpot
            vm.viewContext = viewContext
            if newSpot != nil {
                Task { await vm.loadAll() }
            }
        }
    }

    // MARK: - Onboarding

    private var onboardingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            Text("Welcome to BiteLogic")
                .font(.title.bold())
            Text("Add your first fishing spot to get started.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Fishing Spot") {
                showingAddSpot = true
            }
            .buttonStyle(.borderedProminent)

            Button("Add Demo Spot (Bear Cut)") {
                createDemoSpot()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Main Tab View

    private var mainTabView: some View {
        TabView {
            DashboardView(spotManager: spotManager)
                .tabItem {
                    Label("Dashboard", systemImage: "water.waves")
                }

            LogListView()
                .tabItem {
                    Label("Log", systemImage: "book.fill")
                }

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                }

            SpotComparisonView(spotManager: spotManager)
                .tabItem {
                    Label("Compare", systemImage: "mappin.and.ellipse")
                }
        }
        .environmentObject(vm)
        .onAppear {
            vm.viewContext = viewContext
            vm.activeSpot = spotManager.activeSpot
            Task { await vm.loadAll() }
        }
    }

    // MARK: - Demo Spot

    private func createDemoSpot() {
        let _ = spotManager.createSpot(
            name: "Bear Cut",
            latitude: 25.7275,
            longitude: -80.1572,
            noaaStationId: "8723214",
            timezone: "America/New_York"
        )
    }
}
