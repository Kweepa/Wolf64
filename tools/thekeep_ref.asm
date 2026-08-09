;*****************************************
;
; THE KEEP
;
; for the unexpanded VIC-20
;
; First person texture mapped raycasting game
; with random level generation
;
; Compile with ACME v0.91 or above
; Then compress with pucrunch
;
;*****************************************

!to "thekeep-unc.prg", cbm
!sl "pit.lbl"


tmp         = $8
tmp2        = $9
tmp3        = $a
min         = $b
max         = $c
range       = $d
shf         = $e
mask        = $f

x           = $17
y           = $18
direction   = $19
col         = $1c
w           = $1d
h           = $1e
xloopi      = $1f
yloopi      = $20
xloopstore  = $21
yloopstep   = $22
disjoint    = $27
loops       = $28
runlength   = $29
clampval    = $2a
roomudgindex = $2b
num         = $2c
tileendlow  = $2f

; put everything on the zero page!
; may need to jig these around to avoid locations trashed by interrupts


mac     = $10
aux     = $14
ddx     = $18
ddy     = $1a
xstep   = $1c
ystep   = $1e
sdx     = $20
sdy     = $22
playerx = $24
playery = $26

keys    = $2a ; 3 bytes
hit     = $2f
texy    = $30 ; 2 bytes

angle   = $32
sx      = $33
dxindex = $34
dyindex = $35
hitexit = $36
wallz   = $38
texIndex = $3a
texx    = $3b
wallx   = $3c ; 2 bytes
wally   = $3e ; 2 bytes
pcosa   = $80
mcosa   = $82
psina   = $84
msina   = $86
tile    = $88

sndptr  = $8a
maptype = $8c
udlamp  = $8d ; need to update lamp display
joy     = $8e

; initialized variables
initializedVariables = $d8
lookang = $d8
lfsr    = $d9 ; 2 bytes
numkeys = $db
floor   = $dc
ttnfoot = $dd ; time to next footstep
sndply  = $de
lamp    = $df ; lamp value
dlamp   = $e0 ; lamp countdown
sdlamp  = $e1 ; should count down lamp?

texcache = $e2

lastkey = $c5
tilestart   = $1e00
tileend     = $1fe3 ; 21x23
auxcol      = $60
irqVector   = $314
irqContinue = $eabf


*=$1000

; don't need the basic stub for a pucrunched program
!if 0 {
*=$1001
; BASIC stub
; 2011SYS4107
        !word $100b
        !word 2011
        !byte 158 ; SYS
        !text "4107",0
        jsr initCode
}

newgame
        ; set variables
        ldx #9
-       lda varVal,x
        sta initializedVariables,x
        dex
        bpl -

newmap
        jsr makemap

entergame
        jsr set_up_hud
        lda #0
        sta hitexit

mainloop
        inc sdlamp
        jsr move
        jsr collide
        jsr render
        dec sdlamp

		lda keys+1 ; I
		and #16
		tax
		bne mapscreen
		
		lda lamp
		beq eaten_by_grue

        lda hitexit
        beq mainloop
+
        lda floor
        bne newmap

        ; freedom!
        ldx #8
        ldy #3
        jsr set_vic_regs_for_screen_xy
-
        ldx #(freedomstring - stringstoprint)
        ldy #0
        jsr printStrings
		jmp -


		

mapscreen
		ldx #21
		ldy #23
		jsr set_vic_regs_for_screen_xy
		ldx #31
-       lda arrowgfx,x
        sta $1c00,x
        dex
        bpl -
		ldy #0
-
		lda $9400,y
		jsr filtermapblock
		sta $1e00,y
		txa
		sta $9600,y
		lda $9500,y
		jsr filtermapblock
		sta $1f00,y
		txa
		sta $9700,y
		iny
		bne -
		ldx playerx+1
		ldy playery+1
		jsr xy_to_tile_map
		lda lookang
		adc #32
		rol
		rol
		rol
		and #3
		ldy #0
		sta (tile),y
		lda tile+1
		clc
		adc #($96-$1e)
		sta tile+1
		lda #1
		sta (tile),y
mapwait
        sei
        jsr clearkeys
        jsr checkkeys
		lda keys+1 ; I
		and #16
		tax
        bne mapwait
        cli
		jmp entergame

eaten_by_grue
        inc sdlamp
        sta $900f
        sta $9003
        ldy #Sound_Grue
        jsr playSound
-       ldy lamp
        bpl -
        iny
        ldx #(gruestring - stringstoprint)
        jsr printStrings
        lda floor
        ldx #37
        jsr write3digitnumtoscreen
        ldx #8
        ldy #6
        jsr set_vic_regs_for_screen_xy
        lda #$05  ; bg colour black, border colour green
        sta $900f
-       lda lamp
        cmp #253
        bne -
        jmp newgame

varVal !byte 160,43,117,3,1,5,5,30,60,0

mapgfx !byte 128,128+102,128+102,128+102,128+4,128+5,128+11,128+11
arrowgfx
    !byte 255,255,157,96,96,157,255,255
    !byte 231,219,219,231,231,231,195,231
    !byte 255,255,185,6,6,185,255,255
    !byte 231,195,231,231,231,219,219,231

filtermapblock
		pha
		and #8
		tax
		beq +
		pla
		and #7
		tax
		lda mapgfx,x
		rts
+		pla
		lda #(128+86)
		tax
		rts

set_vic_regs_for_screen_xy
        stx tmp
        sty tmp2
        asl tmp2
        lda $ede4    ; load ROM horizontal screen origin
        adc #22
        sec
        sbc tmp
        sta $9000
        lda $ede5    ; load ROM vertical screen origin
        adc #(2*23)
        sec
        sbc tmp2
        sta $9001
        lda tmp
        ora #128
        sta $9002
        lda tmp2
        sta $9003
        rts

makemap
        ; set up vic registers for map generation
        ldx #1
        ldy #0
        jsr set_vic_regs_for_screen_xy

        ldx #0
        lda #2      
colorloop
        sta $1e00,x
        sta $1f00,x
        inx
        bne colorloop

markborders           ; 33 bytes just to fill the borders :(
        ldy #20
borderloop
        lda #18
        sta $1e00,y
        sta $1fce,y
        tya
        pha
        iny
        ldx #0
        jsr xy_to_tile_map
        ldy #0
        lda #18
        sta (tile),y
        ldy #20
        sta (tile),y
        pla
        tay
        dey
        bpl borderloop

        ldx #1
        lda #2
        jsr rand_num
udgroomloop
        jsr random_udg_room
        dec num
        bpl udgroomloop
       
        ldx #1
        lda #4
        jsr rand_num
rectroomloop
        jsr random_rect_room
        dec num
        bpl rectroomloop
        
newcorridorloop
        jsr random_corridor
        jsr check_connected
        beq newcorridorloop
        
; create doors, keys, player, exit
        ldx #2
        lda #5
        jsr rand_num
keyloop
        jsr random_key
        dec num
        bpl keyloop


        ldx #4
        lda #8
        jsr rand_num
doorloop
        jsr random_door
        dec num
        bpl doorloop

random_exit
        jsr random_key
        lda #5
        sta (tile),y
        lda x
        sta playerx
        lda y
        sta playery

		lda #5
		sta num
        lda #0
        sta tmp2
random_player
        jsr random_point
        ldx x
        ldy y
        jsr xy_to_tile_map
        ldy #0
        lda (tile),y
        bne random_player
manhattan
		lda x
		sbc playerx
		bpl +
		eor #$ff
+		sta tmp
		lda y
		sbc playery
		bpl +
		eor #$ff
+		adc tmp
		cmp tmp2
		bmi +
		sta tmp2
        lda x
        sta playerx+1
        lda y
        sta playery+1
+
		dec num
		bpl random_player

        lda #$7f
        sta playerx
        sta playery

copy_to_colormem
        ldx #0
-
        lda $1e00,x
        sta $9400,x
        lda $1f00,x
        sta $9500,x
        inx
        bne -
        rts

roomudgs
        !byte 124,238,198,238,254,124,56,0
        !byte 80,248,248,248,80,0,0,0
        !byte 254,230,174,130,234,206,254,0
        !byte 254,146,186,186,186,130,254,0
        !byte 248,168,248,168,248,168,248,0
        !byte 254,254,146,214,146,254,254,0
        !byte 214,254,214,16,214,254,214,0
        !byte 130,254,254,254,254,254,130,0
roomwidths  !byte 7, 5, 7, 7, 5, 7, 7, 7
roomheights !byte 7, 5, 7, 7, 7, 7, 7, 7


rando   ; 50 bytes, plus 7 zp
; x = min
; a = max

        stx min
        sec
        sbc min
        sta range
        sta shf
        inc range

maskloop
        ora shf
        lsr shf
        bne maskloop

        sta mask
        sta shf

        lda #0

randloop

        lsr lfsr+1
        ror lfsr

        bcc noxor
        pha
        lda lfsr+1
        eor #$b4
        sta lfsr+1
        pla
noxor

        rol
        and mask

        lsr shf
        bne randloop

        cmp range
        bcs randloop

        adc min
        rts

rand_num
		jsr rando
		sta num
		rts

random_point ; 17 bytes

        ldx #2
        lda #18
        jsr rando
        sta x
        lda #20
        jsr rando
        sta y
        rts

xy_to_tile_game
        ; $9400 + y*21 + x
        stx tmp
        tya
        clc
        adc tmp
        sta tile ; y+x
        tya
        asl
        asl
        pha
        adc tile ; max value for tile is 130 at this point
        sta tile ; 4*y + y + x
        pla
        asl
        asl
        pha
        lda #$94
        adc #0
        sta tile+1 ; $94 or $95
        pla
        adc tile
        sta tile
        lda tile+1
        adc #0
        sta tile+1
        rts
        
xy_to_tile_map
        jsr xy_to_tile_game
        lda tile+1
        sec
        sbc #$76 ; $94 - $1e
        sta tile+1
        rts

boxloop ; 61 bytes
        sta boxloopfn+1
        stx boxloopfn+2
        lda x
        sec
        sbc w
        tax
        lda y
        sec
        sbc h
        tay
        jsr xy_to_tile_map ; store the top left in tile
        lda w
        sec
        rol
        sta xloopi
        sta xloopstore
        lda h
        sec
        rol
        sta yloopi

        lda #21
        sec
        sbc xloopstore
        sta yloopstep

        ldy #0

boxloopcallback
boxloopfn
        jsr $1000

        iny
        dec xloopi
        bne boxloopcallback

        tya
        clc
        adc yloopstep
        tay
        lda xloopstore
        sta xloopi

        dec yloopi
        bne boxloopcallback

        rts

paintfn ; 9 bytes
        lda (tile),y
        beq nopaint
        and #$10 ; preserve border
        ora col
        sta (tile),y
nopaint
        rts

paint   ; 16 bytes

        inc w
        inc h
        lda #<paintfn
        ldx #>paintfn
        jsr boxloop
        dec w
        dec h
        rts

clamp   ; 22 bytes /232
        sta tmp ; x
        lda clampval ; w
        clc
        adc #1
        cmp tmp ; compare w+1 with x
        bcc clampskip1 ; bcc means (w+1) < x
        rts
clampskip1
        tya   ; W
        sec
        sbc clampval ; w
        cmp tmp ; compare W-w with x
        bcs clampskip2 ; bcs means (W-w) >= x
        rts
clampskip2
        lda tmp ; x
        rts

checkspacefn ; 7 bytes
        lda (tile),y
        bne spacehere
        sta tmp
spacehere
        rts

resetloops ; 5 bytes
        lda #255
        sta loops
        rts

clamproom ; 27 bytes
        lda w
        sta clampval
        ldy #19
        lda x
        jsr clamp
        sta x

        lda h
        sta clampval
        ldy #21
        lda y
        jsr clamp
        sta y
        rts

checkforspace ; 14 bytes
        lda #1
        sta tmp
        inc w
        inc h
        lda #<checkspacefn
        ldx #>checkspacefn
        jsr boxloop
        dec w
        dec h
        lda tmp
        rts

paintroom ; 13 bytes
        ldx #1
        lda #3
        jsr rando
        sta col
        jsr paint
        rts

cutoutroomfn ; 5 bytes
        lda #0
        sta (tile),y
        rts

random_rect_room ; 46 bytes / 331

        jsr resetloops

tryrectroomagain
        jsr random_point
        ldx #1
        lda #2
        jsr rando
        sta w
        lda #2
        jsr rando
        sta h
        jsr clamproom

; check for space to place a room

        jsr checkforspace
        bne roomhasspace

        dec loops
        bne tryrectroomagain
        rts

roomhasspace

        lda #<cutoutroomfn
        ldx #>cutoutroomfn
        jsr boxloop

        jsr paintroom
        rts


udgroomfn         ; 25 bytes
        lda roomudgindex
        asl
        asl
        asl
        clc
        adc yloopi
        tax
        dex
        lda roomudgs,x
        ldx xloopi
udgshift
        asl
        dex
        bne udgshift
        bcc noudgpaint
        lda #0
        sta (tile),y
noudgpaint
        rts

random_udg_room  ; 55 bytes

        jsr resetloops

tryudgroomagain
        jsr random_point
        ldx #0
        lda #7
        jsr rando
        sta roomudgindex
        tax
        lda roomwidths,x
        lsr
        sta w
        lda roomheights,x
        lsr
        sta h
        jsr clamproom

        jsr checkforspace
        bne udgroomhasspace

        dec loops
        bne tryudgroomagain
        rts

udgroomhasspace

        lda #<udgroomfn
        ldx #>udgroomfn
        jsr boxloop

        jsr paintroom
        dec w
        dec h
        ; add #32 to center of rooms
        ldx #1
        lda #3
        jsr rando
        ora #32
        sta col
        jsr paint
        rts


tileloop   ; 31 bytes

        sta tileloopfn+1
        stx tileloopfn+2
        sty tileendlow

        lda #<tilestart
        sta tile
        lda #>tilestart
        sta tile+1

tileloopcontinue
tileloopcallback
        ldy #0
        clc
tileloopfn
        jsr $1000

        bcs endtileloop ; early out

        inc tile
        bne tileloopskip1
        inc tile+1
tileloopskip1

        lda tile
        cmp tileendlow
        bne tileloopcontinue
        lda tile+1
        cmp #>tileend
        bne tileloopcontinue

endtileloop
        rts


findandmarkfloorfn    ; 10 bytes
        lda (tile),y
        bne notfloor
        lda #8
        sta (tile),y
        sec
notfloor
        rts

clearfloormarksfn    ; 19 bytes
        lda (tile),y
        bne notdisjoint
        sta disjoint
        beq keepclearing
notdisjoint
        lda (tile),y
        and #(255-8) ; remove flood mark
        sta (tile),y
keepclearing
        rts
        
neighbstab !byte 21,23,43,1

floodfloorfn        ; 31 bytes
        tya  ; .Y=0 on entry
        ldx #3
-       ldy neighbstab,x
        ora (tile),y
        dex
        bpl -
        and #8
        tax
        beq keepflooding
        iny
        lda (tile),y
        bne keepflooding
        lda #8 ; add flood mark
        sta (tile),y
        sta tmp
keepflooding
        rts

check_connected         ; 37 bytes

; find a floor
		ldy #$f3
        lda #<findandmarkfloorfn
        ldx #>findandmarkfloorfn
        jsr tileloop

floodagain
        lda #0
        sta tmp

		ldy #$cd
        lda #<floodfloorfn
        ldx #>floodfloorfn
        jsr tileloop

        ldx tmp
        bne floodagain

        inx
        stx disjoint

		ldy #$f3
        lda #<clearfloormarksfn
        ldx #>clearfloormarksfn
        jsr tileloop

        lda disjoint
        rts

reset_runlength
        ldx #3
        lda #6
        jsr rando
        sta runlength
        rts

turn_right
        inc direction
        inc direction
turn_left
        dec direction
        lda direction
        and #3
        tax
        stx direction
        jsr reset_runlength
        rts

random_offset_tile       
        jsr random_point
        ldx x
        dex
        dex
        ldy y
        dey
        dey
        jsr xy_to_tile_map
        ldy #44 ; center
        lda (tile),y
        rts

; 0   1  2  3  4
; 21 22 23 24 25
; 42 43 44 45 46
; 63 64 65 66 67
; 84 85 86 87 88

edgetestnotwall !byte 43,23,45,65
edgetestiswall2 !byte 23,43,23,43
edgetestiswall3 !byte 65,45,65,45

get_wall_point
        jsr random_offset_tile
        beq didnt_find_good_wall
        sta col

        ldx #3
edgenextdirection
        ldy edgetestnotwall,x
        lda (tile),y
        bne failedgetest
        ldy edgetestiswall3,x
        lda (tile),y
        beq failedgetest
        ldy edgetestiswall2,x
        lda (tile),y
        bne found_good_wall
failedgetest
        dex
        bpl edgenextdirection
didnt_find_good_wall
        clc
        rts
found_good_wall
        ldy #44
		sec
		rts

		
corr_complete
        clc
        ldy edgetestiswall2,x
        jsr corr_complete_in_direction
        ldy edgetestiswall3,x
        jsr corr_complete_in_direction
        ldy fwd,x

corr_complete_in_direction
+       lda (tile),y
        bne +
        sec
+
        rts

fwd     !byte 45,65,43,23
fwd2    !byte 46,86,42,2
lft     !byte 25,87,63,1
rgt     !byte 67,85,21,3

random_corridor

		jsr get_wall_point
		bcc random_corridor
        stx direction
		lda (tile),y
		and #32
		tax
		bne random_corridor
        lda #0
		sta (tile),y

        ldx direction
        jsr corr_complete
        bcc +
        rts
+       
        jsr reset_runlength
        
corr_loop

        ldx direction
        ldy fwd2,x
        lda (tile),y
        beq corr_checkborder
        ldy lft,x
        lda (tile),y
        bne corr_checkright
        jsr turn_right
        jmp corr_advance
corr_checkright
        ldy rgt,x
        lda (tile),y
        bne corr_checkborder
        jsr turn_left
        jmp corr_advance
corr_checkborder
        lda runlength
        beq corr_turnrandom
        ldy fwd,x
        lda (tile),y
        and #16
        tax
        beq corr_advance
corr_turnrandom
        ldx #0
        lda #1
        jsr rando
        beq corr_turnleft
        jsr turn_right
        jmp corr_advance
corr_turnleft
        jsr turn_left

corr_advance

        lda tile
        sec
        sbc #44
        sta tile
        lda tile+1
        sbc #0
        sta tile+1

        ldx direction
        lda tile
        clc
        adc fwd,x
        sta tile
        lda tile+1
        adc #0
        sta tile+1

        dec runlength

        ; before writing, check for border
        ldy #44
        lda (tile),y
        and #16
        tax
        bne corr_end
        sta (tile),y

        ldx direction
        jsr corr_complete
        bcs corr_end

        ldy fwd,x
        jsr paintfn
        ldy edgetestiswall2,x
        jsr paintfn
        ldy edgetestiswall3,x
        jsr paintfn
        jmp corr_loop

corr_end
        rts


random_key
random_key_start
        jsr get_wall_point
        bcc random_key_start
        lda #7
        sta (tile),y
        rts
        
doorneighbs !byte 22,23,24,45,66,65,64,43
doorpatterns
    !byte %01110111, %11011101
    !byte %11011000, %01100011, %10001101, %00110110

random_door
        jsr resetloops
random_door_start
        jsr random_offset_tile
        bne try_door_again
        ; .A=0

        ; generate a bitfield of the neighbours
        ; door can be placed if this is %0101 or %1010
        ldx #7
-
		sta tmp
		ldy doorneighbs,x
        clc
		lda (tile),y
		beq +
		cmp #4
		beq try_door_again
		sec
+    	lda tmp
        rol
		dex
		bpl -

        ldx #5
-       cmp doorpatterns,x
        beq place_door
        dex
        bne -

try_door_again
        dec loops
        bne random_door_start
        rts

place_door
        ldy #44
        lda #4
        sta (tile),y
        rts




Sound_Grue = 0
Sound_Climb = 1
Sound_Door = 2
Sound_Key = 3
Sound_Foot = 4

; ensure these are all on one page
doorSound !byte $70+15, 130, 135, 137, 160, 177, 0
keySound  !byte $70+15, 224, 210, 224, 210, 237, 0
footSound !byte auxcol+5, 128, 130, 0
climbSound !byte auxcol+5
    !byte 128, 130, 127, 127, 127, 127, 127
    !byte 135, 137, 127, 127, 127, 127, 127
    !byte 142, 144, 127, 127, 127, 127, 127
    !byte 149, 151, 127, 127, 127, 127, 127, 0
soundTable
; this order determines the priority
; note I'm using code as a sound effect - for the grue
!byte <playSound, <climbSound, <doorSound, <keySound, <footSound

playSound
        cpy sndply
        bmi +
        rts
+
        sei
        sty sndply
; set up the pointer to the data
        lda soundTable,y
        sta sndptr
        lda #>doorSound
        sta sndptr+1
; set the volume
        ldy #0
        lda (sndptr),y
        sta $900e
        inc sndptr
        cli
        rts


; $fb - keyboard line containing <Ctrl>ADGJL;<Right> [--LJ-DA-]
; $fd - keyboard line containing <Left>WRYIP*<Ret> [---I-RW-]
; $df - keyboard line containing <CBM>SFHK:=<F3> [-----FS-]
keyMaskTab !byte $fb, $fd, $df

; FIRE LEFT DOWN UP RIGHT
joykeybyte !byte 1,0,2,1,0
joykeybit !byte 16,16,2,2,32

checkkeys
        ldx #2
keycheckloop
        lda keyMaskTab,x
        sta $9120
        lda $9121
        eor #$ff
        ora keys,x
        sta keys,x
        dex
        bpl keycheckloop

        ; read joystick and poke into keys
        lda #$7f
        sta $9122
        lda $9120
        asl ; put RIGHT into carry bit
        lda $9111
        eor #$ff
        and #$3c
        bcs +
        adc #$02
+       lsr
        sta joy
        ; joy contains 0 0 0 FIRE LEFT DOWN UP RIGHT
        ; restore state of DDR
        ldy #$ff
        sty $9122

        ldx #4
-       lsr joy
        bcc +
        ldy joykeybyte,x
        lda joykeybit,x
        ora keys,y
        sta keys,y
+       dex
        bpl -
        rts

updateInputIrq

; check this came from timer 1
        bit $912d
        bpl endIrq

        lda sdlamp
        beq +
        dec dlamp
        bne +
        dec dlamp
        dec lamp
        lda #0
        sta udlamp
+

        jsr checkkeys

        ; play next sample
        ldy #0
        lda (sndptr),y
        beq stopPlaying
        sta $900d
        inc sndptr
        bne endIrq

stopPlaying:
        lda #auxcol
        sta $900e
        lda #5
        sta sndply

endIrq
        jmp irqContinue


; fixed point 8:8 x 0:8 -> 8:8
; 141/182/223 cycles + 7*5=35 cycles loop overhead
; 49 bytes
;
; multiplicand in aux and aux+1
; multiplier in A
; result in AX (A low, X high)
;

mul_16x8
        ; 21 bytes
        ; 2+2+3+2+2+3+3 = 17
        ; 2+2+3+3+3+2+3+3+2 = 23

        eor #$ff    ; invert the multiplier to remove clc before adc
mul_16x8_eor
        lsr
        sta tmp
        bcc +
        lda #0
        sta mac+1
        beq ++
+
        lda aux+1
        lsr
        sta mac+1
        lda aux
        ror
++

		ldx #7
-
        ; 20 bytes
        ; 5+2+5+3+2 = 17
        ; 5+3+3+2+3+3+2+3+2+2 = 28
        lsr tmp
        bcc +
        lsr mac+1
        bpl ++
+
        adc aux
        tay
        lda mac+1
        adc aux+1
        ror
        sta mac+1
        tya
++
        ror
        
        dex
        bne -
        
        ldx mac+1
        rts


calc_wall_z
        sta aux
        stx aux+1

        ; wallz = [sdx|sdy] * fishes[sx]
        ldy sx
        lda fishes,y
        jsr mul_16x8

        ; texstep = wallz>>2
        ; texy = wallz>>3
        ; note - wallz and texstep are aliases

        stx wallz+1
        lsr wallz+1
        ror
        lsr wallz+1
        ror

        sta texy
        sta sm_texstep_lo+1
        lda wallz+1
        sta sm_texstep_hi+1
        lsr
        ror texy
        sta texy+1

		rts

render

        ldx #0
        stx sx

xloop

        clc
        lda angles,x
        adc lookang
        sta angle

        and #127
        cmp #63
        bcc +
        eor #127
+       sta dxindex


        tax
        lda fixsecl,x
        sta ddx
        sta sm_ddx_lo+1
        lda fixsech,x
        sta ddx+1
        sta sm_ddx_hi+1

        lda angle
        clc
        adc #64
        sta tmp
        and #127
        cmp #63
        bcc +
        eor #127
+       sta dyindex


        tax
        lda fixsecl,x
        sta ddy
        sta sm_ddy_lo+1
        lda fixsech,x
        sta ddy+1
        sta sm_ddy_hi+1

        lda ddx
        sta aux
        lda ddx+1
        sta aux+1

        lda tmp
        bmi +
        
        lda playerx
        ldx #1 ; xstep = 1
        ldy #0
        beq ++
+
        lda playerx
        eor #$ff
        ldx #255 ; xstep = -1
        ldy #255
++
        stx xstep
        stx sm_xstep_lo+1
        sty xstep+1
        sty sm_xstep_hi+1
        
        ; sdx = LO(x)*ddx (or (255-LO(x))*ddx
        jsr mul_16x8_eor
        sta sdx
        stx sdx+1
        

        lda ddy
        sta aux
        lda ddy+1
        sta aux+1

        lda angle
        bmi +

        lda playery
        ldx #21 ; ystep = 21
        ldy #0
        beq ++
+        
        lda playery
        eor #$ff
        ldx #235 ; ystep = -21
        ldy #255
++
        stx ystep
        stx sm_ystep_lo+1
        sty ystep+1
        sty sm_ystep_hi+1

        ; sdy = LO(y)*ddy (or (255-LO(y))*ddy
        jsr mul_16x8_eor
        sta sdy
        stx sdy+1


        ldx playerx+1
        ldy playery+1
        jsr xy_to_tile_game

        ldy #0

innerloop

        lda sdx+1
        cmp sdy+1
        bcc advancex
        bne advancey
        lda sdx
        cmp sdy
        bcs advancey

advancex

        clc
        lda tile
sm_xstep_lo
        adc #0
        sta tile
        lda tile+1
sm_xstep_hi
        adc #0
        sta tile+1
 
        lda (tile),y
        ora #$08
        sta (tile),y

        and #$07
        bne hitx

        lda sdx
sm_ddx_lo
        adc #0
        sta sdx
        lda sdx+1
sm_ddx_hi
        adc #0
        sta sdx+1

        ; overflow of sdx will end the ray
        bcc innerloop

advancey

        clc
        lda tile
sm_ystep_lo
        adc #0
        sta tile
        lda tile+1
sm_ystep_hi
        adc #0
        sta tile+1

        lda (tile),y
        ora #$08
        sta (tile),y

        and #$07
        bne hity

        lda sdy
sm_ddy_lo
        adc #0
        sta sdy
        lda sdy+1
sm_ddy_hi
        adc #0
        sta sdy+1

        jmp innerloop

hitx
        sta texIndex
        
        lda sdx
        ldx sdx+1
        jsr calc_wall_z

        lda playery
        sta tmp2
        ; texx = sdx * fixcos[dyindex]
        ldy dyindex
        lda fixcos,y
        jsr mul_16x8
       
        ldx ystep+1
        jmp hitcommon
       
hity
        sta texIndex

        lda sdy
        ldx sdy+1
        jsr calc_wall_z

        lda playerx
        sta tmp2
        ; texx = sdy * fixcos[dxindex]
        ldy dxindex
        lda fixcos,y
        jsr mul_16x8

        ldx xstep+1

hitcommon

        cpx #0
        bne +
        clc
        adc tmp2
        jmp ++
   
+
        sec
        sbc tmp2
        eor #$ff

++

        ; texx >>= 5
        lsr
        lsr
        lsr
        lsr
        lsr
        sta texx

        and #3
        sta tmp
        tax
        lda tmasktab,x
        sta sm_tmask+1



        ; calculate appropriate UDG column
        ; set up shifts/masks (for screen and texture)

        ; (texx&3) + 3 - (sx&3)

        lda sx
        and #3
        sta tmp2
        lda tmp   ; texx&3
        clc
        adc #4 ; was 3, but I changed it to 4 so we can count down in the shift code copy loop
        sec
        sbc tmp2
        asl
        asl
        tax
        dex

        ; could optimize a bit more by shuffling these tables
        ; however, that _*destroys*_ readability
        ldy #3
-       lda shiftcode,x
        sta shiftcodegoeshere,y
        dex
        dey
        bpl -

        ; find texupper and texlower (next to one another)
        ; one column of texture is organized 7...0,8...15
        ; unfortunately we can’t use the same trick on the screen
        ; screenAddr = buffer + SCREENHEIGHT*(sx/4);

        ; clear the columns as we draw
        ; every four columns, erase the old
        lda tmp2
        bne +
        lda #0
        ldx #63
-       sta $40,x
        dex
        bpl -
+

        ; texAddr = textures + 32*textureIndex + TEXHEIGHT*(texx/4);

        lda texIndex
        asl
        asl
        asl
        sta tmp
        lda texx
        and #$fc
        adc tmp
        asl
        asl
        sta sm_tex+1

        ; cache the texture column, masked and shifted
        ; saves max of 32*32*38=18432
        ; fixed overhead of 32*16*(4+6+7+4+2+3)=13312
        ; not much of a saving, but it balances out the framerate
        ; and saves some code size
        ldx #15
-
sm_tex
        lda $300,x
sm_tmask
		and #0
shiftcodegoeshere
		lsr
		lsr
		lsr
		lsr
		sta texcache,x
		dex
		bpl -

        ; loop preamble

        ldx #31
        ldy texy+1
        ; can pull clc out of inner loop since nothing overflows
        clc

        ; currently approx 47 cycles per 2 pixels
yloop
        ; write pixels to screen
        ; screen[sx][31-sy] = texupper[HI(texy)]
        ; 4+4+4 = 12
		lda texcache,y
        ora $40,x
        sta $40,x

        ; screen[sx][32+sy] = texlower[HI(texy)]
        ; 4+4+4 = 12
		lda texcache+8,y
        ora $60,x
        sta $60,x

        ; 2+2+3+2+3+2+2+2+2+3 = 23
        dex
        bmi endyloop
        lda texy
sm_texstep_lo
        adc #0
        sta texy
        tya
sm_texstep_hi
        adc #0
        tay
        cmp #8
        bmi yloop
endyloop

        lda tmp2
        cmp #3
        bne dontCopy
       
        lda sx
        and #$1c
        asl
        asl
        asl
        asl
        sta sm_scrbuf1+1
        ora #32
        sta sm_scrbuf2+1
        lda #$1c
        adc #0 ; plus carry
        sta sm_scrbuf1+2
        sta sm_scrbuf2+2

        ldx #31
        ldy #0
copyLoop
        lda $40,x
sm_scrbuf1
        sta $1c00,x
        lda $60,x
sm_scrbuf2
        sta $1c00,y
        iny
        dex
        bpl copyLoop

dontCopy

        ldx sx
        inx
        cpx #32
        beq done
        stx sx
        jmp xloop

done
		lda udlamp
		beq updatelampdisplay
		inc udlamp
		rts

updatelampdisplay
        lda lamp 
        ldx #$65
        bne write3digitnumtoscreen

updatekeydisplay
        lda numkeys
        ldx #$55
        bne write3digitnumtoscreen

updatefloordisplay
        lda floor
        ldx #$5d

write3digitnumtoscreen
        ; .A is the num
        ; .X is the screenpos
        pha
        lda #(128 + '0' - 1)
        sta $1e00,x
        ldy #10 ; start middle digit at 10
        pla
        sec
-       inc $1e00,x
        sbc #100
        bcs -
-       dey
        adc #10
        bmi -
        adc #(128 + '0' - 1)
        sta $1e02,x
        tya
        adc #(128 + '0')
        sta $1e01,x
        rts



; tables
tmasktab !byte $C0, $30, $0C, $03

shiftcode
        asl
        rol
        rol
        nop

        lsr
        lsr
        lsr
        lsr

        lsr
        lsr
        bit 0

        bit 0
        bit 0

        bit 0
        asl
        asl

        asl
        asl
        asl
        asl

        lsr
        ror
        ror
        nop

        ; clamp A to >= 85 if tile[Y] is set
collide_clamp
        cmp #85
        bcc _csq1
        rts
_csq1
        tax
        lda (tile),y
        and #$07
        bne _csq2
        txa
        rts
_csq2
        cmp #4
        bne _csq3
        ; open door
        lda numkeys
        beq _csq5
        lda #0
        sta (tile),y
        ldy #Sound_Door
        jsr playSound
        dec numkeys
        jsr updatekeydisplay
        lda #3
        jsr add_to_lamp
        txa
        rts
_csq3
        cmp #5
        bne _csq4
        sta hitexit
        inc floor
        ; give player (255-floor)/16 lamp oil
        lda floor
        eor #$ff
        lsr
        lsr
        lsr
        lsr
        jsr add_to_lamp
        ldy #Sound_Climb
        jmp playSound
_csq4
        cmp #7
        bne _csq5
        ; pick up key
        lda #6
        sta (tile),y
        ldy #Sound_Key
        jsr playSound
        inc numkeys
        jsr updatekeydisplay
_csq5
        lda #85
        sta hit
        rts

add_to_lamp
        clc
        adc lamp
        bcc +
        lda #255
+       sta lamp
		jsr updatelampdisplay
        rts

tOFFt   !byte 0,2,42,44 ; corners
xEORt   !byte 0,255,0,255
yEORt   !byte 0,0,255,255

collide_co
        lda playerx
        eor xEORt,x
        sta tmp
        lda playery
        eor yEORt,x
        clc
        adc tmp
        ror
        sta tmp
        lda #42
        sec
        sbc tmp
        bcs _cco1
        clc
        rts
_cco1
        sta tmp
        ldy tOFFt,x
        lda (tile),y
        and #$07
        bne _cco6
        sec
        rts
_cco6
        lda xEORt,x
        bne _cco2
        lda playerx
        clc
        adc tmp
        bcc _cco3
_cco2
        lda playerx
        sec
        sbc tmp
_cco3
        sta playerx
        lda xEORt,y
        bne _cco4
        lda playery
        clc
        adc tmp
        bcc _cco5
_cco4
        lda playery
        sec
        sbc tmp
_cco5
        sta playery
        sta hit
        sec
        rts

collide
        ; 168 bytes :|

        ; allow us to find all tiles around by indirect indexing
        ;   0   1   2
        ;  21  22  23
        ;  42  43  44

        ldx playerx+1
        dex
        ldy playery+1
        dey
        jsr xy_to_tile_game

        lda #0
        sta hit

        ; clamp playerx
        lda playerx
        ldy #21
        jsr collide_clamp
        eor #$ff
        ldy #23
        jsr collide_clamp
        eor #$ff
        sta playerx

        ; clamp y
        lda playery
        ldy #1
        jsr collide_clamp
        eor #$ff
        ldy #43
        jsr collide_clamp
        eor #$ff
        sta playery


        lda hit ; already hit? don't check corners
        beq corners
        rts

corners
        ldx #3
cornerloop
        jsr collide_co
        bcs cornerend
        dex
        bpl cornerloop
cornerend
        rts

getcos
        sta tmp
        and #127
        cmp #63
        bcc _mk1
        eor #127
_mk1
        tay
        lda fixcos,y
        lsr
        lsr
        lsr
        pha
        lda #0
        sta pcosa+1,x
        lda tmp
        and #192
        beq _mk2
        cmp #192
        beq _mk2
        pla
        eor #$ff
        pha
        lda #$ff
        sta pcosa+1,x
_mk2
        pla
        sta pcosa,x
        rts


kROTt   !byte    16, 32    ; J,L
aROTt   !byte    248, 8    ; -8/256 & 8/256 revolutions

aCOSt   !byte    0,64,128,192 ; c,c+90=-s,c+180=-c,c+270=s
oCOSt   !byte    0,2,4,6   ; where to write result relative to pcosa

qMOVt   !byte    1,0,2,0   ; index for keys,x
kMOVt   !byte    2,2,2,4   ; mask for W,A,S,D
xMOVt   !byte    0,6,4,2   ; c,-s,-c,s
yMOVt   !byte    6,4,2,0   ; s,c,-s,-c

move
        ; check keys and rotate
        ldx #1
_ms0
        lda kROTt,x
        and keys
        beq _ms1
        lda lookang
        clc
        adc aROTt,x
        sta lookang
_ms1
        dex
        bpl _ms0

        ; calculate +/- sin and cos
        lda #3
        sta tmp2
_ms2
        ldy tmp2
        lda aCOSt,y
        clc
        adc lookang
        ldx oCOSt,y
        jsr getcos
        dec tmp2
        bpl _ms2
        
        lda #0
        sta tmp

        ; check keys and move
        ldy #3
_ms3
        lda kMOVt,y
        ldx qMOVt,y
        and keys,x
        beq _ms4
        inc tmp
        ldx xMOVt,y
        lda playerx
        clc
        adc pcosa,x
        sta playerx
        lda playerx+1
        adc pcosa+1,x
        sta playerx+1
        ldx yMOVt,y
        lda playery
        clc
        adc pcosa,x
        sta playery
        lda playery+1
        adc pcosa+1,x
        sta playery+1
_ms4
        dey
        bpl _ms3

        lda tmp
        beq clearkeys
        dec ttnfoot
        bne clearkeys
        ldy #Sound_Foot
        sty ttnfoot ; use the sound index as the delay! saves a couple of bytes!
        jsr playSound

clearkeys
        lda #0
        sta keys
        sta keys+1
        sta keys+2

        rts


; x points to string
; y points to screen
printString
        lda #7
        sta tmp2 ; screen index
        sta tmp  ; colour (yellow)
        cpx #0
        bne printLoop
        lda #4
        sta tmp  ; colour (magenta)
printLoop
        lda strings,x
        ora #128
        sta $1e00,y
        lda tmp
        sta $9600,y
        inx
        iny
        dec tmp2
        bpl printLoop
        rts

set_up_hud
        ; set up screen & colour maps
        ldy #63
screenSetLoop
        tya
        and #7
        asl
        asl
        asl
        sta tmp
        tya
        lsr
        lsr
        lsr
        ora tmp
        tax
        tya
        sta $1e08,x
        lda #10
        sta $9608,x
        dey
        bpl screenSetLoop

        iny
        ldx #(topbarstring - stringstoprint)
        jsr printStrings
        ldx #(hudstring - stringstoprint)
        ldy #72
        jsr printStrings

        jsr updatekeydisplay
        jsr updatefloordisplay
        jsr updatelampdisplay

        ; set up vic registers for game
        ldx #8
        ldy #14
        jsr set_vic_regs_for_screen_xy

        rts
nmi_rts
        rti

endOfMainCode

*=$1c00

initCode
        jsr clearkeys

        ; insert interrupt into chain
;        sei ; done by pucrunch
        lda #<updateInputIrq
        ldx #>updateInputIrq
        sta irqVector
        stx irqVector+1
        cli

        lda #auxcol  ; aux colour blue
        sta $900e
        lda #$05  ; bg colour black, border colour green
        sta $900f
   
        ; copy textures to page 3
        ldx #$e0 ; 7 textures
-       lda textures-1,x
        sta $31f,x ; need to leave $314 alone
        dex
        bne -
        
        ; copy cos/sec tables to page 1 (under stack)
        ldx #$c3
-       lda costables-1,x
        sta+2 fixcos-1,x ; force non-ZP addressing
        dex
        bne -
        
        ; copy strings to page 2
        ldx #(endofrelocstrings - relocstrings)
-		lda relocstrings-1,x
		sta $200-1,x
		dex
		bne -

        ; copy string printer to page 3
        ldx #(endofrelocstringprinter - relocstringprinter)
-		lda relocstringprinter-1,x
		sta $300-1,x
		dex
		bne -
		
		; copy angles and fishes tables to page 2
        ldx #(endofrelocangles - relocangles)
-		lda relocangles-1,x
		sta $2a0-1,x
		dex
		bne -

        ; get whether to use a fixed sequence or a random sequence of levels
        ldx #8
        ldy #9
        jsr set_vic_regs_for_screen_xy

        lda #255    ; UDG address $1C00
        sta $9005
        
        lda #128    ; disable Shift-C=
        sta $291
        
        lda #<nmi_rts
        sta $318
        lda #>nmi_rts
        sta $319

        ldx #(maptypestring - stringstoprint)
        ldy #0
        sty maptype
        jsr printStrings
        
-       lda keys+2 ; F
        and #4
        tax
        bne +
        lda keys+1 ; R
        and #4
        tax
        beq -
        inc maptype
+
        jmp newgame

costables
!pseudopc $100 {
fixcos
!byte 255, 254, 254, 254, 253, 253, 252, 251, 250, 248, 247, 245, 244, 242, 240, 237
!byte 235, 233, 230, 227, 224, 221, 218, 215, 212, 208, 204, 201, 197, 193, 188, 184
!byte 180, 175, 171, 166, 161, 156, 151, 146, 141, 136, 131, 125, 120, 114, 109, 103
!byte  97,  91,  85,  79,  74,  68,  61,  55,  49,  43,  37,  31,  24,  18,  12,   6,   0
fixsecl
!byte   0,   0,   0,   0,   1,   1,   2,   3,   5,   6,   7,   9,  11,  13,  15,  18
!byte  21,  24,  27,  30,  34,  38,  42,  47,  51,  57,  62,  68,  75,  82,  89,  97
!byte 106, 115, 125, 135, 147, 160, 173, 188, 204, 222, 241,   7,  31,  57,  86, 119
!byte 156, 199, 247,  48, 113, 191,  29, 144,  32, 217, 208,  43,  51, 151,  97, 191,   0
fixsech
!byte   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1
!byte   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1
!byte   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   2,   2,   2,   2,   2
!byte   2,   2,   2,   3,   3,   3,   4,   4,   5,   5,   6,   8,  10,  13,  20,  40,  64
}

textures
!pseudopc $320 {
; rock, brick, panel, door, exit, empty key cab, key
 !byte 252, 252, 3, 240, 211, 3, 243, 243, 252, 0, 207, 207, 207, 0, 252, 252
 !byte 124, 0, 240, 3, 207, 192, 207, 207, 252, 0, 63, 63, 63, 0, 252, 252
 !byte 0, 162, 162, 0, 42, 42, 0, 170, 42, 42, 0, 162, 162, 0, 170, 170
 !byte 0, 162, 162, 0, 42, 42, 0, 170, 42, 42, 0, 162, 162, 0, 170, 170
 !byte 85, 255, 255, 223, 85, 255, 85, 85, 253, 255, 255, 255, 255, 255, 85, 85
 !byte 85, 255, 255, 127, 85, 255, 85, 85, 223, 223, 255, 223, 255, 255, 85, 85
 !byte 17, 17, 17, 85, 17, 17, 85, 17, 17, 17, 17, 17, 17, 85, 17, 17
 !byte 84, 4, 4, 85, 4, 4, 85, 4, 100, 84, 252, 4, 4, 85, 4, 4
 !byte 191, 179, 188, 131, 128, 144, 160, 170, 191, 191, 191, 190, 190, 176, 170, 170
 !byte 50, 242, 194, 50, 2, 6, 10, 170, 226, 226, 2, 162, 162, 2, 170, 170
 !byte 192, 192, 195, 195, 192, 240, 239, 255, 195, 192, 195, 192, 192, 255, 236, 255
 !byte 3, 3, 195, 195, 3, 15, 251, 255, 3, 3, 3, 3, 3, 255, 59, 255
 !byte 193, 193, 196, 196, 193, 240, 223, 255, 193, 193, 193, 193, 192, 255, 220, 255
 !byte 3, 67, 19, 19, 67, 15, 247, 255, 3, 67, 3, 67, 3, 255, 55, 255
}

relocstringprinter
!pseudopc $300 {

; printStrings
-       stx tmp3
        asl
        asl
        asl
        tax
        jsr printString
        ldx tmp3
        inx
printStrings
        lda stringstoprint,x
        bpl -
        rts
}
endofrelocstringprinter

relocstrings
!pseudopc $200 {

stringstoprint
topbarstring
        !byte 0,255 ; top bar
hudstring
        !byte 0,1,2,3,0,255 ; bottom info
freedomstring
        !byte 0,4,0,255 ; freedom!
gruestring
        !byte 0,5,6,0,2,0,255 ; eaten by grue

strings
!byte 102,102,102,102,102,102,102,102 ; bar
!ct scr {
!text "keys 003" ; 1
!text "floor001" ; 2
!text "lamp 030" ; 3
!text "freedom!" ; 4
!text "eaten by" ; 5
!text " a grue " ; 6
!text "the keep" ; 7
!text "f  fixed" ; 8
!text "r random" ; 9
!text "(c) 2011" ; 10
!text " kweepa " ; 11
}
maptypestring
        !byte 0,7,0,8,9,0,10,11,0,255 ; maptype select
}
endofrelocstrings

relocangles
!pseudopc $2a0 {
angles
!byte 225, 226, 227, 229, 231, 232, 234, 236, 238, 240, 243, 245, 247, 250, 252, 255
!byte   1,   4,   6,   9,  11,  13,  16,  18,  20,  22,  24,  25,  27,  29,  30,  31
fishes
!byte 185, 189, 194, 202, 209, 213, 219, 225, 231, 236, 243, 246, 249, 253, 254, 255
!byte 255, 254, 253, 249, 246, 243, 236, 231, 225, 219, 213, 209, 202, 194, 189, 185
}
endofrelocangles

endOfOneTimeCode
