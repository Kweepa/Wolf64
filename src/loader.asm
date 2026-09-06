; Disk load helpers — resident in locode (map load + restart).
; USE_KRILL=1: loadraw, no IOINIT. Default: KERNAL SETNAM/SETLFS/LOAD/CLOSE.
;
; Screen blacked during LoadLevel (DEN off until first swap_view).
!zone loader

level_dos_name
	!text "E1M1"
	!byte 0

; FormatDosName — "ENMM" from episode (0→E1) + level_num (1→M1, 9→MB, 10→MS)
FormatDosName
	lda #'E'
	sta level_dos_name
	lda episode
	clc
	adc #'1'
	sta level_dos_name + 1
	lda #'M'
	sta level_dos_name + 2
	lda level_num
	cmp #LEVEL_SECRET
	bne .fdn_boss
	lda #'S'
	sta level_dos_name + 3
	rts
.fdn_boss
	cmp #LEVEL_MAX
	bne .fdn_digit
	lda #'B'
	sta level_dos_name + 3
	rts
.fdn_digit
	clc
	adc #'0'
	sta level_dos_name + 3
	rts

; Black border/bg, sprites off, DEN off. Border still shows if load fails
; (init_vic leaves DEN off; caller sets $d020).
blank_screen
	lda #$2b				; absolute — RMW writes the live raster MSB into RST8
	sta $d011
	lda #0
	sta $d015
	sta $d01a
	sta $d020
	sta $d021
	lda $d019
	sta $d019
	rts

!if USE_KRILL {

; LoadPrg — X/Y = 0-terminated name. Dest from PRG header (carry clear).
; C=0 ok, C=1 error. Do not IOINIT: $DD02=$3F uninstalls Krill drive code.
LoadPrg
	stx load_name_l
	sty load_name_h

	sei
	cld
	lda #BANK_LOADER
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d01a
	sta $dd0e
	sta $dd0f

	ldx load_name_l
	ldy load_name_h
	clc					; dest from PRG header
	jsr loadraw
	php

	lda #BANK_LOADER
	sta $01
	lda #VIC_BANK_DD00
	sta $dd00
	plp
	rts

; LoadLevel — blank + loadraw. Never IOINIT (kills drive code).
; C=0 ok, C=1 error. Caller must re-init IRQs/ZP (see restart_level).
LoadLevel
	sei
	lda #BANK_LOADER
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d01a
	lda $d019
	sta $d019
	jsr blank_screen
	jsr FormatDosName
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

} else {

; LoadPrg — A=name length, X/Y=name pointer. KERNAL must already be paged in.
; C=0 ok, C=1 error.
LoadPrg
	sta load_namelen
	stx load_name_l
	sty load_name_h

	lda load_namelen
	ldx load_name_l
	ldy load_name_h
	jsr $ffbd				; SETNAM
	lda #1
	ldx $ba					; same device as boot load
	ldy #1					; SA=1 → PRG load address
	jsr $ffba				; SETLFS
	lda #0
	jsr $ffd5				; LOAD (A must be 0)
	php
	pha
	lda #1
	jsr $ffc3				; CLOSE
	pla
	plp
	rts

; IOINIT can leave CIA2 Timer A generating NMIs. Mask the NMI without
; stopping the timers — $dd0e/$dd0f=0 plus DEN=0 stalls KERNAL IEC.
load_cia2_nmi_off
	lda #0
	sta $02a1				; KERNAL CIA2 ICR shadow; prevent FE88 re-enable
	lda #$7f
	sta $dd0d
	lda $dd0d
	rts

; LoadLevel — IOINIT + blank + LoadPrg. DEN off (blank_screen) until the
; caller's first swap_view. load_in_play=1 also masks CIA2 NMI (game left
; CIA2 running); timers keep running so IEC still works with DEN=0.
; C=0 ok, C=1 error. Caller must re-init IRQs/ZP (see restart_level).
LoadLevel
	sei
	lda #$35
	sta $01
	lda #$7f
	sta $dc0d				; kill game Timer A IRQ before KERNAL
	lda $dc0d
	lda #0
	sta $d01a				; raster still latches if $d01a=1 after SEI
	lda $d019
	sta $d019
	lda #$2b				; blank before IOINIT can restore DEN
	sta $d011
	lda #$36
	sta $01
	jsr $ff84				; IOINIT — cold and 2nd+ in-play
	lda #$35
	sta $01
	lda load_in_play
	beq .ll_blank
	jsr load_cia2_nmi_off
.ll_blank
	jsr blank_screen			; DEN off after IOINIT
	lda #$36
	sta $01
	cli
	jsr FormatDosName
	lda #4
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

}

; restart_level — reload current episode/level map and re-init actors
; Preserves lives; caller resets HP/keys and (on death/new game) ammo/weapons.
; LoadLevel clobbers ZP/CIA — recover like game_start.
restart_level
	lda #1
	sta load_in_play
	jsr LoadLevel
	lda #0
	sta load_in_play
	bcs .rl_fail

	sei
	lda #$35
	sta $01
	lda #$ff
	sta $dc02
	lda #0
	sta $dc03
	jsr init_sqtabs
	jsr init_vic
	jsr prof_init
	jsr input_irq_init
	jsr play_sound_init

	lda #$34
	sta $01					; I/O out — TEX / SQTAB / scratch
	jsr doors_clear
	jsr find_spawn
	jsr enemies_init
	lda #$35
	sta $01
	jsr refresh_weapon
	clc
.rl_fail
	rts

; ---------------------------------------------------------------------------
; Quick save (F5) / quick load (F7)
; Two KERNAL files: QS=GAME_STATE (863), QM=MAP (4K). DEN=0 for I/O.
; Patch ZP mirrors. SAVE via $FFD8 (no IOINIT). LOAD via LoadPrg.
; ---------------------------------------------------------------------------

qs_dos_name
	!text "QS"
	!byte 0
qm_dos_name
	!text "QM"
	!byte 0
qs_scratch_cmd
	!text "S0:QS"
qm_scratch_cmd
	!text "S0:QM"

; Snapshot IRQ latches; C=1 if a disk op ran or warp fired (caller should render).
poll_quick_keys
	sei
	lda in_qsave
	sta tmp0
	lda in_qload
	sta tmp1
	lda #0
	sta in_qsave
	sta in_qload
	cli
	lda tmp0
	beq .pqk_chkload
	jsr quick_save
	sec
	rts
.pqk_chkload
	lda tmp1
	beq .pqk_warp
	jsr quick_load
	sec
	rts
.pqk_warp
	jmp poll_warp				; C=1 if warp fired

; Kill game IRQs + blank. Do not IOINIT (keeps Krill drive code).
qs_disk_prep
	sei
	lda #BANK_LOADER
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d01a
	lda $d019
	sta $d019
	jmp blank_screen

; After disk I/O: CIA DDR, Judd ptrs, VIC, IRQs. Leaves $01=$35, SEI held.
qs_recover_hw
	sei
	lda #BANK_LOADER
	sta $01
	lda #VIC_BANK_DD00
	sta $dd00
	lda #$ff
	sta $dc02
	lda #0
	sta $dc03
	jsr init_sqtabs
	jsr init_vic
	jsr prof_init
	jsr input_irq_init
	jmp play_sound_init

; Soft state after QL. Does not re-init doors/enemies/spawn.
qs_after_load
	lda #$34
	sta $01
	lda #0
	sta turn_acc_l
	sta turn_acc_h
	sta level_want
	ldx #39
	lda #$ff
-
	sta col_enemy,x
	dex
	bpl -
	lda #1
	sta bjh_look
	jsr ui_look_reload
	lda #UI_DIRTY_ALL
	sta ui_dirty
	lda #BANK_LOADER
	sta $01
	jsr refresh_weapon
	lda #0
	sta $d020
	rts

qs_fail
	jsr qs_recover_hw
	lda #$02
	sta $d020
	lda #BANK_RAM
	sta $01
	cli
	sec
	rts

; Patch hot ZP (+ difficulty) into GAME_STATE player mirrors. $01=$34.
qs_patch_in
	lda playerx_l
	sta gs_player + 0
	lda playerx_h
	sta gs_player + 1
	lda playery_l
	sta gs_player + 2
	lda playery_h
	sta gs_player + 3
	lda playera
	sta gs_player + 4
	lda owned_weapons
	sta gs_player + 9
	lda cur_weapon
	sta gs_player + 10
	lda episode
	sta gs_player + 19
	lda level_num
	sta gs_player + 20
	lda secret_from
	sta gs_player + 21
	lda difficulty
	sta gs_player + 22
	rts

; Scatter mirrors → ZP / difficulty / map index. $01=$34.
qs_patch_out
	lda gs_player + 0
	sta playerx_l
	lda gs_player + 1
	sta playerx_h
	lda gs_player + 2
	sta playery_l
	lda gs_player + 3
	sta playery_h
	lda gs_player + 4
	sta playera
	lda gs_player + 9
	sta owned_weapons
	lda gs_player + 10
	sta cur_weapon
	lda gs_player + 19
	sta episode
	lda gs_player + 20
	sta level_num
	lda gs_player + 21
	sta secret_from
	lda gs_player + 22
	sta difficulty
	rts

; Magic + version + checksum over GS body + MAP. $01=$34.
qs_write_hdr
	lda #'W'
	sta GAME_STATE
	lda #'6'
	sta GAME_STATE + 1
	lda #'4'
	sta GAME_STATE + 2
	lda #'S'
	sta GAME_STATE + 3
	lda #QS_VERSION
	sta GAME_STATE + 4
	jsr qs_checksum
	lda tmp0
	sta GAME_STATE + 5
	lda tmp1
	sta GAME_STATE + 6
	rts

; ---------------------------------------------------------------------------
quick_save
	jsr qs_disk_prep
	lda #BANK_RAM
	sta $01
	sei
	jsr qs_patch_in
	jsr qs_write_hdr
	lda #BANK_IO
	sta $01
	cli
	ldx #<qs_scratch_cmd
	ldy #>qs_scratch_cmd
	jsr qs_scratch_xy
	ldx #<qm_scratch_cmd
	ldy #>qm_scratch_cmd
	jsr qs_scratch_xy
	jsr qs_kernal_save_gs
	bcs .qss_fail
	jsr qs_kernal_save_map
	bcs .qss_fail
	jsr qs_recover_hw
	lda #0
	sta $d020
	lda #BANK_RAM
	sta $01
	cli
	clc
	rts
.qss_fail
	jmp qs_fail

; X/Y = scratch cmd text "S0:.." (5 chars)
qs_scratch_xy
	lda #5
	jsr $ffbd
	lda #15
	ldx $ba
	ldy #15
	jsr $ffba
	jsr $ffc0
	lda #15
	jmp $ffc3

; SAVE GAME_STATE .. QS_GS_END-1
qs_kernal_save_gs
	lda #2
	ldx #<qs_dos_name
	ldy #>qs_dos_name
	jsr $ffbd
	lda #1
	ldx $ba
	ldy #1
	jsr $ffba
	lda #<GAME_STATE
	sta tmp0
	lda #>GAME_STATE
	sta tmp1
	ldx #<QS_GS_END
	ldy #>QS_GS_END
	lda #tmp0
	jmp $ffd8

; SAVE MAP .. MAP_END-1
qs_kernal_save_map
	lda #2
	ldx #<qm_dos_name
	ldy #>qm_dos_name
	jsr $ffbd
	lda #1
	ldx $ba
	ldy #1
	jsr $ffba
	lda #<MAP
	sta tmp0
	lda #>MAP
	sta tmp1
	ldx #<MAP_END
	ldy #>MAP_END
	lda #tmp0
	jmp $ffd8

; ---------------------------------------------------------------------------
quick_load
	lda #1
	sta load_in_play
	jsr qs_disk_prep
!if USE_KRILL {
	ldx #<qs_dos_name
	ldy #>qs_dos_name
	jsr LoadPrg
	bcs .qsl_fail
} else {
	lda #BANK_IO
	sta $01
	cli
	jsr load_cia2_nmi_off
	lda #2
	ldx #<qs_dos_name
	ldy #>qs_dos_name
	jsr LoadPrg
	bcs .qsl_fail
}
	lda #BANK_RAM
	sta $01
	sei
	jsr qs_verify_hdr			; magic/version only — MAP may still be post-restart
	bcs .qsl_fail
!if USE_KRILL {
	ldx #<qm_dos_name
	ldy #>qm_dos_name
	jsr LoadPrg
} else {
	lda #BANK_IO
	sta $01
	cli
	lda #2
	ldx #<qm_dos_name
	ldy #>qm_dos_name
	jsr LoadPrg
}
	lda #0
	sta load_in_play
	bcs .qsl_fail2
	lda #BANK_RAM
	sta $01
	sei
	jsr qs_verify				; checksum needs QS + QM both loaded
	bcs .qsl_fail2
	jsr qs_patch_out
	jsr qs_recover_hw
	jsr qs_after_load
	lda #BANK_RAM
	sta $01
	cli
	clc
	rts
.qsl_fail
	lda #0
	sta load_in_play
	jmp qs_fail
.qsl_fail2
	jmp qs_fail

; Magic + version only. C=0 ok. $01=$34.
qs_verify_hdr
	lda GAME_STATE
	cmp #'W'
	bne .qsvh_bad
	lda GAME_STATE + 1
	cmp #'6'
	bne .qsvh_bad
	lda GAME_STATE + 2
	cmp #'4'
	bne .qsvh_bad
	lda GAME_STATE + 3
	cmp #'S'
	bne .qsvh_bad
	lda GAME_STATE + 4
	cmp #QS_VERSION
	bne .qsvh_bad
	clc
	rts
.qsvh_bad
	sec
	rts

; Magic + version + checksum (GS body + MAP). C=0 ok. $01=$34.
qs_verify
	jsr qs_verify_hdr
	bcs .qsv_bad
	jsr qs_checksum
	lda tmp0
	cmp GAME_STATE + 5
	bne .qsv_bad
	lda tmp1
	cmp GAME_STATE + 6
	bne .qsv_bad
	clc
	rts
.qsv_bad
	sec
	rts

; Sum (GAME_STATE+HDR .. QS_GS_END) + MAP → tmp0/tmp1
qs_checksum
	lda #<(GAME_STATE + QS_HDR_LEN)
	sta aux_l
	lda #>(GAME_STATE + QS_HDR_LEN)
	sta aux_h
	lda #0
	sta tmp0
	sta tmp1
	lda #<(QS_STATE_SIZE - QS_HDR_LEN)
	sta tmp2
	lda #>(QS_STATE_SIZE - QS_HDR_LEN)
	sta tmp3
	jsr .qsc_add
	lda #<MAP
	sta aux_l
	lda #>MAP
	sta aux_h
	lda #<MAP_SIZE
	sta tmp2
	lda #>MAP_SIZE
	sta tmp3
.qsc_add
	lda tmp2
	ora tmp3
	beq .qsc_done
	ldy #0
	lda (aux_l),y
	clc
	adc tmp0
	sta tmp0
	bcc +
	inc tmp1
+
	inc aux_l
	bne +
	inc aux_h
+
	lda tmp2
	bne +
	dec tmp3
+
	dec tmp2
	jmp .qsc_add
.qsc_done
	rts
