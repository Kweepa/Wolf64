; Narrow 4x8 MCM glyphs (only center bit-pairs - no edge bleed)
hexfont
	!byte $3c,$cc,$cc,$cc,$cc,$cc,$3c,$00	; 0
	!byte $30,$30,$30,$30,$30,$30,$30,$00	; 1
	!byte $3c,$0c,$0c,$3c,$c0,$c0,$fc,$00	; 2
	!byte $3c,$0c,$0c,$3c,$0c,$0c,$3c,$00	; 3
	!byte $cc,$cc,$cc,$fc,$0c,$0c,$0c,$00	; 4
	!byte $fc,$c0,$c0,$fc,$0c,$0c,$fc,$00	; 5
	!byte $3c,$c0,$c0,$fc,$cc,$cc,$3c,$00	; 6
	!byte $fc,$0c,$0c,$30,$30,$30,$30,$00	; 7
	!byte $3c,$cc,$cc,$3c,$cc,$cc,$3c,$00	; 8
	!byte $3c,$cc,$cc,$3c,$0c,$0c,$3c,$00	; 9
	!byte $3c,$cc,$cc,$fc,$cc,$cc,$cc,$00	; A
	!byte $fc,$cc,$cc,$fc,$cc,$cc,$fc,$00	; B
	!byte $3c,$cc,$c0,$c0,$c0,$cc,$3c,$00	; C
	!byte $f0,$cc,$cc,$cc,$cc,$cc,$f0,$00	; D
	!byte $fc,$c0,$c0,$f0,$c0,$c0,$fc,$00	; E
	!byte $fc,$c0,$c0,$f0,$c0,$c0,$c0,$00	; F
