# Megyéről megyére

Függőségmentes, egyjátékos vaktérképes kvíz Magyarország 19 vármegyéjével.

## 3D Godot-játék

A különálló felülnézetes 3D járőrjáték a `godot-game` mappában található. Godot 4.7 vagy újabb verzióval indítható:

```powershell
godot --path godot-game
```

Részletes leírás és irányítás: [`godot-game/README.md`](godot-game/README.md).

## 3D Unity-voxel játék

A Unity-újraírás a `unity-game` mappában készül. A 19 vármegye kockás, voxel stílusú térképként jelenik meg; a billentyűzetes megyejárás, Enteres választás, csaták, három élet és tanulókör a Unity-változatban is megmarad. A játék jelenete Unity Editorral nyitható meg a `unity-game` projektből.

Részletek: [`unity-game/README.md`](unity-game/README.md).

Az SVG vármegyehatárok a [geoBoundaries](https://www.geoboundaries.org/) CC0 licencű, egyszerűsített magyarországi ADM1-adatából készültek.

## Indítás

Nyisd meg az `index.html` fájlt egy modern böngészőben. A betűtípus internetkapcsolat mellett töltődik be; nélküle a rendszer alapértelmezett betűtípusát használja.

## Játékszabályok

- Négy kvíz közül választhatsz: a térképen körvonalazott megye nevét kell beírni, a megadott megyét kell kijelölni a térképen, a megye székhelyét kell megadni, vagy a megadott székhely megyéjére kell kattintani a térképen.
- A székhelykvíz két változata közös, külön pontszámot és előrehaladást használ, így a beírásos és térképes gyakorlás kiegészíti egymást.
- Térképes válasz után a megye székhelyének neve röviden megjelenik a térképen a jelölőjénél.
- Tanuló módban mind a 19 vármegye neve és székhelye megtekinthető; a térképen a vármegyehatárok és a székhelyek ponttal, illetve felirattal is látszanak. A térképfeliratok automatikusan szabad helyre rendeződnek, hogy ne fedjék egymást.
- A már megtanult vármegyék neve a kvíz térképén is megjelenik.
- Helyes válaszért egy pont jár, a megye zöld marad.
- Hibás válasznál a helyes terület vagy név röviden megjelenik, a terület nem zöldül ki, és később újra kérdés lesz.
- Az alapkör után automatikusan külön tanulókör indul, amely kizárólag az alapkörben elhibázott megyéket vagy székhelyeket kérdezi újra; a tanulókörben elhibázott kérdés ismét előkerül, amíg helyes nem lesz.
- A hibás válaszokat a teljes játékmenetben és megyénként is számoljuk; a megye ismételt kérdezésekor megmarad a hibaszám. A befejezés után új menet indítható.
- A menet végén összesítő sorolja fel a hibásan megválaszolt megyéket és székhelyeket; a hibás válasszal érintett megyéket a térképen színes keret jelöli.
- A helyes és hibás válaszok rövid, semleges visszajelzést kapnak.
- A játék akkor ér véget, amikor mind a 19 vármegye zöld.
- Az ékezetek, a kötőjelek és a „megye” / „vármegye” utótag nem befolyásolják a válasz elfogadását.

## Tesztek

```sh
npm test
```
