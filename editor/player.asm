; Menu SID player. Loaded at $5000, init $5000, play $5003, 50 Hz.
; Three voices. Streams, the drum kit, and instrument images are appended by
; the editor and pointed at by the header. Zero page is only $E0-$E5.
; Exactly one STA $D418 (filter mode in the high nibble, volume in the low).
; genmusic appends its 13-byte volume stub, so this image must end by $7FF2.
;
; Instruments are SID-Wizard 1.5 images and play the way its player does:
; hard restart in the gate-off frames before a note, frame-1 waveform, the
; waveform/arp table at the instrument's arp speed, calculated vibrato, and
; the pulse and filter tables.
;
; Melodic stream:
;   $00        end
;   $01-$7F    rest for that many frames
;   $80-$EF    SW note (MIDI note - 11) in bits 0-6, then (gate-1)<<4 | gap
;   $F0        gate frames, gap frames, SW note
; Percussion stream (header flag bit 0):
;   $00        end
;   $FE, n     silence for n frames
;   slot, n    hit kit slot 1-51, then wait n frames (n = 0 ends after this hit)
; Kit entry (5 bytes): SW note, instrument start lo/hi, instrument end lo/hi.

!cpu 6510
*= $5000

player_base
	jmp init
	jmp play

hdr_vptr_lo	!byte 0, 0, 0
hdr_vptr_hi	!byte 0, 0, 0
hdr_vend_lo	!byte 0, 0, 0
hdr_vend_hi	!byte 0, 0, 0
hdr_iptr_lo	!byte 0, 0, 0
hdr_iptr_hi	!byte 0, 0, 0
hdr_iend_lo	!byte 0, 0, 0
hdr_iend_hi	!byte 0, 0, 0
hdr_flags	!byte 0, 0, 0
hdr_kit_lo	!byte 0
hdr_kit_hi	!byte 0

Z_LO	= $e0
Z_HI	= $e1
Z_A	= $e2
Z_B	= $e3
Z_C	= $e4
Z_D	= $e5

; ---- init / play -------------------------------------------------------

!zone init
init
	jsr detect_chip
	jsr reset_pos
	ldy #$18
	lda #0
.clr	sta $d400, y
	dey
	bpl .clr
	ldx #2
.v	lda #0
	sta pw_lo, x
	sta ctrl, x
	sta det, x
	sta pw_kbd, x
	lda #$08
	sta pw_hi, x
	dex
	bpl .v
	lda #$0f
	sta vol_byte
	lda #0
	sta played
	sta filt_cut_lo
	sta filt_cut_hi
	sta filt_res
	sta filt_mode
	sta filt_route
	sta filt_kbd
	lda #$ff
	sta filt_owner
	rts

; The presets were made on an 8580. Voice 3 saw+triangle reads back $80 or
; more on an 8580 and stays low on a 6581; one oscillator period after the
; test bit is about 4096 cycles, and this loop samples ~6600.
!zone detect_chip
detect_chip
	lda #0
	sta $d40e
	lda #$10
	sta $d40f
	lda #$08
	sta $d412
	lda #$30
	sta $d412
	ldx #0
	ldy #2
.rd	lda $d41b
	bmi .is8580
	inx
	bne .rd
	dey
	bne .rd
	lda #1
	bne .set
.is8580	lda #0
.set	sta is6581
	rts

!zone play
play
	jsr maybe_loop
	ldx #0
.v	jsr one_voice
	inx
	cpx #3
	bne .v
	jsr write_filter
	lda vol_byte
	sta $d418
	rts

!zone maybe_loop
maybe_loop
	ldx #2
.ck	lda ended, x
	beq .no
	dex
	bpl .ck
	lda played
	beq .no
	jsr reset_pos
.no	rts

!zone reset_pos
reset_pos
	ldx #2
.rp	lda hdr_vptr_lo, x
	sta pos_lo, x
	lda hdr_vptr_hi, x
	sta pos_hi, x
	lda hdr_vend_lo, x
	sta end_lo, x
	lda hdr_vend_hi, x
	sta end_hi, x
	lda hdr_iptr_lo, x
	sta ins_lo, x
	lda hdr_iptr_hi, x
	sta ins_hi, x
	lda hdr_iend_lo, x
	sta iend_lo, x
	lda hdr_iend_hi, x
	sta iend_hi, x
	lda hdr_flags, x
	sta flags, x
	lda #0
	sta timer, x
	sta ended, x
	sta gate, x
	sta post, x
	sta tie, x
	sta live, x
	sta first, x
	sta hrnow, x
	dex
	bpl .rp
	rts

; ---- one voice ---------------------------------------------------------

!zone one_voice
one_voice
	lda #0
	sta hrnow, x
	lda ended, x
	beq .live
	lda #0
	sta gate, x
	jmp .tick
.live	lda timer, x
	beq .fetch
	dec timer, x
	bne .run
	lda post, x
	beq .fetch
	sta timer, x
	lda #0
	sta post, x
	sta gate, x
	jmp .run
.fetch	lda flags, x
	and #1
	beq .mel
	jsr fetch_perc
	jmp .run
.mel	jsr fetch_mel
.run	jsr hard_restart
.tick	lda live, x
	beq .emit
	lda first, x
	beq .cont
	lda #0
	sta first, x
	jmp .emit
.cont	jsr vibrato
	jsr tick_fi
	jsr tick_pw
	lda hrnow, x
	bne .emit
	jsr tick_wf
.emit	jmp emit_voice

; Hard restart: during the last HR-timer frames of a rest or gap that ends in
; a new note, gate stays off with the instrument's HR ADSR (and the test bit
; if control bit 2 is set), so the envelope is empty when the note starts.
!zone hard_restart
hard_restart
	lda ended, x
	bne .no
	lda gate, x
	bne .no
	lda post, x
	bne .no
	lda live, x
	beq .no
	lda ctrl_b, x
	and #3
	beq .no
	cmp timer, x
	bcc .no
	jsr peek_note
	bcc .no
	lda #1
	sta hrnow, x
	ldy #1
	jsr ins_byte
	sta ad_o, x
	ldy #2
	jsr ins_byte
	sta sr_o, x
	lda ctrl_b, x
	and #4
	beq .no
	lda #$18
	sta ctrl, x
.no	rts

; Carry set if the next stream event starts a note.
!zone peek_note
peek_note
	lda pos_lo, x
	cmp end_lo, x
	lda pos_hi, x
	sbc end_hi, x
	bcs .no
	lda pos_lo, x
	sta Z_LO
	lda pos_hi, x
	sta Z_HI
	ldy #0
	lda (Z_LO), y
	beq .no
	sta Z_A
	lda flags, x
	lsr
	lda Z_A
	bcs .perc
	cmp #$80
	rts
.perc	cmp #$fe
	beq .no
	sec
	rts
.no	clc
	rts

!zone fetch_mel
fetch_mel
	jsr read_byte
	bcs voice_end
	cmp #0
	beq voice_end
	bpl .rest
	cmp #$f0
	bcs .ext
	and #$7f
	sta note, x
	jsr read_byte
	bcs voice_end
	sta Z_A
	lsr
	lsr
	lsr
	lsr
	clc
	adc #1
	sta timer, x
	lda Z_A
	and #$0f
	sta post, x
	jmp .attack
.ext	jsr read_byte
	bcs voice_end
	sta timer, x
	jsr read_byte
	bcs voice_end
	sta post, x
	jsr read_byte
	bcs voice_end
	sta note, x
.attack	lda tie, x
	bne .leg
	jsr trigger
	jmp .tie
.leg	lda #1
	sta gate, x
	lda note, x
	jsr set_freq
.tie	lda post, x
	bne .cut
	lda #1
	sta tie, x
	rts
.cut	lda #0
	sta tie, x
	rts
.rest	sta timer, x
	lda #0
	sta gate, x
	sta tie, x
	rts

voice_end
	lda #1
	sta ended, x
	lda #0
	sta gate, x
	rts

!zone fetch_perc
fetch_perc
	jsr read_byte
	bcs voice_end
	cmp #0
	beq voice_end
	cmp #$fe
	beq .gap
	jsr kit_slot
	jsr trigger
	jsr read_byte
	bcs voice_end
	cmp #0
	beq .last
	sta timer, x
	rts
.last	lda #1
	sta timer, x
	sta ended, x
	rts
.gap	jsr read_byte
	bcs voice_end
	cmp #0
	bne .gapd
	lda #1
.gapd	sta timer, x
	lda #0
	sta gate, x
	rts

; A = kit slot 1-51. Loads the hit's note and instrument for voice X.
!zone kit_slot
kit_slot
	sec
	sbc #1
	sta Z_A
	asl
	asl
	adc Z_A
	tay
	lda hdr_kit_lo
	sta Z_LO
	lda hdr_kit_hi
	sta Z_HI
	lda (Z_LO), y
	sta note, x
	iny
	lda (Z_LO), y
	sta ins_lo, x
	iny
	lda (Z_LO), y
	sta ins_hi, x
	iny
	lda (Z_LO), y
	sta iend_lo, x
	iny
	lda (Z_LO), y
	sta iend_hi, x
	rts

; ---- instrument --------------------------------------------------------

; Note start (SID-Wizard STRTSND). Tables run from the next frame.
!zone trigger
trigger
	lda #1
	sta played
	sta gate, x
	sta live, x
	sta first, x
	lda #0
	sta arp_cnt, x
	lda #$10
	sta wf_pos, x
	ldy #7
	jsr ins_byte
	and #$3f
	sta arp_spd, x
	ldy #0
	jsr ins_byte
	sta ctrl_b, x
	and #$30
	sta vib_type, x
	ldy #6
	jsr ins_byte
	sta vib_del, x
	ldy #5
	jsr ins_byte
	jsr set_vib
	lda ctrl_b, x
	and #$40
	bne .keeppw
	ldy #10
	jsr ins_byte
	sta pw_pos, x
	lda #0
	sta pw_sw, x
.keeppw	lda ctrl_b, x
	bmi .keepfi
	jsr filter_reset
.keepfi	ldy #4
	jsr ins_byte
	sta sr_o, x
	ldy #3
	jsr ins_byte
	sta ad_o, x
	lda ctrl_b, x
	and #8
	beq .nof1
	ldy #15
	jsr ins_byte
	sta ctrl, x
	jmp .freq
.nof1	lda ctrl, x
	and #$fe
	sta ctrl, x
.freq	lda note, x
	jmp set_freq

; First filter-table row: $00 = filtered, $FF = not filtered, anything else
; = filtered and this voice runs the filter program.
!zone filter_reset
filter_reset
	ldy #11
	jsr ins_byte
	cmp #$10
	bcc .off
	tay
	jsr ins_byte
	beq .on
	cmp #$ff
	beq .off
	stx filt_owner
	tya
	sta fi_pos, x
	lda #0
	sta fi_sw, x
.on	lda route_bit, x
	ora filt_route
	sta filt_route
	rts
.off	cpx filt_owner
	bne .unroute
	lda #$ff
	sta filt_owner
.unroute
	lda route_bit, x
	eor #$ff
	and filt_route
	sta filt_route
	rts

; A = vibrato byte (amplitude nibble, speed nibble). Amplitude is scaled by
; the note through the exponent table, as with SID-Wizard's calculated vibrato.
!zone set_vib
set_vib
	pha
	and #$0f
	asl
	sta vib_frq, x
	lsr
	ldy vib_type, x
	cpy #$20
	bcs .half
	lsr
.half	cpy #$30
	bne .cnt
	lda #0
.cnt	sta vib_cnt, x
	pla
	and #$f0
	lsr
	beq .zero
	lsr
	clc
	adc note, x
	bcs .max
	cmp #202
	bcc .look
.max	lda #202
.look	tay
	cpy #107
	bcs .big
	lda exptab, y
	sta vmod_lo, x
	lda #0
	sta vmod_hi, x
	rts
.big	lda freq_lo - 107, y
	sta vmod_lo, x
	lda freq_hi - 107, y
	sta vmod_hi, x
	rts
.zero	sta vmod_lo, x
	sta vmod_hi, x
	rts

; Type $00 grows the amplitude by the delay byte each frame; the others wait
; delay+1 frames. The pitch then ramps by vmod per frame, reversing every
; speed frames.
!zone vibrato
vibrato
	lda vib_type, x
	bne .norm
	lda vmod_lo, x
	clc
	adc vib_del, x
	sta vmod_lo, x
	bcc .do
	inc vmod_hi, x
	jmp .do
.norm	lda vib_del, x
	bmi .do
	dec vib_del, x
	rts
.do	lda vib_cnt, x
	bne .dec
	lda vib_frq, x
.dec	sec
	sbc #1
	sta vib_cnt, x
	asl
	cmp vib_frq, x
	bcc .add
	lda flo, x
	sbc vmod_lo, x
	sta flo, x
	lda fhi, x
	sbc vmod_hi, x
	sta fhi, x
	rts
.add	lda flo, x
	adc vmod_lo, x
	sta flo, x
	lda fhi, x
	adc vmod_hi, x
	sta fhi, x
	rts

; A = note. Sets the voice pitch from the SID-Wizard frequency table.
!zone set_freq
set_freq
	and #$7f
	cmp #96
	bcc .ok
	lda #95
.ok	tay
	lda freq_lo, y
	sta flo, x
	lda freq_hi, y
	sta fhi, x
	rts

; Waveform/arp table, rows of waveform, arp, detune. $00-$0F in the waveform
; column holds the row that many extra frames; $FE jumps; $FF ends.
!zone tick_wf
tick_wf
	dec arp_cnt, x
	bpl .no
	lda arp_spd, x
	sta arp_cnt, x
	ldy wf_pos, x
	jsr ins_byte
	cmp #$fe
	beq .jump
	bcs .no
	cmp #$10
	bcs .wave
	sta arp_cnt, x
	jmp .arp
.jump	iny
	jsr ins_byte
	bmi .no
	sta wf_pos, x
	tay
	jsr ins_byte
.wave	sta ctrl, x
.arp	iny
	jsr ins_byte
	sta Z_A
	iny
	jsr ins_byte
	cmp #$ff
	beq .keepdt
	sta det, x
.keepdt	lda Z_A
	cmp #$7f
	beq .chord
	iny
	tya
	sta wf_pos, x
	lda Z_A
	bpl .rel
	cmp #$80
	beq .no
	cmp #$e0
	bcc .abs
.rel	clc
	adc note, x
.abs	jmp set_freq
.chord	lda note, x
	jmp set_freq
.no	rts

; Pulse table, rows of (hi nibble | $80, lo) or (sweep count, signed step).
!zone tick_pw
tick_pw
	ldy pw_pos, x
	jsr ins_byte
	cmp #$80
	bcs .cmd
	iny
	cmp pw_sw, x
	beq .adv
	inc pw_sw, x
	jsr ins_byte
	sta Z_A
	clc
	adc pw_lo, x
	sta pw_lo, x
	lda Z_A
	bpl .up
	lda #$ff
	bmi .add
.up	lda #0
.add	adc pw_hi, x
	sta pw_hi, x
	rts
.cmd	cmp #$fe
	beq .jump
	bcs .no
.set	and #$7f
	sta pw_hi, x
	iny
	jsr ins_byte
	sta pw_lo, x
.adv	iny
	jsr ins_byte
	sta pw_kbd, x
	iny
	tya
	sta pw_pos, x
	lda #0
	sta pw_sw, x
.no	rts
.jump	iny
	jsr ins_byte
	cmp pw_pos, x
	beq .no
	tay
	jsr ins_byte
	bmi .set
	tya
	sta pw_pos, x
	lda #0
	sta pw_sw, x
	rts

; Filter table, run by the owning voice only. Rows of (band | resonance |
; $80, cutoff hi) or (sweep count, signed step); a third column of $80-$8F
; sets which voices go through the filter.
!zone tick_fi
tick_fi
	cpx filt_owner
	bne .no
	ldy fi_pos, x
	jsr ins_byte
	cmp #$80
	bcs .cmd
	iny
	cmp fi_sw, x
	beq .adv
	inc fi_sw, x
	jmp fi_sweep
.cmd	cmp #$fe
	beq .jump
	bcs .no
.set	sta Z_A
	and #$70
	sta filt_mode
	lda Z_A
	asl
	asl
	asl
	asl
	sta filt_res
	iny
	jsr ins_byte
	sta Z_A
	lda #0
	sta filt_cut_hi
	lda Z_A
	asl
	rol filt_cut_hi
	asl
	rol filt_cut_hi
	asl
	rol filt_cut_hi
	sta filt_cut_lo
.adv	iny
	jsr ins_byte
	cmp #$80
	bcc .kbd
	cmp #$90
	bcs .kbd
	and #$0f
	sta filt_route
	lda #0
.kbd	sta filt_kbd
	iny
	tya
	sta fi_pos, x
	lda #0
	sta fi_sw, x
.no	rts
.jump	iny
	jsr ins_byte
	cmp fi_pos, x
	beq .no
	tay
	jsr ins_byte
	bmi .set
	tya
	sta fi_pos, x
	lda #0
	sta fi_sw, x
	rts

; Y = offset of the signed step. Cutoff is 11 bits, clamped to 0-$7FF.
!zone fi_sweep
fi_sweep
	jsr ins_byte
	sta Z_A
	lda filt_cut_lo
	clc
	adc Z_A
	sta filt_cut_lo
	lda Z_A
	bpl .fhi
	lda #$ff
	bmi .fadd
.fhi	lda #0
.fadd	adc filt_cut_hi
	bmi .zero
	cmp #8
	bcc .keep
	lda #$ff
	sta filt_cut_lo
	lda #7
	bne .keep
.zero	lda #0
	sta filt_cut_lo
.keep	sta filt_cut_hi
	rts

; ---- SID writes --------------------------------------------------------

!zone emit_voice
emit_voice
	lda pw_hi, x
	ldy pw_kbd, x
	beq .pw
	bmi .pw
	sta Z_B
	tya
	clc
	adc note, x
	jsr exp_of
	sec
	sbc exptab - 1, y
	clc
	adc Z_B
.pw	and #$0f
	sta Z_B
	ldy sid_off, x
	lda flo, x
	clc
	adc det, x
	sta $d400, y
	lda fhi, x
	adc #0
	sta $d401, y
	lda pw_lo, x
	sta $d402, y
	lda Z_B
	sta $d403, y
	lda ad_o, x
	sta $d405, y
	lda sr_o, x
	sta $d406, y
	lda ctrl, x
	ldy gate, x
	bne .gated
	and #$fe
.gated	ldy is6581
	beq .write
	sta Z_A
	lsr
	lsr
	lsr
	lsr
	tay
	lda Z_A
	and #$0f
	ora wave6581, y
.write	ldy sid_off, x
	sta $d404, y
	rts

!zone write_filter
write_filter
	lda filt_cut_lo
	and #$07
	sta $d415
	lda filt_cut_hi
	sta Z_A
	lda filt_cut_lo
	lsr Z_A
	ror
	lsr Z_A
	ror
	lsr Z_A
	ror
	ldy filt_kbd
	beq .cut
	bmi .cut
	sta Z_A
	ldx filt_owner
	bmi .cut
	tya
	clc
	adc note, x
	jsr exp_of
	clc
	adc Z_A
	bcc .cut
	lda #$ff
.cut	ldy is6581
	beq .write
	tay
	lda cut6581, y
.write	sta $d416
	lda filt_res
	ora filt_route
	sta $d417
	lda vol_byte
	and #$0f
	ora filt_mode
	sta vol_byte
	rts

; A = keyboard-track amount + note, carry set if that overflowed. Returns
; Y = clamped index and A = exptab[Y].
!zone exp_of
exp_of
	bcs .top
	cmp #107
	bcc .ok
.top	lda #106
.ok	tay
	lda exptab, y
	rts

; Y = offset. Returns A, Y unchanged. $FF if the offset is past the image.
!zone ins_byte
ins_byte
	sty Z_C
	sec
	lda iend_lo, x
	sbc ins_lo, x
	cmp Z_C
	beq .bad
	bcc .bad
	lda ins_lo, x
	sta Z_LO
	lda ins_hi, x
	sta Z_HI
	lda (Z_LO), y
	rts
.bad	lda #$ff
	rts

; Carry set if the stream is exhausted. Otherwise A = byte, pointer advanced.
!zone read_byte
read_byte
	lda pos_lo, x
	cmp end_lo, x
	lda pos_hi, x
	sbc end_hi, x
	bcs .eof
	lda pos_lo, x
	sta Z_LO
	lda pos_hi, x
	sta Z_HI
	ldy #0
	lda (Z_LO), y
	inc pos_lo, x
	bne .ok
	inc pos_hi, x
.ok	clc
	rts
.eof	sec
	rts

sid_off		!byte 0, 7, 14
route_bit	!byte 1, 2, 4

; SID-Wizard tables. exptab runs straight into freq_hi (11 zeros, then the
; 96 hi bytes), the calculated-vibrato lookup for indexes below 107.
freq_lo	!byte $07, $16, $27, $38, $4b, $5e, $73, $89, $a1, $ba, $d4, $f0
	!byte $0d, $2c, $4e, $71, $96, $bd, $e7, $13, $42, $74, $a8, $e0
	!byte $1b, $59, $9c, $e2, $2c, $7b, $ce, $27, $84, $e8, $51, $c0
	!byte $36, $b3, $38, $c4, $59, $f6, $9d, $4e, $09, $d0, $a2, $81
	!byte $6d, $67, $70, $88, $b2, $ed, $3a, $9c, $13, $a0, $44, $02
	!byte $da, $ce, $e0, $11, $64, $da, $75, $38, $26, $40, $89, $04
	!byte $b4, $9c, $c0, $22, $c8, $b4, $eb, $71, $4c, $80, $12, $08
	!byte $68, $38, $80, $45, $90, $68, $d6, $e3, $98, $00, $24, $10
exptab	!fill 11, 0
freq_hi	!byte $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	!byte $02, $02, $02, $02, $02, $02, $02, $03, $03, $03, $03, $03
	!byte $04, $04, $04, $04, $05, $05, $05, $06, $06, $06, $07, $07
	!byte $08, $08, $09, $09, $0a, $0a, $0b, $0c, $0d, $0d, $0e, $0f
	!byte $10, $11, $12, $13, $14, $15, $17, $18, $1a, $1b, $1d, $1f
	!byte $20, $22, $24, $27, $29, $2b, $2e, $31, $34, $37, $3a, $3e
	!byte $41, $45, $49, $4e, $52, $57, $5c, $62, $68, $6e, $75, $7c
	!byte $83, $8b, $93, $9c, $a5, $af, $b9, $c4, $d0, $dd, $ea, $f8

; 6581 stand-ins. Combined waveforms are near silent on a 6581, so any mix of
; triangle, saw and pulse plays as saw. Cutoff moves halfway (in register
; steps) toward the 6581 value with the 8580's -6 dB point, measured in
; reSIDfp; the full move overshoots resonant patches.
wave6581	!byte $00, $10, $20, $20, $40, $20, $20, $20, $80, $90, $a0, $b0, $c0, $d0, $e0, $f0
cut6581	!byte $00, $00, $01, $02, $02, $02, $0a, $0e, $10, $13, $15, $16, $18, $1a, $1b, $1c
	!byte $1e, $1f, $20, $21, $22, $24, $24, $26, $26, $28, $28, $2a, $2a, $2b, $2c, $2d
	!byte $2e, $2f, $30, $30, $32, $32, $33, $34, $34, $36, $36, $37, $38, $38, $3a, $3a
	!byte $3b, $3c, $3c, $3e, $3e, $3f, $40, $40, $41, $42, $42, $44, $44, $45, $46, $46
	!byte $47, $48, $48, $4a, $4a, $4b, $4c, $4c, $4d, $4e, $4e, $4f, $50, $50, $51, $52
	!byte $52, $54, $54, $55, $56, $56, $57, $58, $58, $59, $5a, $5a, $5b, $5c, $5c, $5d
	!byte $5e, $5e, $5f, $60, $60, $62, $62, $62, $64, $64, $65, $66, $66, $67, $68, $68
	!byte $69, $6a, $6a, $6b, $6c, $6c, $6d, $6e, $6e, $6f, $70, $70, $71, $72, $72, $73
	!byte $74, $74, $76, $76, $76, $78, $78, $78, $7a, $7a, $7b, $7c, $7c, $7d, $7e, $7e
	!byte $7f, $80, $80, $81, $82, $82, $83, $84, $84, $85, $86, $86, $88, $88, $89, $8a
	!byte $8a, $8b, $8c, $8c, $8d, $8e, $8e, $8f, $90, $90, $92, $92, $93, $94, $94, $95
	!byte $96, $96, $97, $98, $98, $9a, $9a, $9b, $9c, $9c, $9d, $9e, $9e, $a0, $a0, $a1
	!byte $a2, $a2, $a3, $a4, $a5, $a6, $a6, $a7, $a8, $a8, $aa, $aa, $ab, $ac, $ad, $ae
	!byte $ae, $af, $b0, $b1, $b2, $b2, $b4, $b4, $b5, $b6, $b7, $b8, $b8, $ba, $ba, $bb
	!byte $bc, $bd, $be, $be, $c0, $c0, $c2, $c2, $c3, $c4, $c5, $c6, $c6, $c8, $c8, $ca
	!byte $ca, $cb, $cc, $cd, $ce, $ce, $d0, $d0, $d1, $d2, $d3, $d4, $d4, $d6, $d6, $d7

pos_lo	!byte 0, 0, 0
pos_hi	!byte 0, 0, 0
end_lo	!byte 0, 0, 0
end_hi	!byte 0, 0, 0
ins_lo	!byte 0, 0, 0
ins_hi	!byte 0, 0, 0
iend_lo	!byte 0, 0, 0
iend_hi	!byte 0, 0, 0
flags	!byte 0, 0, 0
timer	!byte 0, 0, 0
ended	!byte 0, 0, 0
gate	!byte 0, 0, 0
note	!byte 0, 0, 0
post	!byte 0, 0, 0
tie	!byte 0, 0, 0
live	!byte 0, 0, 0
first	!byte 0, 0, 0
hrnow	!byte 0, 0, 0
wf_pos	!byte 0, 0, 0
pw_pos	!byte 0, 0, 0
fi_pos	!byte 0, 0, 0
pw_lo	!byte 0, 0, 0
pw_hi	!byte 0, 0, 0
pw_sw	!byte 0, 0, 0
pw_kbd	!byte 0, 0, 0
fi_sw	!byte 0, 0, 0
ctrl	!byte 0, 0, 0
ctrl_b	!byte 0, 0, 0
det	!byte 0, 0, 0
arp_cnt	!byte 0, 0, 0
arp_spd	!byte 0, 0, 0
ad_o	!byte 0, 0, 0
sr_o	!byte 0, 0, 0
flo	!byte 0, 0, 0
fhi	!byte 0, 0, 0
vib_type !byte 0, 0, 0
vib_del	!byte 0, 0, 0
vib_frq	!byte 0, 0, 0
vib_cnt	!byte 0, 0, 0
vmod_lo	!byte 0, 0, 0
vmod_hi	!byte 0, 0, 0

played		!byte 0
is6581		!byte 0
filt_owner	!byte $ff
filt_cut_lo	!byte 0
filt_cut_hi	!byte 0
filt_res	!byte 0
filt_mode	!byte 0
filt_route	!byte 0
filt_kbd	!byte 0
vol_byte	!byte $0f
