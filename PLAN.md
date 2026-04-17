# 3-Day Forecast + Dual Prediction System Plan

## Overview

Major feature expansion: add barometric pressure, split predictions into two metrics (Activity + Position), add a 3-day forecast tab, and make wind/tide cards expandable.

---

## Part 1: Barometric Pressure Variable

### API Change (APIService.swift)
- Add `surface_pressure` to the Open-Meteo hourly weather request
- Open-Meteo returns it in hPa, free, no key needed

### Model Changes (Models.swift)
- Add `pressureHpa: Double` and `pressureChange: Double` (hPa/hr) to `WeatherData`
- Add `OpenMeteoResponse.HourlyData` field: `surfacePressure: [Double]` mapped from `"surface_pressure"`

### Scoring Logic
- What matters is the **rate of change**, not the absolute value
- Dropping pressure (negative change rate) = fish feed aggressively = high score
- Stable = neutral
- Rising = neutral/slight negative

---

## Part 2: Dual Prediction System

### Current: single prediction → "ON TOP / MIXED / ON BOTTOM"
### New: TWO independent predictions

**Metric 1 — "Activity"** (are the fish feeding at all?)
- Output: score 0–100%, label: "Hot" / "Active" / "Moderate" / "Slow" / "Dead"
- Color: green → yellow → orange → red → gray

**Metric 2 — "Position"** (where are they feeding?)
- Output: score 0–100% (probability of top-water), label: "On Top" / "Mixed" / "On Bottom"
- Same as current system, kept intact

### Weight Systems (from user input, normalized to sum to 1.0)

**Activity Weights** (total raw: 35):
| Factor          | Raw | Normalized |
|-----------------|-----|------------|
| Time of Day     | 8   | 0.229      |
| Tide Movement   | 8   | 0.229      |
| Water Temp      | 4   | 0.114      |
| Wind            | 4   | 0.114      |
| Moon Phase      | 5   | 0.143      |
| Bar Pressure    | 6   | 0.171      |

**Position Weights** (total raw: 37):
| Factor          | Raw | Normalized |
|-----------------|-----|------------|
| Time of Day     | 10  | 0.270      |
| Tide Movement   | 4   | 0.108      |
| Water Temp      | 4   | 0.108      |
| Wind            | 10  | 0.270      |
| Moon Phase      | 6   | 0.162      |
| Bar Pressure    | 3   | 0.081      |

### PredictionEngine Changes
- New `ActivityWeights` and `PositionWeights` structs
- New `predictActivity()` → returns activity level score
- Rename current `predict()` to `predictPosition()` → returns on-top probability
- New wrapper that returns both: `FullPrediction { activity: ActivityPrediction, position: PositionPrediction }`
- Add barometric pressure scoring factor to both
- Pressure scoring: rate < -1 hPa/hr = 0.90 (dropping fast), -0.5 to -1 = 0.70, stable = 0.50, rising = 0.40

### Model Changes
- New `ActivityPrediction` struct: probability, level (enum), confidence, factors[]
- New `PositionPrediction` struct: probability, position (.onTop/.mixed/.onBottom), confidence, factors[]
- New `FullPrediction` wrapping both
- New `ActivityLevel` enum: .hot, .active, .moderate, .slow, .dead

---

## Part 3: Dashboard UI Updates

### Prediction Card Redesign (ConditionCards.swift)
- Remove "AI BITE PREDICTION" title
- Show TWO stacked metrics:
  - **Activity**: "ACTIVITY" label + level name + score% + factor bars
  - **Position**: "POSITION" label + on top/mixed/bottom + score% + factor bars
- Each has its own color and progress bar

### Expandable Wind Card
- Current: shows wind speed, direction, mini bar chart
- New: tap to expand showing:
  - Hourly wind forecast for next 12-24 hours
  - Wind direction trend
  - Gust info if available

### Expandable Tide Card
- Current: shows tide graph with extrema
- New: tap to expand showing:
  - Next high/low times and heights
  - Tide change rate trend
  - Current direction (incoming/outgoing)

### New Barometric Pressure Card
- Show current pressure in hPa
- Show trend arrow (rising/falling/stable)
- Show rate of change
- Color: dropping=green (good for fishing), stable=gray, rising=gray

---

## Part 4: 3-Day Forecast Tab

### API Extensions (APIService.swift)
- `TideService.fetchTides3Day()` — extend NOAA date range to 3 days
- `WeatherService.fetchWeather3Day()` — Open-Meteo with `forecast_days=3`, include `surface_pressure`
- `WeatherService.fetchMarine3Day()` — sea surface temp for 3 days

### ForecastViewModel (new file)
- Fetches all 3 APIs in parallel
- Builds 36 ForecastBlocks (12 per day × 3 days)
- Each block: average hourly data into 2-hour windows
- Runs BOTH predictActivity() and predictPosition() per block
- Publishes allBlocks (chart) + forecastDays (grouped list)
- Tracks selectedBlockIndex for chart↔list sync

### ForecastBlock Model
- startTime, endTime
- avgWindMph, avgWindDirection, avgTideHeight, tideChangeRate
- avgWaterTempF, avgAirTempF, pressureHpa, pressureChangeRate
- moonPhase
- fullPrediction (both Activity + Position)

### ForecastView (new file)
- Chart card on top: line chart of activity score OR position score (or both overlaid)
- Scrubbable: drag to highlight blocks
- Day separator lines, NOW marker, % axis
- Below chart: scrollable list grouped by day
- Each row: time range + activity level + position + both %s
- Tap to expand: full factor breakdown for both metrics

### ContentView.swift
- Add "Forecast" tab between Dashboard and Log

---

## File Summary

| Action   | File                              | Changes                                          |
|----------|-----------------------------------|--------------------------------------------------|
| Modify   | Models.swift                      | Add pressure fields, ActivityLevel, FullPrediction, ForecastBlock, ForecastDay |
| Modify   | APIService.swift                  | Add surface_pressure param, 3-day fetch methods  |
| Modify   | PredictionEngine.swift            | Dual weight systems, activity + position predict, pressure factor |
| Modify   | FishingViewModel.swift            | Add pressure data, compute both predictions      |
| Modify   | ConditionCards.swift              | Redesign prediction card (dual metrics), expandable wind, new pressure card |
| Modify   | DashboardView.swift               | Add pressure card, layout adjustments            |
| Modify   | TideGraphView.swift               | Make tide card expandable with extra detail       |
| Create   | ForecastViewModel.swift           | 3-day data loading + block computation           |
| Create   | Views/ForecastView.swift          | Forecast tab main view + chart + block list      |
| Modify   | Views/ContentView.swift           | Add Forecast tab                                 |

No changes to: BearCutFishingApp.swift, Persistence.swift, LogListView, LogEntryFormView, TrendsView
