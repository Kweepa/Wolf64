; Sound effects — Wolf PC-speaker envelopes on SID noise (pcsfreq_*).
; Data: pcsounds.asm + pcsfreq.asm (tools/gensounds.py from AUDIOT.WL1).
; Decimated 3x; stepped once per CIA1 Timer A IRQ (~50 Hz).

!zone playsound

SFX_VOL		= $0f

; ------------------------------------------------------------------
; play_sound_init — clear SID; voice 3 ready; master volume on
; ------------------------------------------------------------------
play_sound_init
	lda #$ff
	sta sound_index
	lda #0
	sta sound_priority
	sta sound_count
	sta sound_max
	ldx #$18
	lda #0
.psi_clr
	sta $d400,x
	dex
	bpl .psi_clr
	jsr sfx_voice3_adsr
	lda #SFX_VOL
	sta $d418
	rts

sfx_voice3_adsr
	lda #$00
	sta $d413				; AD: instant
	lda #$f0
	sta $d414				; SR: full sustain, fast release
	rts

; ------------------------------------------------------------------
; play_sound — A = sound index; higher-or-equal priority preempts
; Queue-only: no SID access (safe at $01=$34); the Timer A IRQ
; (update_sfx) does all SID writes, starting on the next tick.
; Preserves X,Y and caller's I flag; A clobbered
; ------------------------------------------------------------------
play_sound
	php
	sei
	stx ps_save_x
	sty ps_save_y
	tax
	lda sound_priorities,x
	cmp sound_priority
	bcc .ps_skip

	sta sound_priority

	txa
	asl
	tay
	lda sound_table,y
	sta sound_ptr_l
	lda sound_table+1,y
	sta sound_ptr_h
	ldy #0
	lda (sound_ptr_l),y
	tay
	iny
	sty sound_max
	lda #0
	sta sound_count

	stx sound_index
.ps_skip
	ldx ps_save_x
	ldy ps_save_y
	plp
	rts

; ------------------------------------------------------------------
; update_sfx — one PC speaker sample per call (~50 Hz Timer A)
; Must not touch tmp0–tmp5 / other main-thread ZP. Voice 3 only.
; ------------------------------------------------------------------
update_sfx
	lda sound_index
	bmi .sfx_idle

	inc sound_count
	ldy sound_count
	cpy sound_max
	beq .sfx_stop
	lda (sound_ptr_l),y
	beq .sfx_silent
	tax
	jsr sfx_voice3_adsr
	lda pcsfreq_lo,x
	sta $d40e
	lda pcsfreq_hi,x
	sta $d40f
	lda #$81				; noise + gate
	sta $d412
	rts

.sfx_silent
	lda #0
	sta $d412
	rts

.sfx_stop
	lda #0
	sta $d412
	lda #$ff
	sta sound_index
	lda #0
	sta sound_priority
	lda #SFX_VOL
	sta $d418
.sfx_idle
	rts

; ------------------------------------------------------------------
; sfx_reloc — copy load image at BITMAP → SFX_BASE (before fill_bitmap)
; ------------------------------------------------------------------
sfx_reloc
	lda #<BITMAP
	sta tmp0
	lda #>BITMAP
	sta tmp1
	lda #<SFX_BASE
	sta tmp2
	lda #>SFX_BASE
	sta tmp3
	lda #<(sfx_load_end - BITMAP)
	sta tmp4
	lda #>(sfx_load_end - BITMAP)
	sta tmp5
	ldy #0
.sr_lp
	lda tmp4
	ora tmp5
	beq .sr_done
	lda (tmp0),y
	sta (tmp2),y
	iny
	bne .sr_dec
	inc tmp1
	inc tmp3
.sr_dec
	lda tmp4
	bne .sr_lo
	dec tmp5
.sr_lo
	dec tmp4
	jmp .sr_lp
.sr_done
	rts

; BSS (kept with player code; IRQ-safe scrap)
sound_priority	!byte 0
sound_count	!byte 0
sound_max	!byte 0
ps_save_x	!byte 0
ps_save_y	!byte 0
