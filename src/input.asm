; CIA1 Timer A IRQ accumulates hold-ms; read_input scales turn/move (SquareDoom)
!zone input

SAMPLE_MS	= 20
; Timer A load = SAMPLE_MS * 1024 - 1 (binary-ms, φ2 ticks) → 50 Hz
SAMPLE_TA_LO	= <$4FFF
SAMPLE_TA_HI	= >$4FFF

; IRQ accumulates hold times into in_*; read_input snapshots under SEI and
; scales turn/wish by those times (not full-frame dt_ms):
;   turn 90°/sec = 64 angle/sec → turn_acc += vel_ms<<6, deliver >>10
;   move ½ tile/sec = 4 world/sec → delta_8_8 = (sintab * vel_ms) >> 6
; sintab AMP=64; identity: sin=64, dt=1024 → 1024 = 4.0 world.
; W/S move, A/D strafe, J/L turn (SquareDoom bindings).

input_irq_init
	lda #0
	sta in_turn_l
	sta in_turn_r
	sta in_fwd
	sta in_back
	sta in_strafel
	sta in_strafer
	sta in_fire
	sta in_wpn_pistol
	sta in_wpn_chaingun
	sta turn_acc_l
	sta turn_acc_h
	sta $d01a				; no VIC IRQs

	lda #$7f
	sta $dc0d				; clear CIA1 IRQ enables
	lda $dc0d				; ack
	lda #SAMPLE_TA_LO
	sta $dc04
	lda #SAMPLE_TA_HI
	sta $dc05
	lda #<input_irq
	sta $fffe
	lda #>input_irq
	sta $ffff
	lda #<nmi_stub
	sta $fffa
	sta $0318
	lda #>nmi_stub
	sta $fffb
	sta $0319
	lda #$81				; set + enable Timer A IRQ
	sta $dc0d
	lda #$11				; start + force load, continuous φ2
	sta $dc0e
	rts

; Ack CIA2 NMI (RESTORE) with KERNAL banked out
nmi_stub
	pha
	lda $dd0d
	pla
	rti

input_irq
	pha
	txa
	pha
	lda $dc0d				; ack
	and #$01
	bne .irq_keys
	jmp .irq_rti
.irq_keys

	; J (PA4 = $EF) = turn left
	lda #$ef
	sta $dc00
	lda $dc01
	and #$04
	bne .irq_noj
	lda in_turn_l
	jsr .irq_add_ms
	sta in_turn_l
.irq_noj

	; L (PA5 = $DF) = turn right
	lda #$df
	sta $dc00
	lda $dc01
	and #$04
	bne .irq_nol
	lda in_turn_r
	jsr .irq_add_ms
	sta in_turn_r
.irq_nol

	; W / A / S / 4 on PA1 = $FD
	lda #$fd
	sta $dc00
	lda $dc01
	tax
	and #$02				; W = forward
	bne .irq_now
	lda in_fwd
	jsr .irq_add_ms
	sta in_fwd
.irq_now
	txa
	and #$20				; S = back
	bne .irq_nos
	lda in_back
	jsr .irq_add_ms
	sta in_back
.irq_nos
	txa
	and #$04				; A = strafe left
	bne .irq_noa
	lda in_strafel
	jsr .irq_add_ms
	sta in_strafel
.irq_noa
	txa
	and #$08				; 4 = chaingun (1/3 reserved knife/rifle)
	bne .irq_no4
	lda #1
	sta in_wpn_chaingun
.irq_no4

	; D on PA2 = $FB
	lda #$fb
	sta $dc00
	lda $dc01
	and #$04				; D = strafe right
	bne .irq_nod
	lda in_strafer
	jsr .irq_add_ms
	sta in_strafer
.irq_nod

	; 2 / SPACE on PA7 = $7F
	lda #$7f
	sta $dc00
	lda $dc01
	tax
	and #$08				; 2 = pistol
	bne .irq_no2
	lda #1
	sta in_wpn_pistol
.irq_no2
	txa
	and #$10				; SPACE = fire
	bne .irq_nospc
	lda #1
	sta in_fire
.irq_nospc

.irq_rti
	pla
	tax
	pla
	rti

; A = counter → A = min(A + SAMPLE_MS, 255)
.irq_add_ms
	clc
	adc #SAMPLE_MS
	bcc .irq_add_ok
	lda #255
.irq_add_ok
	rts

; Snapshot IRQ accumulators; build turn + move_dx/dy from hold ms
read_input
	lda #0
	sta move_dx_l
	sta move_dx_h
	sta move_dy_l
	sta move_dy_h

	sei
	lda in_turn_l
	sta tmp3
	lda in_turn_r
	sta tmp4
	lda in_fwd
	pha
	lda in_back
	pha
	lda in_strafel
	pha
	lda in_strafer
	pha
	lda in_fire
	sta key_fire
	lda in_wpn_pistol
	sta key_wpn_pistol
	lda in_wpn_chaingun
	sta key_wpn_chaingun
	lda #0
	sta in_turn_l
	sta in_turn_r
	sta in_fwd
	sta in_back
	sta in_strafel
	sta in_strafer
	sta in_fire
	sta in_wpn_pistol
	sta in_wpn_chaingun
	cli

	; --- turn: net hold ms (right − left) ---
	lda tmp4
	cmp tmp3
	beq .turn_done
	bcs .turn_right
	lda tmp3
	sec
	sbc tmp4
	sta vel_ms
	jsr turn_deliver
	eor #$ff
	clc
	adc #1
	clc
	adc playera
	sta playera
	jmp .turn_done
.turn_right
	lda tmp4
	sec
	sbc tmp3
	sta vel_ms
	jsr turn_deliver
	clc
	adc playera
	sta playera
.turn_done

	; stack: strafer, strafel, back, fwd (top = strafer)
	pla					; strafer (D)
	beq .no_d
	sta vel_ms
	ldy playera
	lda sintab,y
	jsr neg_a				; right: dx = -sin
	jsr move_add_x
	ldy playera
	lda costab,y
	jsr neg_a				; dy = -cos
	jsr move_add_y
.no_d
	pla					; strafel (A)
	beq .no_a
	sta vel_ms
	ldy playera
	lda sintab,y				; left: dx = +sin
	jsr move_add_x
	ldy playera
	lda costab,y				; dy = +cos
	jsr move_add_y
.no_a
	pla					; back
	beq .no_s
	sta vel_ms
	ldy playera
	lda costab,y
	jsr neg_a
	jsr move_add_x
	ldy playera
	lda sintab,y				; back: dy = +sin (forward uses −sin)
	jsr move_add_y
.no_s
	pla					; fwd
	beq .no_w
	sta vel_ms
	ldy playera
	lda costab,y
	jsr move_add_x
	ldy playera
	lda sintab,y
	jsr neg_a
	jsr move_add_y
.no_w
	rts

; turn_acc += vel_ms<<6; A = turn_acc>>10; turn_acc &= $03FF
turn_deliver
	lda vel_ms
	tax
	lsr
	lsr
	sta tmp1				; hi = vel>>2
	txa
	and #3
	asl
	asl
	asl
	asl
	asl
	asl
	sta tmp0				; lo = (vel&3)<<6
	clc
	lda turn_acc_l
	adc tmp0
	sta turn_acc_l
	lda turn_acc_h
	adc tmp1
	sta turn_acc_h
	tay
	and #3
	sta turn_acc_h
	tya
	lsr
	lsr					; A = delivered = acc>>10
	rts

; A = signed sintab unit → scale into move_dx
move_add_x
	jsr scale_vel
	clc
	lda move_dx_l
	adc tmp0
	sta move_dx_l
	lda move_dx_h
	adc tmp1
	sta move_dx_h
	rts

move_add_y
	jsr scale_vel
	clc
	lda move_dy_l
	adc tmp0
	sta move_dy_l
	lda move_dy_h
	adc tmp1
	sta move_dy_h
	rts

; A = signed unit → tmp0/tmp1 = (A * vel_ms) >>> 6 (arithmetic)
scale_vel
	sta tmp2
	bpl .sv_abs
	eor #$ff
	clc
	adc #1
.sv_abs
	tay
	lda vel_ms
	jsr mul_8x8				; X=lo A=hi
	sta tmp1
	stx tmp0
	; unsigned >>6 via <<2 take high 16 of 24-bit
	lda #0
	sta tmp3
	asl tmp0
	rol tmp1
	rol tmp3
	asl tmp0
	rol tmp1
	rol tmp3
	lda tmp1
	sta tmp0
	lda tmp3
	sta tmp1
	lda tmp2
	bpl .sv_done
	sec
	lda #0
	sbc tmp0
	sta tmp0
	lda #0
	sbc tmp1
	sta tmp1
.sv_done
	rts

neg_a
	eor #$ff
	clc
	adc #1
	rts
