package text_editor

import "ansi_codes"
import "core:fmt"
import "core:os"

RUNNING := true
main :: proc() {
	using ansi_codes

	_set_terminal()
	defer _restore_terminal()

	alt_buffer_mode(true)
	defer alt_buffer_mode(false)

	_get_window_size()

	erase(.All)

	fmt.println("Text Editor")

	move_to(0, 0)

	for RUNNING {
		update()
		render()
	}

	fmt.println("END")
}

render :: proc() {
	using ansi_codes
	erase(.All)
}

update :: proc() {
	@(static)
	buf: [1024]u8
	n_read, err := os.read(os.stdin, buf[:])

	for i := 0; i < n_read; i += 1 {

		char := buf[i]
		// Arrows 
		if buf[i + 1] == 0x5b {
			// ESC [0x5b] ARROW_CODE
			i += 2

			switch buf[i] {
			case ARROW_UP:
				ansi_codes.move_prev_line()

			case ARROW_DOWN:
				ansi_codes.move_next_line()

			case ARROW_RIGHT:
				ansi_codes.move_right()

			case ARROW_LEFT:
				ansi_codes.move_left()

			}
		}

		if char == CTRL_X {
			RUNNING = false
		} else {
			// fmt.print(char)
		}
	}
}

CTRL_C :: 0x03
CTRL_X :: 0x18

ARROW_UP :: 0x41 // A
ARROW_DOWN :: 0x42 // B
ARROW_RIGHT :: 0x43 // C
ARROW_LEFT :: 0x44 // D
