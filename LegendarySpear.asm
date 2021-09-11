    processor 6502
    include "vcs.h"
    include "macro.h"

NTSC = 0
PAL60 = 1

    IFNCONST SYSTEM
SYSTEM = NTSC
    ENDIF

; ----------------------------------
; constants

#if SYSTEM = NTSC
; NTSC Colors
SKY_BLUE = $A0
SKY_YELLOW = $FA
DARK_WATER = $A0
SUN_RED = $30
CLOUD_ORANGE = $22
GREY_SCALE = $02 
WHITE_WATER = $0A
GREEN = $B3
RED = $43
YELLOW = $1f
WHITE = $0f
BLACK = 0
BROWN = $F1
#else
; PAL Colors
; Mapped by Al_Nafuur @ AtariAge
SKY_BLUE = $92
SKY_YELLOW = $2A
DARK_WATER = $92
SUN_RED = $42
CLOUD_ORANGE = $44
GREY_SCALE = $02 
WHITE_WATER = $0A
GREEN = $72
RED = $65
YELLOW = $2E
WHITE = $0E
BLACK = 0
BROWN = $21
#endif

RIDER_HEIGHT = 24
NUM_RIDERS = 5
PLAYER_COLOR = BLACK
PLAYER_START_HEALTH = 10
RIDER_ANIMATE_SPEED = 3
PLAYER_ANIMATE_SPEED = 3
PLAYER_STRIKE_COUNT = 48
RIDER_RESP_START = $b8
RIDER_GREEN_TYPE = GREEN
RIDER_ROCK_TYPE = $00
RAIL_HEIGHT = 6
LOGO_HEIGHT = 6
WINNING_SCORE = $99
; ----------------------------------
; variables

  SEG.U variables

    ORG $80

game_state      ds 1
game_dark       ds 1
rider_animate   ds 1
rider_ctrl      ds 2
rider_timer     ds 5
rider_hpos      ds 5
rider_colors    ds 5
rider_speed     ds 5
rider_hit       ds 5
rider_damaged   ds 5
rider_pattern   ds 1
player_animate  ds 1
player_tile     ds 1
player_vdelay   ds 1
player_vpos     ds 1
player_hmov     ds 1
player_hmov_x   ds 1
player_charge   ds 1
player_fire     ds 1
player_damaged  ds 1
player_health   ds 1
player_score    ds 1
tmp                  ; overlapping ram
tmp_addr_0    ds 2 ; used in scoring kernels
tmp_addr_1    ds 2 ; used in scoring kernels

    SEG

; ----------------------------------
; code

  SEG
    ORG $F000

Reset

    ; do the clean start macro
            CLEAN_START

  ; black playfield sidebars, on top of players
            lda #$30
            sta PF0
            lda #$05
            sta CTRLPF

init_game
  ; rider positions

            lda #>RIDER_SPRITE_START
            sta rider_ctrl+1
            lda #<RIDER_SPRITE_0_CTRL
            sta rider_ctrl

            ldx #NUM_RIDERS - 1
init_rider_loop
            lda #RIDER_GREEN_TYPE
            sta rider_colors,x
            lda #$70
            sta rider_hpos,x
            lda #$ff
            sta rider_damaged,x
            dex
            bpl init_rider_loop

            ldx #$28
            stx player_vpos
            stx rider_pattern
            ldx #$0f
            stx game_dark

newFrame

  ; Start of vertical blank processing
            
            lda #0
            sta VBLANK
            sta COLUBK              ; background colour to black

    ; 3 scanlines of vertical sync signal to follow

            lda #%00000010
            sta VSYNC               ; turn ON VSYNC bit 1

            sta WSYNC               ; wait a scanline
            sta WSYNC               ; another
            sta WSYNC               ; another = 3 lines total

            lda #0
            sta VSYNC               ; turn OFF VSYNC bit 1

    ; 37 scanlines of vertical blank to follow

;--------------------
; VBlank start
; SL 0
            lda #1
            sta VBLANK

;---------------------
; scoring kernel
; SL 0-9
            ldx #NUM_RIDERS - 1 
            dec player_damaged
            bpl scoringLoop
            lda #0
            sta player_damaged
scoringLoop
            sta WSYNC                  ;3   0
            lda rider_colors,x         ;4   4
            cmp #RIDER_GREEN_TYPE      ;2   6
            beq scoringLoop_wsync_end  ;2   8
            tay                        ;2  10; store if it's a rock
            lda rider_damaged,x        ;4  14
            bpl scoringLoop_decay      ;2  16
            lda rider_hit,x            ;4  20
            and #$80                   ;2  22
            beq scoringLoop_wsync_end  ;2  24
            ; hit scored
            lda #$04                   ;2  26
            sec                        ;2  28
            sbc rider_speed,x          ;4  32
            cpy #RIDER_ROCK_TYPE       ;2  34
            beq scoringLoop_player_hit ;2  36
            ldy player_fire            ;3  39
            beq scoringLoop_player_hit ;2  41
scoringLoop_rider_hit
            sed                        ;2  43
            clc                        ;2  45
            adc player_score           ;2  47
            bcc scoringLoop_save_score ;2  49
            lda #WINNING_SCORE         ;2  51
scoringLoop_save_score
            sta player_score           ;3  54
            cld                        ;2  56
            lda #$08                   ;2  58
            sta rider_damaged,x        ;4  62
            jmp scoringLoop_wsync_end  ;3  65
scoringLoop_player_hit
            tay                        ;2  44
scoringLoop_player_hit_shift
            asl player_health          ;5  49 ; bugbug can glitch lines
            dey                        ;2  51 ; maybe acc damage in tmp, assess later
            bne scoringLoop_player_hit_shift ;2  88 (53 + 4 * 70
            lda #$08                   ;3  91
            sta player_damaged         ;3  94
            sty player_charge          ;3  97 note y is 0 now
            sta rider_damaged,x        ;4  62
            jmp scoringLoop_end        ;3  65
scoringLoop_decay
            dec rider_damaged,x
            bmi scoringLoop_rider_clear
            rol rider_colors,x
            jmp scoringLoop_wsync_end
scoringLoop_rider_clear
            lda #RIDER_GREEN_TYPE
            sta rider_colors,x
scoringLoop_wsync_end
            sta WSYNC
scoringLoop_end
            dex
            bpl scoringLoop

;-----------------------------
; animate player
; SL 10-12 (-26 till picture)
animatePlayer
            sta WSYNC
            ldy player_tile
            lda game_state           
            beq animatePlayer_end           
            lda player_damaged
            beq animatePlayer_seq
            ldy #$03 
            jmp animatePlayer_save
animatePlayer_seq
            dec player_animate
            bpl animatePlayer_end
            lda game_dark
            beq animatePlayer_go
            dec game_dark
animatePlayer_go 
            lda #PLAYER_ANIMATE_SPEED
            sta player_animate
            iny
            cpy #$03
            bmi animatePlayer_save
            ldy #$00
animatePlayer_save
            sty player_tile
animatePlayer_end

 ; now that we have the player tile, load it up
            clc
            lda #<PLAYER_SPRITE_START
            dey
            bmi stackPlayer_load_addr
stackPlayer_tile_loop
            adc #48
            dey
            bpl stackPlayer_tile_loop
stackPlayer_load_addr
            sta tmp_addr_0
            adc #24
            sta tmp_addr_1
            lda #>PLAYER_SPRITE_START
            sta tmp_addr_0+1
            sta tmp_addr_1+1

; SL 13-21 
; we're going to copy the current graphics to the stack
            ldy #$0    
stackPlayer_loop
            cpy #RIDER_HEIGHT
            bpl stackPlayer_loop_end
            cpy #0
            php
            lda (tmp_addr_0),y  
            pha
            lda (tmp_addr_1),y  
            pha
            iny
            jmp stackPlayer_loop
stackPlayer_loop_end

animatePlayer_eval_fire 
            dec player_fire
            bpl animatePlayer_fire_active
            lda #$00
            sta player_fire
            jmp animatePlayer_fire_end
animatePlayer_fire_active
            lda #$ff 
            sta $dc
animatePlayer_fire_end

; SL 22
            sta WSYNC                ;3   0
            lda game_state           ;3   3    
            bne movePlayer           ;2   5
movePlayer_game
; SL 23
            sta WSYNC
            lda #$80                 ;3   8
            bit INPT4                ;3  11
            bne movePlayer_game_check;2  13
            lda #1
            sta player_charge        ;5  18
            jmp movePlayer_end
movePlayer_game_check
            lda player_charge
            beq movePlayer_end
            lda player_score
            ora player_health
            bne movePlayer_end
            sta player_charge
            ldx #$ff
            stx player_health
            inc game_state
            jmp movePlayer_end

movePlayer
            lda player_damaged       ;3   3
            bne movePlayer_dir       ;2   5
            lda #$80                 ;3   8
            bit INPT4                ;3  11
            bne movePlayer_button_up ;2  13
            inc player_charge        ;5  18
            jmp movePlayer_dir       ;3  21
movePlayer_button_up
            lda player_charge             ;3  24
            beq movePlayer_button_up_done ;2  26
            lda #PLAYER_STRIKE_COUNT      ;2  28
            sta player_fire               ;3  31
movePlayer_button_up_done
            lda #0               ;2  33
            sta player_charge    ;3  36

movePlayer_dir
; SL 23
            sta WSYNC            ;3   0
            lda player_fire
            bne movePlayer_fire
            lda #$00
            sta player_hmov_x
            lda #$80             ;3  34 kludge reloading
            bit SWCHA            ;3   3
            beq movePlayer_right ;2   5
            lsr                  ;2   7
            bit SWCHA            ;3  10
            beq movePlayer_left  ;2  12
            lsr                  ;2  14
            bit SWCHA            ;3  17
            beq movePlayer_down  ;2  19
            lsr                  ;3  22
            bit SWCHA            ;3  25
            beq movePlayer_up    ;2  27
            jmp movePlayer_end   ;3  30

movePlayer_fire
            lda #$80             ;2
            sta player_hmov_x    ;3
movePlayer_right
            lda #$F0             ;2   8
            jmp movePlayer_horiz ;3  11
movePlayer_left
            lda #$10             ;2  15
movePlayer_horiz
            clc                  ;2  17
            adc player_hmov      ;3  20
            bvs movePlayer_end   ;2  22
            sta player_hmov      ;3  25
            jmp movePlayer_end   ;3  28
movePlayer_down
            inc player_vpos      ;5  42
            lda #110             ;2  44
            cmp player_vpos      ;3  47
            bmi movePlayer_up    ;2  49
            jmp movePlayer_end   ;3  52
movePlayer_up
            dec player_vpos      ;5  33
            beq movePlayer_down  ;3  36
            
movePlayer_end

; SL 24
            sta WSYNC 
animateRider
            dec rider_animate
            bpl animateRider_end
            lda rider_ctrl
            cmp #<RIDER_SPRITE_2_CTRL
            bne animateRider_skipCtrl0
            lda #<PLAYER_SPRITE_0_CTRL
            jmp animateRider_savCtrl0
animateRider_skipCtrl0
            clc
            adc #48
animateRider_savCtrl0
            sta rider_ctrl
            ldx #RIDER_ANIMATE_SPEED
            stx rider_animate
animateRider_end

            ldx #NUM_RIDERS - 1

; SL 25-34           
moveRider_loop
            sta WSYNC
            lda game_state            ;3   3    
            beq moveRider_noreset     ;2   5
            dec rider_timer,x         ;6  11
            bpl moveRider_noreset     ;2  13
            lda rider_speed,x         ;4  17
            sta rider_timer,x         ;4  29
            lda #$10                  ;2  31
            clc                       ;2  33
            adc rider_hpos,x          ;4  37
            bvs moveRider_dec_hdelay  ;2  39
            sta rider_hpos,x          ;4  43  
            jmp moveRider_noreset     ;3  46
moveRider_dec_hdelay
            adc #$0f              ;2  42
            cmp #$8f              ;2  44
            beq moveRider_reset   ;2  46
            sta rider_hpos,x      ;4  50  
            jmp moveRider_noreset ;2  53
moveRider_reset
            ; reset rider
            inc game_state         ;5  --
            lda #RIDER_RESP_START  ;2  56
            sta rider_damaged,x    ;3  59
            sta rider_hpos,x       ;4  --
            lda rider_pattern      ;3  -- ; Galois LFSA
            lsr                    ;2  -- ; see https://samiam.org/blog/20130617.html
            bcc moveRider_skipEor  ;2  --
            eor #$8e               ;2  75
moveRider_skipEor 
            sta rider_pattern      ;3  78 
            and #$0f
            tay
            lda RIDER_COLORS,y
            sta rider_colors,X
            beq moveRider_parallax
            tya 
            and #$03
            jmp moveRider_setSpeed
moveRider_parallax
            txa
            adc #$02
            lsr
moveRider_setSpeed
            sta rider_speed,x
            jmp moveRider_end
moveRider_noreset
            sta WSYNC              ;3    0
moveRider_end
            dex                    ;2   90
            bpl moveRider_loop     ;2   92

; -----------------------------------
; Display kernels
; 192 scanlines of picture to follow
; ----------------------------------

; horizon kernel(s)
; 36 variable width bands of color gradient 

; horizon + score kernel
; SL 35

            sta WSYNC
            lda #$b0               ;2   2
            sta HMP0               ;3   5
            adc #$20               ;2   7
            sta HMP1               ;3  10
            ldx #$09               ;3  13
horizonScore_resp
            dex                    ;2  15
            bpl horizonScore_resp  ;2  62 (17 + 45)
            sta RESP0              ;3  65
            sta RESP1              ;3  68
; SL 36
            sta WSYNC
            sta HMOVE              ;3   3
            lda #WHITE             ;2   5
            sta COLUP0             ;3   8
            sta COLUP1             ;3  11
            lda #0                 ;2  13 ; end of VBLANK
            sta VBLANK             ;3  16

            ldx #13                ;2  18  
; SL 37 (Display 0)
            sta WSYNC
            lda HORIZON_COLOR,x      ;4   4 
            sta COLUBK               ;3   7
            lda player_score
            and #$0f
            asl
            asl
            asl
            adc #<FONT_0
            sta tmp_addr_1
            lda #>FONT_0
            sta tmp_addr_1 + 1
            lda player_score
            and #$f0
            lsr
            adc #<FONT_0
            sta tmp_addr_0
            lda #>FONT_0
            sta tmp_addr_0 + 1
            ldy #$07

; SL 38-45
horizonScore_Loop
            lda player_health        ;3   3
            sta WSYNC
            sta PF1                  ;3   3
            lda HORIZON_COLOR,x      ;4   7 
            sec                      ;2   9
            sbc game_dark            ;3  12
            sta COLUBK               ;3  15
            lda (tmp_addr_0),y       ;5  20
            sta GRP0                 ;3  23
            lda #RED                 ;2  25
            sta COLUPF               ;3  28
            lda (tmp_addr_1),y       ;5  33
            sta GRP1                 ;3  36
            lda #$00                      
            sta COLUPF
            sta PF1
            dey                      ;2  23
            bmi horizonScore_End     ;2  25
            tya                      ;2  27
            cmp HORIZON_COUNT,x      ;4  31
            bpl horizonScore_Loop    ;2* 33
            dex                      ;2  35
            jmp horizonScore_Loop    ;3  38

horizonScore_End

; horizon + sun kernel 
; SL 46
            sta WSYNC
            lda HORIZON_COLOR,x      ;4   4 
            sec                      ;2   6
            sbc game_dark            ;3   9
            sta COLUBK               ;3  12
            lda #0                   ;2  14
            sta GRP0                 ;3  17
            sta GRP1                 ;3  20
            ldy #$03                 ;2  22
horizonSun_resp
            dey                      ;2  24
            bpl horizonSun_resp      ;2  41 (26 + 15)
            sta RESP0                ;3  44
            sta RESP1                ;3  47
            sta NUSIZ1               ;3  50
            lda #$10                 ;2  52
            sta HMP0                 ;3  55
            lda #$20                 ;2  57
            sta HMP1                 ;3  60
            lda #1                   ;2  62  BUGBUG save inst?            
            sta NUSIZ0               ;3  65

; SL 47
            sta WSYNC                ;3   0
            sta HMOVE                ;3   3
            lda HORIZON_COLOR,x      ;4   4 
            sec                      ;2   6
            sbc game_dark            ;3   9
            sta COLUBK               ;3  12
            lda #SUN_RED             ;2  17
            sta COLUP0               ;3  20
            sta COLUP1               ;3  23
            dex                      ;2  25 ; hardcode

; SL 48 ... 72
            

            ldy #24                  ;2  15
horizonLoop
            sta WSYNC                ;3   0 
            lda HORIZON_COLOR,x      ;4   4 
            sec                      ;2   6
            sbc game_dark            ;3   9
            sta COLUBK               ;3  12
            lda SUN_SPRITE_LEFT,y    ;4  16 
            sta GRP0                 ;3  19
            lda SUN_SPRITE_MIDDLE,y  ;4  23  
            sta GRP1                 ;3  26
            lda #0                   ;2  28
            sta REFP0                ;3  31
            dey                      ;2  33
            bmi horizonEnd           ;2  35
            clc                      ;2  37
            lda #1                   ;2  39
horizonLoop_refp
            sbc #1                   ;2  41
            bpl horizonLoop_refp     ;2  48 (43 + 5)
            lda #8                   ;2  50
            sta REFP0                ;3  53
            tya                      ;2  55
            cmp HORIZON_COUNT,x      ;4  59
            bpl horizonLoop          ;2* 61
            dex                      ;2  62
            jmp horizonLoop          ;3  65
horizonEnd

;-------------------
; top rail kernel

    ; SC 73 .. 78
            ldx #RAIL_HEIGHT / 2 - 1 ;2  10
rail_A_loop 
            sta WSYNC                ;3   0
            lda MOUNTAIN_PF0,x
            sta PF0
            lda MOUNTAIN_PF1,x
            sta PF1
            lda MOUNTAIN_PF2,x
            sta PF2
            sta WSYNC                ;3   0
            dex                      ;2   2
            bpl rail_A_loop          ;2   4
            lda #0                   ;2  33 BUGBUG save inst
            sta GRP0                 ;3  36
            sta GRP1                 ;3  39
            sta REFP0                ;3  42
            sta NUSIZ0               ;3  45
            sta NUSIZ1               ;3  48
            sta HMCLR                ;3  51

; ----------------------------------
; playfield kernel 
;
; locating player first
;
    ; SC 79           
            sta WSYNC                ;3   0
            ;ldx #PLAYER_COLOR       ;2   2 save instr (replace with inx)
            inx                      ;2   2 x was ff
            lda player_vpos          ;3   3 
            ldy #3                   ;2   7
player_resp_loop
            dey                      ;2   9
            bpl player_resp_loop     ;2  11 + 15 = 26
            sta RESBL                ;3  29
            sta RESP0                ;3  32
            stx COLUP0               ;3  39
            sta player_vdelay        ;3  41
            lda player_hmov          ;3  44
            sta HMP0                 ;3  48
            sta HMBL                 ;3  38

    ; SC 80
            sta WSYNC                ;3   0
            sta HMOVE                ;3   3
            lda #$30                 ;2   5
            sta PF0                  ;3   8
            ;ldx #$00                 ;2  10 save instr (x is 0)
            stx PF1                  ;3  13
            stx PF2                  ;3  16
            ;ldx #BLACK               ;2  18 save inst (x is 0)
            stx COLUBK               ;3  21
            lda player_hmov_x        ;3  24
            sta HMP0                 ;3  27
            lda #$d0                 ;3  30
            sta HMBL                 ;3  33

;--------------------
; transition to riders kernel
; x loaded with current rider 
; y used for rider graphics index
; sp used for player graphics index

    ; SC 81
            sta WSYNC                ;3   0
            sta HMOVE                ;3   3
            ldx #>RIDER_SPRITE_START ;2   5
            stx tmp_addr_0+1         ;3   8
            stx tmp_addr_1+1         ;3  11
            lda #GREEN               ;2  13
            sta COLUBK               ;3  16
            iny                      ;2  18 ; save instr (y is ff)
            ldx #NUM_RIDERS - 1      ;2  20
            sty HMBL                 ;3  23
            sty HMP0                 ;3  26
riders_start
            jmp rider_A_prestart     ;3  32

    ; SC 82 .. 216 (27 * 5)

riders_end

;--------------------
; bottom rail kernel
;
            sta RESP0             ;3  67
            sta RESP1             ;3  70
    ; SC 217
            sta WSYNC
            lda #BLACK            ;2   2
            sta COLUBK            ;3   5
            lda #WHITE            ;2   7
            sta COLUP0            ;3  10
            sta COLUP1            ;3  13

    ; SC 218 - 224

            ldx #LOGO_HEIGHT - 1
logo_loop 
            sta WSYNC
            lda DC21_0,x
            sta GRP0
            lda DC21_1,x
            sta GRP1
            dex
            bpl logo_loop

    ; SC 225 - 255
    ; 30 lines of overscan to follow            

            ldx #30
doOverscan  sta WSYNC               ; wait a scanline
            dex
            bne doOverscan
            lda #$01
            bit SWCHB
            bne gameCheck
            jmp Reset

gameCheck
            lda player_score
            cmp #WINNING_SCORE
            beq gameEnd
gameCheckHealth
            lda player_health
            bne gameContinue
gameEnd
            lda #0
            sta game_state
            lda #$0f
            sta game_dark
gameContinue

frameEnd
            jmp newFrame

;-----------------------------------------------------------------------------------
; Rider Kernels
; Riders are drawn using the following strategy
;
;   prestart - at end of previous kernel, check if the rider is on left or right edge
;              (will trigger short versus long strobe kernels) 
;   start    - 1 scanline to strobe resp1 and set hmov1
;   hmov     - 1 scanline to do horizontal HMOV and set up graphics
;   loop     - RIDER_HEIGHT scanlines of graphics
;   
;   the additional complication is the player resulting in at least two variants of each kernel
;   
;   rider A pattern - we are drawing only the rider
;                     every A kernel decrements player_vdelay looking for a transition to B
;   rider B pattern - we draw the player and the rider
;                     player position is strobed before we start drawing riders
;                     player graphics are pushed onto the stack during vblank
;                     every B kernel pulls those graphics off the stack
;                           1 byte of player 0 graphics 
;                           1 byte containing player 0 HMOV0 and NUSIZ0 data 
;                           1 byte of processor status to signal whether to move back to A 
;
;   A to B transitions - enable ball graphics (used for the spear)
;   B to A transitions - disable ball graphics
;
;   each kernel therefore has multiple versions...
;         A vs B pattern
;         the strobe kernels have additional short and long versions
;         transition kernels for crossing between A and B versions
;         a few transitions are very tight...
;           ... and have to splice into the middle of kernels 
;           ... which is super fun
;         
;   labels are used to try and keep the spaghetti from getting out of control:
;        kernels: rider_(A|B)_(kernel)...
;        transitions are named by their target: rider_(A_to_B)_(kernel)...
;
; possible improvements:
;  - could save a third of stack space by not pushing processor status and instead tracking
;    stack pointer ... tradeoff is we would have to manage x register, currently used hold rider #
;  - use of the x register to hold rider # seems wasteful (we basically never touch it in 
;    any kernel)
;
; rider strobe timings (for reference)
; RESPx STROBE CHART
; A Y0 SC 22 PP  12
; A Y1 SC 27 PP  27
; A Y2 SC 32 PP  42
; A Y3 SC 37 PP  57
; A Y4 SC 42 PP  72
; A Y5 SC 47 PP  87
; A Y6 SC 52 PP 102
; A Y7 SC 57 PP 117
; A Y8 SC 62 PP 132
; A Y9 SC 67 PP 147

;-----------------------------------------------------------------------------------
; Rider A Pattern
; rider only, waiting for player

rider_A_start_l
            sta WSYNC                ;3   0 
            sta HMOVE                ;3   3
            tay                      ;2   5
            dec player_vdelay        ;5  10
            beq rider_A_to_B_start_l ;2  12
rider_A_resp_l; strobe resp
            dey                      ;2  14
            bpl rider_A_resp_l       ;2+ 56 (16 + 8 * 5)
            lda tmp                  ;3  59
            sta HMP1                 ;3  62
            sta RESP1                ;3  65 
            jmp rider_A_hmov         ;3  68 

rider_A_to_B_start_l
            dey                      ;2  15
            dey                      ;2  17
            dey                      ;2  19
            lda player_fire          ;3  22
            bne rider_A_to_B_resp_m  ;2  24
            lda #$ff                 ;2  26
            sta ENABL                ;3  29
            sta HMBL                 ;3  32
            dey                      ;2  34
            dey                      ;2  36
            SLEEP 2                  ;2  38 timing shim
rider_A_to_B_resp_l          
            dey                      ;2  40
rider_A_to_B_resp_m
            bpl rider_A_to_B_resp_l  ;2+ 57 / 57 (27 / 42 + 6 * 5 / 3 * 5)
            SLEEP 2                  ;2  59 timing shim
            lda tmp                  ;3  62 
            sta RESP1                ;3  65 
            sta HMP1                 ;3  68
            jmp rider_B_hmov         ;3  71 

rider_A_prestart
            lda rider_hpos,x        ;4  --
            sta tmp                 ;3  --
            and #$0f                ;2  --
            cmp #$05                ;2  --
            bpl rider_A_start_l     ;2  --

rider_A_start
            ; locate p1
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3
            tay                     ;2   5
            iny                     ;2   7
rider_A_resp; strobe resp 
            dey                     ;2   9 
            bpl rider_A_resp        ;2+ 36 (11 + 5 * 5)
            lda tmp                 ;3  39
            sta HMP1                ;3  42
            sta RESP1               ;3  50 
            dec player_vdelay       ;5  55
            bne rider_A_hmov        ;2  57
rider_A_to_B_hmov
            lda player_fire           ;3  60
            bne rider_A_to_B_hmov_jmp ;2  62
            sty HMBL                  ;3  65  ; trick - y is $ff
            sty ENABL                 ;3  68
rider_A_to_B_hmov_jmp
            jmp rider_B_hmov          ;3  72

rider_A_hmov; locating rider horizontally 2
            sta WSYNC                     ;3   0 
            sta HMOVE                     ;3   3 ; process hmoves
rider_A_hmov_0; from rider B
            lda rider_colors,x            ;4  15
            sta COLUP1                    ;3  18
            bne rider_A_hmov_rock
            lda #<ROCK_0_CTRL
            sta tmp_addr_0
            jmp rider_A_hmov_rock_end
rider_A_hmov_rock
            lda rider_ctrl
            sta tmp_addr_0
rider_A_hmov_rock_end
            clc
            adc #24
            sta tmp_addr_1
            lda #$0                       ;2  20
            ldy #RIDER_HEIGHT - 1         ;2  22
            dec player_vdelay             ;5  27
            sta CXCLR                     ;3  30 prep for collision
            sta HMP1                      ;3  33
            beq rider_A_to_B_loop         ;2  35

rider_A_loop;
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3 ; process hmoves
rider_A_loop_body:
            lda (tmp_addr_1),y  ;5   8 ; p1 draw
            sta GRP1                ;3  11
            lda (tmp_addr_0),y      ;5  16
            sta NUSIZ1              ;3  19
            dec player_vdelay       ;5  24
            sta HMP1                ;3  27
            beq rider_A_to_B_loop_a ;2  29
rider_A_loop_a;
            dey                     ;5  34 73
            bpl rider_A_loop        ;2  36 75

rider_A_end
            sta WSYNC               ;3  0
            sta HMOVE               ;3  3
            dec player_vdelay       ;5  8
            beq rider_A_to_B_end_a  ;2  10

rider_A_end_a
            lda CXPPMM              ;2  12 / 48 (from b)    
            sta rider_hit,X         ;4  16 / 52
            dex                     ;2  18 / 54
            bpl rider_A_prestart    ;2  20 / 56
            jmp riders_end          ;3  23 / 59

rider_A_to_B_loop
            lda player_fire
            bne rider_A_to_B_loop_jmp
            lda #$ff                ;2  31
            sta HMBL                ;3  34
            sta ENABL               ;3  37
rider_A_to_B_loop_jmp
            jmp rider_B_loop        ;3  40

rider_A_to_B_loop_a
            lda player_fire
            bne rider_A_to_B_loop_a_jmp
            lda #$ff                ;2  31
            sta HMBL                ;3  34
            sta ENABL               ;3  37
rider_A_to_B_loop_a_jmp
            jmp rider_B_loop_a       ;3  40

rider_A_to_B_end_a
            lda player_fire
            bne rider_A_to_B_end_a_jmp
            lda #$ff                ;2  12
            sta ENABL               ;3  15
            sta HMBL                ;3  18
rider_A_to_B_end_a_jmp
            jmp rider_B_end_a       ;3  21

;-----------------------------------------------------------------------------------
; Rider B Pattern 
; player + rider on same line


rider_B_start_0
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            iny                     ;2  22 y is ff + timing shim + readying COLUPF for after jump
            sta RESP1               ;3  25  
            sta NUSIZ0              ;3  28
            sta HMP0                ;3  31 
            jmp rider_B_resp_end_0  ;3  36

rider_B_start_l
            ; locate p1 at right edge of screen
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            ldy rider_hpos,x        ;4  27
            sty HMP1                ;3  30
            plp                     ;4  34
            beq rider_B_to_A_resp_m ;2  36
            sta HMP0                ;3  39
            lda tmp                 ;3  42
            sbc #$06                ;2  44 ; borrow set due to plp
            bmi rider_B_resp_m      ;2  46 ; BUGBUG COLUPF glitch
            tay                     ;2  48
rider_B_resp_l; strobe resp
            dey                     ;2  50
            bpl rider_B_resp_l      ;2  57 (52 + 1 * 5)
rider_B_resp_m
            iny                     ;2  59 49 from branch (note y is ff)
            sty COLUPF              ;3  62
            sty RESP1               ;3  65
            jmp rider_B_hmov        ;2  68
rider_B_to_A_resp_m
            lda tmp                 ;3  40
            sbc #$06                ;2  42 ; borrow set due to plp
            tay                     ;2  44
            bmi rider_B_to_A_resp_n ;2  46
rider_B_to_A_resp_l; strobe resp
            dey                     ;2  48 
            bpl rider_B_to_A_resp_l ;2  55 (50 + 1 * 5)
            SLEEP 2                 ;2  57 timing shim
rider_B_to_A_resp_n
            iny                     ;2  59 49 from branch (note y is ff)
            sty COLUPF              ;3  62 
            sty RESP1               ;3  65
            sty ENABL               ;3  68
            jmp rider_A_hmov        ;3  71 

rider_B_to_A_hmov
            sty COLUPF              ;3  72 ;
            sta WSYNC               ;3   0 ;
            sta HMOVE               ;3   3 ; transition from B_to_A
            sty ENABL               ;3   9 ; interleave with rider_A_hmov
            jmp rider_A_hmov_0      ;3  12

rider_B_prestart
            lda #$0                ;3  49
            sta COLUPF             ;3  52
            lda rider_hpos,x       ;4  56
            and $0f                ;2  58
            tay                    ;2  60
            dey                    ;2  62
            bmi rider_B_start_0    ;2  64
            sty tmp                ;3  67
            cpy #$05               ;2  69
            bpl rider_B_start_l    ;2  71
rider_B_start_n
            ; locate p1
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
rider_B_resp; strobe resp
            dey                     ;2  25
            bpl rider_B_resp        ;2  47  27 + 4 * 5
            sta RESP1               ;3  49
            sta HMP0                ;3  52
            iny                     ;2  55 y is ff, save instr
rider_B_resp_end_0
            lda rider_hpos,x        ;4  59
            sta HMP1                ;3  62
            plp                     ;4  66
            beq rider_B_to_A_hmov   ;2  68
            sty COLUPF              ;3  71

rider_B_hmov; locating rider horizontally
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3 ; process hmoves
rider_B_hmov_a
            pla                     ;4   7 / 11 (from a)
            sta GRP0                ;3  10 
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            sta HMP0                ;3  26
            lda rider_colors,x      ;4  30
            sta COLUP1              ;3  33
            bne rider_B_hmov_rock   ;2  35
            lda #<ROCK_0_CTRL       ;2  37
            sta tmp_addr_0          ;3  40
            jmp rider_B_hmov_rock_end ;3 43
rider_B_hmov_rock
            lda rider_ctrl          ;3  39
            sta tmp_addr_0          ;3  42
rider_B_hmov_rock_end
            clc                     ;2  45
            adc #24                 ;2  47 / 51
            sta tmp_addr_1          ;3  50
            lda #$00                ;2  52
            sta HMP1                ;3  55 / 59
            sta CXCLR               ;3  58 prep for collision
            sta COLUPF              ;3  61
            ldy #RIDER_HEIGHT - 1   ;2  63
            plp                     ;4  67  exit
            beq rider_B_to_A_loop   ;2  69 / 73 (from a)

rider_B_loop  
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            sta HMP0                ;3  26
            lda (tmp_addr_1),y      ;5  31 ; p1 draw
            sta GRP1                ;3  34
            lda (tmp_addr_0),y      ;5  39
            sta NUSIZ1              ;3  42
            sta HMP1                ;3  45
            plp                     ;5  50 
            beq rider_B_to_A_loop_a ;2  52
            lda #$0                 ;3  55
            sta COLUPF              ;3  58
rider_B_loop_a
            dey                     ;5  63
            bpl rider_B_loop        ;2  65

rider_B_end
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            sta HMP0                ;3  26
            plp                     ;4  30  
            beq rider_B_to_A_end_a  ;2  32

rider_B_end_a
            lda CXPPMM               ;2  34     
            sta rider_hit,X          ;4  38
            dex                      ;2  40
            bpl rider_B_prestart_jmp ;2  42
            lda #$0                  ;3  45
            sta COLUPF               ;3  48
            jmp riders_end           ;3  51

rider_B_prestart_jmp
            jmp rider_B_prestart     ;3  46

rider_B_to_A_loop
            sta ENABL               ;3  73 ; a already 0
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3 ; process hmoves
            jmp rider_A_loop_body   ;3   6

rider_B_to_A_loop_a; BUGBUG running out of cycles in this transition .. or not?
            lda #$0                ;3  56
            sta COLUPF             ;3  59
            sta ENABL              ;3  62
            dey                    ;2  64 ; copy rider_A_loop_a
            sta WSYNC              ;3  0  ; copy rider_A_end
            sta HMOVE              ;3  3
            bpl rider_B_to_A_loop_a_jmp ;2  5 
            jmp rider_A_end_a      ;3  8
rider_B_to_A_loop_a_jmp
            jmp rider_A_loop_body  ;3  9

rider_B_to_A_end_a
            lda #$0                ;2  37
            sta ENABL              ;3  40
            sta COLUPF             ;3  43
            jmp rider_A_end_a      ;3  46

;-----------------------------------------------------------------------------------
; sprite graphics

FONT_0
        byte $3c,$7e,$66,$66,$66,$66,$7e,$3c; 8
FONT_1
        byte $7e,$7e,$18,$18,$18,$18,$78,$78; 8
FONT_2
        byte $7e,$7e,$40,$7e,$7e,$6,$7e,$7e; 8
FONT_3
        byte $7e,$7e,$6,$7e,$7e,$6,$7e,$7e; 8
FONT_4
        byte $6,$6,$6,$7e,$7e,$66,$66,$66; 8
FONT_5
        byte $7e,$7e,$6,$7e,$7e,$60,$7e,$7e; 8
FONT_6
        byte $7e,$7e,$66,$7e,$7e,$60,$7e,$7e; 8
FONT_7
        byte $6,$6,$6,$6,$6,$6,$7e,$7e; 8
FONT_8
        byte $7e,$7e,$66,$7e,$7e,$66,$7e,$7e; 8
FONT_9
        byte $6,$6,$6,$7e,$7e,$66,$7e,$7e; 8

    ORG $F600

PLAYER_SPRITE_START
PLAYER_SPRITE_0_CTRL
    byte $0,$5,$15,$15,$15,$5,$f5,$5,$5,$f7,$35,$c7,$55,$d7,$65,$5,$f5,$5,$50,$10,$0,$0,$0,$0; 24
PLAYER_SPRITE_0_GRAPHICS
    byte $0,$8a,$92,$a2,$ce,$e6,$77,$7f,$7f,$f8,$ff,$f8,$ff,$f8,$ef,$77,$73,$b2,$f0,$e0,$f0,$60,$90,$90; 24
PLAYER_SPRITE_1_CTRL
    byte $0,$5,$f5,$f5,$5,$15,$f5,$5,$5,$5,$d7,$35,$d7,$55,$25,$5,$f5,$25,$30,$10,$0,$0,$0,$0; 24
PLAYER_SPRITE_1_GRAPHICS
    byte $0,$ab,$af,$a6,$c2,$c6,$e7,$fe,$fe,$ff,$f8,$ff,$f8,$ff,$ef,$77,$b3,$e4,$f0,$e0,$f0,$60,$90,$90; 24
PLAYER_SPRITE_2_CTRL
    byte $0,$5,$f5,$5,$f5,$5,$d5,$5,$5,$f7,$35,$c7,$55,$d7,$65,$5,$f5,$5,$40,$20,$0,$0,$0,$0; 24
PLAYER_SPRITE_2_GRAPHICS
    byte $0,$44,$44,$e5,$c5,$cf,$73,$7f,$7f,$f8,$ff,$f8,$ff,$f8,$ef,$77,$73,$b2,$78,$f0,$60,$90,$90,$0; 24
PLAYER_SPRITE_3_CTRL
    byte $0,$0,$5,$5,$f5,$5,$17,$5,$5,$d7,$15,$e7,$35,$f7,$25,$25,$15,$5,$25,$f5,$0,$0,$0,$0; 24
PLAYER_SPRITE_3_GRAPHICS
    byte $0,$66,$a4,$66,$63,$63,$d8,$e7,$ff,$f8,$7f,$f8,$7f,$f8,$7f,$3f,$7f,$7f,$ce,$f6,$f3,$60,$90,$90; 24

SUN_SPRITE_LEFT ; 26
        byte $ff,$ff,$ff,$ff,$7f,$7f,$7f,$7f,$3f,$3f,$3f,$1f,$1f,$f,$f,$7,$3,$1,$0,$0,$0,$0,$0,$0,$0
SUN_SPRITE_MIDDLE ; 26
        byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$3c,$0,$0,$0,$0,$0

MOUNTAIN_PF0 ; 4
        byte $ff, $f0, $f0
MOUNTAIN_PF1 ; 4
        byte $ff, $f3, $c0
MOUNTAIN_PF2 ; 4
        byte $ff, $3f, $0f

    ORG $F700

RIDER_SPRITE_START
RIDER_SPRITE_0_CTRL
    byte $0,$5,$f5,$f5,$5,$5,$f5,$f5,$5,$17,$f5,$7,$f5,$f7,$e5,$5,$15,$5,$50,$0,$10,$0,$0,$0; 24
RIDER_SPRITE_0_GRAPHICS
    byte $0,$51,$49,$45,$77,$67,$6f,$7f,$7f,$f8,$ff,$f8,$ff,$f8,$f7,$ee,$ce,$4d,$3c,$38,$f0,$60,$90,$90; 24
RIDER_SPRITE_1_CTRL
    byte $0,$5,$15,$35,$f5,$f5,$5,$15,$5,$f5,$f7,$5,$f7,$f7,$e5,$5,$15,$25,$40,$0,$0,$0,$0,$0; 24
RIDER_SPRITE_1_GRAPHICS
    byte $0,$9f,$af,$9e,$86,$c6,$ef,$fe,$fe,$ff,$f8,$ff,$f8,$f8,$f7,$ee,$cd,$9c,$78,$70,$f0,$60,$90,$90; 24
RIDER_SPRITE_2_CTRL
    byte $0,$5,$f5,$5,$15,$15,$5,$5,$5,$17,$f5,$7,$f5,$f7,$e5,$5,$15,$5,$40,$0,$20,$0,$0,$0; 24
RIDER_SPRITE_2_GRAPHICS
    byte $0,$44,$22,$a7,$a3,$e7,$67,$7f,$7f,$f8,$ff,$f8,$ff,$f8,$f7,$ee,$ce,$4d,$1e,$3c,$60,$90,$90,$0; 24
ROCK_0_CTRL
    byte $0,$7,$27,$7,$25,$5,$5,$5,$5,$5,$5,$5,$25,$f5,$15,$10,$0,$0,$0,$0,$0,$10,$0,$30; 24
ROCK_0_GRAPHICS
    byte $0,$fc,$f8,$f8,$ff,$7e,$fc,$fe,$fe,$7e,$fc,$fe,$f8,$fc,$f8,$ff,$ff,$fe,$ff,$7e,$fe,$fc,$f8,$c0; 24

RIDER_COLORS ; 16 bytes
        byte BLACK, BLACK, BLACK, BLACK, GREEN, GREEN, GREEN, GREEN, BROWN, RED, WHITE, YELLOW, BROWN, RED, WHITE, YELLOW
        
HORIZON_COLOR ; 14 bytes
        byte CLOUD_ORANGE - 2, CLOUD_ORANGE, CLOUD_ORANGE + 2, CLOUD_ORANGE + 4, SKY_YELLOW, SKY_YELLOW + 2, SKY_YELLOW + 4, SKY_YELLOW + 2, SKY_YELLOW, WHITE_WATER, SKY_BLUE + 8, SKY_BLUE + 4, SKY_BLUE + 2, SKY_BLUE 
HORIZON_COUNT ; 14 bytes
        byte $0, $2, $4, $6, $7, $8, $b, $13, $16, $17, $18, $0, $2, $4 
DC21_0 ; 6 bytes
	    byte	$0,$c6,$a8,$a8,$a8,$c6; 6
DC21_1 ; 6 bytes
        byte	$0,$e8,$88,$e8,$28,$e8; 6
;-----------------------------------------------------------------------------------
; the CPU reset vectors

    ORG $F7FA

    .word Reset          ; NMI
    .word Reset          ; RESET
    .word Reset          ; IRQ

    END