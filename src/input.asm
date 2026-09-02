; Raster IRQ cascade: line 40 = face sprites; line 88 = gun then input/SFX.
; Hold-ms accumulated once per frame at the weapon raster; read_input scales
; turn/move (SquareDoom). CIA1 Timer A does not IRQ (it delayed raster 40).
!zone input

SAMPLE_MS	= 20			; one frame tick (PAL ~50 Hz)

; IRQ accumulates hold times into in_*; read_input snapshots under SEI and
; scales turn/wish by those times (not full-frame dt_ms):
;   turn 90°/sec = 64 angle/sec → turn_acc += vel_ms<<6, deliver >>10
;   move ½ tile/sec = 4 world/sec → delta_8_8 = (sintab * vel_ms) >> 6
; sintab AMP=64; identity: sin=64, dt=1024 → 1024 = 4.0 world.
; W/S or I/K move, A/D strafe, J/L turn (SquareDoom + IJKL).
; 1351 Port 1: POTX delta → playera; left button = FIRE (PB4, same as SPACE).
; Joy Port 2 (joy_en): digital stick + Btn2 strafe; mutex with mouse_en.

input_irq_init
	lda #0
	sta in_turn_l
	sta in_turn_r
	sta in_fwd
	sta in_back
	sta in_strafel
	sta in_strafer
	sta in_fire
	sta in_wpn_knife
	sta in_wpn_pistol
	sta in_wpn_mg
	sta in_wpn_chaingun
	sta turn_acc_l
	sta turn_acc_h
	sta mux_phase

	lda #$2b				; absolute — RST8 = 0; DEN stays off until first paint
	sta $d011
	lda #MUX_HUD_RASTER
	sta $d012
	lda $d019
	sta $d019

	lda joy_en
	beq .init_mouse
	lda #$9f
	bne .init_set
.init_mouse
	lda #$7f
.init_set
	sta $dc00				; pre-select POT multiplexer

	lda $d419				; seed so first IRQ delta is 0
	sta mouse_x

	lda #$7f
	sta $dc0d				; clear CIA1 IRQ enables
	lda $dc0d				; ack
	lda #0
	sta $dc0e				; Timer A stopped — raster-only IRQ
	lda #<input_irq
	sta $fffe
	lda #>input_irq
	sta $ffff
	; Use the same balanced ack-and-RTI handler both as the raw vector
	; (KERNAL out) and through KERNAL's FE43 JMP ($0318) trampoline.
	lda #<nmi_stub
	sta $fffa
	sta $0318
	lda #>nmi_stub
	sta $fffb
	sta $0319
	lda #1
	sta $d01a				; raster IRQ only
	rts

; Ack CIA2 NMI (RESTORE) with KERNAL banked out; banks I/O in for the ack
nmi_stub
	pha
	lda $01
	pha
	lda #$35
	sta $01
	lda $dd0d
	pla
	sta $01
	pla
	rti

input_irq
	pha
	txa
	pha
	tya
	pha
	lda $01					; bank I/O in for CIA/SID; restore at exit
	pha
	lda #$35
	sta $01
	lda mux_phase
	bne .irq_wpn
	jsr mux_hud_spr
	lda #1
	sta mux_phase
	lda #MUX_WPN_RASTER
	sta $d012
	lda $d019
	sta $d019
	jmp .irq_rti
.irq_wpn
	jsr wpn_mux_restore
	; Gun is programmed; input/SFX run here so they cannot delay raster 40.
.irq_run
	; POTX: HUD mux must not touch $DC00. Previous frame's .irq_park left
	; the mux settled for a full frame.
	lda $d419
	sta potx_raw
	jsr update_sfx

	lda joy_en
	bne .irq_joy
	lda mouse_en
	bne .irq_to_mouse
	jmp .irq_keys
.irq_to_mouse
	jmp .irq_mouse

.irq_joy
	lda $dc02
	pha
	lda #0
	sta $dc02
	lda #$ff
	sta $dc00
	lda $dc00
	sta joy_state
	pla
	sta $dc02

	lda joy_state
	and #$01				; Up (Forward)
	bne .joy_nou
	lda in_fwd
	jsr .irq_add_ms
	sta in_fwd
.joy_nou
	lda joy_state
	and #$02				; Down (Backward)
	bne .joy_nod
	lda in_back
	jsr .irq_add_ms
	sta in_back
.joy_nod
	lda joy_state
	and #$10				; Fire 1
	bne .joy_nof
	lda #1
	sta in_fire
.joy_nof

	; Button 2 detection:
	; - Digital 2nd button / Spacebar / Port 1 Fire ($DC01 bit 4 == 0)
	; - Cheetah Annihilator style 2nd button on POTX (port 2)
	; POTX is not read here: it was latched into potx_raw after gun mux, the
	; only point in the frame where the pot mux has been stable long
	; enough for the SID's conversion to be valid. See mem.asm.

	; Spacebar (Row 7, Col 4) / Joy 1 Fire
	lda #$7f
	sta $dc00
	nop
	nop
	nop
	lda $dc01
	and #$10
	beq .btn2_raw_down			; key or fire down: pressed, skip the pot

	; Pot path, with a Schmitt trigger. A pressed Annihilator button pulls
	; POTX low; released, the line floats and reads high. Values between the
	; two thresholds hold the previous state instead of chattering.
	lda potx_raw
	cmp #BTN2_POT_LO
	bcc .btn2_pot_dn
	cmp #BTN2_POT_HI
	bcc .btn2_pot_keep			; dead band: leave btn2_pot alone
	lda #0
	beq .btn2_pot_set
.btn2_pot_dn
	lda #1
.btn2_pot_set
	sta btn2_pot
.btn2_pot_keep
	lda btn2_pot
	bne .btn2_raw_down
	lda #0
	beq .btn2_deb_chk
.btn2_raw_down
	lda #1

.btn2_deb_chk
	; A = this frame's raw state. Require BTN2_DEB agreeing frames before the
	; latched btn2_down flips, so a single bad sample can never toggle it.
	cmp btn2_down
	beq .btn2_deb_rst
	inc btn2_deb
	ldx btn2_deb
	cpx #BTN2_DEB
	bcc .btn2_eval				; not stable yet: keep old btn2_down
	sta btn2_down
.btn2_deb_rst
	ldx #0
	stx btn2_deb

.btn2_eval
	lda btn2_down				; 1 if Button 2 held, 0 if released
	sta btn2_state				; 0 = Turn (default), 1 = Strafe

	lda joy_state
	and #$04				; Left
	bne .joy_nol
	lda btn2_state
	bne .joy_str_l
	lda in_turn_l
	jsr .irq_add_ms
	sta in_turn_l
	jmp .joy_nol
.joy_str_l
	lda in_strafel
	jsr .irq_add_ms
	sta in_strafel
.joy_nol
	lda joy_state
	and #$08				; Right
	bne .joy_nor
	lda btn2_state
	bne .joy_str_r
	lda in_turn_r
	jsr .irq_add_ms
	sta in_turn_r
	jmp .joy_nor
.joy_str_r
	lda in_strafer
	jsr .irq_add_ms
	sta in_strafer
.joy_nor
	jmp .irq_keys

.irq_mouse
	; 1351 POTX wrap-delta. |dx|<=2 noise; |dx|>=33 = wrap (keep mouse_x, no look)
	lda potx_raw				; latched after gun mux; see mem.asm
	tax
	sec
	sbc mouse_x
	stx mouse_x
	tay
	bpl .irq_mpos
	cpy #$fe
	bcs .irq_keys
	cpy #$e0
	bcc .irq_keys
	tya
	bcs .irq_mdx
.irq_mpos
	cpy #3
	bcc .irq_keys
	cpy #33
	bcs .irq_keys
	tya
.irq_mdx
	cmp #$80				; signed /2 into playera (wraps as angle)
	ror
	clc
	adc playera
	sta playera

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

	; W|I / S|K on PA1+PA4 = $ED (OR columns so W+I is not 2× speed)
	lda #$ed
	sta $dc00
	lda $dc01
	tax
	and #$02				; W or I = forward
	bne .irq_now
	lda in_fwd
	jsr .irq_add_ms
	sta in_fwd
.irq_now
	txa
	and #$20				; S or K = back
	bne .irq_nos
	lda in_back
	jsr .irq_add_ms
	sta in_back
.irq_nos

	; A / 3 / 4 on PA1 = $FD (not $ED: that would OR A with J, 3 with 9, 4 with 0)
	lda #$fd
	sta $dc00
	lda $dc01
	tax
	and #$04				; A = strafe left
	bne .irq_noa
	lda in_strafel
	jsr .irq_add_ms
	sta in_strafel
.irq_noa
	txa
	and #$01				; 3 = machinegun
	bne .irq_no3
	lda #1
	sta in_wpn_mg
.irq_no3
	txa
	and #$08				; 4 = chaingun
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

	; 1 / 2 / SPACE on PA7 = $7F
	lda #$7f
	sta $dc00
	lda $dc01
	tax
	and #$01				; 1 = knife
	bne .irq_no1
	lda #1
	sta in_wpn_knife
.irq_no1
	txa
	and #$08				; 2 = pistol
	bne .irq_no2
	lda #1
	sta in_wpn_pistol
.irq_no2
	txa
	and #$10				; SPACE / 1351 left button (PB4)
	bne .irq_nospc
	lda joy_en
	bne .irq_nospc			; joy: PB4 is Button 2 (strafe), not Fire
	lda #1
	sta in_fire
.irq_nospc
	lda #$7f
	ldx joy_en
	beq .irq_park
	lda #$9f
.irq_park
	sta $dc00
	lda #0
	sta mux_phase
	lda #MUX_HUD_RASTER
	sta $d012
	lda $d019
	sta $d019
.irq_rti
	pla
	sta $01					; restore caller's banking
	pla
	tay
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
	lda in_wpn_knife
	sta key_wpn_knife
	lda in_wpn_pistol
	sta key_wpn_pistol
	lda in_wpn_mg
	sta key_wpn_mg
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
	sta in_wpn_knife
	sta in_wpn_pistol
	sta in_wpn_mg
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
	sec
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
	jsr neg_a
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

joy_state: !byte 0
btn2_state: !byte 0
potx_raw: !byte $ff			; SID POTX, sampled after gun mux (mux settled)
btn2_pot: !byte 0			; hysteresis state of the pot button
btn2_down: !byte 0			; debounced Button 2
btn2_deb: !byte 0			; frames the raw state has disagreed

; Raster ~40: unexpanded hi-res BJ-head sprites over the HUD yellow.
mux_hud_spr
	lda #0
	sta $d01d
	sta $d017
	sta $d01c
	sta $d010
	lda #BJH_X
	sta $d000
	sta $d002
	sta $d004
	sta $d006
	sta $d008
	lda #BJH_Y_LOOK
	sta $d001
	lda #BJH_Y_BLOOD
	sta $d003
	lda #BJH_Y_WHITE
	sta $d005

	lda player_hp
	bne .mh_live

	lda #BJH_Y_DEADLT
	sta $d007
	lda #BJH_Y_DEADRED
	sta $d009
	lda #BJH_PTR_DEADLT
	sta $43fb
	sta $47fb
	lda #BJH_PTR_DEADRED
	sta $43fc
	sta $47fc
	lda #10
	sta $d02a
	lda #2
	sta $d02b
	lda #BJH_EN_DEAD
	sta $d015
	rts

.mh_live
	lda #BJH_Y_BASE
	sta $d007
	sta $d009
	ldy bjh_look
	lda bjh_look_ptr,y
	sta $43f8
	sta $47f8
	lda #2
	sta $d027

	lda player_hp
	ldx #0
	cmp #67
	bcs .mh_blood
	inx
	cmp #34
	bcs .mh_blood
	inx
.mh_blood
	lda bjh_blood_ptr,x
	sta $43f9
	sta $47f9
	lda bjh_blood_col,x
	sta $d028

	lda #BJH_PTR_WHITE
	sta $43fa
	sta $47fa
	lda #1
	sta $d029
	lda #BJH_PTR_LTRED
	sta $43fb
	sta $47fb
	lda #10
	sta $d02a
	lda #BJH_PTR_RED
	sta $43fc
	sta $47fc
	lda #2
	sta $d02b

	lda #BJH_EN_ALIVE
	cpx #0
	beq +
	lda #BJH_EN_BLOOD
+
	sta $d015
	rts
