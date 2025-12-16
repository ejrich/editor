#import thread

// Multithreading
init_thread_pool() {
    thread_count = get_processors();
    max_thread_count := thread_count - 1;

    low_priority_count := max_thread_count / 2;
    high_priority_count := max_thread_count - low_priority_count;

    // For very low core count systems, allocate at least one thread to the low priority queue
    // and use the main thread to handle the high priority queue
    if max_thread_count <= 1 {
        high_priority_count = 0;
        low_priority_count = 1;
    }

    init_work_queue(&high_priority_queue, high_priority_count);
    init_work_queue(&low_priority_queue, low_priority_count);
}

struct WorkQueue {
    start: int;
    end: int;
    count: int;
    completed: int;
    semaphore: Semaphore;
    entries: Array<QueueItem>[queue_size];
}

high_priority_queue: WorkQueue;
low_priority_queue: WorkQueue;

union JobData {
    byte: u8;
    sbyte: s8;
    ushort: u16;
    short: s16;
    uint: u32;
    int: s32;
    ulong: u64;
    long: s64;
    pointer: void*;
    string: string;
}

interface Callback(int index, JobData data)

queue_work(WorkQueue* queue, Callback callback) {
    data: JobData;
    queue_work(queue, callback, data);
}

queue_work(WorkQueue* queue, Callback callback, JobData data) {
    current_end := queue.end;
    next_end := (current_end + 1) % queue_size;
    assert(next_end != queue.start);

    while current_end != compare_exchange(&queue.end, next_end, current_end) {
        current_end = queue.end;
        next_end = (current_end + 1) % queue_size;
        assert(next_end != queue.start);
    }

    queue.entries[current_end] = { callback = callback; data = data; }
    atomic_increment(&queue.count);
    semaphore_release(&queue.semaphore);
}

complete_work(WorkQueue* queue) {
    while queue.completed < queue.count
        execute_queued_item(queue, 0);

    queue.completed = 0;
    queue.count = 0;
}

thread_count: int;


#private

thread_index := 0;

init_work_queue(WorkQueue* queue, int thread_count) {
    create_semaphore(&queue.semaphore, 65536);

    each i in thread_count {
        create_thread(thread_worker, queue);
    }
}

void* thread_worker(void* queue) {
    work_queue := cast(WorkQueue*, queue);
    index := atomic_increment(&thread_index);

    while true {
        if execute_queued_item(work_queue, index) {
            semaphore_wait(&work_queue.semaphore);
        }
    }
    return null;
}

queue_size := 256; #const

struct QueueItem {
    callback: Callback;
    data: JobData;
}

bool execute_queued_item(WorkQueue* queue, int thread_index) {
    current_start := queue.start;
    next_start := (current_start + 1) % queue_size;

    if current_start == queue.end {
        return true;
    }

    index := compare_exchange(&queue.start, next_start, current_start);

    if index == current_start {
        queue_item := queue.entries[index];
        queue_item.callback(thread_index, queue_item.data);
        atomic_increment(&queue.completed);
    }

    return false;
}
