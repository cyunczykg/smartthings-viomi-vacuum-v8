# SmartThings Edge Driver: Viomi Vacuum V8

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![SmartThings Edge](https://img.shields.io/badge/SmartThings-Edge%20Driver-blue.svg)](https://developer.smartthings.com/)
[![Platform](https://img.shields.io/badge/Platform-LAN%20%28miIO%29-green.svg)](https://github.com/cyunczykg/smartthings-viomi-vacuum-v8)

Dedykowany sterownik **SmartThings Edge Driver (LAN)** dla robota sprzątającego **Viomi Vacuum V8** oraz modeli kompatybilnych z protokołem miIO (m.in. Viomi V6, V7, V10, V13, SE, V2 Pro).

Sterownik komunikuje się z odkurzaczem **bezpośrednio w sieci lokalnej (LAN)** za pośrednictwem szyfrowanego protokołu UDP miIO (port 54321), bez potrzeby instalowania Home Assistanta ani korzystania z chmury zewnętrznej.

---

## 🚀 Możliwości sterownika

- **Włączanie / Wyłączanie / Pauza (`switch`):**
  - Włączenie przełącznika (`Switch ON`) uruchamia sprzątanie (z automatycznym uwzględnieniem typu zamontowanego pojemnika).
  - Wyłączenie przełącznika (`Switch OFF`) wykonuje wybraną akcję (domyślnie: powrót do bazy i ładowanie, zatrzymanie w miejscu lub pauza).
- **Stan baterii (`battery`):** Odczyt poziomu naładowania w procentach (`0–100%`).
- **Tryb ruchu i pracy (`robotCleanerMovement` / `robotCleanerCleaningMode`):**
  - Odzwierciedlenie stanów odkurzacza: `Bezczynny`, `Sprzątanie`, `Wstrzymany`, `Powrót do bazy` (`homing`), `Ładowanie` (`charging`).
- **Regulacja siły ssania (`fanSpeed`):**
  - 4 poziomy: `0: Silent` (Cichy), `1: Standard` (Standardowy), `2: Medium` (Średni), `3: Turbo` (Maksymalny).
- **Tryb maksymalny (`robotCleanerTurboMode`):** Szybki przełącznik trybu Turbo.
- **Dedykowane przyciski na kafelku (`momentary`):**
  - **Powrót do bazy:** Dedykowany przycisk powrotu do stacji ładującej.
  - **Zlokalizuj odkurzacz:** Wywołanie sygnału dźwiękowego w robocie, aby łatwo go odnaleźć.
- **Automatyczne rozpoznawanie pojemnika i mopa:**
  - Automatycznie dobiera tryb sprzątania w zależności od założonego pojemnika:
    - Pojemnik na kurz -> Tylko odkurzanie
    - Pojemnik 2-w-1 (kurz + woda) -> Odkurzanie i mopowanie
    - Zbiornik na wodę -> Tylko mopowanie
  - Możliwość wymuszenia trybu w preferencjach urządzenia.

---

## 📁 Struktura projektu

```
Viomi Vacuum V8 Edge Driver/
├── config.yml                  # Konfiguracja uprawnień pakietu Edge (LAN, Discovery)
├── LICENSE                     # Licencja MIT
├── profiles/
│   └── viomi-vacuum-v8.yaml    # Profil urządzenia (komponenty, capabilities, preferencje)
├── src/
│   ├── init.lua                # Główny punkt wejścia i obsługa zdarzeń SmartThings
│   ├── discovery.lua           # Tworzenie urządzenia LAN na hubie
│   ├── miio.lua                # Klient protokołu miIO UDP (AES-128-CBC)
│   ├── md5.lua                 # Implementacja MD5 w czystym Lua (generowanie kluczy)
│   └── viomi.lua               # Logika specyficzna dla Viomi V8 (mapowanie komend i stanów)
└── README.md                   # Dokumentacja projektu
```

---

## 🛠️ Wymagania

1. **Hub SmartThings** (np. Samsung SmartThings Hub v2, v3, Aeotec Smart Home Hub lub SmartThings Station).
2. **Adres IP** odkurzacza w Twojej sieci lokalnej (np. `192.168.1.50`). Zalecane jest przypisanie stałego adresu IP w routerze (DHCP Reservation).
3. **32-znakowy token** odkurzacza (np. wyciągnięty z Mi Home lub przez `Xiaomi-cloud-tokens-extractor`).
4. Narzędzie **SmartThings CLI** na komputerze do wgrania sterownika na hub.

---

## 📦 Instrukcja instalacji na hubie SmartThings

### Krok 1: Spakowanie sterownika
Przejdź do katalogu projektu w terminalu:
```bash
smartthings edge:drivers:package .
```
*(CLI zwróci wygenerowany `Driver ID`)*

### Krok 2: Utworzenie lub sprawdzenie kanału
```bash
smartthings edge:channels
```
Jeśli nie masz kanału, utwórz go:
```bash
smartthings edge:channels:create
```

### Krok 3: Zapisanie huba do kanału
```bash
smartthings edge:channels:enroll <TWÓJ_CHANNEL_ID>
```

### Krok 4: Przypisanie sterownika do kanału
```bash
smartthings edge:channels:assign <DRIVER_ID> --channel <TWÓJ_CHANNEL_ID>
```

### Krok 5: Instalacja sterownika na hubie
```bash
smartthings edge:drivers:install <DRIVER_ID> --channel <TWÓJ_CHANNEL_ID>
```

---

## 📱 Dodanie i konfiguracja odkurzacza w aplikacji SmartThings

1. Otwórz aplikację **SmartThings** na telefonie.
2. Przejdź do zakładki **Urządzenia** i naciśnij **`+`** (w prawym górnym rogu) -> **Dodaj urządzenie**.
3. Wybierz opcję **Skanuj w pobliżu** (*Scan nearby*).
4. Hub wykryje nowe urządzenie o nazwie **Viomi Vacuum V8**.
5. Wejdź w nowo utworzone urządzenie, kliknij menu trzech kropek (**`⋮`**) w prawym górnym rogu -> **Ustawienia** (*Settings*).
6. Wypełnij pola konfiguracyjne:
   - **Adres IP:** Wpisz adres IP odkurzacza (np. `192.168.1.50`).
   - **Token urządzenia:** Wklej 32-znakowy klucz szesnastkowy (hex).
   - **Interwał odpytywania (s):** Domyślnie `30` sekund (zakres od `10` do `300`).
   - **Akcja po wyłączeniu:** Wybierz, co odkurzacz ma zrobić po kliknięciu wyłączenia (*Powrót do bazy*, *Zatrzymanie*, *Wstrzymanie*).
   - **Tryb pracy mopa:** *Automatycznie (wg pojemnika)* lub wybrany tryb stały.
7. Naciśnij **Zapisz** (*Save*).

Po zapisaniu ustawień hub natychmiast nawiąże połączenie UDP z robotem, pobierze stan baterii i aktualny status.

---

## 🔍 Rozwiązywanie problemów

- **Urządzenie wyświetla się jako "Offline":**
  - Upewnij się, że hub SmartThings i odkurzacz znajdują się w tej samej sieci LAN/podsieci (port UDP `54321` musi być osiągalny).
  - Upewnij się, że adres IP odkurzacza nie uległ zmianie.
  - Sprawdź poprawność 32-znakowego tokena.
- **Podgląd logów na żywo:**
  ```bash
  smartthings edge:drivers:logcat --hub-address=<ADRES_IP_HUBA>
  ```

---

## 🙏 Podziękowania i inspiracje

Projekt powstał w oparciu o analizę i doświadczenia społeczności:
- **[smartthings-miot-edge-driver](https://github.com/wonjj6768/smartthings-miot-edge-driver)** autorstwa @wonjj6768 – za implementację protokołu miIO w czystym Lua dla SmartThings Edge.
- **[home-assistant-viomi-vacuum-v8](https://github.com/saprumohit/home-assistant-viomi-vacuum-v8)** autorstwa @saprumohit – za mapowanie rejestrów i komend dla odkurzacza Viomi V8.
- **[python-miio](https://github.com/rytilahti/python-miio)** – za dokumentację protokołu komunikacyjnego Viomi.

---

## 📄 Licencja

Projekt jest udostępniany na warunkach licencji **MIT**. Szczegóły znajdują się w pliku [LICENSE](LICENSE).

Autor: **Grzegorz Cyuńczyk** ([@cyunczykg](https://github.com/cyunczykg))
