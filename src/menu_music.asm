; Menu music loader + Jukebox switch. MUS1..MUSN (tools/genmusic.py) load at
; $9000 from disk. Krill vs KERNAL is chosen at assemble time (build.bat
; assembles menu.asm once per disk). Players are relocated to init $9000 /
; play $9003 with zero page at $E0–$F4, so the menu's $F5–$FE pointers stay.

!zone menu_music

MUSIC_INIT	= $9000
MUSIC_PLAY	= $9003

; run_menu entry, before SEI: splash still up. Krill arrives I=1, $01=$35;
; KERNAL arrives I=0, $01=$36. Leaves $01=$36, I=0.
music_pick_load
	lda $a2					; jiffy clock lo
	eor $dc04				; free-running timer A lo
.mpl_mod
	cmp #MUSIC_TRACKS
	bcc .mpl_ok
	sbc #MUSIC_TRACKS			; C already set
	bcs .mpl_mod
.mpl_ok
	sta music_track
	; fall through

; A = track 0..MUSIC_TRACKS-1 → MUSn at $9000. Leaves $01=$36, I=0.
; music_ok = 1 when the file loaded.
music_load
	clc
	adc #'1'
	sta music_name + 3
	lda #0
	sta music_ok
!if USE_KRILL {
	ldx #<music_name
	ldy #>music_name
	sei
	lda #BANK_LOADER
	sta $01
	clc					; address from the PRG header
	jsr loadraw
	php
	lda #BANK_IO
	sta $01
	plp
	cli
} else {
	lda #4
	ldx #<music_name
	ldy #>music_name
	jsr $ffbd				; SETNAM
	lda #1
	ldx $ba
	ldy #1					; SA=1 → PRG header address
	jsr $ffba				; SETLFS
	lda #0
	jsr $ffd5				; LOAD
	php
	lda #1
	jsr $ffc3				; CLOSE
	plp
}
	bcs .ml_rts
	inc music_ok
.ml_rts
	lda #VIC_BANK_DD00			; LOAD RMW of $dd00; keep VIC bank $8000
	sta $dd00
	rts

; A = track 0.., menu IRQs live. Silences, reloads, restarts, repaints.
jukebox_select
	sta music_track
	jsr menu_sfx_done			; raster+CIA off, music silent, $01=$36, I=0
	jsr menu_blank				; no sprite DMA during the transfer
	lda music_track
	jsr music_load
	jsr menu_sfx_init			; MUSIC_INIT + timers + raster mux
	jsr sync_juke_title
	jmp draw_menu

; Jukebox heading follows music_track (menu id 4).
sync_juke_title
	ldx music_track
	lda juke_now_lo,x
	sta section_lo + 4
	lda juke_now_hi,x
	sta section_hi + 4
	rts

music_name	!text "MUS1", 0
