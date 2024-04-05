package text_editor

import "core:fmt"
import "core:os"
import "core:strings"
import "gap_buffer"

TextBuffer :: struct {
	using gb: gap_buffer.GapBuffer,
	cursor:   int, // sb terminal?
	lines:    [dynamic]int, // starts_at
}

text_buf_create :: proc(n_bytes: int = 64) -> (tb := TextBuffer{}) {
	tb.gb = gap_buffer.create(max(64, n_bytes))

	return
}

text_buf_destroy :: proc(tb: ^TextBuffer) {
	gap_buffer.destroy(&tb.gb)
}

// O(n)
text_buf_calculate_lines :: proc(tb: ^TextBuffer) {
	clear(&tb.lines)

	left, right := gap_buffer.get_left_right_strings(&tb.gb)

	append(&tb.lines, 0) // start of file

	// todo:: AVX Scanning?
	// todo:: Only invalidate post-cursor
	// todo:: Handle Wrapping ScreenWidth
	for i := 0; i < len(left); i += 1 {
		if left[i] == '\n' do append(&tb.lines, i + 1)
	}

	for i := 0; i < len(right); i += 1 {
		if right[i] == '\n' do append(&tb.lines, len(left) + i + 1)
	}
}

text_buf_get_len :: proc(tb: ^TextBuffer) -> int {
	return gap_buffer.get_len(&tb.gb)
}

text_buf_get_line_len :: proc(tb: ^TextBuffer, the_line: int) -> int {
	fmt.assertf(the_line >= 0 && the_line <= len(tb.lines), "invalid line %v", the_line)

	// Last line:
	if the_line >= len(tb.lines) - 1 {
		buf_len := text_buf_get_len(tb)
		return buf_len - tb.lines[len(tb.lines) - 1]
	}

	starts_at := tb.lines[the_line]
	next_at := tb.lines[the_line + 1]
	return next_at - starts_at
}

text_buf_insert_string_at :: proc(tb: ^TextBuffer, cursor: int, s: string) {
	gap_buffer.insert(&tb.gb, cursor, s)
	tb.cursor += len(s)
	text_buf_calculate_lines(tb)
}

// todo:: File Cursors?
text_buf_insert_file_at :: proc(tb: ^TextBuffer, cursor: int, handle: os.Handle) -> (ok: bool) {
	if handle == os.INVALID_HANDLE do return false

	fs, err := os.file_size(handle)

	if err < 0 do return false

	gap_buffer.check_size(&tb.gb, int(fs))
	gap_buffer.shift(&tb.gb, cursor)

	gb_slice := tb.buf[tb.gb.start:tb.gb.end]

	n, rerr := os.read(handle, gb_slice)

	fmt.assertf(rerr > -1, "read err 0x%x", -rerr)

	assert(n == int(fs), "mismatched os.read")

	tb.gb.start += n

	text_buf_calculate_lines(tb)

	return true
}

// todo:: Buffer/File Cursors (?)
// Note: Seeks to start of file
text_buf_flush_to_file :: proc(tb: ^TextBuffer, handle: os.Handle) -> (ok: bool) {
	if handle == os.INVALID_HANDLE do return false

	os.seek(handle, 0, os.SEEK_SET)

	left, right := gap_buffer.get_left_right_strings(&tb.gb)

	os.write_string(handle, left)
	os.write_string(handle, right)

	return true
}

text_buf_remove_at :: proc(tb: ^TextBuffer, cursor: int, count: int) {
	eff_cursor := cursor
	if count < 0 do eff_cursor -= 2 // Backspace
	gap_buffer.remove(&tb.gb, cursor, count)

	if count < 0 do tb.cursor = max(0, tb.cursor + count)

	text_buf_calculate_lines(tb)
}

// todo:: actual UTF8 support
text_buf_get_rune_at :: proc(tb: ^TextBuffer) -> rune {
	cursor := clamp(tb.cursor, 0, text_buf_get_len(tb) - 1)

	left, right := gap_buffer.get_left_right_strings(&tb.gb)

	return cursor < len(left) ? rune(left[cursor]) : rune(right[cursor - len(left)])
}

text_buf_print_range :: proc(
	tb: ^TextBuffer,
	buf: ^strings.Builder,
	start_cursor, end_cursor: int,
) {
	left, right := gap_buffer.get_left_right_strings(&tb.gb)

	assert(start_cursor >= 0, "invalid start")
	assert(end_cursor <= text_buf_get_len(tb), "invalid end")

	left_len := len(left)
	if end_cursor <= left_len do strings.write_string(buf, left[start_cursor:end_cursor])
	else if start_cursor >= left_len do strings.write_string(buf, right[start_cursor - left_len:end_cursor - left_len])
	else {
		strings.write_string(buf, left[start_cursor:])
		strings.write_string(buf, right[0:end_cursor - left_len])
	}
}
