// Build a PSID whose code+data load at $5000. genmusic.py relocates it,
// patches the single STA $D418, and rejects anything that would pass $8000.
// genmusic appends a 13-byte volume stub, so the body must end by $7FF2.

const SID_LOAD = 0x5000;
const SID_TOP = 0x8000;
const VOL_STUB = 13;
const MAX_BODY = SID_TOP - SID_LOAD - VOL_STUB;
const SW_NOTE_OFFSET = 11;
const KIT_MAX = 51;
// Gate-off frames before a re-struck note: SID-Wizard instruments hard
// restart for up to two frames.
const HR_FRAMES = 2;

function swNote(midiNote) {
  return Math.max(0, Math.min(95, midiNote - SW_NOTE_OFFSET));
}

function makeSawInstrument() {
  const raw = new Uint8Array(0x15);
  raw[0] = 0x1a;
  raw[1] = 0x0f;
  raw[3] = 0x09;
  raw[4] = 0xf8;
  raw[10] = 0x14;
  raw[11] = 0x15;
  raw[15] = 0x09;
  raw[16] = 0x21;
  raw[19] = 0xff;
  raw[20] = 0xff;
  return raw;
}

function makeNoiseInstrument() {
  const raw = makeSawInstrument();
  raw[3] = 0x0c;
  raw[4] = 0x00;
  raw[16] = 0x81;
  return raw;
}

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

function bytesOf(list) {
  return Uint8Array.from(list);
}

function pushRest(out, frames) {
  let left = frames;
  while (left > 0) {
    const n = Math.min(127, left);
    out.push(n);
    left -= n;
  }
}

function pushPacked(out, note, gate, gap) {
  let left = Math.max(1, gate);
  const hole = Math.max(0, gap);
  if (left > 16 || hole > 15) {
    while (left > 0) {
      const chunk = Math.min(255, left);
      const last = chunk === left;
      out.push(0xf0, chunk, last ? Math.min(255, hole) : 0, note & 0x7f);
      left -= chunk;
      if (last && hole > 255) pushRest(out, hole - 255);
      if (last) return;
    }
  }
  out.push(0x80 | (note & 0x7f), ((left - 1) << 4) | hole);
}

function pushGap(out, frames) {
  let left = frames;
  while (left > 255) {
    out.push(0xfe, 255);
    left -= 255;
  }
  if (left > 0) out.push(0xfe, left);
}

function pushHit(out, slot, frames) {
  out.push(slot);
  let left = Math.max(1, frames);
  out.push(Math.min(255, left));
  left -= Math.min(255, left);
  while (left > 255) {
    out.push(0xfe, 255);
    left -= 255;
  }
  if (left > 0) out.push(0xfe, left);
}

function lineByChannel(song, channel) {
  return song.lines.find((line) => line.channel === channel);
}

function assignedNotes(song, arrange, voice) {
  const notes = [];
  for (const line of song.lines) {
    const row = arrange.lines[line.channel];
    if (!row || row.mute || row.voice !== voice) continue;
    for (const note of line.notes) {
      notes.push({
        line,
        channel: line.channel,
        start: tickToFrame(song, note.start),
        end: Math.max(tickToFrame(song, note.start) + 1, tickToFrame(song, note.end)),
        note: note.note,
        id: `${line.channel}:${note.start}:${note.note}`,
      });
    }
  }
  return notes;
}

function sounding(notes, frame) {
  const active = [];
  for (const note of notes) {
    if (note.start <= frame && frame < note.end) active.push(note);
  }
  return active;
}

function compileMelodic(song, notes, arp) {
  const total = songFrames(song);
  const segs = [];
  let run = null;
  const close = () => {
    if (!run) return;
    segs.push(run);
    run = null;
  };
  for (let frame = 0; frame < total; frame++) {
    const active = sounding(notes, frame);
    if (!active.length) {
      if (run && run.gate) close();
      if (!run) run = { gate: false, frames: 1 };
      else run.frames++;
      continue;
    }
    const chosen = arp ? active[Math.floor(frame / 2) % active.length] : active.reduce((a, b) => (a.note >= b.note ? a : b));
    const bend = bendSemis(chosen.line, frameToTick(song, frame));
    const sw = swNote(chosen.note + bend);
    if (run && run.gate && run.id === chosen.id && run.sw === sw) {
      run.frames++;
      continue;
    }
    const legato = !!(run && run.gate && run.id === chosen.id);
    close();
    run = { gate: true, frames: 1, sw, id: chosen.id, legato };
  }
  close();
  const out = [];
  for (let i = 0; i < segs.length; i++) {
    const seg = segs[i];
    if (!seg.gate) {
      pushRest(out, seg.frames);
      continue;
    }
    let gate = seg.frames;
    let gap = 0;
    const next = segs[i + 1];
    if (next && !next.gate) {
      gap = next.frames;
      next.frames = 0;
    } else if (next && next.gate && !next.legato && gate > 1) {
      gap = Math.min(HR_FRAMES, gate - 1);
      gate -= gap;
    }
    pushPacked(out, seg.sw, gate, gap);
  }
  out.push(0);
  return bytesOf(out);
}

// Kit entry for one drum key: the key's own instrument and pitch, or the
// voice instrument at the key's pitch.
function kitEntry(spec, key) {
  const kit = (spec && spec.kit) || {};
  const entry = kit[key] || {};
  return {
    instrument: entry.instrument || (spec && spec.instrument) || null,
    note: Number.isFinite(entry.note) ? entry.note : key,
  };
}

function drumKeys(notes) {
  return Array.from(new Set(notes.map((note) => note.note))).sort((a, b) => a - b);
}

function compilePercussion(song, notes, slotOf) {
  const total = songFrames(song);
  const hits = new Map();
  for (const note of notes) {
    hits.set(note.start, note);
  }
  const frames = Array.from(hits.keys()).sort((a, b) => a - b);
  const out = [];
  if (!frames.length) {
    out.push(0);
    return bytesOf(out);
  }
  if (frames[0] > 0) pushGap(out, frames[0]);
  for (let i = 0; i < frames.length; i++) {
    const hit = hits.get(frames[i]);
    const next = i + 1 < frames.length ? frames[i + 1] : total;
    const span = Math.max(1, next - frames[i]);
    const room = i + 1 < frames.length ? Math.max(1, span - HR_FRAMES) : span;
    const held = Math.max(1, Math.min(room, hit.end - hit.start));
    pushHit(out, slotOf(hit.note), held);
    if (span > held) pushGap(out, span - held);
  }
  out.push(0);
  return bytesOf(out);
}

function instrumentBytes(instruments, id, percussion) {
  const found = instruments.find((item) => item.id === id);
  if (found) return hexToBytes(found.raw);
  return percussion ? makeNoiseInstrument() : makeSawInstrument();
}

function writeAscii(buf, offset, text, len) {
  const src = (text || "").slice(0, len);
  for (let i = 0; i < len; i++) buf[offset + i] = i < src.length ? src.charCodeAt(i) & 0x7f : 0;
}

// Layout: player, kit table, one image per distinct instrument, streams.
function buildRamImage(song, arrange, instruments, playerBytes, labels) {
  const images = [];
  const imageAt = new Map();
  const useImage = (id, percussion) => {
    const key = (instruments.some((item) => item.id === id) ? id : null) || (percussion ? "#noise" : "#saw");
    if (!imageAt.has(key)) {
      imageAt.set(key, images.length);
      images.push({ key, raw: instrumentBytes(instruments, id, percussion) });
    }
    return imageAt.get(key);
  };
  const kit = [];
  const kitAt = new Map();
  const programs = [1, 2, 3].map((voice) => {
    const spec = arrange.voices[voice] || {};
    const notes = assignedNotes(song, arrange, voice);
    if (!notes.length) return { stream: bytesOf([0]), percussion: false, notes: 0, image: -1 };
    if (!spec.percussion) {
      return {
        stream: compileMelodic(song, notes, !!spec.arp),
        percussion: false,
        notes: notes.length,
        image: useImage(spec.instrument, false),
      };
    }
    const slots = new Map();
    for (const key of drumKeys(notes)) {
      const entry = kitEntry(spec, key);
      const image = useImage(entry.instrument, true);
      const sw = swNote(entry.note);
      const id = `${image}:${sw}`;
      if (!kitAt.has(id)) {
        kitAt.set(id, kit.length);
        kit.push({ image, sw });
      }
      slots.set(key, kitAt.get(id) + 1);
    }
    return {
      stream: compilePercussion(song, notes, (key) => slots.get(key)),
      percussion: true,
      notes: notes.length,
      image: kit[slots.values().next().value - 1].image,
    };
  });
  if (!images.length) useImage(null, false);
  for (const prog of programs) {
    if (prog.image < 0) prog.image = 0;
  }
  const player = playerBytes.length;
  const kitBytes = kit.length * 5;
  const insBytes = images.reduce((sum, img) => sum + img.raw.length, 0);
  const streamBytes = programs.map((prog) => prog.stream.length);
  const total = player + kitBytes + insBytes + streamBytes.reduce((a, b) => a + b, 0);
  const parts = {
    player,
    kit: kitBytes,
    kitSlots: kit.length,
    instruments: insBytes,
    voices: streamBytes,
    total,
    limit: MAX_BODY,
  };
  const body = new Uint8Array(total);
  body.set(playerBytes, 0);
  const kitStart = SID_LOAD + player;
  let cursor = player + kitBytes;
  const insAt = images.map((img) => {
    const at = cursor;
    body.set(img.raw, cursor);
    cursor += img.raw.length;
    return { start: SID_LOAD + at, end: SID_LOAD + cursor };
  });
  kit.forEach((slot, i) => {
    const ins = insAt[slot.image];
    body.set([slot.sw, ins.start & 0xff, ins.start >> 8, ins.end & 0xff, ins.end >> 8], player + i * 5);
  });
  const streamsAt = programs.map((prog) => {
    const at = cursor;
    body.set(prog.stream, cursor);
    cursor += prog.stream.length;
    return { start: SID_LOAD + at, end: SID_LOAD + cursor };
  });
  const off = (addr) => addr - SID_LOAD;
  for (let v = 0; v < 3; v++) {
    const ins = insAt[programs[v].image];
    body[off(labels.hdr_vptr_lo) + v] = streamsAt[v].start & 0xff;
    body[off(labels.hdr_vptr_hi) + v] = streamsAt[v].start >> 8;
    body[off(labels.hdr_vend_lo) + v] = streamsAt[v].end & 0xff;
    body[off(labels.hdr_vend_hi) + v] = streamsAt[v].end >> 8;
    body[off(labels.hdr_iptr_lo) + v] = ins.start & 0xff;
    body[off(labels.hdr_iptr_hi) + v] = ins.start >> 8;
    body[off(labels.hdr_iend_lo) + v] = ins.end & 0xff;
    body[off(labels.hdr_iend_hi) + v] = ins.end >> 8;
    body[off(labels.hdr_flags) + v] = programs[v].percussion ? 1 : 0;
  }
  body[off(labels.hdr_kit_lo)] = kitStart & 0xff;
  body[off(labels.hdr_kit_hi)] = kitStart >> 8;
  let stores = 0;
  for (let i = 0; i < body.length - 2; i++) {
    if (body[i] === 0x8d && body[i + 1] === 0x18 && body[i + 2] === 0xd4) stores++;
  }
  return { body, parts, programs, images, stores };
}

function buildSid(song, arrange, instruments, playerBytes, labels) {
  const image = buildRamImage(song, arrange, instruments, playerBytes, labels);
  const { body, parts, programs, images, stores } = image;
  if (parts.total > MAX_BODY) {
    return {
      ok: false,
      error: `SID is ${parts.total} bytes and the menu allows ${MAX_BODY}. Mute a line or turn arpeggio off.`,
      parts,
    };
  }
  if (parts.kitSlots > KIT_MAX) {
    return { ok: false, error: `Drum kit has ${parts.kitSlots} sounds; the player takes ${KIT_MAX}.`, parts };
  }
  if (stores !== 1) {
    return { ok: false, error: `player has ${stores} STA $D418 instructions`, parts, body };
  }
  const psid = new Uint8Array(0x7c + body.length);
  psid.set([0x50, 0x53, 0x49, 0x44, 0x00, 0x02, 0x00, 0x7c]);
  psid[8] = SID_LOAD >> 8;
  psid[9] = SID_LOAD & 0xff;
  psid[10] = SID_LOAD >> 8;
  psid[11] = SID_LOAD & 0xff;
  psid[12] = (SID_LOAD + 3) >> 8;
  psid[13] = (SID_LOAD + 3) & 0xff;
  psid[15] = 1;
  psid[17] = 1;
  writeAscii(psid, 0x16, arrange.title || song.name, 32);
  writeAscii(psid, 0x36, arrange.author || "", 32);
  writeAscii(psid, 0x56, "2026 Wolf64", 32);
  psid[0x77] = 0x24;
  psid.set(body, 0x7c);
  return { ok: true, bytes: psid, body, parts, programs, images };
}
