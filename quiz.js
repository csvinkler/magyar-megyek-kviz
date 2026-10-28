(function (root) {
  const COUNTIES = root.CountyMapData.counties;

  function normalizeAnswer(value) {
    return String(value)
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLocaleLowerCase("hu-HU")
      .replace(/[-–—]/g, " ")
      .replace(/[^\p{L}\p{N}\s]/gu, " ")
      .replace(/\s+(varmegye|megye|fovaros)\s*$/u, "")
      .trim()
      .replace(/\s+/g, " ");
  }

  function shuffle(items, random = Math.random) {
    const result = items.slice();
    for (let index = result.length - 1; index > 0; index -= 1) {
      const otherIndex = Math.floor(random() * (index + 1));
      [result[index], result[otherIndex]] = [result[otherIndex], result[index]];
    }
    return result;
  }

  function createGame(counties = COUNTIES, random = Math.random, answerType = "name") {
    if (!["name", "seat"].includes(answerType)) {
      throw new Error(`Unsupported answer type: ${answerType}`);
    }
    const queue = shuffle(counties.map((county) => county.id), random);
    return {
      counties,
      answerType,
      queue,
      phase: "quiz",
      reviewQueue: [],
      reviewIds: new Set(),
      activeId: queue.shift() || null,
      mastered: new Set(),
      score: 0,
      attempts: 0,
      wrongAnswers: 0,
      mistakesByCounty: new Map()
    };
  }

  function recordAnswer(game, county, isCorrect, answerName) {
    game.attempts += 1;

    if (isCorrect) {
      game.mastered.add(county.id);
      game.score += 1;
    } else {
      game.wrongAnswers += 1;
      game.mistakesByCounty.set(
        county.id,
        (game.mistakesByCounty.get(county.id) || 0) + 1
      );
      if (game.phase === "quiz") {
        if (!game.reviewIds.has(county.id)) {
          game.reviewIds.add(county.id);
          game.reviewQueue.push(county.id);
        }
      } else {
        game.queue.push(county.id);
      }
    }

    game.activeId = game.queue.shift() || null;
    if (!game.activeId && game.phase === "quiz" && game.reviewQueue.length > 0) {
      game.phase = "review";
      game.queue = game.reviewQueue;
      game.reviewQueue = [];
      game.activeId = game.queue.shift() || null;
    }
    return {
      correct: isCorrect,
      completed: game.activeId === null,
      answerName
    };
  }

  function submitAnswer(game, answer) {
    if (!game.activeId) return { correct: false, completed: true, answerName: null };

    const county = game.counties.find((item) => item.id === game.activeId);
    const acceptedAnswers = [county[game.answerType]];
    if (game.answerType === "name") acceptedAnswers.push(county.alias);
    const isCorrect = acceptedAnswers
      .filter(Boolean)
      .some((accepted) => normalizeAnswer(answer) === normalizeAnswer(accepted));
    return recordAnswer(game, county, isCorrect, county[game.answerType]);
  }

  function submitCountySelection(game, selectedCountyId) {
    if (!game.activeId) return { correct: false, completed: true, answerName: null };

    const county = game.counties.find((item) => item.id === game.activeId);
    return recordAnswer(game, county, selectedCountyId === county.id, county.name);
  }

  function isMastered(game, countyId) {
    return game.mastered.has(countyId);
  }

  function mistakesFor(game, countyId) {
    return game.mistakesByCounty.get(countyId) || 0;
  }

  root.CountyQuiz = {
    normalizeAnswer,
    createGame,
    submitAnswer,
    submitCountySelection,
    isMastered,
    mistakesFor
  };
  if (typeof module !== "undefined" && module.exports) module.exports = root.CountyQuiz;
})(globalThis);
