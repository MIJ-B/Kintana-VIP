# ⭐ KINTANA v4.0 — Flutter Trading App

> **VIP Trading App** with JORO AI, JOROpredict AMD signals, Replay Mode, and live Deriv WebSocket data.

---

## 🚀 Setup Instructions

### 1. Prerequisites
```bash
# Install Flutter SDK (3.x+)
# https://docs.flutter.dev/get-started/install

flutter --version  # verify >= 3.0.0
```

### 2. Clone / Place the project
Put the `kintana/` folder anywhere on your machine.

### 3. Install dependencies
```bash
cd kintana
flutter pub get
```

### 4. Add fonts (SpaceMono)
Create folders and add font files:
```
assets/
  fonts/
    SpaceMono-Regular.ttf
    SpaceMono-Bold.ttf
```

Download SpaceMono from: https://fonts.google.com/specimen/Space+Mono

**OR** simply remove the custom font reference from `pubspec.yaml` and replace `'SpaceMono'` with `'monospace'` in `kintana_theme.dart` for testing.

### 5. Run the app
```bash
# Android
flutter run

# iOS
flutter run -d ios

# Release build (Android APK)
flutter build apk --release
```

---

## 📁 Project Structure
```
lib/
├── main.dart                    # App entry + navigation
├── theme/
│   └── kintana_theme.dart       # Dark trading theme
├── models/
│   └── models.dart              # Candle, Trade, JOROSignal, markets
├── services/
│   └── market_state.dart        # WebSocket, replay, state management
├── widgets/
│   └── candle_chart_painter.dart  # Custom canvas chart
└── screens/
    ├── chart_screen.dart        # Main chart view
    ├── joro_screen.dart         # JORO AI chat
    ├── journal_screen.dart      # News, trades, calendar
    └── settings_screen.dart     # Configuration
```

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📊 **HD Chart** | Custom candlestick chart with zoom/pan, crosshair, volume |
| ⚡ **JOROpredict** | AMD signal detection (Accumulation/Manipulation/Distribution) |
| 🎬 **Replay Mode** | Historical data replay with tick simulation |
| 🤖 **JORO AI** | GROQ-powered AMD signal generation + market analysis |
| 📒 **Trade Journal** | Track all signals with P&L, SL/TP |
| 🔔 **Trailing Stop** | Automatic SL adjustment |
| 📰 **Live News** | AI-generated market news via GROQ |
| 🔗 **Deriv WS** | Real-time Deriv WebSocket, all symbols |

---

## 🔑 Configuration

In **Settings**, add your GROQ API key:
- Free at: https://console.groq.com
- Models: Llama 3.3 70B, Llama 4, Kimi-K2, Compound Beta

---

## 🎨 UI Design

- **Theme**: Dark luxury trading aesthetic
- **Fonts**: Space Mono (mono) + Syne (sans)
- **Colors**: Deep navy bg, cyan accent, neon green/red candles
- **Animations**: Flutter Animate, smooth 60fps

---

## 📦 Key Dependencies

```yaml
web_socket_channel: ^2.4.0    # Deriv WebSocket
http: ^1.1.0                  # GROQ API calls
shared_preferences: ^2.2.2    # Local storage
google_fonts: ^6.1.0          # Syne font
flutter_animate: ^4.3.0       # Animations
provider: ^6.1.0              # State management
```

---

## 🛠 Notes

- **App ID**: Deriv App ID `129691` (embedded)
- **Default symbol**: `frxXAUUSD` (Gold)
- All trades stored locally via `SharedPreferences`
- JOROpredict signals are fully client-side (no API needed)
- GROQ AI requires a free API key for JORO chat + AMD signals

---

*VIP ⭐ KINTANA v4.0 — JORO AI + AMD + JOROpredict + Replay Advanced*
