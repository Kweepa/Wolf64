// Standard MIDI file reader and the default 3-voice arrangement.
// These Wolf MIDIs are format 0, 350 ticks per quarter, no tempo meta.
// 120 BPM (the MIDI default) is 700 ticks/second, so one 50 Hz frame is 14 ticks.

const GM_NAMES = [
  "Acoustic Grand", "Bright Acoustic", "Electric Grand", "Honky-tonk",
  "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet",
  "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
  "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
  "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
  "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
  "Nylon Guitar", "Steel Guitar", "Jazz Guitar", "Clean Guitar",
  "Muted Guitar", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
  "Acoustic Bass", "Finger Bass", "Pick Bass", "Fretless Bass",
  "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
  "Violin", "Viola", "Cello", "Contrabass",
  "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
  "String Ensemble", "Synth Strings 1", "Synth Strings 2", "Choir Aahs",
  "Voice Oohs", "Synth Voice", "Orchestra Hit", "Trumpet",
  "Trombone", "Tuba", "Muted Trumpet", "French Horn",
  "Brass Section", "Synth Brass 1", "Synth Brass 2", "Soprano Sax",
  "Alto Sax", "Tenor Sax", "Baritone Sax", "Oboe",
  "English Horn", "Bassoon", "Clarinet", "Piccolo",
  "Flute", "Recorder", "Pan Flute", "Blown Bottle",
  "Shakuhachi", "Whistle", "Ocarina", "Lead Square",
  "Lead Saw", "Lead Calliope", "Lead Chiff", "Lead Charang",
  "Lead Voice", "Lead Fifths", "Lead Bass+Lead", "Pad New Age",
  "Pad Warm", "Pad Polysynth", "Pad Choir", "Pad Bowed",
  "Pad Metallic", "Pad Halo", "Pad Sweep", "FX Rain",
  "FX Soundtrack", "FX Crystal", "FX Atmosphere", "FX Brightness",
  "FX Goblins", "FX Echoes", "FX Sci-fi", "Sitar",
  "Banjo", "Shamisen", "Koto", "Kalimba",
  "Bagpipe", "Fiddle", "Shanai", "Tinkle Bell",
  "Agogo", "Steel Drums", "Woodblock", "Taiko Drum",
  "Melodic Tom", "Synth Drum", "Reverse Cymbal", "Guitar Fret Noise",
  "Breath Noise", "Seashore", "Bird Tweet", "Telephone",
  "Helicopter", "Applause", "Gunshot",
];

const PERCUSSION_CHANNEL = 9;
const FRAME_HZ = 50;

function gmName(program) {
  if (program == null || program < 0 || program >= GM_NAMES.length) return "Instrument";
  return GM_NAMES[program];
}

function lineLabel(line) {
  const ch = line.channel + 1;
  if (line.channel === PERCUSSION_CHANNEL) return `Ch ${ch}  Percussion`;
  return `Ch ${ch}  ${gmName(line.program)}`;
}

function readVarLen(data, pos) {
  let value = 0;
  for (let i = 0; i < 4; i++) {
    const b = data[pos.index++];
    value = (value << 7) | (b & 0x7f);
    if ((b & 0x80) === 0) return value;
  }
  throw new Error("MIDI variable-length value is too long");
}

function parseMidi(bytes, name) {
  const data = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (data.length < 14 || String.fromCharCode(data[0], data[1], data[2], data[3]) !== "MThd") {
    throw new Error(`${name || "MIDI"} is not a Standard MIDI file`);
  }
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const headerLen = view.getUint32(4);
  const format = view.getUint16(8);
  const ntrks = view.getUint16(10);
  const division = view.getUint16(12);
  if (division & 0x8000) throw new Error(`${name || "MIDI"} uses SMPTE time`);
  let pos = 8 + headerLen;
  const channels = [];
  for (let ch = 0; ch < 16; ch++) {
    channels.push({
      channel: ch,
      program: ch === PERCUSSION_CHANNEL ? null : 0,
      notes: [],
      bends: [],
      open: new Map(),
    });
  }
  let maxTick = 0;
  const tempos = [{ tick: 0, us: 500000 }];
  let numer = 4;
  let denom = 4;

  for (let trk = 0; trk < ntrks; trk++) {
    if (pos + 8 > data.length || String.fromCharCode(data[pos], data[pos + 1], data[pos + 2], data[pos + 3]) !== "MTrk") {
      throw new Error(`${name || "MIDI"} is missing track ${trk + 1}`);
    }
    const tlen = view.getUint32(pos + 4);
    const end = pos + 8 + tlen;
    const cursor = { index: pos + 8 };
    let tick = 0;
    let running = null;
    while (cursor.index < end) {
      tick += readVarLen(data, cursor);
      if (tick > maxTick) maxTick = tick;
      let status = data[cursor.index];
      if (status < 0x80) {
        if (running == null) throw new Error("MIDI running status is missing");
        status = running;
      } else {
        cursor.index++;
        if (status < 0xf0) running = status;
      }
      if (status === 0xff) {
        const meta = data[cursor.index++];
        const len = readVarLen(data, cursor);
        const payload = data.subarray(cursor.index, cursor.index + len);
        cursor.index += len;
        if (meta === 0x51 && payload.length === 3) {
          const us = (payload[0] << 16) | (payload[1] << 8) | payload[2];
          tempos.push({ tick, us });
        } else if (meta === 0x58 && payload.length >= 2) {
          numer = payload[0] || 4;
          denom = 1 << payload[1];
        }
      } else if (status === 0xf0 || status === 0xf7) {
        const len = readVarLen(data, cursor);
        cursor.index += len;
      } else {
        const kind = status & 0xf0;
        const ch = status & 0x0f;
        const line = channels[ch];
        if (kind === 0xc0 || kind === 0xd0) {
          const value = data[cursor.index++];
          if (kind === 0xc0 && line.program == null) line.program = value;
          else if (kind === 0xc0 && line.notes.length === 0) line.program = value;
        } else {
          const d1 = data[cursor.index++];
          const d2 = data[cursor.index++];
          if (kind === 0x90 && d2 > 0) {
            const stack = line.open.get(d1) || [];
            stack.push({ tick, vel: d2 });
            line.open.set(d1, stack);
          } else if (kind === 0x80 || (kind === 0x90 && d2 === 0)) {
            const stack = line.open.get(d1);
            if (stack && stack.length) {
              const on = stack.pop();
              line.notes.push({
                start: on.tick,
                end: Math.max(tick, on.tick + 1),
                note: d1,
                vel: on.vel,
              });
            }
          } else if (kind === 0xe0) {
            const value = ((d2 << 7) | d1) - 8192;
            line.bends.push({ tick, value });
          }
        }
      }
    }
    pos = end;
  }

  for (const line of channels) {
    for (const [note, stack] of line.open) {
      for (const on of stack) {
        line.notes.push({
          start: on.tick,
          end: Math.max(maxTick, on.tick + 1),
          note,
          vel: on.vel,
        });
      }
    }
    line.notes.sort((a, b) => a.start - b.start || a.note - b.note);
    line.bends.sort((a, b) => a.tick - b.tick);
  }

  const lines = channels.filter((line) => line.notes.length > 0);
  const title = (name || "untitled").replace(/\.mid$/i, "");
  return {
    name: title,
    format,
    ppq: division,
    numer,
    denom,
    tempos,
    maxTick,
    lines,
  };
}

function usAtTick(song, tick) {
  let us = 500000;
  for (const tempo of song.tempos) {
    if (tempo.tick > tick) break;
    us = tempo.us;
  }
  return us;
}

function tickToFrame(song, tick) {
  let frame = 0;
  let last = 0;
  let us = 500000;
  const ppq = song.ppq;
  for (const tempo of song.tempos) {
    if (tempo.tick >= tick) break;
    frame += ((tempo.tick - last) / ppq) * (us / 1e6) * FRAME_HZ;
    last = tempo.tick;
    us = tempo.us;
  }
  frame += ((tick - last) / ppq) * (us / 1e6) * FRAME_HZ;
  return Math.max(0, Math.floor(frame + 1e-9));
}

function frameToTick(song, frame) {
  const us = usAtTick(song, 0);
  return Math.round((frame / FRAME_HZ) * (1e6 / us) * song.ppq);
}

function songFrames(song) {
  return Math.max(1, tickToFrame(song, song.maxTick));
}

function barTicks(song) {
  const quarters = song.numer * (4 / song.denom);
  return quarters * song.ppq;
}

function barCount(song) {
  const width = barTicks(song);
  return Math.max(1, Math.ceil(song.maxTick / width));
}

function bendSemis(line, tick) {
  let value = 0;
  for (const bend of line.bends) {
    if (bend.tick > tick) break;
    value = bend.value;
  }
  const semis = (value / 8192) * 2;
  if (Math.abs(semis) < 1) return 0;
  return Math.round(semis);
}

function suggestInstrument(instruments, program, percussion) {
  const keys = percussion
    ? ["SNARE-TIGHT", "SNARE-FUNKY", "HIHAT-SHORT", "BONGO", "CLAP-SNARE"]
    : familyKeys(program);
  for (const key of keys) {
    const hit = instruments.find((item) => item.id === key || item.id.startsWith(key));
    if (hit) return hit.id;
  }
  return instruments[0] ? instruments[0].id : null;
}

function familyKeys(program) {
  const p = program == null ? 0 : program;
  if (p <= 7) return ["PIANO", "MUSICBOX"];
  if (p <= 15) return ["BELL", "CELESTA", "MUSICBOX"];
  if (p <= 23) return ["ORGAN"];
  if (p <= 31) return ["GUITAR"];
  if (p <= 39) return ["BASS"];
  if (p <= 47) return ["VIOLIN", "STRING"];
  if (p <= 55) return ["STRING", "CHOIR"];
  if (p <= 63) return ["BRASS"];
  if (p <= 71) return ["SAX", "FLUTE", "OBOE"];
  if (p <= 79) return ["FLUTE"];
  if (p <= 87) return ["LEAD", "SAW", "SOLO"];
  if (p <= 95) return ["PAD"];
  return ["LEAD", "BELL"];
}

function emptyVoices() {
  const voices = {};
  for (let v = 1; v <= 3; v++) {
    voices[v] = { instrument: null, arp: false, percussion: false, kit: {} };
  }
  return voices;
}

function defaultArrangement(song, instruments) {
  const lines = {};
  const voices = emptyVoices();
  const perc = song.lines.find((line) => line.channel === PERCUSSION_CHANNEL);
  const melodic = song.lines
    .filter((line) => line.channel !== PERCUSSION_CHANNEL)
    .slice()
    .sort((a, b) => b.notes.length - a.notes.length);
  if (perc) {
    lines[perc.channel] = { mute: false, voice: 3 };
    voices[3].percussion = true;
    voices[3].instrument = suggestInstrument(instruments, null, true);
    melodic.forEach((line, index) => {
      if (index < 2) {
        lines[line.channel] = { mute: false, voice: index + 1 };
        voices[index + 1].instrument = suggestInstrument(instruments, line.program, false);
      } else {
        lines[line.channel] = { mute: false, voice: 0 };
      }
    });
  } else {
    melodic.forEach((line, index) => {
      if (index < 3) {
        lines[line.channel] = { mute: false, voice: index + 1 };
        voices[index + 1].instrument = suggestInstrument(instruments, line.program, false);
      } else {
        lines[line.channel] = { mute: false, voice: 0 };
      }
    });
  }
  return { title: song.name, author: "Wolf64", lines, voices };
}

// Drum key -> { instrument, note }. Either field may be left out.
function normalizeKit(src) {
  const kit = {};
  if (!src || typeof src !== "object") return kit;
  for (const [key, value] of Object.entries(src)) {
    const k = Number(key);
    if (!Number.isInteger(k) || k < 0 || k > 127 || !value || typeof value !== "object") continue;
    const entry = {};
    if (typeof value.instrument === "string" && value.instrument) entry.instrument = value.instrument;
    if (Number.isInteger(value.note) && value.note >= 0 && value.note <= 127) entry.note = value.note;
    if (Object.keys(entry).length) kit[k] = entry;
  }
  return kit;
}

function normalizeArrangement(song, saved, instruments) {
  const base = defaultArrangement(song, instruments);
  if (!saved || typeof saved !== "object") return base;
  const arrange = {
    title: typeof saved.title === "string" && saved.title.trim() ? saved.title.trim() : base.title,
    author: typeof saved.author === "string" ? saved.author : base.author,
    lines: {},
    voices: emptyVoices(),
  };
  for (let v = 1; v <= 3; v++) {
    const src = saved.voices && saved.voices[v];
    arrange.voices[v] = {
      instrument: src && src.instrument ? src.instrument : base.voices[v].instrument,
      arp: !!(src && src.arp),
      percussion: !!(src && src.percussion),
      kit: normalizeKit(src && src.kit),
    };
  }
  for (const line of song.lines) {
    const src = saved.lines && (saved.lines[line.channel] || saved.lines[String(line.channel)]);
    if (!src) {
      arrange.lines[line.channel] = base.lines[line.channel] || { mute: false, voice: 0 };
      continue;
    }
    const voice = src.voice >= 1 && src.voice <= 3 ? src.voice : 0;
    arrange.lines[line.channel] = { mute: !!src.mute, voice };
  }
  if (saved.voices) {
    for (let v = 1; v <= 3; v++) {
      const src = saved.voices[v] || saved.voices[String(v)];
      if (src && Object.prototype.hasOwnProperty.call(src, "percussion")) {
        arrange.voices[v].percussion = !!src.percussion;
      }
    }
  }
  return arrange;
}
