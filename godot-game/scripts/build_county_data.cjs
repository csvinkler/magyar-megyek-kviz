const fs = require("node:fs");
const path = require("node:path");

require("../../county-boundaries.js");
const { counties, buildCountyMap } = require("../../counties.js");

const map = buildCountyMap();
const output = {
  source: "geoBoundaries Hungary ADM1 simplified boundaries (CC0), via county-boundaries.js",
  counties: counties.map((county) => {
    const boundary = map.find((item) => item.id === county.id);
    return {
      id: county.id,
      name: county.name,
      seat: county.seat,
      seat_x: county.seatX,
      seat_y: county.seatY,
      points: boundary.points.split(/\s+/).map((pair) => pair.split(",").map(Number))
    };
  })
};

const outputPath = path.join(__dirname, "..", "data", "counties.json");
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, "utf8");
console.log(`Wrote ${output.counties.length} county polygons to ${outputPath}`);
