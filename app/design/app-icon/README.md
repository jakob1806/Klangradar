# App-Icon „Klang-K“

Das Icon für **Klangradar** verwendet ein reduziertes geometrisches
K auf einem exakten Gestaltungsraster. Die beiden gleich gewichteten Flächen
treffen sich in einem klaren gemeinsamen Knotenpunkt und erinnern zugleich an
eine sich öffnende Bühne. Der weiße Hintergrund sowie Schwarz, Ultramarin und
Mint sorgen für eine helle, klare Wirkung. Die Gestaltung ist flach, klar und
frei von Texturen, Glanz, Schatten und generierter Materialästhetik.

Alle drei Striche verwenden dieselbe Stärke von 148 Einheiten und denselben
Rundungsradius von 74 Einheiten. Dadurch folgen Stamm und Arme einer
einheitlichen Formensprache.

## Dateien

- `klassik-muenchen-app-icon.svg`: editierbarer Vektormaster
- `klassik-muenchen-app-icon-master-1024.png`: produktiver PNG-Master ohne Alpha
- `../../tool/regenerate_app_icons.sh`: erzeugt die Plattformgrößen neu

## Regenerieren

```sh
./tool/regenerate_app_icons.sh
```

Der Master ist vollflächig und besitzt keine vorgerundeten Ecken. Die
jeweilige Plattform wendet ihre Icon-Maske selbst an.

## Gestaltungsprinzip

Die großen Flächen, die reduzierte Formenzahl und der Sicherheitsabstand
bleiben auch in 29 px klar. Verwendet werden ausschließlich `#FFFFFF`,
`#111111`, `#6F7EFA` und `#4FCDBA`.
