package text_editor

import "ansi_codes"
import "core:fmt"
import "core:os"
import "core:strings"
import "gap_buffer"


main :: proc() {
	if len(os.args) != 2 {
		fmt.println("Invalid args - expected 'text-editor <file.ext>")
		os.exit(1)
	}

	file_path := os.args[1]

	f, e := os.open(file_path, os.O_CREATE | os.O_RDWR, 0o644)
	if os.INVALID_HANDLE == f {
		fmt.println("Bad Handle")
		os.exit(1)
	}
	if e < 0 {
		fmt.printf("File open error 0x%x", -e)
		os.exit(1)
	}

	using ansi_codes

	_set_terminal()
	defer _restore_terminal()

	alt_buffer_mode(true)
	defer alt_buffer_mode(false)

	fs, err := os.file_size(f)
	assert(err > -1)
	t := terminal_create(int(fs))
	defer terminal_destroy(&t)

	if fs > 0 {
		ok := text_buf_insert_file_at(&t.buffer, 0, f)
		if !ok {
			alt_buffer_mode(false)
			_restore_terminal()
			fmt.println("failed to read input file, aborting")
			os.exit(1)
		}
	}

	// First Paint
	t.buffer.cursor = 0
	render(&t)
	move_to(t.render_cursor.x, t.render_cursor.y)

	// Main Loop
	for RUNNING {
		if update(&t) {
			update_render_cursor(&t)
			render(&t)
		}
		move_to(t.render_cursor.x, t.render_cursor.y)
	}

	os.close(f)

	if SHOULD_SAVE {
		f, e = os.open(file_path, os.O_WRONLY, 0o644)
		assert(e > -1, "Error")
		assert(f != os.INVALID_HANDLE, "Bad Handle")
		defer os.close(f)

		text_buf_flush_to_file(&t.buffer, f)
	}
}

render :: proc(t: ^Terminal) {
	using ansi_codes
	erase(.All) // todo:: repaint only touched?

	// Status Line:
	write_status_line(t)
	move_to(t.dims.x + STATUS_LINE, 0)
	set_graphic_rendition(.Bright_Cyan_Background)
	color_ansi(.Black)

	fmt.print(string(t.status_line[:]))

	move_to(t.dims.x + STATUS_LINE, 0)
	reset()

	// Screen Render
	move_to(1, 1)
	start, end := get_visible_cursors(t)
	text_buf_print_range(&t.buffer, &t.screen_buffer, start, end)

	set_graphic_rendition(.Bright_Black_Background)

	str := strings.to_string(t.screen_buffer)

	when ODIN_OS == .Windows {
		fmt.print(str)
	} else {
		// POSIX really want \r on the screen, and we don't have in our buffer
		prev := 0
		for c, i in str {
			if c == '\n' {
				fmt.print(string(str[prev:i]))
				fmt.print("\r\n")
				prev = i + 1
			}
		}

		fmt.print(string(str[prev:len(str)]))
	}

	reset()
	clear(&t.screen_buffer.buf)
	clear_status_line(t)
}

update :: proc(t: ^Terminal) -> bool {
	@(static)
	buf: [1024]u8
	buf[1] = 0 // Guard for ESC todo:: is this really really needed?
	n_read, err := os.read(os.stdin, buf[:])

	// Status Print:
	free_all(context.temp_allocator)
	print_buf := fmt.tprintf("%x", buf[:n_read])

	fmt.bprint(t.status_line[t.dims.y - len(print_buf):], print_buf)

	for i := 0; i < n_read; i += 1 {
		char := buf[i]

		if char == CTRL_Q {
			RUNNING = false
			break
		} else if char == CTRL_X {
			RUNNING = false
			SHOULD_SAVE = true
			break
		}

		if char == ESC {
			// Arrows - todo:: Guard for `i > n`
			if buf[i + 1] == 0x5b {
				// ESC [0x5b] ARROW_CODE
				i += 2

				switch buf[i] {
				case ARROW_UP:
					move_cursor_by_lines(t, -1)

				case ARROW_DOWN:
					move_cursor_by_lines(t, 1)

				case ARROW_RIGHT:
					move_cursor_by_runes(t, 1)

				case ARROW_LEFT:
					move_cursor_by_runes(t, -1)

				case HOME:
					n := t.render_cursor.y - 1
					move_cursor_by_runes(t, -n)

				case END:
					current_line := t.line_offset + t.render_cursor.x - 1
					ll := text_buf_get_line_len(&t.buffer, current_line)
					n := ll - t.render_cursor.y
					move_cursor_by_runes(t, n)

					// bandaid - sometimes end does not actually land on the end..?
					r := text_buf_get_rune_at(&t.buffer, t.buffer.cursor)
					if r != '\n' do move_cursor_by_runes(t, 1)

				case PAGE_UP:
					move_cursor_by_page(t, -1)

				case PAGE_DOWN:
					move_cursor_by_page(t, 1)

				case 0x33:
					if buf[i + 1] == DEL do text_buf_remove_at(&t.buffer, t.buffer.cursor, 1)
					else if buf[i + 1] == BKSP do text_buf_remove_at(&t.buffer, t.buffer.cursor, -1)
				}
			}
			break
		} else if buf[i] == DEL  /* POSIX */do text_buf_remove_at(&t.buffer, t.buffer.cursor, 1)
		else if buf[i] == BKSP  /* POSIX */do text_buf_remove_at(&t.buffer, t.buffer.cursor, -1)
		else {
			s := [1]u8{char} // todo:: process more than one char at a time

			if char == '\r' || char == '\n' do text_buf_insert_string_at(&t.buffer, t.buffer.cursor, "\n")
			else do text_buf_insert_string_at(&t.buffer, t.buffer.cursor, string(s[:]))
		}
	}

	return n_read > 0
}
