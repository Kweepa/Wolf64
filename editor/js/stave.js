// Proportional staves. Time runs left to right; barlines are 4/4 unless the
// MIDI file says otherwise. Percussion uses cross noteheads.

const SCORE = {
  pxPerBeat: 56,
  rowH: 92,
  space: 7,
  left: 28,
  right: 36,
  top: 22,
};

const STEP_NAME = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
const IS_SHARP = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0];

function diatonic(note) {
  const oct = Math.floor(note / 12);
  return oct * 7 + STEP_NAME[((note % 12) + 12) % 12];
}

function clefFor(line) {
  if (line.channel === PERCUSSION_CHANNEL) return "perc";
  const notes = line.notes.map((note) => note.note).sort((a, b) => a - b);
  const mid = notes[Math.floor(notes.length / 2)] || 60;
  return mid >= 60 ? "treble" : "bass";
}

function middleDiatonic(clef) {
  if (clef === "bass") return diatonic(50);
  return diatonic(71);
}

function scoreWidth(song) {
  const beats = song.maxTick / song.ppq;
  return Math.ceil(SCORE.left + beats * SCORE.pxPerBeat + SCORE.right);
}

function scoreHeight(song) {
  return song.lines.length * SCORE.rowH + 8;
}

function tickX(song, tick) {
  return SCORE.left + (tick / song.ppq) * SCORE.pxPerBeat;
}

function xToTick(song, x) {
  const tick = ((x - SCORE.left) / SCORE.pxPerBeat) * song.ppq;
  return Math.max(0, Math.min(song.maxTick, tick));
}

function drawClef(ctx, clef, x, midY) {
  ctx.save();
  ctx.fillStyle = "#d4a017";
  ctx.font = "28px 'Segoe UI', serif";
  ctx.textBaseline = "middle";
  if (clef === "treble") ctx.fillText("𝄞", x, midY + 4);
  else if (clef === "bass") ctx.fillText("𝄢", x, midY - 2);
  else {
    ctx.font = "bold 16px 'Segoe UI', sans-serif";
    ctx.fillText("perc", x, midY);
  }
  ctx.restore();
}

function drawScore(canvas, song, arrange, selected) {
  const pane = document.getElementById("score-scroll");
  const width = Math.max(scoreWidth(song), pane ? pane.clientWidth : 0);
  const height = scoreHeight(song);
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.floor(width * dpr);
  canvas.height = Math.floor(height * dpr);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#0e1016";
  ctx.fillRect(0, 0, width, height);

  const bars = barTicks(song);
  song.lines.forEach((line, index) => {
    const row = arrange.lines[line.channel] || { mute: false, voice: 0 };
    const top = index * SCORE.rowH;
    const midY = top + SCORE.rowH / 2 + 4;
    const clef = clefFor(line);
    const middle = middleDiatonic(clef);
    ctx.save();
    ctx.globalAlpha = row.mute ? 0.35 : 1;
    if (selected === line.channel) {
      ctx.fillStyle = "rgba(212, 160, 23, 0.08)";
      ctx.fillRect(0, top + 4, width, SCORE.rowH - 8);
    }
    ctx.strokeStyle = "#2e3340";
    ctx.lineWidth = 1;
    for (let i = -2; i <= 2; i++) {
      const y = midY - i * SCORE.space;
      ctx.beginPath();
      ctx.moveTo(SCORE.left - 8, y);
      ctx.lineTo(width - 8, y);
      ctx.stroke();
    }
    drawClef(ctx, clef, 2, midY);
    ctx.fillStyle = row.voice ? "#d4a017" : "#8b91a0";
    ctx.font = "11px 'Segoe UI', sans-serif";
    ctx.textBaseline = "top";
    ctx.fillText(row.voice ? `V${row.voice}` : "—", 4, top + 6);

    ctx.strokeStyle = "#3a4258";
    ctx.fillStyle = "#8b91a0";
    ctx.font = "11px 'Segoe UI', sans-serif";
    ctx.textBaseline = "alphabetic";
    for (let bar = 0, tick = 0; tick <= song.maxTick + bars; bar++, tick += bars) {
      const x = tickX(song, tick);
      ctx.beginPath();
      ctx.moveTo(x, midY - 2 * SCORE.space);
      ctx.lineTo(x, midY + 2 * SCORE.space);
      ctx.stroke();
      if (index === 0) {
        ctx.fillText(String(bar + 1), x + 4, top + 14);
      }
    }

    const yFor = (midi) => midY - (diatonic(midi) - middle) * (SCORE.space / 2);
    for (const note of line.notes) {
      const x = tickX(song, note.start);
      const step = diatonic(note.note) - middle;
      const y = yFor(note.note);
      const evenLimit = step > 4 ? step - (step % 2) : step < -4 ? step + ((-step) % 2) : 0;
      ctx.strokeStyle = "#8b91a0";
      ctx.lineWidth = 1;
      if (step > 4) {
        for (let s = 6; s <= evenLimit; s += 2) {
          const ly = midY - s * (SCORE.space / 2);
          ctx.beginPath();
          ctx.moveTo(x - 8, ly);
          ctx.lineTo(x + 8, ly);
          ctx.stroke();
        }
      } else if (step < -4) {
        for (let s = -6; s >= evenLimit; s -= 2) {
          const ly = midY - s * (SCORE.space / 2);
          ctx.beginPath();
          ctx.moveTo(x - 8, ly);
          ctx.lineTo(x + 8, ly);
          ctx.stroke();
        }
      }
      const endSemis = bendSemis(line, note.end);
      const startSemis = bendSemis(line, note.start);
      ctx.strokeStyle = "#e4e6eb";
      ctx.fillStyle = "#e4e6eb";
      if (clef === "perc") {
        ctx.beginPath();
        ctx.moveTo(x - 4, y - 4);
        ctx.lineTo(x + 4, y + 4);
        ctx.moveTo(x + 4, y - 4);
        ctx.lineTo(x - 4, y + 4);
        ctx.stroke();
      } else {
        ctx.beginPath();
        ctx.ellipse(x, y, 5.5, 4, -0.4, 0, Math.PI * 2);
        ctx.fill();
        ctx.beginPath();
        if (step >= 0) {
          ctx.moveTo(x - 5, y);
          ctx.lineTo(x - 5, y + 22);
        } else {
          ctx.moveTo(x + 5, y);
          ctx.lineTo(x + 5, y - 22);
        }
        ctx.stroke();
        if (IS_SHARP[note.note % 12]) {
          ctx.font = "12px 'Segoe UI', serif";
          ctx.fillText("♯", x - 16, y + 4);
        }
      }
      if (startSemis !== endSemis) {
        const y2 = yFor(note.note + endSemis - startSemis);
        const x2 = tickX(song, note.end);
        ctx.strokeStyle = "#d4a017";
        ctx.beginPath();
        ctx.moveTo(x + 6, y);
        ctx.quadraticCurveTo((x + x2) / 2, (y + y2) / 2 - 8, x2, y2);
        ctx.stroke();
      }
    }
    ctx.restore();
  });
  return { width, height };
}

function drawPlayhead(canvas, song, tick) {
  const width = parseFloat(canvas.style.width) || canvas.width;
  const height = parseFloat(canvas.style.height) || canvas.height;
  const dpr = window.devicePixelRatio || 1;
  if (canvas.width !== Math.floor(width * dpr) || canvas.height !== Math.floor(height * dpr)) {
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
  }
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, width, height);
  if (tick == null) return;
  const x = tickX(song, tick);
  ctx.strokeStyle = "#d4a017";
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(x, 0);
  ctx.lineTo(x, height);
  ctx.stroke();
}
