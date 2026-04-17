# 🎣 Bear Cut Fishing Conditions App

A SwiftUI iOS app for tracking fishing conditions and predicting fish activity
at **Bear Cut, Key Biscayne, Florida** — with tide graphs, wind data, moon phase,
water temperature, an AI-style bite predictor, and a nightly fishing log that
learns from your trips over time.

---

## 📁 Project Structure

```
BearCutFishing/
├── BearCutFishingApp.swift       # App entry point
├── Models.swift                  # All data models
├── Persistence.swift             # Core Data stack
├── APIService.swift              # NOAA + Open-Meteo API calls
├── PredictionEngine.swift        # AI-style weighted bite predictor
├── FishingViewModel.swift        # Main @ObservableObject / state
├── APIKeys.plist                 # API key config (currently all free)
├── BearCutFishing.xcdatamodeld/  # Core Data model
└── Views/
    ├── ContentView.swift         # Tab navigation
    ├── DashboardView.swift       # Main dashboard
    ├── ConditionCards.swift      # Prediction, wind, moon, temp cards
    ├── TideGraphView.swift       # Interactive tide graph
    ├── LogEntryFormView.swift    # Log a fishing night
    ├── LogListView.swift         # Historical log list
    └── TrendsView.swift          # Accuracy & trend analysis
```

---

## ⚙️ Xcode Setup Instructions

### Step 1 — Create the Project
1. Open Xcode → **File → New → Project**
2. Choose **App** under iOS
3. Name: `BearCutFishing`
4. Interface: **SwiftUI**
5. Storage: **Core Data** ✅ (check this box)
6. Language: Swift

### Step 2 — Add the Files
1. Delete the auto-generated `ContentView.swift`, `Persistence.swift`, and `Item` entity in the `.xcdatamodeld`
2. Drag all `.swift` files from this project into the Xcode navigator
3. Replace the `.xcdatamodeld` contents file with the one provided

### Step 3 — Configure Core Data Model
1. Open `BearCutFishing.xcdatamodeld`
2. Add entity named **`LogEntryEntity`** with these attributes:

| Attribute | Type |
|---|---|
| id | UUID |
| date | Date |
| windMph | Double |
| tideHeight | Double |
| tideChangeRate | Double |
| moonPhase | Double |
| waterTempF | Double |
| userRating | Integer 16 |
| actualActivity | String |
| predictedProbability | Double |
| notes | String |

3. Set **Codegen** to **Class Definition**

### Step 4 — Add APIKeys.plist
1. Add `APIKeys.plist` to your project (make sure it's in the bundle target)
2. Currently **no paid API keys are needed** — both APIs used are free:
   - **NOAA CO-OPS** (tide data): completely free, no registration
   - **Open-Meteo** (wind/weather/sea temp): completely free, no key

### Step 5 — Network Permissions
In `Info.plist`, add:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>api.tidesandcurrents.noaa.gov</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
        </dict>
    </dict>
</dict>
```
(Both APIs use HTTPS so this is optional, but good practice.)

### Step 6 — Build & Run
- Select an iPhone simulator (iOS 16+)
- Press ▶ Run
- The app will attempt real API calls; if on simulator without network, it falls back to demo data

---

## 🧠 AI Prediction Logic

The bite predictor uses a **weighted scoring system**:

| Factor | Weight | How it Scores |
|---|---|---|
| Wind speed | 30% | <8 mph → 0.85 score; >20 mph → 0.10 |
| Tide movement | 25% | 0.15–0.30 ft/hr = ideal; slack = low |
| Time of day | 20% | 9PM–2AM = 0.90; daytime = 0.20 |
| Water temp | 15% | 78–84°F = ideal (0.85); <65°F = 0.10 |
| Moon phase | 10% | New moon = 0.75; other phases vary |

The weighted average produces a 0–100% probability that fish are feeding on top.

- **≥ 65%** → ON TOP (green)
- **40–64%** → MIXED (yellow)
- **< 40%** → ON BOTTOM (red)

### Learning Over Time
After each saved log entry, `PredictionEngine.calibrateWeights()` analyzes your
historical data and slightly adjusts factor weights toward better predictors for
YOUR specific Bear Cut sessions. After 10+ entries, the system becomes personalized.

---

## 📊 Example Night

**Conditions:** 9 PM, wind 8 mph SE, tide rising 0.22 ft/hr, water 79°F, new moon

| Factor | Score | Weight | Contribution |
|---|---|---|---|
| Wind (8 mph) | 0.75 | 30% | 0.225 |
| Tide movement (0.22) | 0.75 | 25% | 0.1875 |
| Time (21:00) | 0.90 | 20% | 0.180 |
| Water temp (79°F) | 0.85 | 15% | 0.1275 |
| Moon (new) | 0.75 | 10% | 0.075 |
| **Total** | | | **0.795 → 79%** |

**Result: ON TOP — Moderate Confidence** ✅

---

## 📡 APIs Used

| API | Data | Cost | Docs |
|---|---|---|---|
| NOAA CO-OPS | Hourly tide predictions | Free | tidesandcurrents.noaa.gov |
| Open-Meteo | Wind, air temp (hourly) | Free | open-meteo.com |
| Open-Meteo Marine | Sea surface temperature | Free | open-meteo.com/en/docs/marine-weather-api |

NOAA Station `8723214` = Virginia Key, the closest station to Bear Cut.

---

## 🔮 Future Improvements

- [ ] Push notifications: "Conditions look great tonight at Bear Cut!"
- [ ] Widget for home screen showing quick prediction
- [ ] Photo attachments to log entries
- [ ] Export log as CSV
- [ ] Solunar table integration (peak feeding times)
- [ ] Species-specific predictions (snook vs tarpon vs permit)
