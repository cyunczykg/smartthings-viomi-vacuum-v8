# SmartThings Edge Driver: Viomi Vacuum V8

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![SmartThings Edge](https://img.shields.io/badge/SmartThings-Edge%20Driver-blue.svg)](https://developer.smartthings.com/)
[![Platform](https://img.shields.io/badge/Platform-LAN%20%28miIO%29-green.svg)](https://github.com/cyunczykg/smartthings-viomi-vacuum-v8)
[![Channel Invite](https://img.shields.io/badge/SmartThings%20Channel-Invite%20Link-brightgreen.svg)](https://bestow-regional.api.smartthings.com/invite/VbMbbGG76pMB)

Dedykowany sterownik **SmartThings Edge Driver (LAN)** dla robota sprzątającego **Viomi Vacuum V8** oraz modeli kompatybilnych z protokołem miIO (m.in. Viomi V6, V7, V10, V13, SE, V2 Pro).

Sterownik komunikuje się z odkurzaczem **bezpośrednio w sieci lokalnej (LAN)** za pośrednictwem szyfrowanego protokołu UDP miIO (port 54321), bez potrzeby instalowania Home Assistanta ani korzystania z chmury zewnętrznej.

---

## ⚡ Szybka instalacja (Bez używania terminala)

Możesz zainstalować sterownik bezpośrednio na swoim hubie SmartThings jednym kliknięciem:

1. Kliknij oficjalny link zaproszenia do kanału:  
   👉 **[Dołącz do kanału Viomi Vacuum V8 (SmartThings Channel Invite)](https://bestow-regional.api.smartthings.com/invite/VbMbbGG76pMB)**
2. Zaloguj się na swoje konto Samsung / SmartThings.
3. Kliknij **Enroll** przy Twoim hubie SmartThings.
4. Kliknij **Available Drivers** i wybierz **Install** przy sterowniku **Viomi Vacuum V8**.
5. W aplikacji SmartThings na telefonie kliknij **`+`** -> **Dodaj urządzenie** -> **Skanuj w pobliżu** (*Scan nearby*).

---

## 🚀 Możliwości sterownika

- **Włączanie / Wyłączanie / Pauza (`switch`):**
  - Włączenie głównego przełącznika (`Switch ON`) uruchamia sprzątanie:
    - Jeśli zaznaczono konkretne pokoje (np. Kuchnia i Salon) -> robot posprząta tylko wybrane pokoje.
    - Jeśli żaden pokój lub wszystkie są zaznaczone -> robot posprząta całe mieszkanie.
  - Wyłączenie przełącznika (`Switch OFF`) wykonuje wybraną akcję (domyślnie: powrót do bazy i ładowanie, zatrzymanie w miejscu lub pauza).
- **Powrót do bazy (Zawsze pod ręką):**
  - Dedykowany przycisk **Powrót do bazy** umieszczony bezpośrednio w głównym kafelku sterowania.
  - Standardowe przyciski systemowe SmartThings (`robotCleanerOperatingState`): **Start**, **Wstrzymaj**, **Wróć** (powrót do stacji).
- **Wybór pokojów (Room Cleaning) z jednoczesnym zaznaczaniem wielu pokoi:**
  - Niezależne przełączniki dla każdego pokoju (`Kuchnia`, `Salon`, `Korytarz`, `Sypialnia`, `Pokój Kasi`, `Pokój Maćka`, `Łazienka`, `Pokój 8`):
    - **Równoczesny wybór wielu pokoi:** Możesz włączyć przełącznik dla kilku pokoi naraz (np. Kuchnia i Salon) – zaznaczenia pozostają aktywne!
    - Następnie wystarczy wcisnąć **Start** w sekcji stanu pracy lub włączyć główny przełącznik robota – odkurzacz posprząta wyłącznie wskazane pomieszczenia.
  - **Szybkie akcje grupowe:**
    - `[ Odkurz wszystko ]` – zaznacza wszystkie pokoje i uruchamia całościowe sprzątanie mieszkania.
    - `[ Odznacz wszystko ]` – wyłącza zaznaczenie wszystkich aktywnych przełączników pokojów jednym kliknięciem.
  - **Automatyczny reset:** Po zakończeniu sprzątania i powrocie do stacji dokującej (`DOCKED` / `CHARGING`) przełączniki pokojów automatycznie powracają do stanu wyłączonego.
  - Możliwość edycji nazw pokojów w ustawieniach urządzenia (*Ustawienia -> Nazwa: Pokój 1..8*).
- **Zlokalizuj odkurzacz (`fluteriver09555.vacuumLocate`):**
  - Dedykowany przycisk wywołania sygnału dźwiękowego w robocie, by łatwo go odnaleźć.
- **Stan baterii (`battery`):** Odczyt poziomu naładowania w procentach (`0–100%`).
- **Tryb ruchu i pracy (`robotCleanerMovement` / `robotCleanerCleaningMode`):**
  - Odzwierciedlenie stanów odkurzacza: `Bezczynny`, `Sprzątanie`, `Wstrzymany`, `Powrót do bazy` (`homing`), `Ładowanie` (`charging`).
- **Regulacja siły ssania (`fanSpeed`):**
  - 4 poziomy: `0: Silent` (Cichy), `1: Standard` (Standardowy), `2: Medium` (Średni), `3: Turbo` (Maksymalny).
- **Tryb maksymalny (`robotCleanerTurboMode`):** Szybki przełącznik trybu Turbo.
- **Automatyczne rozpoznawanie pojemnika i mopa:**
  - Automatycznie dobiera tryb sprzątania w zależności od założonego pojemnika:
    - Pojemnik na kurz -> Tylko odkurzanie
    - Pojemnik 2-w-1 (kurz + woda) -> Odkurzanie i mopowanie
    - Zbiornik na wodę -> Tylko mopowanie
  - Możliwość wymuszenia trybu w preferencjach urządzenia.

---

## 🔑 Jak uzyskać adres IP i Token odkurzacza?

Do poprawnego działania sterownik wymaga podania **lokalnego adresu IP** oraz **32-znakowego tokena** urządzenia. 

Najprostszym i najszybszym sposobem na ich pobranie jest użycie narzędzia **[Xiaomi Cloud Tokens Extractor](https://github.com/piotrmachowski/xiaomi-cloud-tokens-extractor)** autorstwa Piotra Machowskiego. Narzędzie loguje się do Twojego konta Xiaomi i automatycznie odczytuje listę wszystkich sparowanych urządzeń wraz z ich tokenami i adresami IP.

### Sposób A: Gotowy program (Windows / Linux)
1. Przejdź do strony wydań: 👉 **[Releases - Xiaomi Cloud Tokens Extractor](https://github.com/piotrmachowski/xiaomi-cloud-tokens-extractor/releases)**.
2. Pobierz plik wykonywalny dla swojego systemu (`token_extractor.exe` dla Windows lub `token_extractor` dla Linux).
3. Uruchom pobrany program.

### Sposób B: Uruchomienie w Pythonie (Linux / macOS / Windows)
```bash
git clone https://github.com/piotrmachowski/xiaomi-cloud-tokens-extractor.git
cd xiaomi-cloud-tokens-extractor
pip install -r requirements.txt
python token_extractor.py
```

### Sposób C: Docker
```bash
docker run -it --rm ghcr.io/piotrmachowski/xiaomi-cloud-tokens-extractor
```

### Instrukcja obsługi narzędzia:
1. Po uruchomieniu program poprosi Cię o dane logowania do konta **Xiaomi / Mi Home**:
   - **Username:** Twój e-mail, numer telefonu lub Xiaomi ID powiązany z aplikacją Mi Home.
   - **Password:** Hasło do konta Xiaomi.
   - **Server / Region:** Wciśnij **Enter** (aby przeszukać automatycznie wszystkie serwery) lub wpisz kod kraju (np. `pl`, `de`, `cn`).
2. Program wyświetli tabelę ze znalezionymi urządzeniami. Odszukaj swój odkurzacz:
   ```text
   ----------------------------------------------------
   NAME:     Viomi Vacuum V8
   ID:       123456789
   IP:       192.168.1.50                       <-- ADRES IP
   TOKEN:    476446704a43794762516a4958474246   <-- 32-ZNAKOWY TOKEN
   MODEL:    viomi.vacuum.v8
   ----------------------------------------------------
   ```
3. Skopiuj wartości **IP** oraz **TOKEN** — będą potrzebne w kolejnym kroku.

> 💡 **Wskazówka:** Zaleca się przypisanie odkurzaczowi stałego adresu IP w ustawieniach routera (funkcja *DHCP Static Lease* / *IP Reservation*), aby adres IP nie uległ zmianie po restarcie sieci.

---

## 📱 Konfiguracja w aplikacji SmartThings

Po dodaniu urządzenia na hubie (poprzez opcję *Skanuj w pobliżu*):
1. Otwórz aplikację **SmartThings** na smartfonie.
2. Wejdź w nowo dodane urządzenie **Viomi Vacuum V8**.
3. Kliknij menu trzech kropek (**`⋮`**) w prawym górnym rogu -> **Ustawienia** (*Settings*).
4. Wypełnij pola konfiguracyjne:
   - **Adres IP:** Wpisz adres IP odkurzacza (uzyskany z ekstraktora, np. `192.168.1.50`).
   - **Token urządzenia:** Wklej 32-znakowy token (uzyskany z ekstraktora).
   - **Interwał odpytywania (s):** Domyślnie `30` sekund (zakres od `10` do `300`).
   - **Akcja po wyłączeniu:** Wybierz, co odkurzacz ma zrobić po kliknięciu wyłączenia (*Powrót do bazy*, *Zatrzymanie*, *Wstrzymanie*).
   - **Tryb pracy mopa:** *Automatycznie (wg pojemnika)* lub wybrany tryb stały.
   - **Nazwy pokojów (Pokój 1..8):** Opcjonalne dostosowanie nazw stref do Twojego mieszkania (np. Kuchnia, Salon, Korytarz).
5. Naciśnij **Zapisz** (*Save*).

Po zapisaniu ustawień hub natychmiast połączy się z robotem w sieci lokalnej, pobierze stan baterii i aktualny status pracy.

---

### 🧹 Sprzątanie wybranych pokojów (Room Cleaning)

1. **Wybór pokojów do posprzątania:**
   - W sekcji **Wybór pokoi** kliknij przyciski stref, które chcesz odkurzyć (np. `[ Kuchnia ]` oraz `[ Salon ]`).
   - Wskaźnik tekstowy *Wybrane do odkurzenia* natychmiast pokaże listę wybranych pomieszczeń: `Kuchnia, Salon`.
   - Ponowne kliknięcie pokoju odznacza go z listy.
   - Kliknięcie `[ Odznacz wszystko ]` resetuje wybór do całego mieszkania.
   - Kliknięcie `[ Wszystkie pokoje ]` zaznacza cały dom.
2. **Start odkurzania:**
   - Kliknij przycisk `[ ▶ Start odkurzania ]` bezpośrednio w sekcji pokoi, LUB
   - Włącz główny przełącznik odkurzacza (**Włącz / ON**), LUB
   - Kliknij **Start** w sekcji stanu robota.
   - Robot natychmiast wyruszy posprzątać tylko wybrane strefy.
   - Po powrocie do bazy wskaźnik automatycznie resetuje się do stanu początkowego.
3. **Powrót do bazy:**
   - Dostępny bezpośrednio w kafelku przycisk **Powrót do bazy** lub systemowy przycisk **Wróć** natychmiast odsyła robota do stacji dokującej.

---

## 🛠️ Instalacja zaawansowana (SmartThings CLI)

Dla programistów i osób zarządzających hubem z poziomu konsoli:

- **Channel ID:** `f4a701eb-9cd9-4158-84a4-0620ef17d053`
- **Driver ID:** `1029a107-421a-48d6-a7ac-30e9c5d98b22`
- **Package Key:** `viomi-vacuum-v8`

```bash
# Zapisz hub do kanału
smartthings edge:channels:enroll f4a701eb-9cd9-4158-84a4-0620ef17d053

# Zainstaluj sterownik na hubie
smartthings edge:drivers:install 1029a107-421a-48d6-a7ac-30e9c5d98b22 --channel f4a701eb-9cd9-4158-84a4-0620ef17d053
```

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

## 🔍 Rozwiązywanie problemów

- **Urządzenie wyświetla się jako "Offline":**
  - Upewnij się, że hub SmartThings i odkurzacz znajdują się w tej samej sieci LAN/podsieci (port UDP `54321` musi być osiągalny bez blokad na firewallu).
  - Zaleca się przypisanie stałego IP w routerze (DHCP reservation).
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
- **[xiaomi-cloud-tokens-extractor](https://github.com/piotrmachowski/xiaomi-cloud-tokens-extractor)** autorstwa @piotrmachowski – za narzędzie do łatwego pozyskiwania tokenów urządzeń Xiaomi/Viomi.
- **[python-miio](https://github.com/rytilahti/python-miio)** – za dokumentację protokołu komunikacyjnego Viomi.

---

## 📄 Licencja

Projekt jest udostępniany na warunkach licencji **MIT**. Szczegóły znajdują się w pliku [LICENSE](LICENSE).

Autor: **Grzegorz Cyuńczyk** ([@cyunczykg](https://github.com/cyunczykg))
