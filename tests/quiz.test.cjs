const test = require("node:test");
const assert = require("node:assert/strict");
require("../county-boundaries.js");
const { counties } = require("../counties.js");
const { buildCountyMap } = require("../counties.js");
const {
  normalizeAnswer,
  createGame,
  submitAnswer,
  submitCountySelection,
  isMastered,
  mistakesFor
} = require("../quiz.js");

test("the map and quiz include only the 19 counties", () => {
  assert.equal(counties.length, 19);
  assert.equal(new Set(counties.map((county) => county.id)).size, 19);
  assert.ok(counties.every((county) => county.id !== "budapest"));
});

test("the map renders a separate vector boundary for each county", () => {
  const map = buildCountyMap();

  assert.equal(map.length, 19);
  assert.equal(map.length, counties.length);
  assert.ok(map.every((county) => county.id !== "budapest"));
  const countyPolygons = map;
  assert.ok(countyPolygons.every((county) => county.points.split(" ").length > 20));
  for (const county of countyPolygons) {
    const coordinates = county.points.split(" ").map((point) => point.split(",").map(Number));
    assert.ok(coordinates.every(([x, y]) => x >= 0 && x <= 760 && y >= 0 && y <= 460));
  }
});

test("each county has its correct county seat", () => {
  const expectedSeats = {
    "bacs-kiskun": ["Kecskemét", 397.0, 267.8],
    baranya: ["Pécs", 259.7, 382.1],
    bekes: ["Békéscsaba", 528.8, 298.7],
    "borsod-abauj-zemplen": ["Miskolc", 499.6, 100.4],
    "csongrad-csanad": ["Szeged", 439.6, 357.1],
    fejer: ["Székesfehérvár", 277.6, 227.6],
    "gyor-moson-sopron": ["Győr", 204.8, 158.1],
    "hajdu-bihar": ["Debrecen", 579.7, 179.7],
    heves: ["Eger", 461.8, 128.3],
    "jasz-nagykun-szolnok": ["Szolnok", 443.5, 231.0],
    "komarom-esztergom": ["Tatabánya", 275.9, 174.5],
    nograd: ["Salgótarján", 407.3, 101.8],
    pest: ["Budapest", 335.8, 184.4],
    somogy: ["Kaposvár", 218.6, 342.3],
    "szabolcs-szatmar-bereg": ["Nyíregyháza", 588.1, 120.9],
    tolna: ["Szekszárd", 304.3, 344.0],
    vas: ["Szombathely", 107.9, 221.4],
    veszprem: ["Veszprém", 229.2, 239.2],
    zala: ["Zalaegerszeg", 128.6, 275.4]
  };

  assert.equal(counties.filter((county) => county.seat).length, 19);
  for (const [countyId, [seat, x, y]] of Object.entries(expectedSeats)) {
    const county = counties.find((item) => item.id === countyId);
    assert.equal(county?.seat, seat);
    assert.equal(county?.seatX, x);
    assert.equal(county?.seatY, y);
  }

  const map = buildCountyMap();
  for (const county of map) {
    const points = county.points.split(" ").map((point) => point.split(",").map(Number));
    let inside = false;
    for (let index = 0, previous = points.length - 1; index < points.length; previous = index, index += 1) {
      const [x, y] = points[index];
      const [previousX, previousY] = points[previous];
      const crossesRay = (y > county.seatY) !== (previousY > county.seatY)
        && county.seatX < ((previousX - x) * (county.seatY - y)) / (previousY - y) + x;
      if (crossesRay) inside = !inside;
    }
    assert.equal(inside, true, `${county.seat} should be inside ${county.name}`);
  }
});

test("answer matching ignores accents, hyphens, and county suffixes", () => {
  assert.equal(normalizeAnswer("GYOR-MOSON-SOPRON megye"), "gyor moson sopron");
  assert.equal(normalizeAnswer("Csongrád–Csanád vármegye"), "csongrad csanad");
});

test("a correct answer earns one point and marks only that county as learned", () => {
  const oneCounty = [counties.find((county) => county.id === "pest")];
  const game = createGame(oneCounty, () => 0);

  const result = submitAnswer(game, "Pest megye");

  assert.equal(result.correct, true);
  assert.equal(result.completed, true);
  assert.equal(game.score, 1);
  assert.equal(game.mastered.size, 1);
  assert.equal(isMastered(game, "pest"), true);
});

test("the county seat quiz accepts the seat name and tracks its progress separately", () => {
  const pest = counties.find((county) => county.id === "pest");
  const game = createGame([pest], () => 0, "seat");

  const result = submitAnswer(game, "Budapest");

  assert.equal(result.correct, true);
  assert.equal(result.completed, true);
  assert.equal(result.answerName, "Budapest");
  assert.equal(game.answerType, "seat");
  assert.equal(game.score, 1);
  assert.equal(isMastered(game, "pest"), true);
});

test("a missed county seat is revealed and can be retried", () => {
  const pest = counties.find((county) => county.id === "pest");
  const game = createGame([pest], () => 0, "seat");

  const missed = submitAnswer(game, "Szeged");

  assert.equal(missed.correct, false);
  assert.equal(missed.answerName, "Budapest");
  assert.equal(missed.completed, false);
  assert.equal(game.wrongAnswers, 1);
  assert.equal(mistakesFor(game, "pest"), 1);
  assert.equal(submitAnswer(game, "Budapest").correct, true);
});

test("the seat map quiz accepts the county matching the given seat", () => {
  const countiesInGame = counties.filter((county) => ["pest", "fejer"].includes(county.id));
  const game = createGame(countiesInGame, () => 0, "seat");
  const targetId = game.activeId;
  const target = countiesInGame.find((county) => county.id === targetId);

  const result = submitCountySelection(game, targetId);

  assert.equal(result.correct, true);
  assert.equal(result.answerName, target.name);
  assert.equal(game.score, 1);
  assert.equal(isMastered(game, targetId), true);
});

test("an incorrect seat map selection is counted and the correct county can be retried", () => {
  const countiesInGame = counties.filter((county) => ["pest", "fejer"].includes(county.id));
  const game = createGame(countiesInGame, () => 0, "seat");
  const targetId = game.activeId;
  const wrongId = countiesInGame.find((county) => county.id !== targetId).id;

  const missed = submitCountySelection(game, wrongId);

  assert.equal(missed.correct, false);
  assert.equal(missed.answerName, countiesInGame.find((county) => county.id === targetId).name);
  assert.equal(missed.completed, false);
  assert.equal(game.wrongAnswers, 1);
  assert.equal(mistakesFor(game, targetId), 1);
  assert.equal(submitCountySelection(game, game.activeId).correct, true);
  const retried = submitCountySelection(game, game.activeId);
  assert.equal(retried.correct, true);
  assert.equal(retried.completed, true);
  assert.equal(isMastered(game, targetId), true);
  assert.equal(mistakesFor(game, targetId), 1);
});

test("a wrong answer queues the county for a separate learning round", () => {
  const twoCounties = counties.filter((county) => ["pest", "fejer"].includes(county.id));
  const game = createGame(twoCounties, () => 0);
  const missedId = game.activeId;
  const missedName = twoCounties.find((county) => county.id === missedId).name;

  const result = submitAnswer(game, "rossz válasz");

  assert.equal(result.correct, false);
  assert.equal(result.answerName, missedName);
  assert.equal(result.completed, false);
  assert.notEqual(game.activeId, missedId);
  assert.deepEqual(game.queue, []);
  assert.deepEqual(game.reviewQueue, [missedId]);
  assert.equal(game.phase, "quiz");
  assert.equal(game.score, 0);
  assert.equal(isMastered(game, missedId), false);
  assert.equal(game.wrongAnswers, 1);
  assert.equal(mistakesFor(game, missedId), 1);
  assert.equal(mistakesFor(game, game.activeId), 0);
});

test("wrong answers are counted per game and per county across repetitions", () => {
  const twoCounties = counties.filter((county) => ["pest", "fejer"].includes(county.id));
  const game = createGame(twoCounties, () => 0);
  const missedId = game.activeId;
  const missedCounty = twoCounties.find((county) => county.id === missedId);

  submitAnswer(game, "rossz válasz");
  const otherCounty = twoCounties.find((county) => county.id === game.activeId);
  assert.equal(submitAnswer(game, otherCounty.name).correct, true);
  assert.equal(game.activeId, missedId);
  assert.equal(game.phase, "review");
  assert.equal(mistakesFor(game, missedId), 1);
  assert.equal(submitAnswer(game, missedCounty.name).correct, true);
  assert.equal(game.wrongAnswers, 1);
  assert.equal(mistakesFor(game, missedId), 1);

  const nextGame = createGame(twoCounties, () => 0);
  assert.equal(nextGame.wrongAnswers, 0);
  assert.equal(mistakesFor(nextGame, missedId), 0);
});

test("the game completes after the only county is mastered", () => {
  const oneCounty = [counties.find((county) => county.id === "pest")];
  const game = createGame(oneCounty, () => 0);

  assert.equal(submitAnswer(game, "Pest").completed, true);
  assert.equal(game.activeId, null);
  assert.equal(game.score, 1);
});

test("a missed county returns after the other counties and can complete the game", () => {
  const game = createGame(counties, () => 0);
  const missedId = game.activeId;
  const missedCounty = counties.find((county) => county.id === missedId);

  assert.equal(submitAnswer(game, "rossz válasz").correct, false);
  while (game.activeId !== missedId) {
    const activeCounty = counties.find((county) => county.id === game.activeId);
    assert.equal(submitAnswer(game, activeCounty.name).correct, true);
  }

  const finalAnswer = submitAnswer(game, missedCounty.name);
  assert.equal(finalAnswer.correct, true);
  assert.equal(finalAnswer.completed, true);
  assert.equal(game.score, 19);
  assert.equal(game.attempts, 20);
  assert.equal(game.phase, "review");
});

test("the learning round repeats only missed counties until they are answered correctly", () => {
  const game = createGame(counties.slice(0, 3), () => 0);
  const missedId = game.activeId;

  submitAnswer(game, "rossz válasz");
  while (game.phase === "quiz") {
    const activeCounty = game.counties.find((county) => county.id === game.activeId);
    submitAnswer(game, activeCounty.name);
  }

  assert.equal(game.phase, "review");
  assert.equal(game.activeId, missedId);
  assert.deepEqual(game.queue, []);
  assert.equal(submitAnswer(game, "még mindig rossz").correct, false);
  assert.equal(game.activeId, missedId);
  assert.deepEqual(game.queue, []);
  assert.equal(submitAnswer(game, game.counties.find((county) => county.id === missedId).name).correct, true);
  assert.equal(game.activeId, null);
  assert.equal(game.wrongAnswers, 2);
  assert.equal(mistakesFor(game, missedId), 2);
});
