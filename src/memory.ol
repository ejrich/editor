// Memory allocation
init_memory() {
    arena_head = create_arena(0);
    allocate_line_arenas();
    init_small_arena();
}

// General allocation
T* new<T>() #inline {
    value: T;
    size := size_of(T);
    pointer: T* = allocate(size);
    *pointer = value;

    return pointer;
}

/*

Memory allocator design

- For sizes <= 256 bytes, try to allocate in an arena reserved for these allocations
- Otherwise allocate in the general purpose arena

Small allocator arena:

// 260 bytes - 4 for block for 256 bytes of storage
struct SmallMemoryBlock {
    used: bool; // 1
    index: u16; // 3-4
}

Allocate 10000 on startup for 2.6mb memory, aka nothing


General allocator arena:

MemoryBlock:
- used
- locked
- size
- next
- previous
- checksum

When allocating, try to find a block that fits the size
If the block is locked, wait until it is unlocked before checking again
Once it is unlocked, verify the checksum. If it fails, restart the search
When a valid block is found, lock it and try to insert another block

Allocate new arenas if a block was not found


When freeing blocks, attempt to merge the surrounding blocks
Lock both blocks being merged and clear the data of the rightmost block, this will cause the checksum verification to fail in allocate

*/

void* allocate(u64 size) {
    // Pad out the size to make sure it is a multiple of 8
    padding := size % 8;
    if padding size += 8 - padding;

    if size <= small_block_size {
        success, pointer := try_small_allocation();
        if success return pointer;
    }

    if size > default_arena_size
        return allocate_arena(size, size);

    arena := arena_head;
    while arena {
        block := arena.first_block;
        retry := false;
        while block {
            while true
                if !block.locked break;

            next := block.next;
            if !verify_checksum(block) {
                retry = true;
                break;
            }

            if !block.used && block.size >= size {
                // Try to obtain a lock on the block
                if !compare_exchange(&block.locked, true, false) {
                    result: void* = block + 1;

                    insert_memory_block_if_possible(block, size, result);
                    clear_memory(result, size);
                    set_checksum(block);
                    block.used = true;
                    block.locked = false;
                    return result;
                }
            }

            block = next;
        }

        if !retry
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

    // Handle small allocations
    if is_small_allocation(pointer) {
        if size <= small_block_size {
            return pointer;
        }

        new_pointer := allocate(size);
        memory_copy(new_pointer, pointer, small_block_size);
        free_small_allocation(pointer);

        return new_pointer;
    }

    // Convert pointer to memory block
    block := cast(MemoryBlock*, pointer) - 1;
    if size <= block.size return pointer;

    // Create a new allocation and free the existing memory block
    new_pointer := allocate(size);
    memory_copy(new_pointer, pointer, block.size);
    free_memory_block(block);

    return new_pointer;
}

free_allocation(void* pointer) {
    if pointer == null return;

    if is_small_allocation(pointer) {
        free_small_allocation(pointer);
        return;
    }

    block := cast(MemoryBlock*, pointer) - 1;
    free_memory_block(block);
}

reallocate_array<T>(Array<T>* array, int length) {
    free_allocation(array.data);
    array.data = allocate(size_of(T) * length);
    array.length = length;
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
            if block.used {
                used += size_with_header;
            }
            else {
                unused += size_with_header;
            }
            log("Block %, Size = %, %\n", block_index++, block.size, block.used);
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

free_lines(BufferLine* line) {
    while line {
        next := line.next;
        free_line_and_children(line);
        line = next;
    }
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

bool can_temp_allocate(u64 size) {
    cursor := temporary_buffer_cursor;
    return cursor + size < temp_buffer_size;
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

bool is_small_allocation(void* pointer) {
    if cast(u64, pointer) < cast(u64, small_arena.data) || cast(u64, pointer) > small_arena.data_end {
        return false;
    }

    return true;
}

#private


temp_buffer_size := 50 * 1024 * 1024; #const
temporary_buffer: CArray<u8>[temp_buffer_size];
temporary_buffer_cursor := 0;


// Small allocation
struct SmallMemoryBlock {
    used: bool;
    index: u16;
}

small_block_size := 256; #const
total_block_size := size_of(SmallMemoryBlock) + small_block_size; #const
small_block_count := 10000; #const

struct SmallMemoryArena {
    size: int;
    used: int;
    first_unused: int;
    last_unused: int;
    first_unused_mutex: Semaphore;
    data: void*;
    data_end: u64;
}

small_arena: SmallMemoryArena = {
    size = small_block_count;
    last_unused = small_block_count - 1;
 }

init_small_arena() {
    allocation_size := total_block_size * small_block_count;

    create_semaphore(&small_arena.first_unused_mutex, initial_value = 1);
    small_arena.data = allocate_memory(allocation_size);
    small_arena.data_end = cast(u64, small_arena.data) + allocation_size;
    clear_memory(small_arena.data, allocation_size);

    each i in small_block_count {
        block := cast(SmallMemoryBlock*, small_arena.data + i * total_block_size);
        block.used = false;
        block.index = i;
    }
}

bool, void* try_small_allocation() {
    while small_arena.used < small_arena.size {
        /*
        each i in small_block_count {
            block: SmallMemoryBlock* = small_arena.data + (total_block_size * i);
            if !block.used && compare_exchange(&block.used, true, false) == false {
                atomic_increment(&small_arena.used);

                result: void* = block + 1;
                clear_memory(result, small_block_size);

                return true, result;
            }
        }
        */

        first_unused := small_arena.first_unused;
        block: SmallMemoryBlock* = small_arena.data + (total_block_size * first_unused);
        if !compare_exchange(&block.used, true, false) {
            atomic_increment(&small_arena.used);
            result: void* = block + 1;
            clear_memory(result, small_block_size);

            semaphore_wait(&small_arena.first_unused_mutex);
            if block.index == small_arena.first_unused {
                each i in small_arena.first_unused + 1..small_arena.last_unused {
                    candidate_block: SmallMemoryBlock* = small_arena.data + (total_block_size * i);
                    if !candidate_block.used {
                        small_arena.first_unused = i;
                        break;
                    }
                }
            }

            semaphore_release(&small_arena.first_unused_mutex);
            return true, result;
        }

        while true {
            if small_arena.first_unused != first_unused break;
        }
    }

    return false, null;
}

free_small_allocation(void* pointer) {
    block := cast(SmallMemoryBlock*, pointer) - 1;
    block.used = false;

    if block.index < small_arena.first_unused {
        semaphore_wait(&small_arena.first_unused_mutex);
        if block.index < small_arena.first_unused {
            small_arena.first_unused = block.index;
        }

        semaphore_release(&small_arena.first_unused_mutex);
    }
    else {
        last_unused := small_arena.last_unused;
        while block.index > last_unused {
            if compare_exchange(&small_arena.last_unused, block.index, last_unused) == last_unused {
                break;
            }

            last_unused = small_arena.last_unused;
        }
    }

    atomic_decrement(&small_arena.used);
}


// General allocation
enum MemoryBlockFlags {
    Unused = 0x0;
    Locked = 0x1;
    Used   = 0x2;
}

struct MemoryBlock {
    previous: MemoryBlock*;
    next: MemoryBlock*;
    size: u64;
    checksum: u64; // 0xFFFFFFFFFFFFFFFF ^ prev ^ next ^ size
    used: bool;
    locked: bool;
    // flags: MemoryBlockFlags;
}

bool verify_checksum(MemoryBlock* block) {
    checksum: u64 = 0xFFFFFFFFFFFFFFFF ^ cast(u64, block.previous) ^ cast(u64, block.previous) ^ block.size;

    return checksum == block.checksum;
}

set_checksum(MemoryBlock* block) {
    block.checksum = 0xFFFFFFFFFFFFFFFF ^ cast(u64, block.previous) ^ cast(u64, block.previous) ^ block.size;
}

clear_block(MemoryBlock* block) {
    block.previous = null;
    block.next = null;
    block.size = 0;
    block.checksum = 0;
}

struct Arena {
    first_block: MemoryBlock*;
    next: Arena*;
    size: u64;
    start: u64;
    end: u64;
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
    first_block.previous = null;

    if initial_block_size == 0 {
        first_block.next = null;
        first_block.size = size;
        first_block.used = true;
        // first_block.flags = MemoryBlockFlags.Unused;
    }
    else if initial_block_size >= size - min_block_size {
        first_block.next = null;
        first_block.size = size;
        first_block.used = true;
        // first_block.flags = MemoryBlockFlags.Used;
    }
    else {
        first_block.size = initial_block_size;
        first_block.used = true;
        // first_block.flags = MemoryBlockFlags.Used;

        insert_memory_block(first_block, size - initial_block_size, cast(void*, first_block + 1) + initial_block_size);
    }

    set_checksum(first_block);

    arena := cast(Arena*, pointer);
    arena.first_block = first_block;
    arena.next = null;
    arena.size = size + size_of(MemoryBlock);
    arena.start = cast(u64, pointer);
    arena.end = cast(u64, pointer) + size_to_allocate;

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
    new_block.used = false;
    new_block.locked = false;
    new_block.previous = previous;

    next := previous.next;
    if next {
        while true {
            // TODO Merge the blocks if they are unused?
            if !next.locked && !compare_exchange(&next.locked, true, false) {
                next.previous = new_block;
                set_checksum(next);
                next.locked = false;
                break;
            }
        }

        new_block.next = next;
    }
    else {
        new_block.next = null;
    }

    set_checksum(new_block);
    previous.next = new_block;
}

free_memory_block(MemoryBlock* block) {
    assert(block != null);

    while true {
        if !block.locked && !compare_exchange(&block.locked, true, false) {
            break;
        }
    }

    merge_blocks(block.next, block, block.next);
    merge_blocks(block.previous, block.previous, block);

    block.used = false;
    block.locked = false;
}

merge_blocks(MemoryBlock* check_block, MemoryBlock* previous, MemoryBlock* next) {
    if previous == null || next == null return;

    // TODO Verify checksums
    if check_block != null && !check_block.used && !check_block.locked && !compare_exchange(&check_block.locked, true, false) {
        next_next := next.next;
        if next_next {
            // Only merge if next.next can be locked
            if !next_next.locked && !compare_exchange(&next_next.locked, true, false) {
                next_next.previous = previous;
                set_checksum(next_next);
                next_next.locked = false;

                previous.next = next_next;
                previous.size += size_of(MemoryBlock) + next.size;
                set_checksum(previous);

                clear_block(next);
            }
        }
        else {
            previous.next = null;
            previous.size += size_of(MemoryBlock) + next.size;
            set_checksum(previous);

            clear_block(next);
        }

        check_block.locked = false;
    }
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
