// PAL SID model with the 8580 filter curve the SID-Wizard presets were tuned
// on. Pulse width, the exponential envelope, and the filter are what make two
// patches sound different.

const SID_CLOCK = 985248;
const OVERSAMPLE = 4;
const OUTPUT_GAIN = 0.3;
const ENV_PERIOD = [
  8, 31, 63, 95, 149, 220, 267, 313, 392, 977,
  1954, 3126, 3906, 11720, 19531, 31251,
];

function envMul(level) {
  if (level < 0x06) return 30;
  if (level < 0x0e) return 16;
  if (level < 0x1a) return 8;
  if (level < 0x36) return 4;
  if (level < 0x5d) return 2;
  return 1;
}

// The chip's 8 noise output taps, as waveform bits 11-4.
function noiseBits(l) {
  return (((l >> 20) & 1) << 11) | (((l >> 18) & 1) << 10) | (((l >> 14) & 1) << 9) |
    (((l >> 11) & 1) << 8) | (((l >> 9) & 1) << 7) | (((l >> 5) & 1) << 6) |
    (((l >> 2) & 1) << 5) | ((l & 1) << 4);
}

class SidVoice {
  constructor() {
    this.freq = 0;
    this.pw = 0x800;
    this.ctrl = 0;
    this.attack = 0;
    this.decay = 0;
    this.sustain = 0;
    this.release = 0;
    this.acc = 0;
    this.lfsr = 0x7ffff8;
    this.noise = noiseBits(this.lfsr);
    this.env = 0;
    this.phase = "rel";
    this.envTimer = 1;
    this.gate = false;
  }
}

class SidChip {
  constructor(sampleRate) {
    this.sampleRate = sampleRate || 44100;
    this.cyclesPerSample = SID_CLOCK / this.sampleRate;
    this.voices = [new SidVoice(), new SidVoice(), new SidVoice()];
    this.cut = 0;
    this.res = 0;
    this.mode = 0;
    this.vol = 15;
    this.routed = 0;
    this.low = 0;
    this.band = 0;
    this.high = 0;
    this.cycleFrac = 0;
    this.lp = 0;
    this.hp = 0;
    this.lpCoef = 1 - Math.exp(-2 * Math.PI * 16000 / (this.sampleRate * OVERSAMPLE));
    this.hpCoef = 1 - Math.exp(-2 * Math.PI * 16 / this.sampleRate);
  }

  reset() {
    this.voices = [new SidVoice(), new SidVoice(), new SidVoice()];
    this.cut = 0;
    this.res = 0;
    this.mode = 0;
    this.vol = 15;
    this.routed = 0;
    this.low = this.band = this.high = 0;
    this.lp = this.hp = 0;
    this.cycleFrac = 0;
  }

  write(reg, val) {
    const v = reg < 21 ? this.voices[(reg / 7) | 0] : null;
    const r = reg < 21 ? reg % 7 : reg;
    if (r === 0 && v) v.freq = (v.freq & 0xff00) | val;
    else if (r === 1 && v) v.freq = (v.freq & 0x00ff) | (val << 8);
    else if (r === 2 && v) v.pw = (v.pw & 0x0f00) | val;
    else if (r === 3 && v) v.pw = (v.pw & 0x00ff) | ((val & 0x0f) << 8);
    else if (r === 4 && v) this.setCtrl(v, val);
    else if (r === 5 && v) {
      v.attack = val >> 4;
      v.decay = val & 15;
    } else if (r === 6 && v) {
      v.sustain = val >> 4;
      v.release = val & 15;
    } else if (reg === 21) this.cut = (this.cut & 0x7f8) | (val & 7);
    else if (reg === 22) this.cut = (this.cut & 7) | (val << 3);
    else if (reg === 23) {
      this.res = val >> 4;
      this.routed = val & 7;
    } else if (reg === 24) {
      this.mode = val & 0x70;
      this.vol = val & 15;
    }
  }

  setCtrl(voice, val) {
    const gate = (val & 1) !== 0;
    if (gate && !voice.gate) {
      voice.phase = "atk";
      voice.envTimer = this.period(voice, false);
    } else if (!gate && voice.gate) {
      voice.phase = "rel";
      voice.envTimer = this.period(voice, true);
    }
    voice.gate = gate;
    voice.ctrl = val;
    if (val & 0x08) {
      voice.acc = 0;
      voice.lfsr = 0x7ffff8;
      voice.noise = noiseBits(voice.lfsr);
    }
  }

  period(voice, releasing) {
    const rate = voice.phase === "atk" ? voice.attack : (releasing || voice.phase === "rel" ? voice.release : voice.decay);
    const mul = voice.phase === "atk" ? 1 : envMul(voice.env);
    return Math.max(1, ENV_PERIOD[rate] * mul);
  }

  sustainLevel(voice) {
    const n = voice.sustain;
    return (n << 4) | n;
  }

  advanceEnv(cycles) {
    for (const voice of this.voices) {
      let left = cycles;
      while (left > 0) {
        if (voice.phase === "sus") break;
        if (voice.phase === "dec" && voice.env <= this.sustainLevel(voice)) {
          voice.phase = "sus";
          voice.env = this.sustainLevel(voice);
          break;
        }
        if ((voice.phase === "dec" || voice.phase === "rel") && voice.env <= 0) {
          voice.env = 0;
          break;
        }
        if (voice.envTimer > left) {
          voice.envTimer -= left;
          break;
        }
        left -= voice.envTimer;
        if (voice.phase === "atk") {
          voice.env = Math.min(255, voice.env + 1);
          if (voice.env >= 255) voice.phase = "dec";
        } else {
          voice.env = Math.max(0, voice.env - 1);
        }
        voice.envTimer = this.period(voice, voice.phase === "rel");
      }
    }
  }

  advanceOsc(cycles) {
    for (const voice of this.voices) {
      if (voice.ctrl & 0x08) {
        voice.acc = 0;
        continue;
      }
      const prev = voice.acc;
      const delta = voice.freq * cycles;
      voice.acc = (voice.acc + delta) & 0xffffff;
      // The LFSR steps on each rising edge of accumulator bit 19.
      const clocks = Math.floor((prev + delta + 0x80000) / 0x100000) - Math.floor((prev + 0x80000) / 0x100000);
      if (!clocks) continue;
      let lfsr = voice.lfsr;
      for (let i = 0; i < clocks; i++) {
        const bit = ((lfsr >> 22) ^ (lfsr >> 17)) & 1;
        lfsr = ((lfsr << 1) | bit) & 0x7fffff;
      }
      voice.lfsr = lfsr || 1;
      voice.noise = noiseBits(voice.lfsr);
    }
  }

  clock(cycles) {
    if (cycles <= 0) return;
    this.advanceEnv(cycles);
    this.advanceOsc(cycles);
  }

  wave(voice) {
    if (voice.ctrl & 0x08) return 0;
    const saw = voice.acc >>> 12;
    let tri = (voice.acc >>> 11) & 0xfff;
    if (voice.acc & 0x800000) tri ^= 0xfff;
    const pulse = saw >= voice.pw ? 0xfff : 0;
    const noise = voice.noise;
    const ctrl = voice.ctrl;
    let bits = 0xfff;
    let any = false;
    if (ctrl & 0x10) { bits &= tri; any = true; }
    if (ctrl & 0x20) { bits &= saw; any = true; }
    if (ctrl & 0x40) { bits &= pulse; any = true; }
    if (ctrl & 0x80) { bits &= noise; any = true; }
    if (!any) return 0;
    return (bits - 0x800) / 0x800;
  }

  output() {
    let dry = 0;
    let wet = 0;
    for (let i = 0; i < 3; i++) {
      const voice = this.voices[i];
      const sample = this.wave(voice) * (voice.env / 255);
      if (this.routed & (1 << i)) wet += sample;
      else dry += sample;
    }
    const f = this.filterCoef();
    const damp = 1 / (0.707 + this.res / 15 * 1.5);
    this.low += f * this.band;
    this.high = wet - this.low - damp * this.band;
    this.band += f * this.high;
    let shaped = 0;
    if (this.mode & 0x10) shaped += this.low;
    if (this.mode & 0x20) shaped += this.band;
    if (this.mode & 0x40) shaped += this.high;
    const mixed = (dry + shaped) * (this.vol / 15);
    this.lp += this.lpCoef * (mixed - this.lp);
    return this.lp;
  }

  filterCoef() {
    if (this.coefCut === this.cut) return this.coef;
    const fs = this.sampleRate * OVERSAMPLE;
    const hz = 30 + this.cut * 5.8;
    this.coefCut = this.cut;
    this.coef = 2 * Math.sin(Math.PI * Math.min(hz, 0.2 * fs) / fs);
    return this.coef;
  }

  // The chip is stepped OVERSAMPLE times per output sample and averaged, then
  // goes through the C64's output stage: ~16 kHz lowpass, ~16 Hz DC block.
  render(out, offset, length) {
    const step = this.cyclesPerSample / OVERSAMPLE;
    for (let i = 0; i < length; i++) {
      let sum = 0;
      for (let s = 0; s < OVERSAMPLE; s++) {
        this.cycleFrac += step;
        const whole = this.cycleFrac | 0;
        this.cycleFrac -= whole;
        this.clock(whole);
        sum += this.output();
      }
      const x = sum / OVERSAMPLE;
      this.hp += this.hpCoef * (x - this.hp);
      out[offset + i] = Math.tanh((x - this.hp) * OUTPUT_GAIN);
    }
  }

  skip(samples) {
    const cycles = this.cyclesPerSample * samples;
    this.clock(cycles);
  }
}
