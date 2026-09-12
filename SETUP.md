# Flutter App — Setup

## 1. Create the project

```powershell
cd C:\Development
flutter create advantage
cd advantage
```

## 2. Add the http package

```powershell
flutter pub add http
```

## 3. Copy in these files

Replace / create these inside `C:\Development\advantage\lib\`:

```
lib\
  main.dart                      <- replace the generated one
  services\
    api_service.dart             <- create the "services" folder
  screens\
    home_screen.dart             <- create the "screens" folder
    stock_screen.dart
```

## 4. Allow the app to use the internet

Open `android\app\src\main\AndroidManifest.xml` and add this line
**above** the `<application>` tag:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## 5. Allow plain HTTP (needed while the API runs on your PC)

Android blocks non-HTTPS traffic by default. Since your local API is `http://`,
add this **inside** the `<application ...>` tag in the same file:

```xml
android:usesCleartextTraffic="true"
```

So it looks like:

```xml
<application
    android:label="advantage"
    android:usesCleartextTraffic="true"
    ...>
```

_(Once you deploy the backend over HTTPS you can remove this.)_

## 6. Make sure the Python API is running

In a **separate** PowerShell window:

```powershell
cd C:\MyDashboard
python -m uvicorn api:app --reload --host 0.0.0.0
```

Note `--host 0.0.0.0` — without it, the API only listens to your PC and the
emulator/phone can't reach it.

## 7. Run the app

```powershell
cd C:\Development\advantage
flutter run
```

Pick a device when prompted (emulator or your USB-connected phone).

---

## The URL: the thing that will trip you

Open `lib/services/api_service.dart` and check `baseUrl`:

| Where you run it | What baseUrl must be |
|---|---|
| **Android emulator** | `http://10.0.2.2:8000` (the default) |
| **Real phone over USB/WiFi** | `http://<YOUR-PC-IP>:8000` |
| **Deployed backend** | `https://your-api.onrender.com` |

`10.0.2.2` is a special alias — inside the Android emulator, it means "the PC
running me". Using `localhost` would point the emulator at *itself*, where no
server is running.

**To find your PC's IP** (for a real phone):

```powershell
ipconfig
```

Look for "IPv4 Address" under your WiFi adapter, e.g. `192.168.1.5`.
Your phone must be on the **same WiFi network** as your PC.

---

## What you should see

The home screen shows a **connection banner**:

- 🟢 **"Connected to backend"** → everything works, search a stock
- 🔴 **"Can't reach the API"** → the API isn't running, or `baseUrl` is wrong

That banner exists specifically so you learn *immediately* whether the phone can
reach your Python, instead of hitting a confusing error later.
