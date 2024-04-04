package text_editor

import "ansi_codes"
import "core:fmt"
import "core:os"

RUNNING := true
main :: proc() {
	using ansi_codes

	_set_terminal()
	defer _restore_terminal()

	fmt.println("Text Editor")
	for RUNNING {
		proccess_io()
	}

	fmt.println("END")
}

proccess_io :: proc() {
	@(static)
	buf: [1024]u8
	n_read, err := os.read(os.stdin, buf[:])

	for i := 0; i < n_read; i += 1 {
		char := buf[i]
		if char == CTRL_X {
			RUNNING = false
		} else {
			fmt.print(char)
		}
	}
}

CTRL_X :: 0x18
