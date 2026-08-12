; CIA2 cascade frame timer + optional buckets (SquareDoom-style)
; DBG_FPS=1: F ≈ ms.
; PROFILE=1, PROF_SPLIT=0: C P U O L I — I = items near-culled into vis
; PROFILE=1, PROF_SPLIT=1: R D P U O L I — R/D timed per column (~80 samples)
; L = one LOS grant (nested)
!zone profil

; CIA2 — timers only; do not touch $dd00 (VIC bank)
CIA2_TA_LO	= $dd04
CIA2_TA_HI	= $dd05
CIA2_TB_LO	= $dd06
CIA2_TB_HI	= $dd07
CIA2_ICR	= $dd0d
CIA2_CRA	= $dd0e
CIA2_CRB	= $dd0f

!if PROFILE = 1 {
!if PROF_SPLIT = 1 {
PROF_RAY	= 0				; fold/secant/sdx/sdy/SMC/map_to_tile (×40)
PROF_DDA	= 1				; inner march + hit_wall (×40)
PROF_PAINT	= 2
PROF_OBJUPD	= 3				; enemies_update
PROF_OBJDRAW	= 4				; enemies_draw
PROF_LOS	= 5				; single RR LOS grant (nested; also inside U)
PROF_NBUCKET	= 6
} else {
PROF_CAST	= 0				; setup + cast_column ×40
PROF_PAINT	= 1
PROF_OBJUPD	= 2				; enemies_update
PROF_OBJDRAW	= 3				; enemies_draw
PROF_LOS	= 4				; single RR LOS grant (nested; also inside U)
PROF_NBUCKET	= 5
}
}

prof_init
	lda #$7f
	sta CIA2_ICR
	lda CIA2_ICR
	lda #$ff
	sta CIA2_TA_LO
	sta CIA2_TA_HI
	sta CIA2_TB_LO
	sta CIA2_TB_HI
	lda #$11				; TA start + force load, ϕ2
	sta CIA2_CRA
	lda #$51				; TB start + force load, count TA underflows
	sta CIA2_CRB
	jsr prof_read_casc
	jsr prof_store_t0
	lda #0
	sta frame_cy
	sta frame_cy + 1
	sta frame_cy + 2
	sta frame_cy + 3
	sta turn_acc_l
	sta turn_acc_h
	lda #20
	sta dt_ms
	rts

; frame_cy >> 10 → dt_ms (HUD binary-ms). 0 → 20; saturate at 255.
calc_frame_dt
	lda frame_cy + 1
	sta tmp0
	lda frame_cy + 2
	lsr
	ror tmp0
	lsr
	ror tmp0
	tay					; hi after >>2
	bne .cfd_sat
	lda tmp0
	bne .cfd_ok
	lda #20
.cfd_ok
	sta dt_ms
	rts
.cfd_sat
	lda #255
	sta dt_ms
	rts

prof_read_casc
	lda $01
	pha
	lda #$35
	sta $01
.prc_retry
	lda CIA2_TB_HI
	sta casc_now + 3
	lda CIA2_TB_LO
	sta casc_now + 2
	lda CIA2_TA_HI
	sta casc_now + 1
	lda CIA2_TA_LO
	sta casc_now
	lda CIA2_TB_HI
	cmp casc_now + 3
	bne .prc_retry
	lda CIA2_TB_LO
	cmp casc_now + 2
	bne .prc_retry
	pla
	sta $01
	rts

prof_store_t0
	lda casc_now
	sta frame_t0
	lda casc_now + 1
	sta frame_t0 + 1
	lda casc_now + 2
	sta frame_t0 + 2
	lda casc_now + 3
	sta frame_t0 + 3
	rts

; Period since last call → frame_cy (countdown timers: t0 − now)
prof_frame_sample
	jsr prof_read_casc
	sec
	lda frame_t0
	sbc casc_now
	sta frame_cy
	lda frame_t0 + 1
	sbc casc_now + 1
	sta frame_cy + 1
	lda frame_t0 + 2
	sbc casc_now + 2
	sta frame_cy + 2
	lda frame_t0 + 3
	sbc casc_now + 3
	sta frame_cy + 3
	jmp prof_store_t0

!if PROFILE = 1 {
; 32-bit cascade snap (Timer A alone wraps ~65ms and under-reports paint)
prof_snap
	jsr prof_read_casc
	lda casc_now
	sta casc_snap
	lda casc_now + 1
	sta casc_snap + 1
	lda casc_now + 2
	sta casc_snap + 2
	lda casc_now + 3
	sta casc_snap + 3
	rts

prof_reset_frame
	ldx #PROF_NBUCKET * 4 - 1
	lda #0
-
	sta prof_cy,x
	dex
	bpl -
	jmp prof_snap

; Y = bucket 0..N-1. Add (casc_snap − now) into prof_cy[Y] (32-bit).
prof_add_bucket
	jsr prof_read_casc
	tya
	asl
	asl
	tax					; X = bucket × 4
	sec
	lda casc_snap
	sbc casc_now
	sta prof_dt + 0
	lda casc_snap + 1
	sbc casc_now + 1
	sta prof_dt + 1
	lda casc_snap + 2
	sbc casc_now + 2
	sta prof_dt + 2
	lda casc_snap + 3
	sbc casc_now + 3
	sta prof_dt + 3
	clc
	lda prof_cy,x
	adc prof_dt + 0
	sta prof_cy,x
	lda prof_cy + 1,x
	adc prof_dt + 1
	sta prof_cy + 1,x
	lda prof_cy + 2,x
	adc prof_dt + 2
	sta prof_cy + 2,x
	lda prof_cy + 3,x
	adc prof_dt + 3
	sta prof_cy + 3,x
	lda casc_now
	sta casc_snap
	lda casc_now + 1
	sta casc_snap + 1
	lda casc_now + 2
	sta casc_snap + 2
	lda casc_now + 3
	sta casc_snap + 3
	rts

; Nested LOS sample — does not touch casc_snap (U/C/P/O stay sequential).
prof_los_begin
	jsr prof_read_casc
	lda casc_now
	sta los_t0
	lda casc_now + 1
	sta los_t0 + 1
	lda casc_now + 2
	sta los_t0 + 2
	lda casc_now + 3
	sta los_t0 + 3
	rts

prof_los_end
	jsr prof_read_casc
	ldx #PROF_LOS * 4
	sec
	lda los_t0
	sbc casc_now
	sta prof_dt + 0
	lda los_t0 + 1
	sbc casc_now + 1
	sta prof_dt + 1
	lda los_t0 + 2
	sbc casc_now + 2
	sta prof_dt + 2
	lda los_t0 + 3
	sbc casc_now + 3
	sta prof_dt + 3
	clc
	lda prof_cy,x
	adc prof_dt + 0
	sta prof_cy,x
	lda prof_cy + 1,x
	adc prof_dt + 1
	sta prof_cy + 1,x
	lda prof_cy + 2,x
	adc prof_dt + 2
	sta prof_cy + 2,x
	lda prof_cy + 3,x
	adc prof_dt + 3
	sta prof_cy + 3,x
	rts
}

; Bitmap row 0 ms digits (≈ (cy>>8)>>2)
; PROF_SPLIT=0: F C P U O L I  (I = items in vis after near-cull)
; PROF_SPLIT=1: F R D P U O L I
prof_print
	lda #$35
	sta $01					; .pp_digit writes colour RAM at $d800
	jsr set_scr_front
!if DBG_FPS = 1 {
	ldx #0
	lda frame_cy + 2
	ldy frame_cy + 1
	jsr .pp_ms3
}
!if PROFILE = 1 {
!if PROF_SPLIT = 1 {
	ldx #4
	lda prof_cy + PROF_RAY * 4 + 2
	ldy prof_cy + PROF_RAY * 4 + 1
	jsr .pp_ms3
	ldx #8
	lda prof_cy + PROF_DDA * 4 + 2
	ldy prof_cy + PROF_DDA * 4 + 1
	jsr .pp_ms3
	ldx #12
	lda prof_cy + PROF_PAINT * 4 + 2
	ldy prof_cy + PROF_PAINT * 4 + 1
	jsr .pp_ms3
	ldx #16
	lda prof_cy + PROF_OBJUPD * 4 + 2
	ldy prof_cy + PROF_OBJUPD * 4 + 1
	jsr .pp_ms3
	ldx #20
	lda prof_cy + PROF_OBJDRAW * 4 + 2
	ldy prof_cy + PROF_OBJDRAW * 4 + 1
	jsr .pp_ms3
	ldx #24
	lda prof_cy + PROF_LOS * 4 + 2
	ldy prof_cy + PROF_LOS * 4 + 1
	jsr .pp_ms3
	ldx #28
	lda item_considered
	jsr .pp_u8_3
} else {
	ldx #4
	lda prof_cy + PROF_CAST * 4 + 2
	ldy prof_cy + PROF_CAST * 4 + 1
	jsr .pp_ms3
	ldx #8
	lda prof_cy + PROF_PAINT * 4 + 2
	ldy prof_cy + PROF_PAINT * 4 + 1
	jsr .pp_ms3
	ldx #12
	lda prof_cy + PROF_OBJUPD * 4 + 2
	ldy prof_cy + PROF_OBJUPD * 4 + 1
	jsr .pp_ms3
	ldx #16
	lda prof_cy + PROF_OBJDRAW * 4 + 2
	ldy prof_cy + PROF_OBJDRAW * 4 + 1
	jsr .pp_ms3
	ldx #20
	lda prof_cy + PROF_LOS * 4 + 2
	ldy prof_cy + PROF_LOS * 4 + 1
	jsr .pp_ms3
	ldx #24
	lda item_considered
	jsr .pp_u8_3
}
}
	lda #$34
	sta $01
	rts

; A = 0..255 → 3 decimal digits at columns X..X+2
.pp_u8_3
	sta pp_tmp_l
	lda #0
	sta pp_tmp_h
	jmp .pp_dec3

; A:Y = hi:mid (cycles>>8) → ≈ ms → 3 digits at bitmap columns X,X+1,X+2
.pp_ms3
	sta pp_tmp_h
	sty pp_tmp_l
	lsr pp_tmp_h
	ror pp_tmp_l
	lsr pp_tmp_h
	ror pp_tmp_l
	lda pp_tmp_h
	beq .pp_dec3
	cmp #4
	bcs .pp_sat
	cmp #3
	bcc .pp_dec3
	lda pp_tmp_l
	cmp #$e8
	bcc .pp_dec3
.pp_sat
	lda #3
	sta pp_tmp_h
	lda #$e7
	sta pp_tmp_l
.pp_dec3
	txa
	pha
	ldx #0
.pp_hund
	lda pp_tmp_h
	bne .pp_sub100
	lda pp_tmp_l
	cmp #100
	bcc .pp_tens
.pp_sub100
	sec
	lda pp_tmp_l
	sbc #100
	sta pp_tmp_l
	lda pp_tmp_h
	sbc #0
	sta pp_tmp_h
	inx
	bne .pp_hund
.pp_tens
	ldy #0
.pp_tenlp
	lda pp_tmp_l
	cmp #10
	bcc .pp_ones
	sbc #10
	sta pp_tmp_l
	iny
	bne .pp_tenlp
.pp_ones
	stx pp_dig_h
	sty pp_dig_t
	pla
	tax
	lda pp_dig_h
	jsr .pp_digit
	inx
	lda pp_dig_t
	jsr .pp_digit
	inx
	lda pp_tmp_l
	jsr .pp_digit
	rts

; A = 0..9, X = bitmap column. Clobbers tmp0/tmp1/tmp2/tmp3/Y
.pp_digit
	and #15
	asl
	asl
	asl
	clc
	adc #<hexfont
	sta tmp0
	lda #0
	adc #>hexfont
	sta tmp1
	lda #0
	sta tmp3
	txa
	asl
	rol tmp3
	asl
	rol tmp3
	asl
	rol tmp3
	clc
	adc #<BITMAP
	sta tmp2
	lda tmp3
	adc #>BITMAP
	sta tmp3
	ldy #0
-
	lda (tmp0),y
	sta (tmp2),y
	iny
	cpy #8
	bne -
	txa
	tay
	lda #$70				; yellow-ish MCM pair for visibility
	sta (scr_front_l),y
	lda #7
	sta $d800,x
	rts

; ---------------------------------------------------------------------------
; Status bar from glyph bank rows 3-4. I/O in ($01=$35).
ui_update
	lda ui_dirty
	bne +
	rts
+
	lda ui_dirty
	and #UI_DIRTY_LEVEL
	beq +
	ldx #UI_COL_LEVEL
	lda level_num
	ldy #2
	jsr .ui_num
+
	lda ui_dirty
	and #UI_DIRTY_LIVES
	beq +
	ldx #UI_COL_LIVES
	lda player_lives
	ldy #2
	jsr .ui_num
+
	lda ui_dirty
	and #UI_DIRTY_HP
	beq +
	ldx #UI_COL_HP
	lda player_hp
	ldy #3
	jsr .ui_num
+
	lda ui_dirty
	and #UI_DIRTY_AMMO
	beq +
	ldx #UI_COL_AMMO
	lda player_ammo
	ldy #3
	jsr .ui_num
+
	lda ui_dirty
	and #UI_DIRTY_FACE
	beq +
	jsr .ui_face
+
	lda ui_dirty
	and #UI_DIRTY_KEYS
	beq +
	jsr .ui_keys
+
	lda #0
	sta ui_dirty
	rts

; A=value X=col Y=#digits (2/3)
; tmp0-3 are clobbered by .ui_dig/.ui_blitcell — keep counters in pp_*.
.ui_num
	sta pp_tmp_l
	stx pp_tmp_h
	sty pp_dig_t				; extract count
	sty pp_dig_h				; draw count (must survive .ui_dig)
.un_spl
	ldx #0
	lda pp_tmp_l
.un_d
	cmp #10
	bcc .un_r
	sbc #10
	inx
	bne .un_d
.un_r
	pha
	stx pp_tmp_l
	dec pp_dig_t
	bne .un_spl
	ldx pp_tmp_h
.un_out
	pla
	jsr .ui_dig
	inx
	dec pp_dig_h
	bne .un_out
	rts

; A=digit X=dest col (preserved)
.ui_dig
	sta tmp4
	stx tmp5
	lda #0
	ldy #1
	jsr .ui_blitcell
	lda #1
	ldy #2
	jsr .ui_blitcell
	ldx tmp4
	lda UI_ATTR_DIGIT,x
	ldy tmp5
	sta SCREEN+40,y
	sta SCREEN_B+40,y
	sta SCREEN+80,y
	sta SCREEN_B+80,y
	lda UI_COLR_DIGIT,x
	sta $d800+40,y
	sta $d800+80,y
	ldx tmp5
	rts

; tmp4=src col, tmp5=dst col, A=src row ofs (0=r3,1=r4), Y=dst row (0..2)
; Clobbers tmp0-tmp3.
.ui_blitcell
	sta tmp3
	tya
	pha
	lda tmp4
	asl
	asl
	asl
	sta tmp0
	lda #<UI_BMP_ROW3
	ldx #>UI_BMP_ROW3
	ldy tmp3
	beq +
	clc
	adc #<$140
	pha
	txa
	adc #>$140
	tax
	pla
+
	clc
	adc tmp0
	sta tmp0
	bcc +
	inx
+
	stx tmp1
	lda tmp5
	asl
	asl
	asl
	sta tmp2
	pla					; dst row
	tay
	lda #<UI_BMP_ROW0
	ldx #>UI_BMP_ROW0
	cpy #0
	beq .ub_dst
-
	clc
	adc #<$140
	pha
	txa
	adc #>$140
	tax
	pla
	dey
	bne -
.ub_dst
	clc
	adc tmp2
	sta tmp2
	bcc +
	inx
+
	stx tmp3
	ldy #7
-
	lda (tmp0),y
	sta (tmp2),y
	dey
	bpl -
	rts

; HP → face 0..2 by thirds; face 3 when dead. 16×24 (2×3 cells).
.ui_face
	lda player_hp
	bne .uf_live
	lda #3
	bne .uf_got
.uf_live
	cmp #34
	bcc .uf_f2
	cmp #67
	bcc .uf_f1
	lda #0
	beq .uf_got
.uf_f1
	lda #1
	bne .uf_got
.uf_f2
	lda #2
.uf_got
	asl
	clc
	adc #UI_FACE_TOP0
	sta pp_dig_h				; top/bot src left
	lda #0
	sta pp_dig_t				; 0..5 = dy*2+dx
.uf_c
	lda pp_dig_t
	and #1
	clc
	adc #UI_COL_FACE
	sta tmp5
	lda pp_dig_t
	lsr					; dy
	cmp #1
	beq .uf_mid
	; dy0: src r3 @ top; dy2: src r4 @ top
	tax					; save dy
	lda pp_dig_t
	and #1
	clc
	adc pp_dig_h
	sta tmp4
	lda #0					; src ofs 0 = row3
	cpx #0
	bne +
	ldy #0
	beq .uf_do
+
	lda #1					; src ofs 1 = row4
	ldy #2
	bne .uf_do
.uf_mid
	lda pp_dig_h
	clc
	adc #UI_FACE_MID0 - UI_FACE_TOP0
	sta tmp4
	lda pp_dig_t
	and #1
	clc
	adc tmp4
	sta tmp4
	lda #0
	ldy #1
.uf_do
	jsr .ui_blitcell
	ldx tmp5
	lda pp_dig_t
	lsr
	tay					; dy
	lda UI_ATTR_FACE
	cpy #1
	beq .uf_a1
	bcs .uf_a2
	sta SCREEN,x
	sta SCREEN_B,x
	lda UI_COLR_FACE
	sta $d800,x
	jmp .uf_n
.uf_a1
	sta SCREEN+40,x
	sta SCREEN_B+40,x
	lda UI_COLR_FACE
	sta $d800+40,x
	jmp .uf_n
.uf_a2
	sta SCREEN+80,x
	sta SCREEN_B+80,x
	lda UI_COLR_FACE
	sta $d800+80,x
.uf_n
	inc pp_dig_t
	lda pp_dig_t
	cmp #6
	bcs +
	jmp .uf_c
+
	rts

; Gold/silver keys: bitmap always present at row2 cols 18/21; show via attrs.
.ui_keys
	lda player_keys
	and #KEY_GOLD
	beq .uk_goff
	lda UI_ATTR_KEY_GOLD
	ldy #UI_COL_KEY_GOLD
	sta SCREEN+80,y
	sta SCREEN_B+80,y
	lda UI_COLR_KEY_GOLD
	sta $d800+80,y
	jmp .uk_sil
.uk_goff
	lda #0
	ldy #UI_COL_KEY_GOLD
	sta SCREEN+80,y
	sta SCREEN_B+80,y
	sta $d800+80,y
.uk_sil
	lda player_keys
	and #KEY_SILVER
	beq .uk_soff
	lda UI_ATTR_KEY_SILVER
	ldy #UI_COL_KEY_SILVER
	sta SCREEN+80,y
	sta SCREEN_B+80,y
	lda UI_COLR_KEY_SILVER
	sta $d800+80,y
	rts
.uk_soff
	lda #0
	ldy #UI_COL_KEY_SILVER
	sta SCREEN+80,y
	sta SCREEN_B+80,y
	sta $d800+80,y
	rts

