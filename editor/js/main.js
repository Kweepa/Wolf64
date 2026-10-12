let musicDir = null;
let midiNames = [];
let song = null;
let songName = "";
let arrange = null;
let selected = null;
let saveTimer = 0;
let cursorTick = 0;
let instQuery = "";
let instScroll = 0;
let kitKey = null;
const transport = new Transport();

const GM_DRUMS = {
  35: "Acoustic Kick", 36: "Kick", 37: "Side Stick", 38: "Snare", 39: "Clap",
  40: "Electric Snare", 41: "Low Floor Tom", 42: "Closed Hi-hat", 43: "High Floor Tom",
  44: "Pedal Hi-hat", 45: "Low Tom", 46: "Open Hi-hat", 47: "Low-mid Tom",
  48: "Hi-mid Tom", 49: "Crash", 50: "High Tom", 51: "Ride", 52: "China",
  53: "Ride Bell", 54: "Tambourine", 55: "Splash", 56: "Cowbell", 57: "Crash 2",
  58: "Vibraslap", 59: "Ride 2", 60: "High Bongo", 61: "Low Bongo",
  62: "Mute High Conga", 63: "Open High Conga", 64: "Low Conga", 65: "High Timbale",
  66: "Low Timbale", 67: "High Agogo", 68: "Low Agogo", 69: "Cabasa", 70: "Maracas",
  71: "Short Whistle", 72: "Long Whistle", 73: "Short Guiro", 74: "Long Guiro",
  75: "Claves", 76: "High Woodblock", 77: "Low Woodblock", 78: "Mute Cuica",
  79: "Open Cuica", 80: "Mute Triangle", 81: "Open Triangle",
};

function drumName(key) {
  return GM_DRUMS[key] || `Drum ${key}`;
}

const scoreCanvas = () => document.getElementById("score");
const headCanvas = () => document.getElementById("playhead");

function setStatus(text, isError) {
  const el = document.getElementById("status");
  el.textContent = text || "";
  el.classList.toggle("error", !!isError);
}

function sidecarName(name) {
  return name.replace(/\.mid$/i, "") + ".w64m.json";
}

function sidFileName(name) {
  return name.replace(/\.mid$/i, "") + ".sid";
}

async function chooseFolder() {
  if (!window.showDirectoryPicker) {
    setStatus("This editor needs a Chromium browser so it can read the music folder.", true);
    return;
  }
  const handle = await window.showDirectoryPicker({ mode: "readwrite" });
  await storeMusicHandle(handle);
  await openFolder(handle);
}

async function openFolder(handle) {
  if (!(await ensurePermission(handle))) {
    document.getElementById("file-gate").classList.remove("hidden");
    return;
  }
  musicDir = handle;
  document.getElementById("file-gate").classList.add("hidden");
  const listed = await listMusic(handle);
  midiNames = listed.mids;
  renderSongs();
  if (!midiNames.length) {
    setStatus("No .mid files in that folder.", true);
    return;
  }
  const keep = midiNames.includes(songName) ? songName : midiNames[0];
  await openSong(keep);
}

function renderSongs() {
  const ul = document.getElementById("song-list");
  ul.innerHTML = "";
  for (const name of midiNames) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = name;
    btn.className = name === songName ? "current" : "";
    btn.addEventListener("click", () => openSong(name));
    li.appendChild(btn);
    ul.appendChild(li);
  }
}

async function openSong(name) {
  transport.stop();
  setPlayButtons(null);
  const handle = await musicDir.getFileHandle(name);
  const bytes = await readFile(handle);
  songName = name;
  song = parseMidi(bytes, name);
  let saved = null;
  try {
    const side = await musicDir.getFileHandle(sidecarName(name));
    saved = JSON.parse(new TextDecoder().decode(await readFile(side)));
  } catch (err) {
    saved = null;
  }
  arrange = normalizeArrangement(song, saved, INSTRUMENTS);
  selected = song.lines.length ? song.lines[0].channel : null;
  cursorTick = 0;
  instQuery = "";
  instScroll = 0;
  kitKey = null;
  renderSongs();
  renderLines();
  renderInspector();
  redraw();
  setStatus(`${name}  ·  ${barCount(song)} bars  ·  ${song.lines.length} lines`);
}

function renderLines() {
  const ul = document.getElementById("line-list");
  ul.innerHTML = "";
  if (!song) return;
  for (const line of song.lines) {
    const row = arrange.lines[line.channel];
    const li = document.createElement("li");
    li.className = "line-row" + (selected === line.channel ? " current" : "");
    const name = document.createElement("button");
    name.type = "button";
    name.className = "line-name";
    name.textContent = lineLabel(line);
    name.addEventListener("click", () => selectLine(line.channel));
    const mute = document.createElement("button");
    mute.type = "button";
    mute.className = "tiny" + (row.mute ? " active" : "");
    mute.textContent = row.mute ? "Muted" : "Mute";
    mute.addEventListener("click", () => {
      row.mute = !row.mute;
      changed();
    });
    const voice = document.createElement("button");
    voice.type = "button";
    voice.className = "tiny voice-chip" + (row.voice && arrange.voices[row.voice].percussion ? " drum" : "");
    voice.textContent = row.voice ? `V${row.voice}` : "—";
    voice.title = "Cycle SID voice. The same voice merges lines.";
    voice.addEventListener("click", () => {
      const next = (row.voice + 1) % 4;
      row.voice = next;
      if (line.channel === PERCUSSION_CHANNEL && next) {
        for (let v = 1; v <= 3; v++) arrange.voices[v].percussion = v === next;
      }
      changed();
    });
    li.append(name, mute, voice);
    ul.appendChild(li);
  }
}

function selectLine(channel) {
  selected = channel;
  instQuery = "";
  kitKey = null;
  renderLines();
  renderInspector({ scrollToCurrent: true });
  redraw();
}

function quarterSeconds() {
  if (!song) return 0.5;
  return usAtTick(song, cursorTick) / 1e6;
}

function linePitch(line) {
  const notes = line.notes.map((note) => note.note).sort((a, b) => a - b);
  return notes[Math.floor(notes.length / 2)] || 60;
}

function auditionLine(line) {
  const row = arrange.lines[line.channel];
  const spec = row && row.voice ? arrange.voices[row.voice] : null;
  if (spec && spec.percussion) {
    auditionDrum(spec, linePitch(line));
    return;
  }
  transport.audition(spec && spec.instrument, false, linePitch(line), quarterSeconds());
}

function auditionDrum(spec, key) {
  const entry = kitEntry(spec, key);
  transport.audition(entry.instrument, true, entry.note, quarterSeconds());
}

function auditionInstrument(spec) {
  if (spec.percussion && kitKey != null) auditionDrum(spec, kitKey);
  else transport.audition(spec.instrument, !!spec.percussion, 60, quarterSeconds());
  if (transport.playing() === "sid") transport.relayout();
}

// Drum keys on the lines that feed this voice, with hit counts.
function voiceDrumKeys(voice) {
  const counts = new Map();
  for (const line of song.lines) {
    const row = arrange.lines[line.channel];
    if (!row || row.voice !== voice) continue;
    for (const note of line.notes) counts.set(note.note, (counts.get(note.note) || 0) + 1);
  }
  return Array.from(counts.entries()).sort((a, b) => a[0] - b[0]);
}

function renderKit(root, spec, voice) {
  const keys = voiceDrumKeys(voice);
  if (!keys.length) return;
  if (kitKey != null && !keys.some(([key]) => key === kitKey)) kitKey = null;
  const heading = document.createElement("p");
  heading.className = "field-label";
  heading.textContent = "Drum kit";
  root.appendChild(heading);
  const list = document.createElement("ul");
  list.className = "kit-list";
  const addRow = (key, label, detail) => {
    const li = document.createElement("li");
    li.className = "kit-row" + (kitKey === key ? " current" : "");
    li.dataset.key = key == null ? "" : String(key);
    const pick = document.createElement("button");
    pick.type = "button";
    pick.className = "kit-pick";
    pick.innerHTML = `<span class="kit-name"></span><span class="kit-ins"></span>`;
    pick.querySelector(".kit-name").textContent = label;
    pick.querySelector(".kit-ins").textContent = detail;
    pick.addEventListener("click", () => {
      kitKey = key;
      instQuery = "";
      renderInspector({ scrollToCurrent: true });
      if (key == null) auditionInstrument(spec);
      else auditionDrum(spec, key);
    });
    li.appendChild(pick);
    if (key != null) {
      const pitch = document.createElement("input");
      pitch.type = "number";
      pitch.min = "0";
      pitch.max = "127";
      pitch.className = "kit-pitch";
      pitch.title = "MIDI note the SID plays for this drum";
      pitch.value = String(kitEntry(spec, key).note);
      pitch.addEventListener("click", (event) => event.stopPropagation());
      pitch.addEventListener("change", () => {
        const n = Math.max(0, Math.min(127, Math.round(Number(pitch.value))));
        const entry = { ...(spec.kit[key] || {}) };
        if (!Number.isFinite(n) || n === key) delete entry.note;
        else entry.note = n;
        if (Object.keys(entry).length) spec.kit[key] = entry;
        else delete spec.kit[key];
        changed();
        auditionDrum(spec, key);
      });
      li.appendChild(pitch);
    }
    list.appendChild(li);
  };
  addRow(null, "Default", kitLabel(spec, null));
  for (const [key, count] of keys) addRow(key, `${key} ${drumName(key)} ×${count}`, kitLabel(spec, key));
  root.appendChild(list);
}

function kitLabel(spec, key) {
  if (key == null) return spec.instrument || "—";
  return (spec.kit[key] && spec.kit[key].instrument) || "default";
}

function refreshKitLabels(spec) {
  document.querySelectorAll("#inspector .kit-row").forEach((li) => {
    const key = li.dataset.key === "" ? null : Number(li.dataset.key);
    li.querySelector(".kit-ins").textContent = kitLabel(spec, key);
  });
}

function renderInspector(opts) {
  const root = document.getElementById("inspector");
  root.innerHTML = "";
  if (!song || !arrange) return;
  if (selected == null) {
    renderSongFields(root);
    return;
  }
  const line = song.lines.find((item) => item.channel === selected);
  if (!line) {
    renderSongFields(root);
    return;
  }
  const row = arrange.lines[line.channel];
  const title = document.createElement("h2");
  title.textContent = lineLabel(line);
  root.appendChild(title);
  const meta = document.createElement("p");
  meta.className = "muted";
  meta.textContent = `${line.notes.length} notes`;
  root.appendChild(meta);

  const mute = document.createElement("label");
  mute.className = "check";
  mute.innerHTML = `<input type="checkbox" ${row.mute ? "checked" : ""}/> Mute`;
  mute.querySelector("input").addEventListener("change", (event) => {
    row.mute = event.target.checked;
    changed();
  });
  root.appendChild(mute);

  const voiceField = document.createElement("label");
  voiceField.className = "field";
  voiceField.innerHTML = `<span>SID voice</span>`;
  const voice = document.createElement("select");
  [["0", "Off"], ["1", "Voice 1"], ["2", "Voice 2"], ["3", "Voice 3"]].forEach(([value, label]) => {
    const opt = document.createElement("option");
    opt.value = value;
    opt.textContent = label;
    if (String(row.voice) === value) opt.selected = true;
    voice.appendChild(opt);
  });
  voice.addEventListener("change", () => {
    row.voice = Number(voice.value);
    if (line.channel === PERCUSSION_CHANNEL && row.voice) {
      for (let v = 1; v <= 3; v++) arrange.voices[v].percussion = v === row.voice;
    }
    changed();
  });
  voiceField.appendChild(voice);
  root.appendChild(voiceField);

  if (!row.voice) {
    const note = document.createElement("p");
    note.className = "muted";
    note.textContent = "Unassigned lines play in MIDI preview and stay out of the SID.";
    root.appendChild(note);
    renderSongFields(root);
    return;
  }

  const spec = arrange.voices[row.voice];
  const drum = document.createElement("label");
  drum.className = "check";
  drum.innerHTML = `<input type="checkbox" ${spec.percussion ? "checked" : ""}/> Drum channel`;
  drum.querySelector("input").addEventListener("change", (event) => {
    for (let v = 1; v <= 3; v++) arrange.voices[v].percussion = false;
    spec.percussion = event.target.checked;
    if (spec.percussion && !spec.instrument) spec.instrument = suggestInstrument(INSTRUMENTS, null, true);
    changed();
  });
  root.appendChild(drum);

  if (!spec.percussion) {
    const arp = document.createElement("label");
    arp.className = "check";
    arp.innerHTML = `<input type="checkbox" ${spec.arp ? "checked" : ""}/> Arpeggio when notes overlap`;
    arp.querySelector("input").addEventListener("change", (event) => {
      spec.arp = event.target.checked;
      changed();
    });
    root.appendChild(arp);
  }

  if (spec.percussion) renderKit(root, spec, row.voice);
  const drumTarget = spec.percussion && kitKey != null;
  const currentId = () => (drumTarget ? kitEntry(spec, kitKey).instrument : spec.instrument);
  const setCurrent = (id) => {
    if (!drumTarget) {
      spec.instrument = id;
      return;
    }
    const entry = { ...(spec.kit[kitKey] || {}) };
    if (id === spec.instrument) delete entry.instrument;
    else entry.instrument = id;
    if (Object.keys(entry).length) spec.kit[kitKey] = entry;
    else delete spec.kit[kitKey];
  };
  const search = document.createElement("label");
  search.className = "field";
  search.innerHTML = "<span></span>";
  search.querySelector("span").textContent = drumTarget
    ? `SID instrument for ${kitKey} ${drumName(kitKey)}`
    : spec.percussion ? `Default drum instrument (voice ${row.voice})` : `SID instrument for voice ${row.voice}`;
  const input = document.createElement("input");
  input.type = "text";
  input.className = "inst-search";
  input.placeholder = "Search the SID-Wizard collection";
  input.value = instQuery;
  search.appendChild(input);
  root.appendChild(search);
  const list = document.createElement("ul");
  list.className = "inst-list";
  root.appendChild(list);
  const matches = (item, q) => !q || item.id.toLowerCase().includes(q) || item.name.toLowerCase().includes(q);
  const fill = () => {
    const q = input.value.trim().toLowerCase();
    list.innerHTML = "";
    let shown = INSTRUMENTS.filter((item) => matches(item, q)).slice(0, 80);
    const current = INSTRUMENTS.find((item) => item.id === currentId());
    if (current && matches(current, q) && !shown.some((item) => item.id === current.id)) shown.unshift(current);
    for (const item of shown) {
      const li = document.createElement("li");
      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = item.id;
      btn.title = item.name;
      if (item.id === currentId()) btn.className = "current";
      btn.addEventListener("click", () => {
        setCurrent(item.id);
        instScroll = list.scrollTop;
        list.querySelectorAll("button").forEach((el) => el.classList.toggle("current", el.textContent === item.id));
        if (spec.percussion) refreshKitLabels(spec);
        scheduleSave();
        updateSize();
        auditionInstrument(spec);
      });
      li.appendChild(btn);
      list.appendChild(li);
    }
  };
  input.addEventListener("input", () => {
    instQuery = input.value;
    fill();
  });
  let scrollLock = false;
  list.addEventListener("scroll", () => {
    if (!scrollLock) instScroll = list.scrollTop;
  });
  fill();
  scrollLock = true;
  if (opts && opts.scrollToCurrent) {
    const cur = list.querySelector("button.current");
    if (cur) cur.scrollIntoView({ block: "nearest" });
  } else {
    list.scrollTop = instScroll;
  }
  scrollLock = false;
  renderSongFields(root);
}

function renderSongFields(root) {
  const heading = document.createElement("h2");
  heading.textContent = "Song";
  heading.style.marginTop = "1rem";
  root.appendChild(heading);
  const title = document.createElement("label");
  title.className = "field";
  title.innerHTML = "<span>Title</span>";
  const titleInput = document.createElement("input");
  titleInput.type = "text";
  titleInput.value = arrange.title;
  titleInput.addEventListener("change", () => {
    arrange.title = titleInput.value.trim() || song.name;
    scheduleSave();
    updateSize();
  });
  title.appendChild(titleInput);
  root.appendChild(title);
  const author = document.createElement("label");
  author.className = "field";
  author.innerHTML = "<span>Author</span>";
  const authorInput = document.createElement("input");
  authorInput.type = "text";
  authorInput.value = arrange.author;
  authorInput.addEventListener("change", () => {
    arrange.author = authorInput.value;
    scheduleSave();
  });
  author.appendChild(authorInput);
  root.appendChild(author);
  const size = document.createElement("p");
  size.id = "size-line";
  size.className = "muted size-line";
  root.appendChild(size);
  updateSize();
}

function updateSize() {
  const el = document.getElementById("size-line");
  if (!el || !song || !arrange) return;
  const built = buildSid(song, arrange, INSTRUMENTS, PLAYER_BYTES, PLAYER_LABELS);
  const p = built.parts;
  const voiceText = p.voices.map((n, i) => `v${i + 1} ${n}`).join("  ");
  el.textContent = `${p.total}/${p.limit} bytes  ·  player ${p.player}  ·  ${voiceText}`;
  el.classList.toggle("over", !built.ok);
  if (!built.ok) el.title = built.error;
}

function changed() {
  const list = document.querySelector("#inspector .inst-list");
  if (list) instScroll = list.scrollTop;
  renderLines();
  renderInspector();
  redraw();
  scheduleSave();
  transport.relayout();
}

function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveSidecar, 300);
}

async function saveSidecar() {
  if (!musicDir || !arrange || !songName) return;
  const payload = JSON.stringify(arrange, null, 2);
  await writeFile(musicDir, sidecarName(songName), new TextEncoder().encode(payload));
}

function shownTick() {
  if (transport.playing()) return transport.heardTick || 0;
  return cursorTick;
}

function redraw() {
  if (!song || !arrange) return;
  const score = scoreCanvas();
  const head = headCanvas();
  const box = drawScore(score, song, arrange, selected);
  head.style.width = `${box.width}px`;
  head.style.height = `${box.height}px`;
  drawPlayhead(head, song, shownTick());
}

function seekTo(tick) {
  cursorTick = Math.max(0, Math.min(song.maxTick, tick));
  const mode = transport.playing();
  if (mode) play(mode, true);
  else drawPlayhead(headCanvas(), song, cursorTick);
}

function scrollPlayhead(tick) {
  const scroller = document.getElementById("score-scroll");
  const x = tickX(song, tick);
  const pad = 80;
  if (x < scroller.scrollLeft + pad || x > scroller.scrollLeft + scroller.clientWidth - pad) {
    scroller.scrollLeft = Math.max(0, x - scroller.clientWidth * 0.25);
  }
}

function setPlayButtons(mode) {
  document.getElementById("btn-midi").classList.toggle("active", mode === "midi");
  document.getElementById("btn-sid").classList.toggle("active", mode === "sid");
}

function play(mode, restart) {
  if (!song || !arrange) return;
  if (!restart && transport.playing() === mode) {
    cursorTick = transport.heardTick || cursorTick;
    transport.stop();
    setPlayButtons(null);
    drawPlayhead(headCanvas(), song, cursorTick);
    return;
  }
  transport.onend = () => {
    cursorTick = 0;
    setPlayButtons(null);
    if (song) drawPlayhead(headCanvas(), song, 0);
  };
  transport.onframe = (tick) => {
    transport.heardTick = tick;
    drawPlayhead(headCanvas(), song, tick);
    scrollPlayhead(tick);
  };
  transport.heardTick = cursorTick;
  if (mode === "midi") transport.playMidi(song, arrange, cursorTick);
  else transport.playSid(song, arrange, INSTRUMENTS, cursorTick);
  setPlayButtons(mode);
  setStatus(mode === "midi" ? "Playing MIDI" : "Playing SID preview");
}

async function exportSid() {
  if (!song || !arrange || !musicDir) return;
  const built = buildSid(song, arrange, INSTRUMENTS, PLAYER_BYTES, PLAYER_LABELS);
  updateSize();
  if (!built.ok) {
    setStatus(built.error, true);
    return;
  }
  const name = sidFileName(songName);
  await writeFile(musicDir, name, built.bytes);
  setStatus(`Wrote ${name} (${built.parts.total} bytes).`);
}

function bootClicks() {
  document.getElementById("btn-folder").addEventListener("click", () => chooseFolder().catch((err) => setStatus(err.message, true)));
  document.getElementById("btn-gate").addEventListener("click", () => chooseFolder().catch((err) => setStatus(err.message, true)));
  document.getElementById("btn-midi").addEventListener("click", () => play("midi"));
  document.getElementById("btn-sid").addEventListener("click", () => play("sid"));
  document.getElementById("btn-stop").addEventListener("click", () => {
    if (transport.playing()) cursorTick = transport.heardTick || cursorTick;
    transport.stop();
    setPlayButtons(null);
    if (song) drawPlayhead(headCanvas(), song, cursorTick);
  });
  document.getElementById("btn-export").addEventListener("click", () => exportSid().catch((err) => setStatus(err.message, true)));
  document.getElementById("btn-song").addEventListener("click", () => selectLine(null));
  document.getElementById("score-scroll").addEventListener("click", (event) => {
    if (!song) return;
    const rect = scoreCanvas().getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    const rows = song.lines.length * SCORE.rowH;
    const line = y >= 0 && y < rows ? song.lines[Math.floor(y / SCORE.rowH)] : null;
    if (!line) {
      seekTo(xToTick(song, x));
      return;
    }
    selectLine(line.channel);
    auditionLine(line);
  });
  window.addEventListener("resize", () => redraw());
}

async function boot() {
  bootClicks();
  const stored = await loadMusicHandle();
  if (stored && (await ensurePermission(stored).catch(() => false))) {
    await openFolder(stored);
    return;
  }
  document.getElementById("file-gate").classList.remove("hidden");
}

boot().catch((err) => setStatus(err.message, true));
