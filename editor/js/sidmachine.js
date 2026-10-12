// Runs editor/player.bin and clocks a SID chip from the registers it writes.
// The image is the same bytes the menu loads at SID_LOAD.

const SID_INIT = SID_LOAD;
const SID_PLAY = SID_LOAD + 3;

class SidMachine {
  constructor(sampleRate) {
    this.cpu = new CPU6502();
    this.sid = new SidChip(sampleRate);
    this.cpu.sidWrite = (reg, val) => this.sid.write(reg, val);
    // SidChip models the 8580 filter, so the player's chip check must see one.
    this.cpu.sidRead = () => 0xff;
    this.sampleRate = this.sid.sampleRate;
    this.samplesPerFrame = this.sampleRate / 50;
    this.sampleDebt = 0;
    this.frame = 0;
  }

  load(image) {
    this.cpu.mem.fill(0);
    this.cpu.mem.set(image, SID_LOAD);
    this.cpu.reset();
    this.sid.reset();
    this.cpu.call(SID_INIT);
    this.frame = 0;
    this.sampleDebt = 0;
  }

  playFrame() {
    this.cpu.call(SID_PLAY);
    this.frame++;
  }

  seek(frames) {
    for (let i = 0; i < frames; i++) {
      this.playFrame();
      this.sid.skip(this.samplesPerFrame);
    }
  }

  fill(out) {
    let i = 0;
    while (i < out.length) {
      if (this.sampleDebt <= 0) {
        this.playFrame();
        this.sampleDebt += this.samplesPerFrame;
      }
      const n = Math.min(out.length - i, Math.ceil(this.sampleDebt));
      this.sid.render(out, i, n);
      this.sampleDebt -= n;
      i += n;
    }
  }
}
