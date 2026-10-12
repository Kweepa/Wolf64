// Enough of a 6510 to run editor/player.bin. RAM is a flat 64K.
// Writes to $D400–$D418 are also reported to the SID chip.

class CPU6502 {
  constructor() {
    this.mem = new Uint8Array(65536);
    this.a = 0;
    this.x = 0;
    this.y = 0;
    this.sp = 0xff;
    this.pc = 0;
    this.p = 0x20;
    this.sidWrite = null;
    this.sidRead = null;
  }

  reset() {
    this.a = this.x = this.y = 0;
    this.sp = 0xff;
    this.p = 0x20;
    this.pc = 0;
  }

  zn(v) {
    this.p = (this.p & ~0x82) | (v & 0x80) | (v === 0 ? 2 : 0);
  }

  push(v) {
    this.mem[0x100 + this.sp] = v;
    this.sp = (this.sp - 1) & 255;
  }

  pop() {
    this.sp = (this.sp + 1) & 255;
    return this.mem[0x100 + this.sp];
  }

  read(addr) {
    addr &= 0xffff;
    if (addr === 0xd41b && this.sidRead) return this.sidRead(addr);
    return this.mem[addr];
  }

  write(addr, val) {
    addr &= 0xffff;
    val &= 255;
    this.mem[addr] = val;
    if (addr >= 0xd400 && addr <= 0xd418 && this.sidWrite) this.sidWrite(addr & 0x1f, val);
  }

  wordAt(pc) {
    return this.mem[pc] | (this.mem[(pc + 1) & 0xffff] << 8);
  }

  fetchWord() {
    const w = this.wordAt(this.pc);
    this.pc = (this.pc + 2) & 0xffff;
    return w;
  }

  zpAddr(index) {
    return (this.mem[this.pc++] + index) & 255;
  }

  absAddr(index) {
    return (this.fetchWord() + index) & 0xffff;
  }

  indYAddr() {
    const zp = this.mem[this.pc++];
    const base = this.mem[zp] | (this.mem[(zp + 1) & 255] << 8);
    return (base + this.y) & 0xffff;
  }

  indXAddr() {
    const zp = (this.mem[this.pc++] + this.x) & 255;
    return this.mem[zp] | (this.mem[(zp + 1) & 255] << 8);
  }

  setC(on) {
    this.p = (this.p & ~1) | (on ? 1 : 0);
  }

  adc(v) {
    const a = this.a;
    let sum = a + v + (this.p & 1);
    this.setC(sum > 255);
    sum &= 255;
    if (~(a ^ v) & (a ^ sum) & 0x80) this.p |= 0x40;
    else this.p &= ~0x40;
    this.a = sum;
    this.zn(sum);
  }

  sbc(v) {
    this.adc(v ^ 0xff);
  }

  cmp(reg, v) {
    const r = (reg - v) & 0xffff;
    this.setC(reg >= v);
    this.zn(r & 255);
  }

  branch(cond) {
    const off = this.mem[this.pc++];
    if (!cond) return;
    const rel = off < 128 ? off : off - 256;
    this.pc = (this.pc + rel) & 0xffff;
  }

  asl(v) {
    this.setC(v & 0x80);
    const r = (v << 1) & 255;
    this.zn(r);
    return r;
  }

  lsr(v) {
    this.setC(v & 1);
    const r = v >> 1;
    this.zn(r);
    return r;
  }

  rol(v) {
    const r = ((v << 1) | (this.p & 1)) & 255;
    this.setC(v & 0x80);
    this.zn(r);
    return r;
  }

  ror(v) {
    const r = (v >> 1) | ((this.p & 1) << 7);
    this.setC(v & 1);
    this.zn(r);
    return r;
  }

  rmw(addr, fn) {
    const r = fn.call(this, this.read(addr));
    this.write(addr, r);
  }

  step() {
    const op = this.mem[this.pc++];
    switch (op) {
      case 0x00: this.pc = (this.pc + 1) & 0xffff; break;
      case 0x01: { const a = this.indXAddr(); this.a |= this.read(a); this.zn(this.a); break; }
      case 0x05: { const a = this.zpAddr(0); this.a |= this.read(a); this.zn(this.a); break; }
      case 0x06: { const a = this.zpAddr(0); this.rmw(a, this.asl); break; }
      case 0x08: this.push(this.p | 0x30); break;
      case 0x09: this.a |= this.mem[this.pc++]; this.zn(this.a); break;
      case 0x0a: this.a = this.asl(this.a); break;
      case 0x0d: { const a = this.absAddr(0); this.a |= this.read(a); this.zn(this.a); break; }
      case 0x0e: { const a = this.absAddr(0); this.rmw(a, this.asl); break; }

      case 0x10: this.branch((this.p & 0x80) === 0); break;
      case 0x11: { const a = this.indYAddr(); this.a |= this.read(a); this.zn(this.a); break; }
      case 0x15: { const a = this.zpAddr(this.x); this.a |= this.read(a); this.zn(this.a); break; }
      case 0x16: { const a = this.zpAddr(this.x); this.rmw(a, this.asl); break; }
      case 0x18: this.setC(false); break;
      case 0x19: { const a = this.absAddr(this.y); this.a |= this.read(a); this.zn(this.a); break; }
      case 0x1d: { const a = this.absAddr(this.x); this.a |= this.read(a); this.zn(this.a); break; }
      case 0x1e: { const a = this.absAddr(this.x); this.rmw(a, this.asl); break; }

      case 0x20: {
        const addr = this.fetchWord();
        const ret = (this.pc - 1) & 0xffff;
        this.push(ret >> 8);
        this.push(ret & 255);
        this.pc = addr;
        break;
      }
      case 0x21: { const a = this.indXAddr(); this.a &= this.read(a); this.zn(this.a); break; }
      case 0x24: { const v = this.read(this.zpAddr(0)); this.p = (this.p & ~0xc2) | (v & 0xc0) | ((this.a & v) === 0 ? 2 : 0); break; }
      case 0x25: { const a = this.zpAddr(0); this.a &= this.read(a); this.zn(this.a); break; }
      case 0x26: { const a = this.zpAddr(0); this.rmw(a, this.rol); break; }
      case 0x28: this.p = (this.pop() & ~0x10) | 0x20; break;
      case 0x29: this.a &= this.mem[this.pc++]; this.zn(this.a); break;
      case 0x2a: this.a = this.rol(this.a); break;
      case 0x2c: { const v = this.read(this.absAddr(0)); this.p = (this.p & ~0xc2) | (v & 0xc0) | ((this.a & v) === 0 ? 2 : 0); break; }
      case 0x2d: { const a = this.absAddr(0); this.a &= this.read(a); this.zn(this.a); break; }
      case 0x2e: { const a = this.absAddr(0); this.rmw(a, this.rol); break; }

      case 0x30: this.branch((this.p & 0x80) !== 0); break;
      case 0x31: { const a = this.indYAddr(); this.a &= this.read(a); this.zn(this.a); break; }
      case 0x35: { const a = this.zpAddr(this.x); this.a &= this.read(a); this.zn(this.a); break; }
      case 0x36: { const a = this.zpAddr(this.x); this.rmw(a, this.rol); break; }
      case 0x38: this.setC(true); break;
      case 0x39: { const a = this.absAddr(this.y); this.a &= this.read(a); this.zn(this.a); break; }
      case 0x3d: { const a = this.absAddr(this.x); this.a &= this.read(a); this.zn(this.a); break; }
      case 0x3e: { const a = this.absAddr(this.x); this.rmw(a, this.rol); break; }

      case 0x40: {
        this.p = (this.pop() & ~0x10) | 0x20;
        const lo = this.pop();
        const hi = this.pop();
        this.pc = (hi << 8) | lo;
        break;
      }
      case 0x41: { const a = this.indXAddr(); this.a ^= this.read(a); this.zn(this.a); break; }
      case 0x45: { const a = this.zpAddr(0); this.a ^= this.read(a); this.zn(this.a); break; }
      case 0x46: { const a = this.zpAddr(0); this.rmw(a, this.lsr); break; }
      case 0x48: this.push(this.a); break;
      case 0x49: this.a ^= this.mem[this.pc++]; this.zn(this.a); break;
      case 0x4a: this.a = this.lsr(this.a); break;
      case 0x4c: this.pc = this.fetchWord(); break;
      case 0x4d: { const a = this.absAddr(0); this.a ^= this.read(a); this.zn(this.a); break; }
      case 0x4e: { const a = this.absAddr(0); this.rmw(a, this.lsr); break; }

      case 0x50: this.branch((this.p & 0x40) === 0); break;
      case 0x51: { const a = this.indYAddr(); this.a ^= this.read(a); this.zn(this.a); break; }
      case 0x55: { const a = this.zpAddr(this.x); this.a ^= this.read(a); this.zn(this.a); break; }
      case 0x56: { const a = this.zpAddr(this.x); this.rmw(a, this.lsr); break; }
      case 0x58: this.p &= ~0x04; break;
      case 0x59: { const a = this.absAddr(this.y); this.a ^= this.read(a); this.zn(this.a); break; }
      case 0x5d: { const a = this.absAddr(this.x); this.a ^= this.read(a); this.zn(this.a); break; }
      case 0x5e: { const a = this.absAddr(this.x); this.rmw(a, this.lsr); break; }

      case 0x60: {
        const lo = this.pop();
        const hi = this.pop();
        this.pc = ((hi << 8) | lo) + 1;
        this.pc &= 0xffff;
        break;
      }
      case 0x61: { const a = this.indXAddr(); this.adc(this.read(a)); break; }
      case 0x65: { const a = this.zpAddr(0); this.adc(this.read(a)); break; }
      case 0x66: { const a = this.zpAddr(0); this.rmw(a, this.ror); break; }
      case 0x68: this.a = this.pop(); this.zn(this.a); break;
      case 0x69: this.adc(this.mem[this.pc++]); break;
      case 0x6a: this.a = this.ror(this.a); break;
      case 0x6c: {
        const ptr = this.fetchWord();
        const lo = this.mem[ptr];
        const hiAddr = (ptr & 0xff) === 0xff ? ptr & 0xff00 : ptr + 1;
        const hi = this.mem[hiAddr];
        this.pc = (hi << 8) | lo;
        break;
      }
      case 0x6d: { const a = this.absAddr(0); this.adc(this.read(a)); break; }
      case 0x6e: { const a = this.absAddr(0); this.rmw(a, this.ror); break; }

      case 0x70: this.branch((this.p & 0x40) !== 0); break;
      case 0x71: { const a = this.indYAddr(); this.adc(this.read(a)); break; }
      case 0x75: { const a = this.zpAddr(this.x); this.adc(this.read(a)); break; }
      case 0x76: { const a = this.zpAddr(this.x); this.rmw(a, this.ror); break; }
      case 0x78: this.p |= 0x04; break;
      case 0x79: { const a = this.absAddr(this.y); this.adc(this.read(a)); break; }
      case 0x7d: { const a = this.absAddr(this.x); this.adc(this.read(a)); break; }
      case 0x7e: { const a = this.absAddr(this.x); this.rmw(a, this.ror); break; }

      case 0x81: this.write(this.indXAddr(), this.a); break;
      case 0x84: this.write(this.zpAddr(0), this.y); break;
      case 0x85: this.write(this.zpAddr(0), this.a); break;
      case 0x86: this.write(this.zpAddr(0), this.x); break;
      case 0x88: this.y = (this.y - 1) & 255; this.zn(this.y); break;
      case 0x8a: this.a = this.x; this.zn(this.a); break;
      case 0x8c: this.write(this.absAddr(0), this.y); break;
      case 0x8d: this.write(this.absAddr(0), this.a); break;
      case 0x8e: this.write(this.absAddr(0), this.x); break;

      case 0x90: this.branch((this.p & 1) === 0); break;
      case 0x91: this.write(this.indYAddr(), this.a); break;
      case 0x94: this.write(this.zpAddr(this.x), this.y); break;
      case 0x95: this.write(this.zpAddr(this.x), this.a); break;
      case 0x96: this.write(this.zpAddr(this.y), this.x); break;
      case 0x98: this.a = this.y; this.zn(this.a); break;
      case 0x99: this.write(this.absAddr(this.y), this.a); break;
      case 0x9a: this.sp = this.x; break;
      case 0x9d: this.write(this.absAddr(this.x), this.a); break;

      case 0xa0: this.y = this.mem[this.pc++]; this.zn(this.y); break;
      case 0xa1: this.a = this.read(this.indXAddr()); this.zn(this.a); break;
      case 0xa2: this.x = this.mem[this.pc++]; this.zn(this.x); break;
      case 0xa4: this.y = this.read(this.zpAddr(0)); this.zn(this.y); break;
      case 0xa5: this.a = this.read(this.zpAddr(0)); this.zn(this.a); break;
      case 0xa6: this.x = this.read(this.zpAddr(0)); this.zn(this.x); break;
      case 0xa8: this.y = this.a; this.zn(this.y); break;
      case 0xa9: this.a = this.mem[this.pc++]; this.zn(this.a); break;
      case 0xaa: this.x = this.a; this.zn(this.x); break;
      case 0xac: this.y = this.read(this.absAddr(0)); this.zn(this.y); break;
      case 0xad: this.a = this.read(this.absAddr(0)); this.zn(this.a); break;
      case 0xae: this.x = this.read(this.absAddr(0)); this.zn(this.x); break;

      case 0xb0: this.branch((this.p & 1) !== 0); break;
      case 0xb1: this.a = this.read(this.indYAddr()); this.zn(this.a); break;
      case 0xb4: this.y = this.read(this.zpAddr(this.x)); this.zn(this.y); break;
      case 0xb5: this.a = this.read(this.zpAddr(this.x)); this.zn(this.a); break;
      case 0xb6: this.x = this.read(this.zpAddr(this.y)); this.zn(this.x); break;
      case 0xb8: this.p &= ~0x40; break;
      case 0xb9: this.a = this.read(this.absAddr(this.y)); this.zn(this.a); break;
      case 0xba: this.x = this.sp; this.zn(this.x); break;
      case 0xbc: this.y = this.read(this.absAddr(this.x)); this.zn(this.y); break;
      case 0xbd: this.a = this.read(this.absAddr(this.x)); this.zn(this.a); break;
      case 0xbe: this.x = this.read(this.absAddr(this.y)); this.zn(this.x); break;

      case 0xc0: this.cmp(this.y, this.mem[this.pc++]); break;
      case 0xc1: this.cmp(this.a, this.read(this.indXAddr())); break;
      case 0xc4: this.cmp(this.y, this.read(this.zpAddr(0))); break;
      case 0xc5: this.cmp(this.a, this.read(this.zpAddr(0))); break;
      case 0xc6: { const a = this.zpAddr(0); this.write(a, (this.read(a) - 1) & 255); this.zn(this.mem[a]); break; }
      case 0xc8: this.y = (this.y + 1) & 255; this.zn(this.y); break;
      case 0xc9: this.cmp(this.a, this.mem[this.pc++]); break;
      case 0xca: this.x = (this.x - 1) & 255; this.zn(this.x); break;
      case 0xcc: this.cmp(this.y, this.read(this.absAddr(0))); break;
      case 0xcd: this.cmp(this.a, this.read(this.absAddr(0))); break;
      case 0xce: { const a = this.absAddr(0); this.write(a, (this.read(a) - 1) & 255); this.zn(this.mem[a]); break; }

      case 0xd0: this.branch((this.p & 2) === 0); break;
      case 0xd1: this.cmp(this.a, this.read(this.indYAddr())); break;
      case 0xd5: this.cmp(this.a, this.read(this.zpAddr(this.x))); break;
      case 0xd6: { const a = this.zpAddr(this.x); this.write(a, (this.read(a) - 1) & 255); this.zn(this.mem[a]); break; }
      case 0xd8: this.p &= ~0x08; break;
      case 0xd9: this.cmp(this.a, this.read(this.absAddr(this.y))); break;
      case 0xdd: this.cmp(this.a, this.read(this.absAddr(this.x))); break;
      case 0xde: { const a = this.absAddr(this.x); this.write(a, (this.read(a) - 1) & 255); this.zn(this.mem[a]); break; }

      case 0xe0: this.cmp(this.x, this.mem[this.pc++]); break;
      case 0xe1: this.sbc(this.read(this.indXAddr())); break;
      case 0xe4: this.cmp(this.x, this.read(this.zpAddr(0))); break;
      case 0xe5: this.sbc(this.read(this.zpAddr(0))); break;
      case 0xe6: { const a = this.zpAddr(0); this.write(a, (this.read(a) + 1) & 255); this.zn(this.mem[a]); break; }
      case 0xe8: this.x = (this.x + 1) & 255; this.zn(this.x); break;
      case 0xe9: this.sbc(this.mem[this.pc++]); break;
      case 0xea: break;
      case 0xec: this.cmp(this.x, this.read(this.absAddr(0))); break;
      case 0xed: this.sbc(this.read(this.absAddr(0))); break;
      case 0xee: { const a = this.absAddr(0); this.write(a, (this.read(a) + 1) & 255); this.zn(this.mem[a]); break; }

      case 0xf0: this.branch((this.p & 2) !== 0); break;
      case 0xf1: this.sbc(this.read(this.indYAddr())); break;
      case 0xf5: this.sbc(this.read(this.zpAddr(this.x))); break;
      case 0xf6: { const a = this.zpAddr(this.x); this.write(a, (this.read(a) + 1) & 255); this.zn(this.mem[a]); break; }
      case 0xf8: this.p |= 0x08; break;
      case 0xf9: this.sbc(this.read(this.absAddr(this.y))); break;
      case 0xfd: this.sbc(this.read(this.absAddr(this.x))); break;
      case 0xfe: { const a = this.absAddr(this.x); this.write(a, (this.read(a) + 1) & 255); this.zn(this.mem[a]); break; }

      default:
        throw new Error("unknown opcode $" + op.toString(16) + " at $" + ((this.pc - 1) & 0xffff).toString(16));
    }
  }

  // Run addr until RTS back to the caller. The player's init and play both RTS.
  call(addr) {
    this.push(0x7f);
    this.push(0xff);
    this.pc = addr & 0xffff;
    let n = 0;
    while (this.pc !== 0x8000) {
      this.step();
      if (++n > 250000) {
        throw new Error("player ran too long at $" + this.pc.toString(16));
      }
    }
  }
}
