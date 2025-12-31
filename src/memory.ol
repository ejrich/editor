// Memory allocation
init_memory() {
    arena_head = create_arena(0);
    allocate_line_arenas();
}

// General allocation
T* new<T>() #inline {
    value: T;
    size := size_of(T);
    pointer: T* = allocate(size);
    *pointer = value;

    return pointer;
}

enum MemoryBlockFlags {
    Unused = 0x0;
    Locked = 0x1;
    Used   = 0x2;
}

struct MemoryBlock {
    previous: MemoryBlock*;
    next: MemoryBlock*;
    size: u64;
    flags: MemoryBlockFlags;
}

void* allocate(u64 size) {
    // Pad out the size to make sure it is a multiple of 8
    padding := size % 8;
    if padding size += 8 - padding;

    if size > default_arena_size
        return allocate_arena(size, size);

    arena := arena_head;
    while arena {
        block := arena.first_block;
        while block {
            if block.flags == MemoryBlockFlags.Unused && block.size >= size {
                // Try to obtain a lock on the block
                if compare_exchange(&block.flags, MemoryBlockFlags.Locked, MemoryBlockFlags.Unused) == MemoryBlockFlags.Unused {
                    result: void* = block + 1;

                    insert_memory_block_if_possible(block, size, result);
                    clear_memory(result, size);
                    block.flags = MemoryBlockFlags.Used;
                    return result;
                }
            }

            // Ensure that the block is not locked until moving to the next block
            while true {
                if block.flags != MemoryBlockFlags.Locked break;
            }

            block = block.next;
        }

        arena = arena.next;
    }

    return allocate_arena(size);
}

void* reallocate(void* pointer, u64 old_size, u64 size) {
    assert(pointer != null);
    if old_size >= size return pointer;

    // Pad out the size to make sure it is a multiple of 8
    padding := size % 8;
    if padding size += 8 - padding;

    // Convert pointer to memory block
    block := cast(MemoryBlock*, pointer) - 1;

    // Create a new allocation and free the existing memory block
    new_pointer := allocate(size);
    memory_copy(new_pointer, pointer, old_size);
    free_memory_block(block);

    return new_pointer;
}

free_allocation(void* pointer) {
    if pointer == null return;

    block := cast(MemoryBlock*, pointer) - 1;
    free_memory_block(block);
}

deallocate_arenas() {
    // print_arenas();

    arena := arena_head;
    while arena {
        pointer := arena;
        size := arena.size;
        arena = arena.next;

        free_memory(pointer, size);
    }
}

print_arenas() {
    total_allocated, i: u64;

    arena := arena_head;
    while arena {
        size, used, unused: u64;
        log("\nArena %, Size = %\n", i++, arena.size);
        total_allocated += arena.size;

        block_index := 0;
        block := arena.first_block;
        while block {
            size_with_header := block.size + size_of(MemoryBlock);
            size += size_with_header;
            if block.flags == MemoryBlockFlags.Unused {
                unused += size_with_header;
            }
            else {
                used += size_with_header;
            }
            log("Block %, Size = %, %\n", block_index++, block.size, block.flags);
            block = block.next;
        }

        log("Allocated arena size = %, Sum of blocks = %, Used = %, Unused = %, Missing = %\n", arena.size, size, used, unused, arena.size - size);
        arena = arena.next;
    }

    log("% arenas allocated, % mb memory\n", i, total_allocated / 1000000.0);
}

// Line allocation
BufferLine* allocate_line(BufferLine* parent = null, BufferLine* previous = null) {
    line_memory_size := size_of(BufferLine) + line_buffer_length; #const
    lines_to_allocate := 0x10000; #const

    each line_arena, i in line_arenas {
        // Initialize the line arena or wait until it has been initialized
        if !line_arena.initializing && !compare_exchange(&line_arena.initializing, true, false) {
            line_arena.index = i;
            line_arena.first_available = 0;
            line_arena.data = allocate_memory(line_memory_size * lines_to_allocate);

            each j in lines_to_allocate {
                line: BufferLine* = line_arena.data + (j * line_memory_size);
                line.arena_index = i;
                line.index = j;
                line.data.length = line_buffer_length;
                line.data.data = cast(void*, line) + size_of(BufferLine);
            }

            line_arena.initialized = true;
        }
        else {
            while !line_arena.initialized {}
        }

        tries := 0;
        max_tries := 10; #const
        while line_arena.first_available < lines_to_allocate && tries++ < max_tries {
            line: BufferLine* = line_arena.data + (line_arena.first_available * line_memory_size);
            if !line.allocated && !compare_exchange(&line.allocated, true, false) {
                line.length = 0;

                available_line := false;
                original_first_available := line_arena.first_available;
                each j in line_arena.first_available + 1..lines_to_allocate - 1 {
                    target_line: BufferLine* = line_arena.data + (j * line_memory_size);
                    if line_arena.first_available < original_first_available {
                        available_line = true;
                        break;
                    }
                    else if !target_line.allocated {
                        available_line = true;
                        if line_arena.first_available == original_first_available || j < line_arena.first_available {
                            line_arena.first_available = j;
                        }
                        break;
                    }
                }

                if !available_line && line_arena.first_available != original_first_available {
                    line_arena.first_available = lines_to_allocate;
                }

                line.parent = parent;
                line.previous = previous;
                line.next = null;
                line.child = null;

                return line;
            }
        }
    }

    assert(false, "Unable to allocate new line arena");
    return null;
}

free_line(BufferLine* line) {
    line_arena := &line_arenas[line.arena_index];
    line.allocated = false;
    if line.index < line_arena.first_available {
        line_arena.first_available = line.index;
    }
}

free_child_lines(BufferLine* line) {
    while line {
        next := line.next;
        free_line(line);
        line = next;
    }
}

free_line_and_children(BufferLine* line) {
    free_child_lines(line.child);
    free_line(line);
}


// Temporary allocation (resets every frame)
void* temp_allocate(u64 size) {
    cursor := temporary_buffer_cursor;
    assert(cursor + size < temp_buffer_size);

    while compare_exchange(&temporary_buffer_cursor, cursor + size, cursor) != cursor {
        cursor = temporary_buffer_cursor;
        assert(cursor + size < temp_buffer_size);
    }

    return &temporary_buffer[cursor];
}

Array<T> temp_allocate_array<T>(u32 length) {
    array: Array<T>;
    array.length = length;
    array.data = temp_allocate(length * size_of(T));
    return array;
}

reset_temp_buffer() #inline {
    temporary_buffer_cursor = 0;
}

#private


temp_buffer_size := 50 * 1024 * 1024; #const
temporary_buffer: CArray<u8>[temp_buffer_size];
temporary_buffer_cursor := 0;

// General allocation
struct Arena {
    first_block: MemoryBlock*;
    next: Arena*;
    size: u64;
}

min_block_size := 1024; #const
default_arena_size: u64 = 50 * 1024 * 1024; #const

arena_head: Arena*;

void* allocate_arena(u64 initial_block_size, u64 size = default_arena_size) {
    new_arena := create_arena(initial_block_size, size);

    log("Allocating new arena with initial block = %, total size = %\n", initial_block_size, size);

    arena := arena_head;
    while arena {
        if arena.next == null && compare_exchange(&arena.next, new_arena, null) == null
            break;

        arena = arena.next;
    }

    return new_arena.first_block + 1;
}

Arena* create_arena(u64 initial_block_size, u64 size = default_arena_size) {
    assert(size >= initial_block_size);

    header_size := size_of(Arena) + size_of(MemoryBlock);

    size_to_allocate := header_size + size;
    pointer := allocate_memory(size_to_allocate);

    first_block: MemoryBlock* = pointer + size_of(Arena);

    if initial_block_size == 0 {
        first_block.previous = null;
        first_block.next = null;
        first_block.size = size;
        first_block.flags = MemoryBlockFlags.Unused;
    }
    else if initial_block_size >= size - min_block_size {
        first_block.previous = null;
        first_block.next = null;
        first_block.size = size;
        first_block.flags = MemoryBlockFlags.Used;
    }
    else {
        first_block.previous = null;
        first_block.size = initial_block_size;
        first_block.flags = MemoryBlockFlags.Used;

        insert_memory_block(first_block, size - initial_block_size, cast(void*, first_block + 1) + initial_block_size);
    }

    arena := cast(Arena*, pointer);
    arena.first_block = first_block;
    arena.next = null;
    arena.size = size + size_of(MemoryBlock);

    return arena;
}

insert_memory_block_if_possible(MemoryBlock* block, u64 size, void* pointer) {
    remaining_size := block.size - size;
    if remaining_size > min_block_size {
        block.size -= remaining_size;
        insert_memory_block(block, remaining_size, pointer + size);
    }
}

insert_memory_block(MemoryBlock* previous, u64 size, MemoryBlock* new_block) {
    assert(size > size_of(MemoryBlock));
    assert(previous != null);

    new_block.size = size - size_of(MemoryBlock);
    new_block.flags = MemoryBlockFlags.Unused;
    new_block.previous = previous;
    next := previous.next;
    new_block.next = next;
    if next {
        next.previous = new_block;
    }
    previous.next = new_block;
}

free_memory_block(MemoryBlock* block) {
    assert(block != null);

    block.flags = MemoryBlockFlags.Locked;

    // Attempt to merge the the previous and next blocks with the current block, then unlock the current block
    if merge_blocks(block.previous, block.previous, block)
        block = block.previous;

    merge_blocks(block.next, block, block.next);
    block.flags = MemoryBlockFlags.Unused;
}

bool merge_blocks(MemoryBlock* check_block, MemoryBlock* previous, MemoryBlock* next) {
    if check_block != null && check_block.flags == MemoryBlockFlags.Unused {
        if compare_exchange(&check_block.flags, MemoryBlockFlags.Locked, MemoryBlockFlags.Unused) == MemoryBlockFlags.Unused {
            previous.next = next.next;
            if next.next {
                next.next.previous = next.previous;
            }

            previous.size += size_of(MemoryBlock) + next.size;
            return true;
        }
    }

    return false;
}

// Line allocation
struct LineArena {
    initializing: bool;
    initialized: bool;
    index: u8;
    first_available: u32;
    data: void*;
}

line_arenas: Array<LineArena>;

allocate_line_arenas() {
    array_resize(&line_arenas, 0x100, allocate);
}
