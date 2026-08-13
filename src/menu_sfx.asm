; Menu CIA1 Timer A (~50 Hz) → update_sfx. Same SAMPLE_TA as input.asm.
; Banks KERNAL out ($01=$35) so $fffe is live; boot restores $36 after menu.

!zone menu_sfx

SAMPLE_TA_LO	= <$4FFF
SAMPLE_TA_HI	= >$4FFF

menu_sfx_init
	sei
	lda #$35
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #SAMPLE_TA_LO
	sta $dc04
	lda #SAMPLE_TA_HI
	sta $dc05
	lda #<menu_sfx_irq
	sta $fffe
	lda #>menu_sfx_irq
	sta $ffff
	lda #<menu_nmi_stub
	sta $fffa
	sta $0318
	lda #>menu_nmi_stub
	sta $fffb
	sta $0319
	lda #$81
	sta $dc0d
	lda #$11
	sta $dc0e
	jsr play_sound_init
	cli
	rts

menu_sfx_done
	sei
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d412
	lda #$36
	sta $01
	cli
	rts

menu_nmi_stub
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

menu_sfx_irq
	pha
	txa
	pha
	tya
	pha
	lda $01
	pha
	lda #$35
	sta $01
	lda $dc0d
	and #$01
	beq .msi_rti
	jsr update_sfx
.msi_rti
	pla
	sta $01
	pla
	tay
	pla
	tax
	pla
	rti

sfx_movegun1
	lda #SOUND_MOVEGUN1
	jmp play_sound

sfx_movegun2
	lda #SOUND_MOVEGUN2
	jmp play_sound

sfx_shoot
	lda #SOUND_SHOOT
	jmp play_sound

sfx_esc
	lda #SOUND_ESCPRESSED
	jmp play_sound
