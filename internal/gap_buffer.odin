package internal

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:testing"
import "core:unicode/utf8"

main :: proc() {

	b := gap_buffer_create(2)
	defer gap_buffer_destroy(&b)

	// insert_char(&b, 0, '0')
	// insert_rune(&b, 1, '1')
	// insert(&b, 2, "2345678")
	// insert(&b, 0, rune('a'))
	gap_buffer_insert(&b, 0, "012456789")
	gap_buffer_insert(&b, 3, "3")
	fmt.println(gap_buffer_get_left_right_strings(&b))
	gap_buffer_remove(&b, 1, 8)
	fmt.println(gap_buffer_get_left_right_strings(&b))

}

BufferPosition :: int
GapBuffer :: struct {
	buf:       []u8, // Can be dynamic to manage the size and insertion, deletion by the Odin dynamic array
	start:     BufferPosition,
	end:       BufferPosition,
	allocator: runtime.Allocator,
}

gap_buffer_get_len :: proc(gb: ^GapBuffer) -> int {
	gap := gb.end - gb.start
	return len(gb.buf) - gap
}

// Gets strings that point into the left and right sides of the gap. Note that this is neither thread, or even operation safe.
// Strings need to be immediately cloned or operated on prior to editing the buffer again.
gap_buffer_get_left_right_strings :: proc(gb: ^GapBuffer) -> (left: string, right: string) {
	left = string(gb.buf[:gb.start])
	right = string(gb.buf[gb.end:])

	return
}

// Allocates the Gap Buffer, stores the provided allocator for all future reallocations
gap_buffer_create :: proc(n_bytes: int, allocator := context.allocator) -> (gb := GapBuffer{}) {
	gb.buf = make([]u8, n_bytes, allocator)

	gb.end = n_bytes

	gb.allocator = allocator

	return
}

// Deletes the internal buffer
gap_buffer_destroy :: proc(gb: ^GapBuffer) {
	delete(gb.buf)
	gb.buf = nil
}

// Moves the Gap to the cursor position. Cursors are clamped [0,n) where n is the filled count of the buffer.
gap_buffer_shift :: proc(gb: ^GapBuffer, cursor: BufferPosition) {
	gap_len := gb.end - gb.start

	cursor := clamp(cursor, 0, len(gb.buf) - gap_len)

	if cursor == gb.start do return

	if gb.start < cursor {
		// Gap is before the cursor:
		//    v~~~~v
		// [12]                             [3456789abc]
		// --------|------------------------------------ Gap is BEFORE Cursor
		// [123456]                             [789abc]

		delta := cursor - gb.start
		mem.copy(&gb.buf[gb.start], &gb.buf[gb.end], delta)
		gb.start += delta
		gb.end += delta
	} else if gb.start > cursor {
		// Gap is after the cursor
		//
		// [123456]                             [789abc]
		// ---|----------------------------------------- Gap is AFTER Cursor
		// [12]                             [3456789abc]

		delta := gb.start - cursor
		mem.copy(&gb.buf[gb.end - delta], &gb.buf[gb.start - delta], delta)
		gb.start -= delta
		gb.end -= delta
	}
}

// Verifies the buffer can hold the needed write. Resizes the array if not. By default doubles array size.
gap_buffer_check_size :: proc(gb: ^GapBuffer, n_required: int) {
	gap_len := gb.end - gb.start

	if gap_len < n_required {
		gap_buffer_shift(gb, len(gb.buf) - gap_len)
		req_buf_size := n_required + len(gb.buf) - gap_len
		new_buf := make([]u8, 2 * req_buf_size, gb.allocator)
		copy_slice(new_buf, gb.buf[:gb.end])
		delete(gb.buf)
		gb.buf = new_buf
		gb.end = len(gb.buf)
	}
}

// Moves the gap to the cursor, then moves the gap pointer beyond count, effectively deleting it.  
// Note: Do not rely on the gap being 0, remove will leave as-is values behind in the gap  
// WARNING: Does not protect for unicode at present, simply deletes bytes
gap_buffer_remove :: proc(gb: ^GapBuffer, cursor: BufferPosition, count: int) {
	n_del := abs(count)

	eff_cursor := cursor

	if count < 0 do eff_cursor = max(0, eff_cursor - n_del)

	gap_buffer_shift(gb, eff_cursor)

	gb.end = min(gb.end + n_del, len(gb.buf))
}

gap_buffer_insert :: proc {
	gap_buffer_insert_char,
	gap_buffer_insert_rune,
	gap_buffer_insert_slice,
	gap_buffer_insert_string,
}

gap_buffer_insert_char :: proc(gb: ^GapBuffer, cursor: BufferPosition, char: u8) {
	gap_buffer_check_size(gb, 1)
	gap_buffer_shift(gb, cursor)
	gb.buf[gb.start] = char
	gb.start += 1
}

gap_buffer_insert_rune :: proc(gb: ^GapBuffer, cursor: BufferPosition, r: rune) {
	bytes, length := utf8.encode_rune(r)
	gap_buffer_insert_slice(gb, cursor, bytes[:length])
}

gap_buffer_insert_slice :: proc(gb: ^GapBuffer, cursor: BufferPosition, slice: []u8) {
	gap_buffer_check_size(gb, len(slice))
	gap_buffer_shift(gb, cursor)
	copy_slice(gb.buf[gb.start:gb.end], slice)
	gb.start += len(slice)
}

gap_buffer_insert_string :: proc(gb: ^GapBuffer, cursor: BufferPosition, str: string) {
	gap_buffer_insert_slice(gb, cursor, transmute([]u8)str)
}
