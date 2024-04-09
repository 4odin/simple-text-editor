package config

/////////////////// CONSTANTS
//ctrl+letter = ascii - 64 (0x40)
ESC :: 0x1b

CTRL_C :: 0x03
CTRL_X :: 0x18
CTRL_Q :: 0x11

DEL :: 0x7e
BKSP :: 0x7f

HOME :: 0x48 // CTRL+ [1b, 5b, 31, 3b, 35, 48],
END :: 0x46
PAGE_UP :: 0x35 //[1b, 5b, 35, 7e]
PAGE_DOWN :: 0x36 // [1b, 5b, 36, 7e]

ARROW_UP :: 0x41 // A
ARROW_DOWN :: 0x42 // B
ARROW_RIGHT :: 0x43 // C
ARROW_LEFT :: 0x44 // D


/////////////////// STATE
STATUS_LINE :: 1
RUNNING := true
SHOULD_SAVE := false
