(function () {
  const { counties, buildCountyMap } = window.CountyMapData;
  const { createGame, submitAnswer, submitCountySelection, isMastered, mistakesFor } = window.CountyQuiz;
  let countyGame = createGame();
  let seatGame = createGame(counties, Math.random, "seat");
  let game = countyGame;
  let sessionNumber = 1;
  const mapRegions = document.getElementById("county-regions");
  const countySeats = document.getElementById("county-seats");
  const answerForm = document.getElementById("answer-form");
  const answerInput = document.getElementById("answer-input");
  const submitButton = answerForm.querySelector("button");
  const feedback = document.getElementById("feedback");
  const modeButtons = document.querySelectorAll(".mode-option");
  const newGameButton = document.getElementById("new-game-button");
  const quizPanel = document.getElementById("quiz-panel");
  const learningPanel = document.getElementById("learning-panel");
  const quizViewButton = document.getElementById("quiz-view-mode");
  const learnViewButton = document.getElementById("learn-view-mode");
  const countyList = document.getElementById("county-list");
  const completionReview = document.getElementById("completion-review");
  const pageShell = document.querySelector(".page-shell");
  let mainView = "quiz";
  let mode = "type";
  let revealingAnswer = false;
  let revealedId = null;
  let revealedName = null;
  let revealedSeatId = null;
  let feedbackTimeoutId = null;
  let questionTitle = "Melyik megye?";
  let questionHint = "Írd be a körvonallal jelölt megye nevét.";

  function renderMap() {
    mapRegions.replaceChildren();
    for (const county of buildCountyMap()) {
      const region = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
      region.setAttribute("class", "county-region");
      region.setAttribute("points", county.points);
      region.dataset.countyId = county.id;
      region.setAttribute("role", "button");
      region.setAttribute("aria-label", "Terület kiválasztása");
      region.setAttribute("tabindex", "0");
      mapRegions.append(region);
    }

    for (const county of buildCountyMap()) {
      const points = county.points.split(" ").map((pair) => pair.split(",").map(Number));
      const centroid = polygonCentroid(points);
      const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
      label.setAttribute("class", "county-label");
      label.setAttribute("x", centroid.x.toFixed(1));
      label.setAttribute("y", centroid.y.toFixed(1));
      label.setAttribute("text-anchor", "middle");
      label.setAttribute("aria-hidden", "true");
      label.dataset.countyId = county.id;
      county.name.split("-").forEach((word, index, words) => {
        const line = document.createElementNS("http://www.w3.org/2000/svg", "tspan");
        line.setAttribute("x", centroid.x.toFixed(1));
        line.setAttribute("dy", index === 0 ? `${-((words.length - 1) * 5)}px` : "10px");
        line.textContent = `${word}${index < words.length - 1 ? "-" : ""}`;
        label.append(line);
      });
      mapRegions.append(label);

      const marker = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      marker.setAttribute("class", "seat-marker");
      marker.setAttribute("cx", county.seatX);
      marker.setAttribute("cy", county.seatY);
      marker.setAttribute("r", "4");
      marker.dataset.countyId = county.id;
      countySeats.append(marker);

      const seatLabel = document.createElementNS("http://www.w3.org/2000/svg", "text");
      seatLabel.setAttribute("class", "seat-label");
      seatLabel.setAttribute("x", county.seatX + 6);
      seatLabel.setAttribute("y", county.seatY + 3);
      seatLabel.setAttribute("text-anchor", "start");
      seatLabel.dataset.countyId = county.id;
      seatLabel.textContent = county.seat;
      countySeats.append(seatLabel);
    }
    layoutLearningLabels();

    countyList.replaceChildren();
    for (const county of counties.slice().sort((a, b) => a.name.localeCompare(b.name, "hu"))) {
      const row = document.createElement("tr");
      const nameCell = document.createElement("th");
      const seatCell = document.createElement("td");
      nameCell.scope = "row";
      nameCell.textContent = county.name;
      seatCell.textContent = county.seat;
      row.append(nameCell, seatCell);
      countyList.append(row);
    }
  }

  function layoutLearningLabels() {
    const preferredPositions = new Map([
      ["county:veszprem", { x: 0, y: -24 }],
      ["seat:veszprem", { x: 0, y: 0 }],
      ["county:fejer", { x: 18, y: 0 }],
      ["seat:gyor-moson-sopron", { x: 0, y: 0 }]
    ]);
    const labels = [
      ...mapRegions.querySelectorAll(".county-label"),
      ...countySeats.querySelectorAll(".seat-label")
    ].map((element) => {
      const bounds = element.getBBox();
      const type = element.classList.contains("seat-label") ? "seat" : "county";
      const preferredOffset = preferredPositions.get(`${type}:${element.dataset.countyId}`);
      return {
        element,
        bounds,
        width: bounds.width,
        height: bounds.height,
        preferredOffset
      };
    }).sort((a, b) => Number(Boolean(b.preferredOffset)) - Number(Boolean(a.preferredOffset))
      || b.width - a.width);
    const placed = [];
    const offsets = [{ x: 0, y: 0 }];
    for (let distance = 12; distance <= 120; distance += 12) {
      offsets.push(
        { x: 0, y: -distance },
        { x: distance, y: 0 },
        { x: 0, y: distance },
        { x: -distance, y: 0 },
        { x: distance, y: -distance },
        { x: distance, y: distance },
        { x: -distance, y: distance },
        { x: -distance, y: -distance }
      );
    }

    for (const label of labels) {
      const originX = label.bounds.x;
      const originY = label.bounds.y;
      const candidates = label.preferredOffset
        ? [label.preferredOffset, ...offsets.filter((candidate) =>
          candidate.x !== label.preferredOffset.x || candidate.y !== label.preferredOffset.y
        )]
        : offsets;
      const offset = candidates.find((candidate) => {
        const box = {
          left: originX + candidate.x - 3,
          top: originY + candidate.y - 3,
          right: originX + candidate.x + label.width + 3,
          bottom: originY + candidate.y + label.height + 3
        };
        const inMap = box.left >= 0 && box.top >= 0 && box.right <= 760 && box.bottom <= 460;
        const overlaps = placed.some((other) =>
          box.left < other.right && box.right > other.left
          && box.top < other.bottom && box.bottom > other.top
        );
        return inMap && !overlaps;
      }) || offsets[offsets.length - 1];
      label.element.setAttribute("transform", `translate(${offset.x} ${offset.y})`);
      placed.push({
        left: originX + offset.x - 3,
        top: originY + offset.y - 3,
        right: originX + offset.x + label.width + 3,
        bottom: originY + offset.y + label.height + 3
      });
    }
  }

  function polygonCentroid(points) {
    let twiceArea = 0;
    let xTotal = 0;
    let yTotal = 0;

    for (let index = 0; index < points.length; index += 1) {
      const current = points[index];
      const next = points[(index + 1) % points.length];
      const cross = current[0] * next[1] - next[0] * current[1];
      twiceArea += cross;
      xTotal += (current[0] + next[0]) * cross;
      yTotal += (current[1] + next[1]) * cross;
    }

    if (Math.abs(twiceArea) < 1e-8) {
      return {
        x: points.reduce((sum, point) => sum + point[0], 0) / points.length,
        y: points.reduce((sum, point) => sum + point[1], 0) / points.length
      };
    }
    return { x: xTotal / (3 * twiceArea), y: yTotal / (3 * twiceArea) };
  }

  function updateCountyLabels() {
    for (const label of mapRegions.querySelectorAll(".county-label")) {
      label.classList.toggle(
        "is-visible",
        mainView === "learn" || isMastered(game, label.dataset.countyId)
      );
    }
  }

  function renderProgress() {
    const learned = game.mastered.size;
    const seatMode = mode === "seat" || mode === "seat-map";
    document.getElementById("learned-count").textContent = learned;
    document.getElementById("map-count").textContent = `${learned} / ${counties.length}`;
    document.getElementById("score").textContent = game.score;
    document.getElementById("session-number").textContent = sessionNumber;
    document.getElementById("wrong-count").textContent = game.wrongAnswers;
    document.getElementById("county-wrong-label").textContent = seatMode
      ? "Ennél a székhelynél"
      : "Ennél a megyénél";
    document.getElementById("progress-label-text").textContent = seatMode
      ? "székhely megtanulva"
      : "megye megtanulva";
    document.getElementById("county-wrong-count").textContent = mistakesFor(
      game,
      revealingAnswer ? revealedId : game.activeId
    );
    const bar = document.getElementById("progress-bar");
    bar.setAttribute("aria-label", seatMode ? "Megtanult székhelyek" : "Megtanult megyék");
    bar.setAttribute("aria-valuemax", counties.length);
    bar.setAttribute("aria-valuenow", learned);
    document.getElementById("progress-fill").style.width = `${(learned / counties.length) * 100}%`;
  }

  function renderGame() {
    pageShell.classList.toggle("is-playing", mainView === "quiz");
    quizPanel.hidden = mainView !== "quiz";
    learningPanel.hidden = mainView !== "learn";
    document.getElementById("county-map").classList.toggle("is-learning", mainView === "learn");
    document.getElementById("seat-legend").hidden = mainView !== "learn";
    document.getElementById("review-legend").hidden =
      mainView !== "quiz" || Boolean(game.activeId) || game.wrongAnswers === 0;
    document.getElementById("map-description").textContent = mainView === "learn"
      ? "Magyarország 19 vármegyéjének határai, nevei és székhelyei ütközésmentesen elrendezve."
      : mode === "seat" || mode === "seat-map"
        ? "Magyarország vármegyéinek határai. A székhelykvízben a már megtanult vármegyék neve látható; a befejezéskor a hibás válaszokkal érintett megyéket keret jelöli."
        : "Magyarország 19 vármegyéjének határai. A kvízben a megtanult vármegyék neve látható; a befejezéskor a hibás válaszokkal érintett megyéket keret jelöli.";
    const canSelectMapArea = mainView === "quiz"
      && (mode === "map" || mode === "seat-map")
      && !revealingAnswer
      && Boolean(game.activeId);
    for (const region of mapRegions.querySelectorAll(".county-region")) {
      const countyId = region.dataset.countyId;
      region.classList.toggle("is-mastered", isMastered(game, countyId));
      region.classList.toggle(
        "is-review-mistake",
        mainView === "quiz" && !game.activeId && mistakesFor(game, countyId) > 0
      );
      region.classList.toggle("is-current", mainView === "quiz"
        && (((mode === "type" || mode === "seat") && game.activeId === countyId && !revealingAnswer)
          || (countyId === revealedId && revealingAnswer)));
      region.classList.toggle("is-clickable", canSelectMapArea);
      region.setAttribute("aria-disabled", String(!canSelectMapArea));
      region.setAttribute("tabindex", canSelectMapArea ? "0" : "-1");
    }
    for (const label of countySeats.querySelectorAll(".seat-label")) {
      label.classList.toggle(
        "is-answer-revealed",
        mainView === "quiz" && label.dataset.countyId === revealedSeatId
      );
    }
    for (const marker of countySeats.querySelectorAll(".seat-marker")) {
      marker.classList.toggle(
        "is-answer-revealed",
        mainView === "quiz" && marker.dataset.countyId === revealedSeatId
      );
    }
    updateCountyLabels();
    if (mainView === "learn") return;
    completionReview.hidden = true;

    renderProgress();

    const questionNumber = String(game.attempts + 1).padStart(2, "0");
    document.getElementById("question-number").textContent = questionNumber;
    document.getElementById("round-label").textContent =
      game.phase === "review" ? "TANULÓKÖR" : "ALAPKÖR";
    const seatMode = mode === "seat" || mode === "seat-map";
    document.querySelector(".question-body .card-kicker").textContent = seatMode
      ? mode === "seat-map" ? "KERESD MEG A TÉRKÉPEN" : "ADD MEG A SZÉKHELYET"
      : "NÉZZ A TÉRKÉPRE";
    const activeCounty = counties.find((county) => county.id === game.activeId);
    document.getElementById("question-title").textContent = game.activeId
      ? revealingAnswer ? revealedName
        : mode === "map" ? activeCounty.name
          : mode === "seat" ? activeCounty.name
            : mode === "seat-map" ? activeCounty.seat
              : questionTitle
      : seatMode ? "Minden székhelyet megtanultál!" : "Minden megye zöld!";
    document.querySelector(".question-hint").textContent = game.activeId
      ? mode === "map" ? "Kattints a megadott megye területére a térképen."
        : mode === "seat" ? "Írd be a megadott megye székhelyének nevét."
          : mode === "seat-map" ? "Kattints annak a vármegyének a területére, amelynek ez a székhelye."
            : questionHint
      : seatMode ? `Gratulálunk, mind a ${counties.length} székhelyet megtanultad.`
        : `Gratulálunk, mind a ${counties.length} területet megtanultad.`;
    answerForm.hidden = mode === "map" || mode === "seat-map" || !game.activeId;
    newGameButton.hidden = Boolean(game.activeId);
    modeButtons.forEach((button) => {
      button.disabled = revealingAnswer;
    });

    if ((mode === "type" || mode === "seat") && game.activeId && !revealingAnswer) {
      answerInput.disabled = false;
      submitButton.disabled = false;
      answerInput.value = "";
      answerInput.placeholder = mode === "seat" ? "A székhely neve…" : "A megye neve…";
      document.querySelector('label[for="answer-input"]').textContent =
        mode === "seat" ? "A székhely neve" : "A megye neve";
      if (!window.matchMedia("(max-width: 600px)").matches) {
        answerInput.focus({ preventScroll: true });
      }
      return;
    }
    answerInput.disabled = true;
    submitButton.disabled = true;
    if (!game.activeId) showCompletion();
  }

  function showCompletion() {
    const seatMode = mode === "seat" || mode === "seat-map";
    const mistakes = game.counties
      .filter((county) => mistakesFor(game, county.id) > 0)
      .sort((a, b) => a.name.localeCompare(b.name, "hu"));
    document.getElementById("question-title").textContent = seatMode
      ? "Minden székhelyet megtanultál!"
      : "Minden megye zöld!";
    document.querySelector(".question-hint").textContent = seatMode
      ? `Gratulálunk, mind a ${counties.length} székhelyet megtanultad.`
      : `Gratulálunk, mind a ${counties.length} területet megtanultad.`;
    answerForm.hidden = true;
    feedback.textContent = `Menet kész: ${game.score} pont, ${game.wrongAnswers} hibás válasz.`;
    feedback.className = "feedback is-complete";
    document.getElementById("question-number").textContent = String(game.attempts).padStart(2, "0");
    newGameButton.hidden = false;
    completionReview.replaceChildren();
    completionReview.hidden = mistakes.length === 0;
    if (mistakes.length > 0) {
      const heading = document.createElement("h3");
      const list = document.createElement("ul");
      heading.textContent = "Ezeket érdemes átismételni";
      list.className = "review-list";
      for (const county of mistakes) {
        const item = document.createElement("li");
        const answer = document.createElement("span");
        const count = document.createElement("span");
        answer.textContent = seatMode ? `${county.seat} — ${county.name}` : `${county.name} — ${county.seat}`;
        count.className = "review-mistake-count";
        count.textContent = `${mistakesFor(game, county.id)} hiba`;
        item.append(answer, count);
        list.append(item);
      }
      completionReview.append(heading, list);
    }
  }

  function showAnswerResult(result, answeredId, showSeatOnMap = false) {
    if (feedbackTimeoutId !== null) window.clearTimeout(feedbackTimeoutId);
    revealedSeatId = showSeatOnMap ? answeredId : null;
    if (result.correct) {
      revealedId = null;
      revealedName = null;
      feedback.textContent = "Helyes válasz.";
      feedback.className = "feedback";
      renderGame();
      if (result.completed) {
        showCompletion();
      } else if (showSeatOnMap) {
        feedbackTimeoutId = window.setTimeout(() => {
          revealedSeatId = null;
          feedback.textContent = "";
          feedback.className = "feedback";
          feedbackTimeoutId = null;
          renderGame();
        }, 1600);
      }
      return;
    }

    revealingAnswer = true;
    revealedId = answeredId;
    revealedName = result.answerName;
    feedback.textContent = `${mode === "map"
      ? `A keresett terület: ${result.answerName}.`
      : mode === "seat-map"
        ? `A székhelyhez tartozó vármegye: ${result.answerName}.`
      : mode === "seat"
        ? `Nem helyes. A székhely neve: ${result.answerName}.`
        : `Nem helyes. A megye neve: ${result.answerName}.`}`;
    feedback.className = "feedback is-wrong";
    renderGame();
    feedbackTimeoutId = window.setTimeout(() => {
      revealingAnswer = false;
      revealedId = null;
      revealedName = null;
      revealedSeatId = null;
      feedback.textContent = "";
      feedback.className = "feedback";
      feedbackTimeoutId = null;
      renderGame();
    }, 1900);
  }

  function answerForCounty(countyId) {
    if (revealingAnswer || !game.activeId) return;
    const selectedCounty = counties.find((county) => county.id === countyId);
    if (!selectedCounty) return;

    const answeredId = game.activeId;
    const result = mode === "seat-map"
      ? submitCountySelection(game, selectedCounty.id)
      : submitAnswer(game, selectedCounty.name);
    showAnswerResult(result, answeredId, mode === "map" || mode === "seat-map");
  }

  answerForm.addEventListener("submit", (event) => {
    event.preventDefault();
    if (revealingAnswer || !game.activeId || !answerInput.value.trim()) return;

    const answeredId = game.activeId;
    const result = submitAnswer(game, answerInput.value);
    showAnswerResult(result, answeredId, mode === "seat");
  });

  function handleMapSelection(event) {
    const region = event.target.closest("[data-county-id]");
    if (region && mapRegions.contains(region)) {
      answerForCounty(region.dataset.countyId);
    }
  }

  document.getElementById("county-map").addEventListener("click", (event) => {
    if (mainView === "quiz" && (mode === "map" || mode === "seat-map")) handleMapSelection(event);
  });
  document.getElementById("county-map").addEventListener("keydown", (event) => {
    if (mainView !== "quiz" || !["map", "seat-map"].includes(mode) || !["Enter", " "].includes(event.key)) return;
    const region = event.target.closest("[data-county-id]");
    if (region && mapRegions.contains(region)) {
      event.preventDefault();
      answerForCounty(region.dataset.countyId);
    }
  });
  modeButtons.forEach((button) => {
    button.addEventListener("click", () => {
      mode = button.dataset.mode;
      game = mode === "seat" || mode === "seat-map" ? seatGame : countyGame;
      questionTitle = mode === "map" ? "Nevezd meg a térképen!" : "Melyik megye?";
      questionHint = mode === "map"
        ? "Kattints a megadott megye területére a térképen."
        : mode === "seat"
          ? "Írd be a körvonallal jelölt megye székhelyét."
          : mode === "seat-map"
            ? "Kattints a megadott székhelyhez tartozó vármegye területére."
            : "Írd be a körvonallal jelölt megye nevét.";
      modeButtons.forEach((modeButton) => {
        const selected = modeButton === button;
        modeButton.classList.toggle("is-selected", selected);
        modeButton.setAttribute("aria-pressed", String(selected));
      });
      feedback.textContent = "";
      feedback.className = "feedback";
      revealedSeatId = null;
      if (feedbackTimeoutId !== null) {
        window.clearTimeout(feedbackTimeoutId);
        feedbackTimeoutId = null;
      }
      renderGame();
    });
  });

  function setMainView(view) {
    mainView = view;
    quizViewButton.classList.toggle("is-selected", view === "quiz");
    quizViewButton.setAttribute("aria-pressed", String(view === "quiz"));
    learnViewButton.classList.toggle("is-selected", view === "learn");
    learnViewButton.setAttribute("aria-pressed", String(view === "learn"));
    renderGame();
  }

  quizViewButton.addEventListener("click", () => setMainView("quiz"));
  learnViewButton.addEventListener("click", () => setMainView("learn"));

  newGameButton.addEventListener("click", () => {
    if (mode === "seat" || mode === "seat-map") {
      seatGame = createGame(counties, Math.random, "seat");
      game = seatGame;
    } else {
      countyGame = createGame();
      game = countyGame;
    }
    sessionNumber += 1;
    revealingAnswer = false;
    revealedId = null;
    revealedName = null;
    revealedSeatId = null;
    if (feedbackTimeoutId !== null) {
      window.clearTimeout(feedbackTimeoutId);
      feedbackTimeoutId = null;
    }
    feedback.textContent = "";
    feedback.className = "feedback";
    renderGame();
  });

  renderMap();
  document.fonts.ready.then(layoutLearningLabels);
  renderGame();
})();
