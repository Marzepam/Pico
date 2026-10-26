# Pico

Minimalistyczna, natywna przeglądarka obrazów na macOS, w stylu Movi
(„Shave Video”/VirtualDub, tylko dla zdjęć zamiast wideo). Napisana w
Swift/SwiftUI + ImageIO/CoreGraphics, bez żadnych zewnętrznych zależności.

Projekt (foldery, plik `project.yml`, target Xcode, entitlements, punkt
wejścia `PicoApp`) jest w całości nazwany **Pico** — identyfikator pakietu
to `com.pico.Pico`. Wersja **1.0**. Okno „O Pico” (menu Pico → O Pico) jest
w całości własne (`AboutPanel.show()` w `PicoApp.swift`, zastępuje domyślny
`CommandGroup(replacing: .appInfo)`) — pokazuje numer wersji, „Made by
Marzepam” i klikalny link „Project available on
https://github.com/Marzepam”, przez ten sam standardowy panel, którego
używa samo AppKit (`NSApplication.orderFrontStandardAboutPanel(options:)`).

## Funkcje

| Funkcja | Jak działa |
|---|---|
| **Otwórz** | `NSOpenPanel` filtrowany do `UTType.image` — każdy format, jaki system/ImageIO potrafi zdekodować (HEIC, JPEG, PNG, GIF, TIFF, BMP, WebP, ICO i inne), bez ręcznie wypisywanej listy rozszerzeń. |
| **Przeglądaj** | Wybiera folder (`NSOpenPanel` w trybie wyboru katalogu) i pokazuje siatkę miniatur jego zawartości wewnątrz tego samego okna — przycisk działa jak przełącznik między siatką a podglądem pojedynczego zdjęcia. |
| **Zapisz jako…** | Konwertuje bieżący obraz do wybranego formatu (JPEG/PNG/TIFF/HEIC/BMP/GIF) przez `NSSavePanel` z własnym widokiem dodatkowym: suwak jakości dla JPEG/HEIC, wybór kompresji (LZW/brak) dla TIFF — nic dodatkowego dla PNG/BMP/GIF, bo tam nie ma czego ustawiać. |
| **Poprzedni / Następny** | Nawigacja w obrębie folderu, w kolejności własnego sortowania aplikacji (nazwa / data modyfikacji / data utworzenia / rozmiar / typ, rosnąco lub malejąco) — patrz sekcja „Sortowanie” niżej. W trybie okna dopasowują przy tym szerokość okna do proporcji nowego obrazu (wysokość zostaje bez zmian) — patrz „Okno vs. Movi” niżej. |
| **Powiększ / Pomniejsz / Dopasuj do okna** | Zmieniają tylko to, co widać w oknie — samo okno nigdy nie zmienia rozmiaru przy zoomowaniu (patrz „Okno vs. Movi”). |
| **Pełny ekran** | Przełącza okno w/z trybu pełnoekranowego (`NSWindow.toggleFullScreen(_:)`); ikona na pasku i jej podpis zmieniają się zgodnie z aktualnym stanem okna, śledzonym przez powiadomienia `willEnterFullScreenNotification`/`didExitFullScreenNotification` — także wtedy, gdy pełny ekran zostanie włączony/wyłączony inną drogą (zielony przycisk okna, ⌃⌘F). |

Dodatkowo (drobne, naturalne rozszerzenia, nieopisane wprost w specyfikacji,
ale spójne z resztą aplikacji): podwójne kliknięcie przełącza między
„Dopasuj do okna” a rzeczywistym rozmiarem (100%), gest „uszczypnięcia”
(pinch-to-zoom) i przeciąganie obrazu myszą, gdy jest powiększony ponad
rozmiar okna, przeciąganie pliku **lub folderu** na okno (drop pliku =
„Otwórz”, drop folderu = „Przeglądaj”), obsługa „Otwórz z…” w Finderze oraz
skróty klawiszowe: ⌘O, ⇧⌘B, ⌘S, strzałki ←/→ (bez modyfikatora),
⌘+/⌘−/⌘0 oraz goła +/-/0, Esc (wychodzi z siatki miniatur). ⌘N otwiera
zawsze **nowe, niezależne okno** — natywne zakładki okien (window tabbing)
są celowo wyłączone, patrz niżej.

## Wymagania

- macOS 14.0 lub nowszy
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Budowanie

```bash
cd Pico
xcodegen generate
open Pico.xcodeproj
```

Bez XcodeGen: utwórz nowy projekt macOS App w Xcode (SwiftUI, bez Core
Data), skopiuj zawartość `Sources/` do projektu, podmień wygenerowany
`Info.plist` na ten z repo, dodaj `Pico.entitlements` jako Code Signing
Entitlements, ustaw `CFBundleIdentifier` na `com.pico.Pico` i upewnij się,
że `Localizable.xcstrings` oraz pliki `*.lproj/InfoPlist.strings` są
dołączone do targetu.

## Struktura projektu

```
Pico/
├── project.yml                          ← definicja projektu dla XcodeGen
├── Info.plist                           ← CFBundleDocumentTypes, CFBundleLocalizations
├── Pico.entitlements                    ← celowo pusty (bez App Sandbox — patrz niżej)
└── Sources/
    ├── App/
    │   └── PicoApp.swift                 ← @main, WindowGroup, menu, panel „O Pico”
    ├── Models/
    │   ├── BrowsableImage.swift          ← metadane jednego pliku w przeglądanym folderze
    │   └── ImageSortOption.swift         ← pole sortowania + kierunek, komparator
    ├── ViewModels/
    │   └── ImageViewerViewModel.swift    ← cały stan i akcje (otwórz/przeglądaj/zapisz/zoom/nawigacja)
    ├── Views/
    │   ├── ContentView.swift             ← okno, auto-hide paska, rozmiar okna, drag&drop, skróty
    │   ├── ImageCanvasView.swift         ← widok pojedynczego zdjęcia (zoom/pan/gesty)
    │   ├── BrowseGridView.swift          ← siatka miniatur + menu sortowania
    │   ├── FloatingControlBar.swift      ← pływający pasek narzędzi na dole okna
    │   └── SaveOptionsAccessoryView.swift ← widok dodatkowy NSSavePanel („Zapisz jako…”)
    ├── Support/
    │   ├── ImageExporter.swift           ← odczyt (z korektą orientacji EXIF) i zapis przez ImageIO
    │   ├── SupportedImageTypes.swift     ← jakie formaty są czytelne/zapisywalne, listowanie folderu
    │   └── Array+Safe.swift
    ├── Resources/
    │   └── Localizable.xcstrings         ← String Catalog z tłumaczeniami (pl → en/fr/de/es)
    └── {pl,en,fr,de,es}.lproj/
        └── InfoPlist.strings             ← lokalizacja CFBundleTypeName
```

## Jak to działa

### Architektura stanu

Jeden `ImageViewerViewModel` na okno (`@StateObject` w `ContentView`,
dokładnie jak `EditorViewModel` w Movi) — `WindowGroup` tworzy osobną
instancję `ContentView` dla każdego okna, więc każde trzyma własny obraz,
własny kontekst folderu i własny poziom powiększenia. Komendy menu
(`ImageCommands` w `PicoApp.swift`) sięgają po aktualnie aktywne okno przez
`@FocusedValue(\.imageViewerViewModel)`.

### Jasny/ciemny motyw — zgodnie z systemem, nie zablokowany na sztywno

Wcześniejsza wersja ustawiała `.preferredColorScheme(.dark)` na całym oknie
w `PicoApp.swift`, co wymuszało ciemny motyw bez względu na to, w jakim
trybie jest macOS — łącznie z trybem „Automatycznie”, który sam przełącza
się jasny/ciemny w zależności o pory dnia. To ustawienie zostało usunięte:
Pico teraz po prostu podąża za aktualnym wyglądem systemu, tak jak każda
zwyczajna aplikacja AppKit/SwiftUI.

Samo usunięcie `.preferredColorScheme` nie wystarczało, dopóki tło okna,
siatka „Przeglądaj” i część tekstów używały twardo wpisanych kolorów
(`Color.black`, `.foregroundStyle(.white...)`) zamiast systemowych,
adaptacyjnych odpowiedników — stąd np. siatka miniatur zostawała czarna
nawet w jasnym trybie. Poprawione miejsca: tło okna w `ContentView`
(`Color(nsColor: .windowBackgroundColor)` zamiast `Color.black`), tło i
teksty `BrowseGridView` (to samo `.windowBackgroundColor`, plus
`.foregroundStyle(.primary)`/`.secondary` zamiast wpisanej na sztywno
bieli), oraz obramowania/wypełnienia miniatur (`Color.primary.opacity(…)`
zamiast `Color.white.opacity(…)` — jasny odcień szarości w jasnym trybie,
jasny odcień bieli w ciemnym).

Celowym wyjątkiem jest pływający pasek narzędzi (`FloatingControlBar`) —
zostaje na stałe ciemną, półprzezroczystą belką niezależnie od motywu
systemu, tak samo jak sterowanie odtwarzaczem w QuickTime Playerze czy w
Movi: pasek pływa nad dowolnym zdjęciem o nieprzewidywalnej jasności, więc
stały, ciemny kontrast jest tu bardziej czytelny niż belka, która sama
zmieniałaby jasność.

Ten celowy wyjątek miał jednak swoją własną usterkę: ikony przycisków w
`controlButton` i dwa boczne etykiety (procent zoomu, pozycja w folderze)
nie miały własnego, wpisanego na sztywno koloru — korzystały z domyślnego/
`.secondary`, czyli systemowego, adaptacyjnego. W ciemnym motywie to
wychodziło jako biały na czarnym (przypadkiem czytelne), ale w jasnym
motywie `.secondary`/domyślny kolor robił się ciemny, więc ikony stawały
się praktycznie czarne na czarnym, niewidoczne tle paska. Skoro sam pasek
ma zawsze być ciemny, jego zawartość też musi mieć wpisany na sztywno
biały, a nie systemowy kolor — stąd `Image(systemName:)` w `controlButton`
ma teraz `.foregroundStyle(.white)`, a etykiety zoomu/pozycji
`.foregroundStyle(.white.opacity(0.6))` (nazwa pliku pośrodku paska już
wcześniej miała `.white.opacity(0.85)` i została bez zmian).

**Korekta: tylko siatka „Przeglądaj” podąża za systemem — a tło zdjęcia
zmienia się na czarne dopiero po pierwszym wyświetleniu obrazka, nie od
razu przy otwarciu okna.** Powyższe „wszystko adaptacyjne” okazało się za
szerokie: płótno z pojedynczym zdjęciem (tak w trybie okna jak i
pełnoekranowym) ma być zawsze czarne niezależnie od motywu systemu — tak
samo jak w Preview, Photos czy QuickTime, zdjęcie nigdy nie ma stawać na
tle, które samo zmienia kolor. Adaptacyjny pozostał `BrowseGridView`
(siatka miniatur) — ale też stan „brak pliku” (`emptyState`), pokazywany
od razu po otwarciu okna, zanim jakikolwiek obrazek został wyświetlony:
to wciąż ma wyglądać jak zwykłe okno systemowe, nie czarny ekran.

W `ContentView` tę trzecią możliwość obsługuje `backgroundColor`
(zastępując wcześniejszy prosty warunek `isBrowsing ? clear : black`):
`isBrowsing` → `Color.clear` (przepuszcza własne tło `BrowseGridView`);
inaczej, dopóki `hasShownImage` jest `false` → `Color(nsColor:
.windowBackgroundColor)` (adaptacyjne, jak zwykłe okno); od momentu, gdy
`hasShownImage` zostanie ustawione na `true`, → `Color.black`, i to się
już nie odwraca — nawet jeśli płótno później na chwilę wróci do `nil`
(błąd dekodowania), tło zostaje czarne, zamiast migać z powrotem do
adaptacyjnego. `hasShownImage` to `@State` ustawiane raz, w tym samym
`onReceive(viewModel.$currentImage...)`, które już wywołuje
`fitWindowFullHeight`. Teksty/ikona `emptyState` wróciły z powrotem do
adaptacyjnych `.tertiary`/`.secondary`, bo stoją teraz na adaptacyjnym tle,
nie na czarnym.

### Rozmiar okna w trybie Przeglądaj — pamiętany między uruchomieniami

Tylko siatka „Przeglądaj” ma własną pamięć rozmiaru okna — zwykłe
przeglądanie zdjęć działa dokładnie tak jak opisano wyżej
(`fitWindowFullHeight`, pełna wysokość ekranu przy każdym zdjęciu) i nie
jest tym w żaden sposób dotknięte. W `ContentView`:

- `saveBrowseWindowSize(_:)` zapisuje bieżący rozmiar okna do
  `UserDefaults` (`pico.browseWindowWidth`/`pico.browseWindowHeight`) przy
  każdym `NSWindow.didResizeNotification`, o ile w tym momencie
  `viewModel.isBrowsing` jest `true` i okno nie jest w pełnym ekranie (tam
  rozmiar ramki to po prostu rozmiar ekranu, nie ma sensu go pamiętać).
  Zapis dzieje się na żywo, przy każdym przeciągnięciu, więc to, co jest
  zapisane w chwili zamknięcia aplikacji, jest zawsze aktualne — nie trzeba
  osobnego haka na zamknięcie okna/aplikacji.
- `applyBrowseWindowSize(window:)` odczytuje te dwie wartości i — jeśli są
  zapisane (pierwsze uruchomienie: nie są, więc okno zostaje bez zmian) —
  przestawia okno na ten rozmiar, przycięty do `window.minSize` i do
  widocznego obszaru ekranu, zachowując bieżący środek okna. Wywoływane
  raz, w `onChange(of: viewModel.isBrowsing)` w `body`, tylko gdy tryb
  Przeglądaj właśnie się włącza — wyjście z niego (bez wczytania nowego
  zdjęcia) zostaje bez zmian, tak jak wcześniej.

Efekt: powiększenie okna w trybie Przeglądaj zostaje zapamiętane, kolejne
wejście do Przeglądaj (w tej samej sesji albo po ponownym uruchomieniu
aplikacji) przywraca właśnie ten rozmiar.

### Zakładki (window tabbing) — wyłączone

Natywne zakładki okien macOS są celowo wyłączone, na wyraźne życzenie:
`PicoApp.init()` ustawia `NSWindow.allowsAutomaticWindowTabbing = false`
jeszcze przed utworzeniem pierwszego okna (usuwa przycisk „+” i pozycje
„Pokaż pasek kart”/„Scal wszystkie okna” z menu Okno w całej aplikacji), a
`ContentView` dodatkowo ustawia `window.tabbingMode = .disallowed` na
każdym oknie z osobna, gdy tylko zostanie rozpoznane (`WindowAccessor`) —
podwójne zabezpieczenie, nie tylko globalny przełącznik. ⌘N nadal otwiera
nowe okno (to zwykłe zachowanie `WindowGroup`, niezależne od tabbingu) —
po prostu nigdy nie dołącza się ono do paska kart innego okna.

### Korekta orientacji EXIF

`CGImageSourceCreateImageAtIndex` **nie** stosuje automatycznie tagu
orientacji z EXIF/TIFF — zdjęcie zrobione telefonem trzymanym pionowo
wyszłoby bokiem, zarówno na ekranie, jak i w eksportowanej kopii.
`ImageExporter.loadUprightImage(url:)` czyta ten tag osobno
(`kCGImagePropertyOrientation`) i — jeśli różni się od „normalnej”
orientacji — rysuje obraz na nowo przez odpowiednią `CGAffineTransform` w
świeżym `CGContext`, tak że wynikowy `CGImage` jest już zawsze „prosto”.
Dzięki temu „Zapisz jako…” zawsze zapisuje piksele w poprawnej orientacji,
nawet przy konwersji między formatami o różnych konwencjach zapisu tagu
(np. HEIC z boczną orientacją → JPEG) — bo orientacja jest już przeliczona
na poziomie pikseli, a nie przenoszona jako tag do reinterpretacji.

Jeśli `CGContext` odmówi utworzenia się dla jakiegoś nietypowego formatu
piksela (zdarza się przy plikach CMYK/indeksowanych), kod po cichu wraca do
nieobróconego obrazu zamiast się wywalić — do przetestowania z prawdziwymi
plikami w Xcode; to jedyne miejsce w aplikacji, gdzie dopuszczam ciche
pogorszenie zamiast twardego błędu, bo alternatywą byłby crash na pliku,
który i tak dałoby się obejrzeć (tylko ewentualnie źle obrócony).

### Okno vs. Movi — zoom nigdy nie zmienia rozmiaru okna; każdy obraz używa pełnej wysokości ekranu

To największa różnica względem Movi. Movi blokuje proporcje okna do
proporcji wideo (`NSWindow.contentAspectRatio` + własny
`NSWindowDelegate.windowWillResize`), żeby wideo zawsze wypełniało okno
bez czarnych pasków — to miało sens, bo tam zoom = rozmiar okna.

W Pico **Powiększ/Pomniejsz/Dopasuj do okna nigdy nie zmieniają rozmiaru
okna** — to zastrzeżenie zostaje w mocy bez zmian: okno nie ma blokady
proporcji ani własnego `NSWindowDelegate`, a to `ImageCanvasView`
dopasowuje/powiększa obraz *wewnątrz* dowolnego aktualnego rozmiaru okna.

Osobna sprawa to **zmiana samego obrazu** (Otwórz/Poprzedni/Następny/
kliknięcie miniatury) i **ręczna zmiana rozmiaru okna** przez przeciąganie
jego krawędzi — dwa osobne mechanizmy:

1. **Każdy obraz w trybie okna** — pierwszy w danym oknie, po zmianie
   folderu i każdy kolejny Następny/Poprzedni — korzysta z jednej i tej
   samej reguły, `ContentView.fitWindowFullHeight`: okno zajmuje **całą
   dostępną wysokość ekranu** między paskiem menu a Dockiem
   (`screen.visibleFrame.height`) i jest wyśrodkowane; przelicza się
   tylko **szerokość**, do proporcji aktualnego obrazu przy tej
   wysokości — więc bocznych pasów nie ma, o ile obraz nie jest węższy,
   niż pozwala minimalna szerokość paska narzędzi (patrz punkt 3. niżej).
   Zmiana jest **natychmiastowa, bez animacji** (`animate: false`) —
   okno powinno mieć docelowy rozmiar w tej samej chwili, w której
   pojawia się nowy obraz, a nie dogania go z opóźnieniem.
2. **Ręczna zmiana rozmiaru okna** (przeciąganie krawędzi/narożnika) nie
   jest przez Pico w żaden sposób korygowana — obraz jest wtedy w
   dynamicznym trybie „Dopasuj” (`isZoomFit == true`, patrz niżej), więc
   `ImageCanvasView`'s `GeometryReader` sam, na żywo, przelicza skalę z
   nowego rozmiaru okna; paski są tu normalnym, oczekiwanym skutkiem
   przeciągnięcia okna do proporcji, których obraz nie ma — tak jak w
   Preview.app. Taka ręczna zmiana zostaje w mocy dokładnie do
   następnego obrazu — przejście Następny/Poprzedni (punkt 1.) zawsze z
   powrotem wymusza pełną wysokość ekranu, niezależnie od tego, do
   czego okno było wcześniej przeciągnięte.
3. **Minimalny rozmiar okna** (`window.minSize`) ma teraz tę samą wartość
   na obu osiach — `FloatingControlBar.minWindowWidth` — zamiast, jak
   wcześniej, dużo niższego minimum na wysokości (tyle, co sama stopka
   paska narzędzi). Bez tego dało się przeciągnąć okno do bardzo niskiej,
   szerokiej belki, w której obraz był już tylko małą ikoną — ten sam
   dolny limit na obu osiach to wyklucza. `fitWindowFullHeight` używa
   tego samego minimum jako dolnego ograniczenia szerokości (dla bardzo
   wąskich/pionowych zdjęć przy pełnej wysokości ekranu).

   Ta funkcja **nie** wymusza jawnej skali na modelu widoku (tak jak
   robiła to jedna z wcześniejszych wersji, `applyExplicitScale`) —
   zostaje w dynamicznym trybie „Dopasuj” (ustawionym już wcześniej przez
   `resetZoom()` dla każdego nowo wczytanego obrazu), więc
   `ImageCanvasView` sam przelicza skalę z faktycznego, aktualnego
   rozmiaru okna. To jest też **poprawka błędu**: jedna z wcześniejszych
   wersji ustawiała jawną, zafiksowaną skalę po każdej zmianie obrazu, co
   skutkowało tym, że obraz „zamarzał” na tej skali i nie reagował na
   żadną późniejszą ręczną zmianę rozmiaru okna, aż do następnej zmiany
   zdjęcia. Pozostawienie trybu „Dopasuj” włączonym naprawia to —
   przeglądanie i ręczne przeciąganie okna zawsze współpracują ze sobą,
   niezależnie od kolejności.

W pełnym ekranie mechanizm z punktu 1. się nie uruchamia — treść okna to
wtedy rozmiar ekranu, więc zamiast tego `installFullScreenObservers`
przełącza na wejściu w pełny ekran z powrotem na dynamiczny tryb
„Dopasuj” (`viewModel.zoomToFit()`) — przydatne tylko wtedy, gdy obraz był
akurat w trybie jawnego zoomu (pinch/przyciski) sprzed wejścia w pełny
ekran; podczas zwykłego przeglądania tryb „Dopasuj” jest już włączony,
więc to wywołanie wtedy nic nie zmienia. **Wyjście** z pełnego ekranu z
kolei ponownie uruchamia `fitWindowFullHeight` — ta sama reguła co dla
każdego innego obrazu.

### Zoom: tryb „Dopasuj” kontra jawny procent

`isZoomFit: Bool` + `zoomScale: CGFloat` w `ImageViewerViewModel`. Gdy
`isZoomFit == true`, `ImageCanvasView` codziennie przelicza skalę z
własnego, aktualnego rozmiaru viewportu (przez `GeometryReader`) — więc
zmiana rozmiaru okna automatycznie przelicza dopasowanie. Gdy ktoś jawnie
powiększy/pomniejszy (przyciski, ⌘+/⌘−, pinch, podwójny klik), tryb
przełącza się na jawny procent niezależny od rozmiaru okna — zgodnie z
poleceniem. Osobny mały widok, `FitScaleTracker`, publikuje aktualnie
wyliczoną skalę „dopasowania” z powrotem do modelu widoku wyłącznie po to,
żeby etykieta procentowa w pasku narzędzi (siostrzany widok, nie dziecko
płótna) mogła ją pokazać poprawnie również w trybie „Dopasuj”.

**Animacja skali — tylko tam, gdzie jest dyskretna, celowa zmiana.**
Wcześniej `ImageCanvasView` miał ogólny modyfikator
`.animation(.easeOut(duration: 0.15), value: baseScale)` na obrazie,
animujący *każdą* zmianę wyświetlanej skali — również ciągłe, już-i-tak
liczone na żywo przeliczenie trybu „Dopasuj” w trakcie zmiany rozmiaru
okna. Najbardziej widoczne w trybie pełnoekranowym: systemowa animacja
wejścia/wyjścia z pełnego ekranu sama już zmienia rozmiar okna płynnie
klatka po klatce, a doklejona do tego osobna, niezależnie zsynchronizowana
animacja 0,15 s nakładała się na to i wyglądała na „szarpaną”/dziwną.
Modyfikator został usunięty z `ImageCanvasView` całkowicie; animacja
przeniosła się do konkretnych miejsc w `ImageViewerViewModel`, które same
decydują o zmianie skali — `zoomIn()`, `zoomOut()`, `toggleActualSize()` —
owinięte w `withAnimation(.easeOut(duration: 0.15))`. Zmiany skali, które
już są zsynchronizowane z czymś innym, co sam jest płynne/natychmiastowe,
zostają bez animacji — `zoomToFit()` i tryb „Dopasuj” w ogóle (zarówno
przy ręcznym przeciąganiu okna, jak i przy zmianie obrazu —
`fitWindowFullHeight` celowo zostawia ten tryb włączony, patrz wyżej) —
`ImageCanvasView` przelicza tę skalę sam, co klatka, z aktualnego
rozmiaru okna, więc dodanie tu animacji ponownie rozjechałoby obraz z
oknem — oraz `setZoom(_:)` (pinch — już śledzony na żywo w trakcie
gestu).

Przeciąganie (pan) jest ograniczone (`clampedPan`) tak, by nie dało się
wyrzucić obrazu całkowicie poza okno — oś bez nadmiaru (np. gdy obraz jest
mniejszy od okna w danym wymiarze) jest po prostu zablokowana na zero.

### Sortowanie — własne, nie odwzorowanie Findera

Dokładna kolejność „Uporządkuj według” w danym folderze w Finderze nie
jest dostępna przez żadne publiczne API — jedyny sposób na jej odczytanie
to parsowanie niedokumentowanego, binarnego formatu `.DS_Store`, co jest
zawodne i różni się między wersjami macOS (patrz rozmowa przed
implementacją). Zamiast tego Pico ma własne, w pełni przewidywalne
sortowanie (`ImageSortOption`: pole + kierunek), ustawiane w menu „Sortuj”
w widoku siatki — domyślnie po nazwie, rosnąco. Remisy (np. ten sam rozmiar
pliku) zawsze rozstrzyga nazwa, więc kolejność jest zawsze deterministyczna.

### Poprzedni/Następny po „Otwórz” — skanowanie folderu w tle, bez sandboksa

Pico **nie jest w piaskownicy** — `Pico.entitlements` jest celowo pusty.
Aplikacja nie trafia do Mac App Store, więc App Sandbox nie jest wymagany, a
jego brak usuwa źródło wcześniejszego ograniczenia: w pełnym sandboksie
wybór **pojedynczego pliku** przez `NSOpenPanel` daje dostęp tylko do tego
jednego pliku, nie do jego sąsiadów w folderze, więc Poprzedni/Następny nie
miały jak zadziałać po samym „Otwórz”. Bez sandboksa ten problem znika.

Zamiast tego `ImageViewerViewModel.openSingleFile(url:)` najpierw pokazuje
otwarty obraz od razu, a zaraz potem, w tle (`scanContainingFolder(of:)`,
`Task.detached` poza aktorem głównym), skanuje jego folder macierzysty przez
zwykłe `FileManager.contentsOfDirectory` — żadnego dodatkowego okna ani
pytania o zgodę (poza ewentualnym jednorazowym systemowym pytaniem o dostęp
do chronionej lokalizacji typu Pulpit/Dokumenty/Pobrane, identycznym jak przy
każdej innej, niesandboksowanej aplikacji na Macu). Gdy skan się skończy,
Pico przyjmuje ten folder jako aktywny kontekst przeglądania — stąd
Poprzedni/Następny włączają się same (razem, patrz niżej — nie szarzeją już
osobno przy brzegach listy), bez przełączania w widok siatki i bez osobnego
kroku „Przeglądaj”. Jeśli w międzyczasie zdjęcie
zmieni się ponownie (szybkie kolejne „Otwórz” albo Next/Previous, zanim duży
folder skończy się skanować), wynik nieaktualnego skanu jest po prostu
odrzucany.

Jeśli „Otwórz” wskaże plik, który akurat już należy do aktualnie
przeglądanego folderu (np. ponowne otwarcie przez Finder „Otwórz z…” pliku
z tego samego folderu, albo kliknięcie miniatury), Pico rozpoznaje to po
samej liście `folderImages` i nie skanuje niczego od nowa — Poprzedni/Następny
zostają aktywne od razu.

### Poprzedni/Następny zapętlają się, zamiast gasnąć na krańcach listy

`canGoPrevious`/`canGoNext` w `ImageViewerViewModel` sprawdzają tylko, czy
aktywny folder ma więcej niż jedno zdjęcie (`folderImages.count > 1`) — nie
sprawdzają już, czy bieżący indeks jest akurat pierwszy/ostatni. Obie ikony
są więc zawsze razem aktywne albo razem wyszarzone, nigdy osobno. Samo
przejście liczy nowy indeks modulo liczby zdjęć (`(idx + 1) %
folderImages.count` i analogicznie w tył), więc Następny na ostatnim
zdjęciu przeskakuje na pierwsze, a Poprzedni na pierwszym — na ostatnie,
zamiast się zatrzymywać na krańcach.

### Zapisz jako — opcje tylko tam, gdzie mają sens

`SaveOptionsAccessoryView` to własny widok dodatkowy `NSSavePanel`, napisany
w czystym AppKicie (`NSStackView` + `NSPopUpButton`/`NSSlider` sterowane
target/action) — **nie** jako widok SwiftUI osadzony przez `NSHostingView`.
Pierwsza wersja właśnie tak robiła, ale okazało się, że `Picker` SwiftUI
osadzony w `accessoryView` panelu to zawodne połączenie: nawet z jawnie
ustawioną ramką i `sizingOptions` na `NSHostingView`, rozwijana lista
formatu bywała nieklikalna, dopóki coś innego nie wymusiło ponownego układu
(widać to było jako „lista formatów nagle się pojawia po kliknięciu
Zapisz”). Zwykły `NSPopUpButton` nie przechodzi przez ten mostek w ogóle i
jest klikalny od razu. Wybór formatu na żywo aktualizuje
`panel.allowedContentTypes` i rozszerzenie w nazwie pliku przez zamykanie
`onChange: (() -> Void)?` wywoływane z akcji każdego kontrolu. Suwak jakości
pokazuje się tylko dla JPEG/HEIC (`supportsQuality`), wybór kompresji
LZW/brak — tylko dla TIFF (`supportsCompressionChoice`); PNG/BMP/GIF nie
pokazują nic dodatkowego, bo tam nie ma czego ustawiać —
`NSStackView.isHidden` na odpowiedniej grupie wierszy chowa/pokazuje je bez
zmiany szerokości panelu. Domyślna nazwa pliku to zawsze
`<oryginał>_pico.<rozszerzenie>` (ten sam wzorzec co `_movi` w Movi; jeśli
`<oryginał>` sam już kończy się na `_pico` — bo zapisywany plik był już
wcześniej eksportem z Pico — ten sufiks jest najpierw zdejmowany, żeby nie
dostać `_pico_pico`) — nigdy nie nadpisuje cicho oryginału.

Formaty zapisu są świadomie węższe niż formaty odczytu: ImageIO potrafi
**czytać** WebP i ICO, ale nie ma dla nich enkodera, więc te dwa formaty są
tylko do podglądu — nigdy nie pojawią się jako cel „Zapisz jako…”.

### Ikona aplikacji

Dostarczona przez autora (plik `icon-source/pico-icon-1024.png`) — szklista,
biała kula z tęczowym, akwarelowym „okiem” pośrodku, osadzona na białej,
zaokrąglonej karcie z delikatnym cieniem pod spodem, kadrowana krawędź do
krawędzi (karta wypełnia cały kwadrat, bez marginesu dookoła). Używana
**w całości, jako pełny kwadrat 1024×1024** (bez wycinania samej kuli ani
własnej przezroczystości) — macOS nakłada swoją maskę „squircle” sam przy
wyświetlaniu, zgodnie z wytycznymi Apple, więc biel karty i tak pozostaje
niewidoczna na większości miejsc, w których ikona się pojawia. Przeskalowana
(Lanczos) do wszystkich 10 rozmiarów wymaganych przez `AppIcon.appiconset`.

### Pasek narzędzi — jedna wspólna siatka odstępów

Wszystkie ikony `FloatingControlBar` (Otwórz, Przeglądaj, Poprzedni,
Pomniejsz, Dopasuj do okna, Powiększ, Następny, Pełny ekran, Zapisz jako)
siedzą w jednym `HStack` z jednym, jednakowym odstępem między każdą parą —
żadnego mieszania pozycji o sztywnej szerokości z elastycznymi `Spacer`ami,
co wcześniej dawało nierówne odstępy (duża przerwa przed grupą, wąskie
przerwy wewnątrz niej). Szerokość samego paska (`barWidth`) jest liczona
wprost z liczby ikon, ich rozmiaru i odstępu, więc nie może już „rozjechać
się” z rzeczywistą zawartością. Ikony „Dopasuj do okna” zmieniły symbol na
`viewfinder`, żeby zwolnić parę `arrow.up.left.and.arrow.down.right` /
`arrow.down.right.and.arrow.up.left` dla nowego przycisku pełnego ekranu.

## Znane ograniczenia

- Animowane GIF-y pokazują tylko pierwszą klatkę — bez odtwarzania animacji.
- Podgląd miniatur w siatce nie odświeża się automatycznie, jeśli zawartość
  folderu zmieni się na dysku, gdy okno jest już otwarte (trzeba kliknąć
  „Przeglądaj”/„Zmień folder…” ponownie).
- Formaty zapisu ograniczone są do tych, dla których ImageIO ma enkoder
  (JPEG/PNG/TIFF/HEIC/BMP/GIF) — WebP i ICO są tylko do odczytu.
- „Otwórz z…” w Finderze czasem wymaga odświeżenia LaunchServices po pierwszym
  zbudowaniu aplikacji (np. ponowne uruchomienie Findera albo wylogowanie/
  zalogowanie) — patrz komentarz przy `CFBundleDocumentTypes` w `Info.plist`.

## Licencja

Kod wolny do użycia i modyfikacji w dowolny sposób — bez dodatkowych
ograniczeń.
