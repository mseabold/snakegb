; vim: set syntax=asm_wlagb:
.include "hardware.inc"
.include "gb_header.inc"

.define NFRAMES 5

; Direction is store in 2 bits. Opposite directions are the complement of each other:
;    Up    - 0b00
;    Left  - 0b10
;    Right - 0b01
;    Down  - 0b11
.define DIR_UP    $00
.define DIR_LEFT  $01
.define DIR_RIGHT $02
.define DIR_DOWN  $03

.define SNAKE_START $88;Row 1 Col 1
.define SNAKE_START_TAIL $83;Row 1 Col 1
.define SNAKE_START_ATTR $86
.define SNAKE_START_DIR DIR_RIGHT
.define SNAKE_START_OFFSET $0001
.define SNAKE_START_LEN 5


.ramsection "Work Vars" slot 2
snake_head dw
snake_tail dw
dir db
framecount db
vblank_flag db
stale_flag db
joypad_pressed db
joypad_held db
xpos db
ypos db
xpos_old db
ypos_old db
vx db
vy db
.ends

.ramsection "Tile Attrs" slot 2
; Attributes per tile:
; bit 7 - Wall/Snake collision
; bit 6 - Food tile
; bit 5-4 - Reserved
; bit 3-2 - Prev snake tile
; bit 1-0 - Next snake tile
;
; Note that Prev Snake Tile is always valid, even on the snake tail. This allows the graphics routine to determine
; the last snake tile that is now stale to be updated back to an empty tile.
;
; The Next Snake Tile field for the Snake Head is unused
;
; Attributes are arranged in a 32x20 grid. 32 width is used so that attributes can map directly to
; VRAM tilemap indices. 20 Height is used as the screen is 18 tiles + 2 rows for upper and lower collisions
tile_attributes ds 640
.ends

.bank 0 slot 0
.org INTR_VEC_VBLANK
    jp vblank_isr

.org $100
    nop
    jp $150

.org $150
    ld B,$03
    ld C,$01

    ; Wait for first vblank
--  ld A,(STAT)
    and B
    cp C
    jr nz,--

    xor A
    ld (LCDC),A ; disable LCD

    ; Set tilemap to all 0
    LD HL,TILEMAP0
    ld BC,$400
    call memset

    ; Load tile set into VRAM
    ld HL,$8000
    ld DE,tiles
    ld BC,$20
    call memcpy

    ; Set up tile attributes
    ;
    ; One line of wall at top of board
    ld HL,tile_attributes
    ld DE,nonplayable_line
    ld BC,$20
    call memcpy

    ; 18 lines of playable space
    ld B,18

--- push BC
    ld BC,$20
    ld DE,playable_line
    call memcpy
    pop BC
    dec B
    jr nz,---

    ; Final lower wall line
    ld DE,nonplayable_line
    ld BC,$20
    call memcpy

    ; Initialize the frame counter that control movement speed
    ld A,NFRAMES
    ld HL,framecount
    ld (HL),A

    ld B,B

    ; Set up snake start position
    ld C,SNAKE_START_DIR << 1
    ld B,0
    ld HL,dir_offset_map
    add HL,BC
    ld C,(HL)
    inc HL
    ld B,(HL)

    ld D,>SNAKE_START
    ld E,<SNAKE_START

    ld HL,snake_tail
    ld (HL),E
    inc HL
    ld (HL),D

    ld A,SNAKE_START_LEN
-   push AF
    ld A,$80 | ((SNAKE_START_DIR << 2) ~ $0c) | SNAKE_START_DIR
    ld HL,tile_attributes
    add HL,DE
    ld (HL),A

    ld A,$01
    ld HL,TILEMAP0
    add HL,DE
    ld (HL),A

    pop AF
    dec A
    jr z,+

    ld H,D
    ld L,E
    add HL,BC
    ld D,H
    ld E,L
    jr -

+   ld HL,snake_head
    ld (HL),E
    inc HL
    ld (HL),D

    ; Set joypad variables to 0
    xor A
    ld HL,joypad_pressed
    ld (HL),A
    inc HL
    ld (HL),A
    ld HL,stale_flag
    ld (HL),A

    ld A,$01
    ld (IE),A

    ld A,SNAKE_START_DIR
    ld HL,dir
    ld (HL),A

    ld A,$e4
    ld (BGP),A

    ;Scroll 1 tile right and down (hide the invisible edge walls
    ld A,8
    ld (SCX),A
    ld (SCY),A

    ld A,$91
    ld (LCDC),A ; Restart the LCD (8000 data made, BG map at 9800)
    ei
    nop

main_loop:
    halt
    nop
    ld A,$01
    ld HL,vblank_flag
    cp (HL)
    jr NZ,main_loop

    xor A
    ld (HL),A

    ld HL,framecount
    dec (HL)
    jr nz,main_loop

    ld A,NFRAMES
    ld (HL),A

    ld HL,dir
    ld B,0
    ld C,(HL)
    sla C
    ld HL,dir_offset_map
    add HL,BC
    ld C,(HL)
    inc HL
    ld B,(HL)
    push BC

    ld HL,snake_head
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld HL,tile_attributes

    add HL,DE ; Add the head tile's offset
    push HL ; Stash the head tile's attribute address
    add HL,BC ; Add an offset based on current direction (destination tile)
    ld A,(HL) ; Get the destination tile's attributes

    ; If the tile is a wall, just skip to the next movement frame without moving
    bit 7,A
    jr z,+
    pop HL
    pop BC
    jr main_loop

    ; Get direction again
+   ld DE,dir
    ld A,(DE)
    ld D,A


    ; Set up new tiles attributes
    ld A,$80
    ld E,D
    sla E
    sla E ; C = dir << 2
    or E ; Mask on the dir bits
    xor $0c ; Complement the dir (previous tile is in the reverse direction)

    ld (HL),A ; Store the new attributes

    pop HL ; Retrieve the head tile's address from the stack
    ld A,(HL)
    and $fc
    or D
    ld (HL),A

    ; Finally, update head and tail
    pop BC ; dir offset
    ld HL,snake_head
    ld A,(HL)
    add C
    ld (HL+),A
    ld A,(HL)
    adc B
    ld (HL),A


    ld HL,snake_tail
    push HL
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld B,B
    ld HL,tile_attributes
    add HL,DE
    ld A,(HL)
    res 7,A
    ld (HL),A
    and $03
    sla A

    ld C,A
    ld B,0

    ld HL,dir_offset_map
    add HL,BC
    ld C,(HL)
    inc HL
    ld B,(HL)

    ld A,E
    add C
    ld E,A
    ld A,D
    adc B
    ld D,A

    pop HL
    ld (HL),E
    inc HL
    ld (HL),D

    ld HL,stale_flag
    ld A,$01
    ld (HL),A

    jp main_loop

; A - new map value
; B - X pos
; C - Y pos
set_map_pos:
    push AF
    push DE
    push HL

    ld D,$00
    ld E,B

    push DE

    ld E,C

    ld HL,TILEMAP0

    ;; Multiply DE by 32
    sla E
    rl D
    sla E
    rl D
    sla E
    rl D
    sla E
    rl D
    sla E
    rl D

    add HL,DE

    pop DE
    add HL,DE

    ld (HL),A

    pop HL
    pop DE
    pop AF
    ret

get_joypad:
    ld HL,$ff00
    ld A,$20
    ld (HL),A
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    cpl
    and $0f
    swap A
    ld B,A
    ld A,$10
    ld (HL),A
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    cpl
    and $0f
    or B
    ld B,A
    ld HL,joypad_held ;TODO faster if this is in HRAM
    ld A,(HL)
    cpl
    and B
    ld (HL),B
    ld HL,joypad_pressed
    ld (HL),A
    ret

check_pressed:
    ld HL,joypad_pressed
    ld A,(HL)

    ; Nothing to do if nothing was pressed
    or A
    ret z

    ld b,b

    ld HL,dir

    bit 7,A
    jr z,@joypad_check_up
    ld (HL),DIR_DOWN
    ret
@joypad_check_up:
    bit 6,A
    jr z,@joypad_check_left
    ld (HL),DIR_UP
    ret
@joypad_check_left:
    bit 5,A
    jr z,@joypad_check_right
    ld (HL),DIR_LEFT
    ret
@joypad_check_right:
    bit 4,A
    ret z
    ld (HL),DIR_RIGHT
    ret

; HL - destination
; DE - source
; BC - length
memcpy:
-   ld A,B
    or C
    ret z
    ld A,(DE)
    ld (HL+),A
    inc DE
    dec BC
    jr -

memset:
-   ld D,A
    ld A,B
    or C
    ret z
    ld A,D
    ld (HL+),A
    dec BC
    jr -

vblank_isr:
    push AF
    push BC
    push DE
    push HL

    ld HL,stale_flag
    ld A,(HL)
    or A
    jr z,@joypad

    ld HL,snake_tail
    ld C,(HL)
    inc HL
    ld B,(HL)

    ld HL,tile_attributes
    add HL,BC
    ld A,(HL)

    and $0c
    sra A

    ld E,A
    ld D,0
    ld HL,dir_offset_map
    add HL,DE
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld HL,TILEMAP0
    add HL,DE
    add HL,BC
    xor A
    ld (HL),A

    ld HL,snake_head
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld HL, TILEMAP0
    add HL,DE
    ld A,$01
    ld (HL),A

    xor A
    ld HL,stale_flag
    ld (HL),A

@joypad:
    push AF
    call get_joypad
    pop AF

    call check_pressed

    ld HL,vblank_flag
    ld A,$01
    ld (HL),A

    pop HL
    pop DE
    pop BC
    pop AF
    reti

.bank 1 slot 1
.org $00
tiles:
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $ff, $ff, $ff, $81, $ff, $bd, $ff, $bd
    .db $ff, $bd, $ff, $bd, $ff, $81, $ff, $ff

nonplayable_line:
    .db $80, $80, $80, $80, $80, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80

playable_line:
    .db $80, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80

dir_offset_map:
    .db $e0, $ff, $ff, $ff, $01, $00, $20, $00
