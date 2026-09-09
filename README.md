# Sterownik SmartThings Edge: Viomi Vacuum V8

Dedykowany sterownik **SmartThings Edge Driver (LAN)** dla robota sprzątającego **Viomi Vacuum V8** (oraz modeli kompatybilnych z protokołem miIO, m.in. Viomi V6, V7, V10, V13, SE, V2 Pro). 

Sterownik komunikuje się z odkurzaczem **bezpośrednio w sieci lokalnej (LAN)** za pośrednictwem szyfrowanego protokołu UDP miIO, bez pośrednictwa chmury zewnętrznej ani Home Assistanta.

---

## 🚀 Możliwości sterownika

- **Sterowanie pracą (Włącz / Wyłącz / Pauza):**
  - Włączenie przełącznika głównego (`Switch ON`) uruchamia sprzątanie (z uwzględnieniem typu zamontowanego pojemnika).
  - Wyłączenie przełącznika (`Switch OFF`) wykonuje akcję wybraną w preferencjach (domyślnie: powrót do bazy i ładowanie, zatrzymanie w miejscu lub pauza).
- **Stan baterii:** Odczyt poziomu naładowania w procentach (`0-100%`).
- **Status ruchu i tryb pracy:**
  - Odzwierciedlenie stanów odkurzacza: `Bezczynny`, `Sprzątanie`, `Wstrzymany`, `Powrót do bazy` (`homing`), `Ładowanie` (`charging`).
- **Regulacja siły ssania (Fan Speed):**
  - 4 poziomy: `0: Silent` (Cichy), `1: Standard` (Standardowy), `2: Medium` (Średni), `3: Turbo` (Maksymalny).
- **Tryb Turbo (Robot Cleaner Turbo Mode):** Szybki przełącznik maksymalnej siły ssania.
- **Dedykowane przyciski akcji (Komponenty pomocnicze):**
  - **Powrót do bazy:** Dedykowany przycisk powrotu do stacji ładującej.
  - **Zlokalizuj odkurzacz:** Wywołanie sygnału dźwiękowego w robocie, aby łatwo go znaleźć.
- **Automatyczne rozpoznawanie pojemnika i mopa:**
  - Automatycznie dopasowuje tryb sprzątania w zależności od założonego pojemnika:
    - Pojemnik na kurz -> Tylko odkurzanie
    - Pojemnik 2-w-1 (kurz + woda) -> Odkurzanie i mopowanie
    - Zbiornik na wodę -> Tylko mopowanie
  - Możliwość wymuszenia trybu w preferencjach urządzenia.

---

## 📁 Struktura projektu

```
Viomi Vacuum V8 Edge Driver/
├── config.yml                  # Konfiguracja uprawnień pakietu Edge (LAN, Discovery)
├── profiles/
│   └── viomi-vacuum-v8.yaml    # Profil urządzenia (komponenty, capabilities, preferencje)
├── src/
│   ├── init.lua                # Główny punkt wejścia i obsługa zdarzeń SmartThings
│   ├── discovery.lua           # Tworzenie urządzenia LAN na hubie
│   ├── miio.lua                # Klient protokołu miIO UDP (AES-128-CBC)
│   ├── md5.lua                 # Implementacja MD5 w czystym Lua (generowanie kluczy)
│   └── viomi.lua               # Logika specyficzna dla Viomi V8 (mapowanie komend i stanów)
└── README.md                   # Niniejsza dokumentacja
```

---

## 🛠️ Wymagania

1. **Hub SmartThings** (np. Samsung SmartThings Hub v2, v3, Aeotec Smart Home Hub lub SmartThings Station).
2. **Adres IP** odkurzacza w Twojej sieci lokalnej (np. `192.168.1.50`). Zalecane jest przypisanie stałego adresu IP w routerze (DHCP Reservation).
3. **32-znakowy token** odkurzacza (np. `476446704a43794762516a4958474246`).
4. Narzędzie **SmartThings CLI** na komputerze do wgrania sterownika na hub.

---

## 📦 Instrukcja instalacji na hubie SmartThings

### Krok 1: Pobranie SmartThings CLI
Jeśli nie masz jeszcze SmartThings CLI:
1. Pobierz plik wykonywalny dla swojego systemu z oficjalnego repozytorium:
   👉 **[SmartThings CLI Releases](https://github.com/SmartThingsCommunity/smartthings-cli/releases)**
   - Linux: `smartthings-linux-x64.tar.gz` (lub binarka)
   - Windows: `smartthings-win-x64.zip`
   - macOS: `smartthings-macos-x64.tar.gz`
2. Rozpakuj i umieść plik `smartthings` w katalogu dostępnym w `PATH` (np. `/usr/local/bin` lub `~/.local/bin`), a w systemie Linux nadaj prawa wykonywania:
   ```bash
   chmod +x smartthings
   ```

### Krok 2: Logowanie do SmartThings CLI
Otwórz terminal w katalogu tego projektu i zaloguj się do swojego konta Samsung SmartThings:
```bash
smartthings edge:channels
```
CLI otworzy przeglądarkę z prośbą o autoryzację Twojego konta.

### Krok 3: Utworzenie własnego kanału (jeśli jeszcze go nie masz)
```bash
smartthings edge:channels:create
```
Podaj nazwę, np. `Moje Sterowniki Edge`, i wybierz typ kanału. Skopiuj wygenerowany identyfikator kanału (`Channel ID`).

### Krok 4: Wpisanie huba do kanału
Zapisz swój hub do nowo utworzonego kanału:
```bash
smartthings edge:channels:enroll <CHANNEL_ID>
```
Wybierz swój hub z listy.

### Krok 5: Spakowanie i wysłanie sterownika
Będąc w głównym katalogu sterownika (`Viomi Vacuum V8 Edge Driver`), uruchom:
```bash
smartthings edge:drivers:package .
```
Zostanie utworzona paczka sterownika, a w terminalu pojawi się `Driver ID`.

### Krok 6: Przypisanie sterownika do kanału
```bash
smartthings edge:channels:assign <DRIVER_ID> --channel <CHANNEL_ID>
```

### Krok 7: Instalacja sterownika na Twoim hubie
```bash
smartthings edge:drivers:install <DRIVER_ID> --channel <CHANNEL_ID>
```
Wybierz swój hub. Sterownik zostanie pobrany i zainstalowany bezpośrednio na Twoim hubie SmartThings!

---

## 📱 Dodanie i konfiguracja odkurzacza w aplikacji SmartThings

1. Otwórz aplikację **SmartThings** na smartfonie.
2. Przejdź do zakładki **Urządzenia** i naciśnij `+` (w prawym górnym rogu) -> **Dodaj urządzenie**.
3. Wybierz opcję **Skanuj w pobliżu** (Scan nearby).
4. Hub wykryje nowe urządzenie o nazwie **Viomi Vacuum V8**.
5. Wejdź w nowo utworzone urządzenie, kliknij menu trzech kropek (`⋮`) w prawym górnym rogu i wybierz **Ustawienia** (Settings).
6. Wypełnij pola konfiguracyjne:
   - **Adres IP:** Wpisz adres IP odkurzacza (np. `192.168.1.50`).
   - **Token urządzenia:** Wklej 32-znakowy klucz szesnastkowy.
   - **Interwał odpytywania:** Domyślnie `30` sekund (możesz ustawić od `10` do `300`).
   - **Akcja po wyłączeniu:** Wybierz, co odkurzacz ma zrobić po kliknięciu wyłączenia (domyślnie: *Powrót do bazy*).
   - **Tryb pracy mopa:** Pozostaw *Automatycznie* lub wybierz stały tryb.
7. Naciśnij **Zapisz** (Save).

Po zapisaniu ustawień hub natychmiast nawiąże połączenie UDP z robotem, zaktualizuje stan baterii i tryb pracy, a odkurzacz stanie się w pełni sterowalny!

---

## 🔍 Rozwiązywanie problemów

- **Urządzenie wyświetla się jako "Offline":**
  - Upewnij się, że hub SmartThings i odkurzacz znajdują się w tej samej sieci LAN/VLAN (UDP port `54321` musi być osiągalny bez blokowania na firewallu).
  - Sprawdź, czy adres IP odkurzacza nie zmienił się w routerze.
  - Sprawdź poprawność 32-znakowego tokena (nie powinien zawierać spacji).
- **Podgląd logów na żywo:**
  Aby zobaczyć komunikaty diagnostyczne w czasie rzeczywistym, uruchom:
  ```bash
  smartthings edge:drivers:logcat --hub-address=<ADRES_IP_HUBA>
  ```
