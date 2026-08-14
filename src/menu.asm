; Wolf64 MENU overlay — load @ LOCODE_BASE ($0900), JSR from boot, then overwritten by LOCODE.
; Entry: +0 run_menu, +3 copy_enemy. Hires bitmap UI + full menufont (options + text screens).
; difficulty → $08FF; effects_vol/game_complete → $08FD/$08FE (survive LOCODE overwrite).
; Menu SFX: CIA1 Timer A + playsound (MOVEGUN/SHOOT/ESC from AUDIOT).
!cpu 6502
!to "menu.prg", cbm

!source "mem.asm"

ENEMY_STAGING	= PAINTERS
ENEMY_COPY_PAGES = (MAP - ENEMY_BASE + 255) / 256

MENU_SLOTS	= 8
BOX_PAD		= 2
BOX_VGAP	= 1			; empty rows inside box top/bottom
CURSOR_GAP	= 1			; blank cols between pistol and text
BAR_TOP		= 2			; leave 2 rows of main bg above bar
BAR_ROWS	= 3
BADGE_TOP	= BAR_TOP - 1		; 5-row logo plaque overlaps bar
BADGE_LEFT	= 8			; (40 - 24) / 2 — 2 cols pad each side of logo
BRAND_KEEP_ROWS	= 6			; rows 0..5 fixed (bar + badge); skip on repaint
HINT_ROW	= 23
HINT_COL	= 0			; black help text
CURSOR_CH	= '@'			; pistol glyph in menufont
LOGO_SPR_RAM	= $4800			; 7×64 in VIC bank 1 (menu-only)
LOGO_SPR_PTR0	= (LOGO_SPR_RAM - SCREEN) / 64

TEXT_COL	= 12			; grey options
HILITE_COL	= 1			; white selected / logo ink
TITLE_COL	= 7			; yellow titles
MENU_BORDER	= 6			; blue
COL_MAIN	= 14			; light blue
COL_BAR		= 0			; black
COL_BOX		= 6			; dark blue
COL_LOGO_RED	= 2			; sprite fill under logo
STORY_BG	= 12			; grey screen around story panel
STORY_BOX	= 1			; white story panel
STORY_TEXT	= 0			; black story text
STORY_GREY_TOP	= BRAND_KEEP_ROWS + 1	; grey starts one row below brand
MARK_CARET	= $1e			; !scr "^" — white span toggle, not drawn

NM_BACK		= 256 - 66
NM_START	= 256 - 10
NM_ORDER	= 256 - 3
NM_CTRL		= 256 - 4
NM_HELP		= 256 - 5
NM_CREDITS	= 256 - 7
NM_QUIT		= 256 - 6

UI_UP		= 1
UI_DOWN		= 2
UI_LEFT		= 4
UI_RIGHT	= 8
UI_SELECT	= 16
UI_ESC		= 32

ptr_l		= $fb
ptr_h		= $fc
ui_str_l	= $f9
ui_str_h	= $fa
tmp0		= $02
tmp1		= $03
tmp2		= $04
tmp3		= $05
tmp4		= $06
tmp5		= $07
aux_l		= $fd
aux_h		= $fe
; Match zp.asm — playsound / menu_sfx (boot BSS still holds boot.prg)
sound_index	= $b2
sound_ptr_l	= $b3
sound_ptr_h	= $b4
sound_priority	= $c1
sound_count	= $c2
sound_max	= $c3
ps_save_x	= $c4
ps_save_y	= $c5

*= LOCODE_BASE
	jmp run_menu
	jmp copy_enemy

copy_enemy
	sei
	lda #$34
	sta $01
	lda #>ENEMY_STAGING
	sta .s + 2
	lda #>ENEMY_BASE
	sta .d + 2
	ldx #0
	ldy #ENEMY_COPY_PAGES
.pg
.s	lda ENEMY_STAGING,x
.d	sta ENEMY_BASE,x
	inx
	bne .pg
	inc .s + 2
	inc .d + 2
	dey
	bne .pg
	lda #$36
	sta $01
	cli
	rts

run_menu
	jsr init_menu_vic
	lda #0
	sta menu_id
	sta menu_item
	sta menu_stack_d
	sta menu_can_ret
	lda #15
	sta effects_vol
	jsr menu_sfx_init
	jsr clear_screen_all
	jsr draw_brand
	jsr sync_vol_strings
	lda game_complete
	cmp #1
	bne .rm_menu
	lda #0
	sta game_complete
	lda #<ending1_text
	ldy #>ending1_text
	jsr show_story_screen
	lda #<ending2_text
	ldy #>ending2_text
	jsr show_story_screen
.rm_menu
	jsr draw_menu
.rm_loop
	jsr ui_read_keys
	jsr wait_frame

	lda #UI_UP
	and ui_pressed
	beq .rm_nou
	jsr menu_move_up
.rm_nou
	lda #UI_DOWN
	and ui_pressed
	beq .rm_nod
	jsr menu_move_down
.rm_nod
	lda menu_id
	cmp #3
	bne .rm_nov
	jsr menu_vol_input
.rm_nov
	lda #UI_ESC
	and ui_pressed
	beq .rm_noe
	jsr menu_esc
.rm_noe
	lda #UI_SELECT
	and ui_pressed
	beq .rm_acted
	jsr menu_select
	bcs .rm_done
.rm_acted
	lda ui_pressed
	beq .rm_loop
.rm_rel
	jsr wait_frame
	jsr ui_read_keys
	lda ui_keys
	bne .rm_rel
	jmp .rm_loop
.rm_done
	jsr menu_sfx_done
	lda #0
	sta $d015
	sta $d020
	sta $d021
	rts

menu_move_up
	lda menu_item
	sta menu_prev
	tax
	dex
	bpl .mmu
	ldx menu_size
	dex
.mmu
	stx menu_item
	jsr update_selection
	jmp sfx_movegun2

menu_move_down
	lda menu_item
	sta menu_prev
	tax
	inx
	cpx menu_size
	bcc .mmd
	ldx #0
.mmd
	stx menu_item
	jsr update_selection
	jmp sfx_movegun2

; Repaint only old + new rows (no clear / full redraw)
update_selection
	ldx menu_prev
	stx tmp4
	jsr draw_menu_item
	ldx menu_item
	stx tmp4
	jmp draw_menu_item

menu_esc
	jsr sfx_esc
	lda menu_stack_d
	beq .me_rts
	tax
	dex
	stx menu_stack_d
	lda menu_stk_m,x
	sta menu_id
	lda menu_stk_i,x
	sta menu_item
	jsr draw_menu
.me_rts
	rts

menu_vol_input
	lda menu_item
	bne .mvi_o				; only effects row (0); back is 1
	lda #UI_RIGHT
	and ui_pressed
	bne .mvi_i
	lda #UI_LEFT
	and ui_pressed
	beq .mvi_o
	jmp vol_fx_dec
.mvi_i
	jmp vol_fx_inc
.mvi_o
	rts

vol_fx_inc
	inc effects_vol
	lda effects_vol
	and #15
	sta effects_vol
	sta $d418
	jsr sfx_movegun1
	jmp sync_redraw
vol_fx_dec
	dec effects_vol
	lda effects_vol
	and #15
	sta effects_vol
	sta $d418
	jsr sfx_movegun1
sync_redraw
	jsr sync_vol_strings
	ldx menu_item
	stx tmp4
	jmp draw_menu_item

sync_vol_strings
	lda #<str_fx_vol
	sta ptr_l
	lda #>str_fx_vol
	sta ptr_h
	ldx #15
	lda effects_vol
	jmp write_vol2

write_vol2
	sta tmp0
	txa
	tay
	lda tmp0
	cmp #10
	bcc .wv1
	lda #'1'
	sta (ptr_l),y
	iny
	lda tmp0
	sec
	sbc #10
	clc
	adc #'0'
	sta (ptr_l),y
	rts
.wv1
	lda #' '
	sta (ptr_l),y
	iny
	lda tmp0
	clc
	adc #'0'
	sta (ptr_l),y
	rts

menu_select
	lda menu_id
	asl
	asl
	asl
	clc
	adc menu_item
	tax
	lda next_menu,x
	sta tmp0

	cmp #NM_BACK
	bne .ms_nb
	jsr menu_esc
	jmp .ms_st
.ms_nb
	lda tmp0
	cmp #NM_START
	bne .ms_nv
	lda menu_id
	cmp #2				; skill menu
	beq .ms_go
	jmp .ms_st
.ms_go
	jsr sfx_shoot
	lda menu_item
	sta difficulty
	lda #0
	sta $d015
	jsr clear_screen_all
	ldx #20
	jsr wait_frames_x
	sec
	rts
.ms_nv
	lda tmp0
	bmi .ms_tx
	; same-menu nop (e.g. sound sliders)
	cmp menu_id
	bne .ms_ne
	jmp .ms_st
.ms_ne
	bcc .ms_po
	jsr sfx_shoot
	ldx menu_stack_d
	lda menu_id
	sta menu_stk_m,x
	lda menu_item
	sta menu_stk_i,x
	inx
	stx menu_stack_d
	lda #0
	sta menu_item
	lda tmp0
	sta menu_id
	jsr draw_menu
	jmp .ms_st
.ms_po
	jsr sfx_shoot
	ldx menu_stack_d
	dex
	stx menu_stack_d
	lda menu_stk_i,x
	sta menu_item
	lda tmp0
	sta menu_id
	jsr draw_menu
	jmp .ms_st
.ms_tx
	lda tmp0
	cmp #NM_ORDER
	beq .ms_ord
	cmp #NM_CTRL
	beq .ms_ctl
	cmp #NM_HELP
	beq .ms_hlp
	cmp #NM_CREDITS
	beq .ms_crd
	cmp #NM_QUIT
	beq quit_to_basic
	jmp .ms_st
.ms_ord
	jsr sfx_shoot
	lda #<order_text
	ldy #>order_text
	jsr show_text_screen
	jmp .ms_ret
.ms_ctl
	jsr sfx_shoot
	lda #<control_text
	ldy #>control_text
	jsr show_text_screen
	jmp .ms_ret
.ms_hlp
	jsr sfx_shoot
	lda #<readthis1_text
	ldy #>readthis1_text
	jsr show_story_screen
	lda #<readthis2_text
	ldy #>readthis2_text
	jsr show_story_screen
	lda #<readthis3_text
	ldy #>readthis3_text
	jsr show_story_screen
	jmp .ms_ret
.ms_crd
	jsr sfx_shoot
	lda #<credits_text
	ldy #>credits_text
	jsr show_text_screen
.ms_ret
	jsr clear_screen
	jsr draw_menu
.ms_st
	clc
	rts

; Warm-start BASIC → READY.
quit_to_basic
	jsr sfx_shoot
	jsr menu_sfx_done
	sei
	lda #$37
	sta $01
	ldx #$ff
	txs
	jsr $ff8a				; RESTOR
	jsr $ff84				; IOINIT
	jsr $ff81				; CINT (default VIC/charset)
	lda #0
	sta $c6					; clear keyboard buffer (NDX)
	cli
	jmp ($a002)				; BASIC warm start

; Root→eps/sound/ctrl/help/credits/quit; E1→skill; E2-6→order; skill→start; sound stay/back
next_menu
	!byte 1, 3, NM_CTRL, NM_HELP, NM_CREDITS, NM_QUIT, 0, 0
	!byte 2, NM_ORDER, NM_ORDER, NM_ORDER, NM_ORDER, NM_ORDER, NM_BACK, 0
	!byte NM_START, NM_START, NM_START, NM_START, NM_BACK, 0, 0, 0
	!byte 3, NM_BACK, 0, 0, 0, 0, 0, 0

menu_sizes
	!byte 6, 7, 5, 2

; --- drawing ---------------------------------------------------------------
draw_menu
	jsr clear_screen

	ldx menu_id
	lda menu_sizes,x
	sta menu_size

	jsr calc_box
	jsr draw_section_title
	lda #COL_BOX
	sta cell_bg
	jsr fill_option_box

	ldx #0
.dm_l
	stx tmp4
	jsr draw_menu_item
	ldx tmp4
	inx
	cpx menu_size
	bcc .dm_l

	lda #COL_MAIN
	sta cell_bg
	lda #HINT_COL
	sta ui_text_col
	lda #<str_hint
	ldy #>str_hint
	ldx #HINT_ROW
	jmp print_centered

; Title two lines above the box
draw_section_title
	lda box_top
	sec
	sbc #2
	tax
	lda #COL_MAIN
	sta cell_bg
	lda #TITLE_COL
	sta ui_text_col
	ldy menu_id
	lda section_lo,y
	pha
	lda section_hi,y
	tay
	pla
	jmp print_centered

; box_top, box_left, box_width from menu strings
calc_box
	lda #0
	sta tmp2				; max len
	ldx #0
.cb_i
	stx tmp4
	lda menu_id
	asl
	asl
	asl
	clc
	adc tmp4
	tay
	lda menu_str_lo,y
	sta ui_str_l
	lda menu_str_hi,y
	sta ui_str_h
	jsr str_len
	cmp tmp2
	bcc .cb_n
	sta tmp2
.cb_n
	ldx tmp4
	inx
	cpx menu_size
	bcc .cb_i
	; Center option *text* on screen; pistol sits left with CURSOR_GAP.
	lda #40
	sec
	sbc tmp2				; max_len
	lsr
	sta tmp3				; text column
	sec
	sbc #1 + CURSOR_GAP			; cursor col
	sec
	sbc #BOX_PAD
	clc
	adc #1					; nudge box one column right
	sta box_left
	lda tmp2
	clc
	adc #1 + CURSOR_GAP			; cursor + gap
	adc #BOX_PAD
	adc #BOX_PAD
	sta box_width
	; Vertically center box (items + top/bottom gaps) below bar
	lda menu_size
	clc
	adc #BOX_VGAP
	adc #BOX_VGAP
	sta tmp5				; box_height
	lda #BADGE_TOP + MENU_LOGO_ROWS + 1
	sta box_top
	lda #HINT_ROW
	sec
	sbc tmp5				; last valid box_top
	sec
	sbc box_top
	bcc .cb_ok
	lsr
	clc
	adc box_top
	sta box_top
.cb_ok
	rts

draw_menu_item
	lda box_top
	clc
	adc #BOX_VGAP
	adc tmp4
	sta pr_row

	lda #COL_BOX
	sta cell_bg

	; Always clear pistol cell (needed for selection-only updates)
	lda box_left
	clc
	adc #BOX_PAD
	ldx pr_row
	jsr bmp_cell_addr
	ldy #0
	jsr bmp_blank_cell_y
	lda #COL_BOX
	sta (aux_l),y

	lda tmp4
	cmp menu_item
	beq .di_h
	lda #TEXT_COL
	sta ui_text_col
	jmp .di_g
.di_h
	lda #HILITE_COL
	sta ui_text_col
	lda box_left
	clc
	adc #BOX_PAD
	sta pr_col
	lda #CURSOR_CH
	jsr bmp_put_scr
.di_g
	lda menu_id
	asl
	asl
	asl
	clc
	adc tmp4
	tax
	lda menu_str_lo,x
	sta ui_str_l
	lda menu_str_hi,x
	sta ui_str_h
	lda box_left
	clc
	adc #BOX_PAD
	adc #1 + CURSOR_GAP
	ldx pr_row
	jmp print_at

; A/Y = text blob: body lines\0..., empty\0 ends.
; Brand bar + dark-blue box; ^text^ = white (spans may cross lines). Any key returns.
show_text_screen
	sta txt_ptr_l
	sty txt_ptr_h
	lda #COL_BOX
	sta cell_bg
	lda #TEXT_COL
	sta mark_col_a
	sta ui_text_col			; ^ spans persist across lines
	lda #HILITE_COL
	sta mark_col_b
	jmp .sts_body

; Read This! / endings: grey surround, white panel, black text. Restores COL_MAIN.
show_story_screen
	sta txt_ptr_l
	sty txt_ptr_h
	lda #STORY_BG
	sta clear_bg
	sta $d021
	lda #STORY_BOX
	sta cell_bg
	lda #STORY_TEXT
	sta mark_col_a
	sta mark_col_b
	sta ui_text_col
	jsr .sts_body
	lda #COL_MAIN
	sta clear_bg
	sta $d021
	lda #TEXT_COL
	sta mark_col_a
	lda #HILITE_COL
	sta mark_col_b
	rts

.sts_body
	jsr clear_screen
	jsr calc_text_box
	jsr apply_story_layout
	jsr fill_option_box
	ldx #0
.st_l
	stx tmp4
	ldy #0
	lda (ui_str_l),y
	beq .st_wait
	lda box_top
	clc
	adc #BOX_VGAP
	adc tmp4
	tax
	lda box_left
	clc
	adc #BOX_PAD
	jsr print_marked
	jsr str_skip
	ldx tmp4
	inx
	cpx menu_size
	bcc .st_l
.st_wait
	jsr wait_any_key
	rts

; Size box from body lines. Leaves ui_str at first line.
calc_text_box
	lda txt_ptr_l
	sta ui_str_l
	lda txt_ptr_h
	sta ui_str_h
	lda #0
	sta tmp2				; max visible len
	sta tmp4				; line count
.ct_l
	ldy #0
	lda (ui_str_l),y
	beq .ct_done
	jsr marked_str_len
	cmp tmp2
	bcc .ct_n
	sta tmp2
.ct_n
	jsr str_skip
	inc tmp4
	bne .ct_l
.ct_done
	lda tmp4
	sta menu_size
	lda tmp2
	clc
	adc #BOX_PAD
	adc #BOX_PAD
	sta box_width
	lda #40
	sec
	sbc box_width
	lsr
	sta box_left
	lda menu_size
	clc
	adc #BOX_VGAP
	adc #BOX_VGAP
	sta tmp5
	lda #BADGE_TOP + MENU_LOGO_ROWS + 1
	sta box_top
	lda #HINT_ROW
	sec
	sbc tmp5
	sec
	sbc box_top
	bcc .ct_ok
	lsr
	clc
	adc box_top
	sta box_top
.ct_ok
	lda txt_ptr_l
	sta ui_str_l
	lda txt_ptr_h
	sta ui_str_h
	rts

; Story pages: leave one light-blue row under the brand, center panel in grey.
apply_story_layout
	lda clear_bg
	cmp #STORY_BG
	bne .asl_rts
	ldx #0
	lda #COL_MAIN
.asl_r6
	sta SCREEN + BRAND_KEEP_ROWS * 40,x
	inx
	cpx #40
	bne .asl_r6
	lda menu_size
	clc
	adc #BOX_VGAP
	adc #BOX_VGAP
	sta tmp5				; box height
	lda #25
	sec
	sbc #STORY_GREY_TOP
	sec
	sbc tmp5				; spare rows in grey
	bcc .asl_min
	lsr
	clc
	adc #STORY_GREY_TOP
	sta box_top
	rts
.asl_min
	lda #STORY_GREY_TOP
	sta box_top
.asl_rts
	rts

; --- hires bitmap (full menufont) ------------------------------------------
init_menu_vic
	lda #$35				; I/O in, KERNAL out (menu_sfx IRQ uses $fffe)
	sta $01
	lda $dd00
	and #%11111100
	ora #%00000010			; VIC bank 1 ($4000-$7FFF)
	sta $dd00
	lda $d011
	and #%10000111			; clear ECM/BMM/DEN/RSEL
	ora #%00111011			; hires bitmap + enable + 25 rows
	sta $d011
	lda $d016
	and #%11100111			; hires (not MCM), 40 cols
	ora #%00001000
	sta $d016
	lda #%00001000			; matrix $4000, bitmap $6000
	sta $d018
	lda #0
	sta $d015
	lda #MENU_BORDER
	sta $d020
	lda #COL_MAIN
	sta $d021
	rts

; Clear rows BRAND_KEEP_ROWS..24 only — bar/badge stay put.
clear_screen
	lda #<BITMAP + BRAND_KEEP_ROWS * 320
	sta ptr_l
	lda #>BITMAP + BRAND_KEEP_ROWS * 320
	sta ptr_h
	ldy #0
	lda #>(BITMAP + $2000)
	sta tmp5
.cs_p
	lda #0
	sta (ptr_l),y
	iny
	bne .cs_p
	inc ptr_h
	lda ptr_h
	cmp tmp5
	bcc .cs_p
	; colour matrix from row 6: 760 bytes (do not touch sprite ptrs @ $43F8)
	ldx #0
	lda clear_bg
.cs_c
	sta SCREEN + BRAND_KEEP_ROWS * 40,x
	sta SCREEN + BRAND_KEEP_ROWS * 40 + $100,x
	inx
	bne .cs_c
	ldx #0
.cs_c2
	sta SCREEN + BRAND_KEEP_ROWS * 40 + $200,x
	inx
	cpx #248				; 240+512+248 = 1000
	bne .cs_c2
	rts

; Full bitmap + matrix clear (menu entry / exit).
clear_screen_all
	lda #<BITMAP
	sta ptr_l
	lda #>BITMAP
	sta ptr_h
	lda #0
	tax
	tay
.csa_p
	sta (ptr_l),y
	iny
	bne .csa_p
	inc ptr_h
	inx
	cpx #32
	bcc .csa_p
	ldx #0
	lda #COL_MAIN
.csa_c
	sta SCREEN,x
	sta SCREEN+$100,x
	sta SCREEN+$200,x
	sta SCREEN+$2e8,x
	inx
	bne .csa_c
	rts

fill_top_bar
	ldx #BAR_TOP
.ftb_r
	stx tmp4
	lda #0
	ldx tmp4
	jsr bmp_cell_addr
	ldy #39
.ftb_c
	jsr bmp_blank_cell_y
	lda #COL_BAR
	sta (aux_l),y
	dey
	bpl .ftb_c
	ldx tmp4
	inx
	cpx #BAR_TOP + BAR_ROWS
	bcc .ftb_r
	rts

; 3-row bar + 5-row badge + white logo + red sprite fill
draw_brand
	jsr fill_top_bar
	jsr fill_logo_badge
	jsr blit_menu_logo
	jmp setup_logo_sprites

fill_logo_badge
	ldx #0
.flb_r
	stx tmp4
	txa
	clc
	adc #BADGE_TOP
	tax
	lda #BADGE_LEFT
	jsr bmp_cell_addr
	ldy #0
.flb_c
	jsr bmp_blank_cell_y
	lda #COL_BAR
	sta (aux_l),y
	iny
	cpy #MENU_LOGO_COLS
	bcc .flb_c
	ldx tmp4
	inx
	cpx #MENU_LOGO_ROWS
	bcc .flb_r
	rts

blit_menu_logo
	lda #<menu_logo_data
	sta .bld + 1
	lda #>menu_logo_data
	sta .bld + 2
	ldx #0
.blr
	stx tmp4
	txa
	clc
	adc #BADGE_TOP
	tax
	lda #BADGE_LEFT
	jsr bmp_cell_addr
	ldx #0
.blc
	stx tmp5
	txa
	asl
	asl
	asl
	tay
	ldx #0
.blb
.bld	lda $ffff,x
	sta (ptr_l),y
	iny
	inx
	cpx #8
	bne .blb
	lda .bld + 1
	clc
	adc #8
	sta .bld + 1
	bcc .bln
	inc .bld + 2
.bln
	lda #HILITE_COL
	asl
	asl
	asl
	asl
	ora #COL_BAR
	ldy tmp5
	sta (aux_l),y
	ldx tmp5
	inx
	cpx #MENU_LOGO_COLS
	bcc .blc
	ldx tmp4
	inx
	cpx #MENU_LOGO_ROWS
	bcc .blr
	rts

setup_logo_sprites
	ldx #0
.slc0
	lda menu_logo_spr,x
	sta LOGO_SPR_RAM,x
	inx
	bne .slc0
	ldx #0
.slc1
	lda menu_logo_spr + $100,x
	sta LOGO_SPR_RAM + $100,x
	inx
	cpx #$c0
	bne .slc1
	ldx #0
	lda #LOGO_SPR_PTR0
.slp
	sta SCREEN + $3f8,x
	clc
	adc #1
	inx
	cpx #MENU_LOGO_SPR_COUNT
	bne .slp
	lda #COL_LOGO_RED
	ldx #0
.slcol
	sta $d027,x
	inx
	cpx #MENU_LOGO_SPR_COUNT
	bne .slcol
	ldx #0
	ldy #0
.slx
	lda logo_spr_x,x
	sta $d000,y
	iny
	iny
	inx
	cpx #MENU_LOGO_SPR_COUNT
	bne .slx
	lda #0
	sta $d010
	lda #50 + BADGE_TOP * 8 + MENU_LOGO_PAD_Y + MENU_LOGO_SPR_OFF_Y
	ldx #0
	ldy #1
.sly
	sta $d000,y
	iny
	iny
	inx
	cpx #MENU_LOGO_SPR_COUNT
	bne .sly
	lda #0
	sta $d01b				; sprites in front of bitmap
	sta $d017
	sta $d01d
	lda #%01111111
	sta $d015
	rts

logo_spr_x
	!byte 104, 128, 152, 176, 200, 224, 248

fill_option_box
	lda menu_size
	clc
	adc #BOX_VGAP
	adc #BOX_VGAP
	sta tmp5
	ldx #0
.fob_r
	stx tmp4
	txa
	clc
	adc box_top
	tax
	lda box_left
	jsr bmp_cell_addr
	ldy #0
.fob_c
	jsr bmp_blank_cell_y
	lda cell_bg
	sta (aux_l),y
	iny
	cpy box_width
	bcc .fob_c
	ldx tmp4
	inx
	cpx tmp5
	bcc .fob_r
	rts

; Blank 8 bitmap bytes for cell Y relative to ptr (col base). Saves Y.
bmp_blank_cell_y
	sty tmp1
	tya
	asl
	asl
	asl					; cell offset *8 within row strip
	tay
	lda #0
	sta (ptr_l),y
	iny
	sta (ptr_l),y
	iny
	sta (ptr_l),y
	iny
	sta (ptr_l),y
	iny
	sta (ptr_l),y
	iny
	sta (ptr_l),y
	iny
	sta (ptr_l),y
	iny
	sta (ptr_l),y
	ldy tmp1
	rts

; A=col X=row → ptr=bitmap cell, aux=screen matrix cell
bmp_cell_addr
	sta pr_col
	stx pr_row
	lda #0
	sta tmp3				; mat_off hi
	txa
	asl
	asl
	adc pr_row				; *5
	asl
	rol tmp3				; *10
	asl
	rol tmp3				; *20
	asl
	rol tmp3				; *40
	adc pr_col
	bcc .bca1
	inc tmp3
.bca1
	sta tmp2				; mat_off lo
	clc
	adc #<SCREEN
	sta aux_l
	lda tmp3
	adc #>SCREEN
	sta aux_h
	lda tmp2
	sta ptr_l
	lda tmp3
	sta ptr_h
	asl ptr_l
	rol ptr_h
	asl ptr_l
	rol ptr_h
	asl ptr_l
	rol ptr_h				; *8
	lda ptr_l
	clc
	adc #<BITMAP
	sta ptr_l
	lda ptr_h
	adc #>BITMAP
	sta ptr_h
	rts

print_centered
	sta ui_str_l
	sty ui_str_h
	stx pr_row
	jsr str_len
	lsr
	sta pr_len
	lda #20
	sec
	sbc pr_len
	bcs .pc
	lda #0
.pc
	ldx pr_row
print_at
	sta pr_col
	stx pr_row
	ldy #0
.pa
	lda (ui_str_l),y
	beq .pa_d
	sty tmp1
	jsr bmp_put_scr
	inc pr_col
	ldy tmp1
	iny
	bne .pa
.pa_d
	rts

; mark_col_a/b via ^; A=col X=row. Leaves ui_text_col so spans can cross lines.
print_marked
	sta pr_col
	stx pr_row
	ldy #0
.pm
	lda (ui_str_l),y
	beq .pm_d
	cmp #MARK_CARET
	bne .pm_ch
	lda ui_text_col
	cmp mark_col_a
	bne .pm_to_a
	lda mark_col_b
	jmp .pm_set
.pm_to_a
	lda mark_col_a
.pm_set
	sta ui_text_col
	iny
	bne .pm
.pm_ch
	sty tmp1
	jsr bmp_put_scr
	inc pr_col
	ldy tmp1
	iny
	bne .pm
.pm_d
	rts

; A = !scr byte → blit at pr_col/pr_row with ui_text_col / cell_bg
bmp_put_scr
	cmp #MARK_CARET
	beq .bps_rts
	jsr scr_to_font
	sta tmp0				; font index 0..95
	lda #0
	sta tmp5
	lda tmp0
	asl
	rol tmp5
	asl
	rol tmp5
	asl
	rol tmp5				; index*8
	clc
	adc #<menufont_udgs
	sta .bps_src + 1
	lda tmp5
	adc #>menufont_udgs
	sta .bps_src + 2
	lda pr_col
	ldx pr_row
	jsr bmp_cell_addr
	ldy #0
.bps_src
	lda $ffff,y				; patched
	sta (ptr_l),y
	iny
	cpy #8
	bne .bps_src
	lda ui_text_col
	asl
	asl
	asl
	asl
	ora cell_bg
	ldy #0
	sta (aux_l),y
.bps_rts
	rts

; !scr byte → font index (ascii-32). 1..26 = a..z; $20+ = ASCII.
scr_to_font
	cmp #27
	bcs .stf_asc
	cmp #1
	bcc .stf_sp
	clc
	adc #'a' - 1			; screencode → lowercase ASCII
	bne .stf_idx
.stf_asc
	cmp #' '
	bcc .stf_sp
	cmp #128
	bcc .stf_idx
.stf_sp
	lda #' '
.stf_idx
	sec
	sbc #' '
	rts

str_len
	ldy #0
.sl
	lda (ui_str_l),y
	beq .sl_d
	iny
	bne .sl
.sl_d
	tya
	rts

; Visible length ignoring ^ markers.
marked_str_len
	ldy #0
	ldx #0
.msl
	lda (ui_str_l),y
	beq .msl_d
	cmp #MARK_CARET
	beq .msl_s
	inx
.msl_s
	iny
	bne .msl
.msl_d
	txa
	rts

; Advance ui_str past current NUL-terminated string.
str_skip
	ldy #0
.ssk
	lda (ui_str_l),y
	beq .ssk_d
	iny
	bne .ssk
.ssk_d
	iny
	tya
	clc
	adc ui_str_l
	sta ui_str_l
	bcc .ssk_c
	inc ui_str_h
.ssk_c
	rts

wait_raster
	lda $d012
.wr
	cmp $d012
	beq .wr
	rts

wait_frame
.wf_hi
	lda $d011
	bpl .wf_hi
.wf_lo
	lda $d011
	bmi .wf_lo
	rts

wait_frames_x
.wf
	jsr wait_frame
	dex
	bne .wf
	rts

wait_key
.wk_up
	jsr ui_read_keys
	lda ui_keys
	bne .wk_up
.wk_dn
	jsr ui_read_keys
	lda ui_keys
	beq .wk_dn
.wk_rel
	jsr ui_read_keys
	lda ui_keys
	bne .wk_rel
	rts

; Any key (full keyboard matrix) — text screens.
; Wait for release + a few quiet frames so Return-to-enter doesn't bounce-dismiss.
wait_any_key
.wau
	lda #0
	sta $dc00
	lda $dc01
	cmp #$ff
	bne .wau
	ldx #5
.wau_s
	jsr wait_frame
	lda #0
	sta $dc00
	lda $dc01
	cmp #$ff
	bne .wau
	dex
	bne .wau_s
.wad
	lda #0
	sta $dc00
	lda $dc01
	cmp #$ff
	beq .wad
.war
	lda #0
	sta $dc00
	lda $dc01
	cmp #$ff
	bne .war
	rts

ui_read_keys
	lda ui_keys
	sta ui_old
	lda #0
	sta ui_keys

	lda #$fd
	sta $dc00
	lda $dc01
	tax
	and #$02
	bne .urk_now
	lda ui_keys
	ora #UI_UP
	sta ui_keys
.urk_now
	txa
	and #$20
	bne .urk_nos
	lda ui_keys
	ora #UI_DOWN
	sta ui_keys
.urk_nos
	txa
	and #$04
	bne .urk_noa
	lda ui_keys
	ora #UI_LEFT
	sta ui_keys
.urk_noa
	lda #$fb
	sta $dc00
	lda $dc01
	and #$04
	bne .urk_nod
	lda ui_keys
	ora #UI_RIGHT
	sta ui_keys
.urk_nod
	lda #$fe
	sta $dc00
	lda $dc01
	and #$02
	bne .urk_noret
	lda ui_keys
	ora #UI_SELECT
	sta ui_keys
.urk_noret
	lda #$7f
	sta $dc00
	lda $dc01
	and #$80
	bne .urk_noesc
	lda ui_keys
	ora #UI_ESC
	sta ui_keys
.urk_noesc
	lda ui_old
	eor #$ff
	and ui_keys
	sta ui_pressed
	rts

; --- state / strings --------------------------------------------------------
menu_id		!byte 0
menu_item	!byte 0
menu_prev	!byte 0
menu_size	!byte 0
menu_stack_d	!byte 0
menu_can_ret	!byte 0
menu_stk_m	!byte 0, 0, 0
menu_stk_i	!byte 0, 0, 0
box_top		!byte 0
box_left	!byte 0
box_width	!byte 0
ui_keys		!byte 0
ui_old		!byte 0
ui_pressed	!byte 0
ui_text_col	!byte 0
pr_row		!byte 0
pr_col		!byte 0
pr_len		!byte 0
txt_ptr_l	!byte 0
txt_ptr_h	!byte 0
cell_bg		!byte 0
clear_bg	!byte COL_MAIN
mark_col_a	!byte TEXT_COL
mark_col_b	!byte HILITE_COL

str_hint	!scr "W/S move  A/D adjust  Return select",0
str_new_game	!scr "New Game",0
str_sound	!scr "Sound",0
str_control	!scr "Control",0
str_read_this	!scr "Read This!",0
str_credits	!scr "Credits",0
str_quit	!scr "Quit",0
str_back	!scr "Back",0
str_e1		!scr "Escape from Wolfenstein",0
str_e2		!scr "Operation Eisenfaust",0
str_e3		!scr "Die, Fuhrer, Die!",0
str_e4		!scr "A Dark Secret",0
str_e5		!scr "Trail of the Madman",0
str_e6		!scr "Confrontation",0
str_fx_vol	!scr "Effects Volume 15",0
str_itytd	!scr "Can I play, Daddy?",0
str_dhm		!scr "Don't hurt me.",0
str_hmp		!scr "Bring 'em on!",0
str_uv		!scr "I am Death incarnate!",0

str_sec_main	!scr "Options",0
str_sec_new	!scr "Which episode to play?",0
str_sec_skill	!scr "How tough are you?",0
str_sec_sound	!scr "Sound",0

section_lo
	!byte <str_sec_main, <str_sec_new, <str_sec_skill, <str_sec_sound
section_hi
	!byte >str_sec_main, >str_sec_new, >str_sec_skill, >str_sec_sound

!source "menu_text.asm"

menu_str_lo
	!byte <str_new_game, <str_sound, <str_control, <str_read_this
	!byte <str_credits, <str_quit, 0, 0
	!byte <str_e1, <str_e2, <str_e3, <str_e4
	!byte <str_e5, <str_e6, <str_back, 0
	!byte <str_itytd, <str_dhm, <str_hmp, <str_uv
	!byte <str_back, 0, 0, 0
	!byte <str_fx_vol, <str_back, 0, 0
	!byte 0, 0, 0, 0
menu_str_hi
	!byte >str_new_game, >str_sound, >str_control, >str_read_this
	!byte >str_credits, >str_quit, 0, 0
	!byte >str_e1, >str_e2, >str_e3, >str_e4
	!byte >str_e5, >str_e6, >str_back, 0
	!byte >str_itytd, >str_dhm, >str_hmp, >str_uv
	!byte >str_back, 0, 0, 0
	!byte >str_fx_vol, >str_back, 0, 0
	!byte 0, 0, 0, 0

!source "menu_logo.asm"
!source "../assets/menufont.asm"
!source "playsound.asm"
!source "menu_sfx.asm"
!source "menu_pcsounds.asm"
!source "pcsfreq.asm"

end_menu = *
!if end_menu > $4000 {
	!error "Menu overlaps SCREEN; end=$", end_menu
}
