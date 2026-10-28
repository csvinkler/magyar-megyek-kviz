(function (root) {
  const COUNTY_NAMES = [
    ["vas", "Vas", "Szombathely", 107.9, 221.4],
    ["gyor-moson-sopron", "Győr-Moson-Sopron", "Győr", 204.8, 158.1],
    ["zala", "Zala", "Zalaegerszeg", 128.6, 275.4],
    ["veszprem", "Veszprém", "Veszprém", 229.2, 239.2],
    ["komarom-esztergom", "Komárom-Esztergom", "Tatabánya", 275.9, 174.5],
    ["fejer", "Fejér", "Székesfehérvár", 277.6, 227.6],
    ["somogy", "Somogy", "Kaposvár", 218.6, 342.3],
    ["tolna", "Tolna", "Szekszárd", 304.3, 344.0],
    ["baranya", "Baranya", "Pécs", 259.7, 382.1],
    ["pest", "Pest", "Budapest", 335.8, 184.4],
    ["nograd", "Nógrád", "Salgótarján", 407.3, 101.8],
    ["heves", "Heves", "Eger", 461.8, 128.3],
    ["borsod-abauj-zemplen", "Borsod-Abaúj-Zemplén", "Miskolc", 499.6, 100.4],
    ["szabolcs-szatmar-bereg", "Szabolcs-Szatmár-Bereg", "Nyíregyháza", 588.1, 120.9],
    ["hajdu-bihar", "Hajdú-Bihar", "Debrecen", 579.7, 179.7],
    ["jasz-nagykun-szolnok", "Jász-Nagykun-Szolnok", "Szolnok", 443.5, 231.0],
    ["bekes", "Békés", "Békéscsaba", 528.8, 298.7],
    ["csongrad-csanad", "Csongrád-Csanád", "Szeged", 439.6, 357.1],
    ["bacs-kiskun", "Bács-Kiskun", "Kecskemét", 397.0, 267.8]
  ];

  function buildCountyMap() {
    const counties = COUNTY_NAMES.map(([id, name, seat, seatX, seatY]) => ({
      id,
      name,
      seat,
      seatX,
      seatY,
      points: root.CountyBoundaries[id]
    }));
    const missingBoundary = counties.find((county) => !county.points);
    if (missingBoundary) throw new Error(`Missing map boundary for ${missingBoundary.name}.`);

    return counties;
  }

  const data = {
    counties: COUNTY_NAMES.map(([id, name, seat, seatX, seatY]) => ({
      id,
      name,
      seat,
      seatX,
      seatY
    })),
    buildCountyMap
  };

  root.CountyMapData = data;
  if (typeof module !== "undefined" && module.exports) module.exports = data;
})(globalThis);
