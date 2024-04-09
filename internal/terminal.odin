package internal

import "../config"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

Terminal :: struct {
	dims:          [2]int,
	render_cursor: [2]int,
	line_offset:   int,
	buffer:        TextBuffer,
	screen_buffer: strings.Builder,
	status_line:   [dynamic]u8,
}

terminal_create :: proc(n_bytes: int = 4) -> (t: Terminal) {
	t.dims = _get_window_size()
	t.screen_buffer = strings.builder_make_len_cap(0, t.dims.x * t.dims.y)
	t.status_line = make([dynamic]u8, t.dims.y)

	terminal_clear_status_line(&t)

	t.dims.x -= config.STATUS_LINE

	t.buffer = text_buf_create(n_bytes)

	t.render_cursor = {1, 1}

	t.buffer.cursor = 0

	return
}

terminal_destroy :: proc(t: ^Terminal) {
	text_buf_destroy(&t.buffer)
	strings.builder_destroy(&t.screen_buffer)
	delete(t.status_line)
	t.status_line = nil
}

terminal_update_render_cursor :: proc(t: ^Terminal) {
	abs_row := 0
	end_of_buffer := text_buf_get_len(&t.buffer)

	// todo:: binary search
	for starts_at, i in t.buffer.lines {
		past_start_of_row := t.buffer.cursor >= starts_at
		on_last_row := i == len(t.buffer.lines) - 1
		if past_start_of_row && (on_last_row || t.buffer.cursor < t.buffer.lines[i + 1]) {
			t.render_cursor.y = t.buffer.cursor - starts_at + 1
			abs_row = i
			break
		}
	}

	need_to_move := abs_row - t.line_offset - (t.render_cursor.x - 1)
	if need_to_move < 0 {
		balance := min(abs(need_to_move), t.render_cursor.x - 1) // mutate in zero-space, dont need to xform back
		t.render_cursor.x -= balance
		t.line_offset -= abs(need_to_move) - balance
	} else if need_to_move > 0 {
		balance := min(need_to_move, t.dims.x - t.render_cursor.x)
		t.render_cursor.x += balance
		t.line_offset += need_to_move - balance
	}
}

terminal_move_cursor_by_page :: proc(t: ^Terminal, n: int) {
	if len(t.buffer.lines) == 0 do return

	move_by := n * t.dims.x
	requested_offset := move_by + t.line_offset
	actual_offset := clamp(requested_offset, 0, len(t.buffer.lines) - t.dims.x)

	overstep := abs(actual_offset - requested_offset) // todo:: remove abs, not really needed
	overstep *= n < 0 ? -1 : 1
	t.line_offset = actual_offset

	t.render_cursor.x = clamp(t.render_cursor.x + overstep, 1, t.dims.x)

	abs_line := t.line_offset + t.render_cursor.x - 1
	starts_at := t.buffer.lines[abs_line]
	col := min(t.render_cursor.y - 1, text_buf_get_line_len(&t.buffer, abs_line))
	t.buffer.cursor = starts_at + col
}

terminal_move_cursor_by_lines :: proc(t: ^Terminal, n: int) {
	if len(t.buffer.lines) == 0 do return

	row := (t.render_cursor.x - 1) + n

	need_to_move := 0

	if row < 0 {
		need_to_move = row
		row = 0
	} else if row > t.dims.x {
		need_to_move = row - t.dims.x
		row = t.dims.x
	}

	t.line_offset = clamp(t.line_offset + need_to_move, 0, len(t.buffer.lines) - 1)
	abs_line := clamp(t.line_offset + row, 0, len(t.buffer.lines) - 1)
	starts_at := t.buffer.lines[abs_line]
	col := min(t.render_cursor.y - 1, text_buf_get_line_len(&t.buffer, abs_line) - 1)

	t.buffer.cursor = starts_at + col
}

// todo:: maybe move into text buffer?
terminal_move_cursor_by_runes :: proc(t: ^Terminal, n: int) {
	buffer := t.buffer.gb.buf
	cursor := t.buffer.cursor

	if n > 0 {
		for i := 0; i < n; i += 1 {
			if cursor >= len(buffer) do break
			r, rune_size := utf8.decode_rune_in_bytes(buffer[cursor:])
			cursor += rune_size
		}
	} else {
		for i := 0; i > n; i -= 1 {
			if cursor <= 0 do break
			r, rune_size := utf8.decode_last_rune_in_bytes(buffer[:cursor])
			cursor -= rune_size
		}
	}

	t.buffer.cursor = clamp(cursor, 0, text_buf_get_len(&t.buffer))
}

terminal_clear_status_line :: proc(t: ^Terminal) {
	mem.set(&t.status_line[0], ' ', len(t.status_line))
}

terminal_write_status_line :: proc(t: ^Terminal) {
	fmt.bprintf(
		t.status_line[:],
		"[%v,%v] | Offset: %v | Cursor: %v/%v | #Lines: %v | CTRL+X: Save & Exit | CTRL+Q: Quit, No Save",
		t.render_cursor.x,
		t.render_cursor.y,
		t.line_offset,
		t.buffer.cursor,
		text_buf_get_len(&t.buffer),
		len(t.buffer.lines),
	)
}

terminal_get_visible_cursors :: proc(t: ^Terminal) -> (start, end: int) {
	if len(t.buffer.lines) == 0 {
		end = text_buf_get_len(&t.buffer)
		return
	}

	start = t.buffer.lines[t.line_offset]
	last_line := min(len(t.buffer.lines) - 1, t.line_offset + t.dims.x)

	if last_line == len(t.buffer.lines) - 1 do end = text_buf_get_len(&t.buffer)
	else do end = t.buffer.lines[last_line]

	return
}
