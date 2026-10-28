# Megyejárőr — 3D vármegyejáték

Önálló Godot 4-es, felülnézetes 3D játék. A magyar vármegyehatárok a meglévő, egyszerűsített geoBoundaries CC0 térképadatból készülnek. A katona 3D modellje és járóanimációja a Godot-ban, futásidőben épül fel, ezért külön Blender- vagy modelltelepítés nem kell.

## Indítás

Godot 4.7 vagy újabb verzióval nyisd meg ezt a mappát, vagy indítsd terminálból:

```powershell
godot --path godot-game
```

## Irányítás és játékmenet

- Mozgás: nyílbillentyűk vagy WASD.
- A képernyőn megjelenik a célvármegye neve; vezesd oda a katonát. A térkép nem jelöli ki előre a célterületet, és a katona alatt álló megye neve rejtve marad.
- A vármegyébe érkezés után nyomj Entert. Ekkor kezdődik a ráközelítő, animált csata, amelyben véletlenszerű árnylovag, vadkan vagy sárkány ellen küzd a katona.
- A csatajelenetek többféle győzelmi és vereségi mozdulatot használnak. A vereség rajzfilmszerű, nem véres sérülést mutat; mindhárom élet elvesztésekor véget ér a menet.
- Minden menet három élettel indul. Három hibás, Enterrel megerősített megyeválasztás után a JÁTÉK VÉGE képernyőn az „Új játékmenet” gombbal lehet újrakezdeni.
- A sikeres csata után a megye zöldre vált; az elhibázott célvármegyék összesítője a menet végén jelenik meg.
- A térkép zöldre váltja a helyesen megtanult területeket; a menet végén a hibás vármegyéket és székhelyeiket összesítő mutatja.

## Térképadat frissítése

A mellékelt `data/counties.json` a projekt része, futtatáskor nem kell Node.js. Ha a gyökérben lévő vármegyehatárok változnak, a JSON újragenerálható:

```powershell
node godot-game/scripts/build_county_data.cjs
```

## Ellenőrzés

```powershell
godot --headless --path godot-game --editor --quit
godot --headless --path godot-game --scene res://tests/smoke_test.tscn --quit-after 600
```
