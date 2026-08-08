# Klangradar – UI-Redesign-Mockups

Sechs stilistische Varianten desselben Homescreens. Navigation, Inhalte und
Informationshierarchie sind bewusst vergleichbar gehalten.

## Varianten

1. `01-glassmorphism.png` – atmosphärisch, dunkel, starke Bildwirkung; benötigt
   sehr saubere Kontrast- und Blur-Regeln.
2. `02-flat-design.png` – direkt, schnell erfassbar und technisch robust; die
   eigenständigste pragmatische Basis.
3. `03-apple-liquid-glass.png` – aktuelle iOS-Anmutung mit selektivem,
   physikalisch nachvollziehbarem Glas; höherer Implementierungsaufwand.
4. `04-swiss-international.png` – streng, typografisch und unverwechselbar;
   besonders geeignet für eine starke Markenidentität.
5. `05-editorial-design.png` – kultiviert, bildstark und inhaltlich passend für
   Klassik; Serifenschrift nur für Überschriften, Metadaten bleiben nüchtern.
6. `06-native-apple-ios.png` – vertraut, zugänglich und am sichersten nutzbar;
   geringstes visuelles Risiko, aber weniger eigenständig.

## Empfehlung

Als Zielrichtung bietet sich ein Hybrid aus **Editorial**, **Swiss** und
**Native iOS** an:

- Editorial für Bildsprache und große Veranstaltungsüberschriften
- Swiss für Raster, Typohierarchie und klare Informationsdichte
- Native iOS für Navigation, Interaktion, Barrierefreiheit und Zustände

Liquid Glass sollte dabei nur in Navigation und wenigen Controls erscheinen.
So wirkt Klangradar modern und eigenständig, ohne wie ein kurzfristiger
Designeffekt oder ein generisches KI-Interface auszusehen.

## Gemeinsame Vorgaben der Mockups

- iPhone-Homescreen im Hochformat, ohne Geräte-Rahmen
- Inhalte: Klangradar, Featured Event, „Heute in München“, zwei Eventkarten
- Tabs: Home, Suche, Karte, Kalender, Profil
- keine rot-goldene Farbwelt
- echte, redaktionelle Konzertfotografie als zentraler Bestandteil
- gut lesbare deutsche Texte, 44-Punkt-Touch-Ziele und umsetzbare Abstände

Die Bilder wurden mit dem integrierten Imagegen-Werkzeug als visuelle
Entwurfsvarianten erstellt. Sie sind Richtungsentscheidungen, keine pixelgenauen
Implementierungsvorlagen; finale Komponenten sollten anschließend direkt in
Flutter mit echten Design-Tokens aufgebaut werden.
