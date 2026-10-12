// MIDI preview uses one oscillator per line. SID preview runs the export
// player on SidMachine and streams the chip output.

class Transport {
  constructor() {
    this.ctx = null;
    this.mode = null;
    this.timer = 0;
    this.onframe = null;
    this.song = null;
    this.frame = 0;
    this.nodes = [];
  }

  audio() {
    if (!this.ctx) this.ctx = new AudioContext();
    if (this.ctx.state === "suspended") this.ctx.resume();
    return this.ctx;
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = 0;
    }
    this.stopPreview();
    for (const node of this.nodes) {
      try { node.stop && node.stop(); } catch (err) { /* already stopped */ }
      try { node.disconnect && node.disconnect(); } catch (err) { /* already gone */ }
    }
    this.nodes = [];
    this.sounding = [];
    this.mode = null;
    this.machine = null;
    if (this.proc) {
      try { this.proc.disconnect(); } catch (err) { /* already gone */ }
      this.proc.onaudioprocess = null;
      this.proc = null;
    }
  }

  stopPreview() {
    if (this.previewTimer) {
      clearInterval(this.previewTimer);
      this.previewTimer = 0;
    }
    for (const node of this.previewNodes || []) {
      try { node.stop && node.stop(); } catch (err) { /* already stopped */ }
      try { node.disconnect && node.disconnect(); } catch (err) { /* already gone */ }
    }
    this.previewNodes = [];
  }

  track(node, channel) {
    this.nodes.push(node);
    this.sounding.push({ node, channel });
  }

  silenceChannel(channel) {
    for (const item of this.sounding || []) {
      if (item.channel !== channel) continue;
      try { item.node.stop(); } catch (err) { /* already stopped */ }
    }
  }

  playing() {
    return this.mode;
  }

  playMidi(song, arrange, originTick) {
    this.stop();
    const ctx = this.audio();
    this.mode = "midi";
    this.song = song;
    this.arrange = arrange;
    this.originTick = Math.max(0, originTick || 0);
    this.startedAt = ctx.currentTime;
    this.t0 = this.startedAt + 0.05;
    const us = usAtTick(song, 0);
    this.secPerTick = (us / 1e6) / song.ppq;
    this.sounding = [];
    this.scheduleMidi(this.originTick);
    this.frame = 0;
    this.timer = setInterval(() => this.midiClock(), 20);
  }

  scheduleMidi(originTick) {
    const ctx = this.ctx;
    const song = this.song;
    for (const line of song.lines) {
      const row = this.arrange.lines[line.channel];
      if (row && row.mute) continue;
      const perc = line.channel === PERCUSSION_CHANNEL;
      for (const note of line.notes) {
        const endTick = Math.max(note.end, note.start + 1);
        if (endTick <= originTick) continue;
        const startTick = Math.max(note.start, originTick);
        const start = this.t0 + (startTick - originTick) * this.secPerTick;
        const end = this.t0 + (endTick - originTick) * this.secPerTick;
        const vel = note.vel || 100;
        if (perc) this.drum(ctx, start, end, note.note, vel, line.channel);
        else this.tone(ctx, start, end, 440 * 2 ** ((note.note - 69) / 12), "triangle", vel, line.channel);
      }
    }
  }

  midiNow() {
    const elapsed = this.ctx.currentTime - this.startedAt - 0.05;
    return this.originTick + Math.max(0, elapsed / this.secPerTick);
  }

  midiClock() {
    if (!this.ctx || !this.song) return;
    const tick = this.midiNow();
    if (this.onframe) this.onframe(tick);
    if (tick > this.song.maxTick + this.song.ppq) {
      this.stop();
      if (this.onend) this.onend();
    }
  }

  rescheduleMidi() {
    if (this.mode !== "midi" || !this.ctx) return;
    for (const item of this.sounding) {
      try { item.node.stop(); } catch (err) { /* already stopped */ }
    }
    this.sounding = [];
    this.nodes = this.nodes.filter((node) => node === this.master);
    const tick = this.midiNow();
    this.originTick = tick;
    this.startedAt = this.ctx.currentTime - 0.05;
    this.t0 = this.ctx.currentTime;
    this.scheduleMidi(tick);
  }

  tone(ctx, start, end, hz, type, velocity, channel) {
    const dur = Math.max(0, end - start);
    const attack = Math.min(0.004, Math.max(0.001, dur * 0.3));
    const peak = Math.max(0.0002, 0.16 * (Math.max(1, velocity || 100) / 127));
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(hz, start);
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(peak, start + attack);
    const releaseAt = Math.max(end, start + attack);
    if (releaseAt > start + attack + 0.0005) gain.gain.setValueAtTime(peak, releaseAt);
    gain.gain.exponentialRampToValueAtTime(0.0001, releaseAt + 0.012);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(start);
    osc.stop(releaseAt + 0.03);
    this.track(osc, channel);
  }

  // GM channel 10 in these files is kick (36) and snare (38). The hit lasts
  // as long as the MIDI note, and velocity sets the level.
  drum(ctx, start, end, note, velocity, channel) {
    const dur = Math.max(0.02, end - start);
    const amount = Math.max(1, velocity || 100) / 127;
    if (note < 38) {
      this.pitchedHit(ctx, start, dur, 170, 48, 0.7 * amount, "sine", channel);
      this.noiseHit(ctx, start, Math.min(0.03, dur), 0.28 * amount, 0.5, "lowpass", 280, channel);
    } else {
      this.pitchedHit(ctx, start, Math.min(0.08, dur), 196, 168, 0.28 * amount, "triangle", channel);
      this.noiseHit(ctx, start, dur, 0.55 * amount, 1.7, "highpass", 900, channel);
    }
  }

  pitchedHit(ctx, start, dur, hz0, hz1, peak, type, channel) {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(hz0, start);
    osc.frequency.exponentialRampToValueAtTime(Math.max(20, hz1), start + dur);
    const level = Math.max(0.0002, peak);
    gain.gain.setValueAtTime(level, start);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + dur);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(start);
    osc.stop(start + dur + 0.02);
    this.track(osc, channel);
  }

  noiseBuffer(ctx) {
    if (this.noiseBuf && this.noiseBuf.sampleRate === ctx.sampleRate) return this.noiseBuf;
    const length = ctx.sampleRate;
    const buffer = ctx.createBuffer(1, length, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;
    this.noiseBuf = buffer;
    return buffer;
  }

  noiseHit(ctx, start, dur, peak, rate, filterType, freq, channel) {
    const src = ctx.createBufferSource();
    src.buffer = this.noiseBuffer(ctx);
    src.loop = true;
    src.playbackRate.setValueAtTime(rate, start);
    const filter = ctx.createBiquadFilter();
    filter.type = filterType;
    filter.frequency.setValueAtTime(freq, start);
    const gain = ctx.createGain();
    const level = Math.max(0.0002, peak);
    gain.gain.setValueAtTime(level, start);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + dur);
    src.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    src.start(start);
    src.stop(start + dur + 0.02);
    this.track(src, channel);
  }

  playSid(song, arrange, instruments, originTick) {
    this.stop();
    const ctx = this.audio();
    this.mode = "sid";
    this.song = song;
    this.arrange = arrange;
    this.instruments = instruments;
    const image = buildRamImage(song, arrange, instruments, PLAYER_BYTES, PLAYER_LABELS);
    this.machine = new SidMachine(ctx.sampleRate);
    this.machine.load(image.body);
    const startFrame = tickToFrame(song, Math.max(0, originTick || 0));
    this.machine.seek(startFrame);
    this.proc = ctx.createScriptProcessor(2048, 0, 1);
    this.proc.onaudioprocess = (event) => {
      const out = event.outputBuffer.getChannelData(0);
      if (!this.machine) {
        out.fill(0);
        return;
      }
      try {
        this.machine.fill(out);
      } catch (err) {
        out.fill(0);
        console.error(err);
      }
    };
    this.proc.connect(ctx.destination);
    this.timer = setInterval(() => {
      if (this.onframe && this.machine) this.onframe(frameToTick(song, this.machine.frame));
    }, 40);
  }

  relayout() {
    if (this.mode === "midi") {
      this.rescheduleMidi();
      return;
    }
    if (this.mode !== "sid" || !this.machine) return;
    const frame = this.machine.frame;
    const image = buildRamImage(this.song, this.arrange, this.instruments, PLAYER_BYTES, PLAYER_LABELS);
    this.machine.load(image.body);
    this.machine.seek(frame);
  }

  audition(instrumentId, percussion, midiNote, seconds) {
    const ctx = this.audio();
    this.stopPreview();
    const frames = Math.max(1, Math.round((seconds || 0.5) * FRAME_HZ));
    const note = midiNote == null ? 60 : midiNote;
    const channel = percussion ? 9 : 0;
    const song = {
      name: "preview",
      ppq: 350,
      numer: 4,
      denom: 4,
      tempos: [{ tick: 0, us: 500000 }],
      maxTick: frames * 14,
      lines: [{
        channel,
        program: 0,
        notes: [{ start: 0, end: frames * 14, note, vel: 110 }],
        bends: [],
      }],
    };
    const arrange = {
      title: "preview",
      author: "",
      lines: { [channel]: { mute: false, voice: 1 } },
      voices: {
        1: { instrument: instrumentId, arp: false, percussion: !!percussion },
        2: { instrument: instrumentId, arp: false, percussion: false },
        3: { instrument: instrumentId, arp: false, percussion: false },
      },
    };
    const image = buildRamImage(song, arrange, INSTRUMENTS, PLAYER_BYTES, PLAYER_LABELS);
    const machine = new SidMachine(ctx.sampleRate);
    machine.load(image.body);
    const tail = Math.floor(ctx.sampleRate * 0.15);
    const pcm = new Float32Array(Math.floor(ctx.sampleRate * (seconds || 0.5)) + tail);
    machine.fill(pcm);
    const buffer = ctx.createBuffer(1, pcm.length, ctx.sampleRate);
    buffer.copyToChannel(pcm, 0);
    const src = ctx.createBufferSource();
    src.buffer = buffer;
    src.connect(ctx.destination);
    src.start();
    this.previewNodes = [src];
  }
}
