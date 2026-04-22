const builtin = @import("builtin");
const std = @import("std");
const io = std.Options.debug_io;

threadlocal var parallel_depth: usize = 0;

pub fn forChunks(
    total_items: usize,
    work_items: usize,
    min_items_per_chunk: usize,
    comptime func: anytype,
    args: anytype,
) !void {
    if (total_items == 0) {
        callInParallelContext(func, args ++ .{ @as(usize, 0), @as(usize, 0) });
        return;
    }

    const worker_count = chooseWorkerCount(total_items, work_items, min_items_per_chunk);
    if (builtin.single_threaded or worker_count <= 1 or parallel_depth > 0) {
        callInParallelContext(func, args ++ .{ @as(usize, 0), total_items });
        return;
    }

    const chunk_size = std.math.divCeil(usize, total_items, worker_count) catch unreachable;
    const spawned_capacity = worker_count - 1;
    const threads = try std.heap.page_allocator.alloc(std.Thread, spawned_capacity);
    defer std.heap.page_allocator.free(threads);

    var start: usize = 0;
    var thread_count: usize = 0;
    while (start < total_items) {
        const end = @min(total_items, start + chunk_size);
        if (end == total_items) {
            callInParallelContext(func, args ++ .{ start, end });
        } else {
            threads[thread_count] = try std.Thread.spawn(.{}, runChunk, .{ func, args, start, end });
            thread_count += 1;
        }
        start = end;
    }

    for (threads[0..thread_count]) |thread| {
        thread.join();
    }
}

pub fn forChunksFallible(
    total_items: usize,
    work_items: usize,
    min_items_per_chunk: usize,
    comptime func: anytype,
    args: anytype,
) !void {
    if (total_items == 0) {
        try callInParallelContext(func, args ++ .{ @as(usize, 0), @as(usize, 0) });
        return;
    }

    const worker_count = chooseWorkerCount(total_items, work_items, min_items_per_chunk);
    if (builtin.single_threaded or worker_count <= 1 or parallel_depth > 0) {
        try callInParallelContext(func, args ++ .{ @as(usize, 0), total_items });
        return;
    }

    const Args = @TypeOf(args);
    const State = struct {
        mutex: std.Io.Mutex = .init,
        first_error: ?anyerror = null,

        fn run(state: *@This(), args_inner: Args, start: usize, end: usize) void {
            callInParallelContext(func, args_inner ++ .{ start, end }) catch |err| {
                state.mutex.lockUncancelable(io);
                defer state.mutex.unlock(io);
                if (state.first_error == null) state.first_error = err;
            };
        }
    };

    var state: State = .{};
    const chunk_size = std.math.divCeil(usize, total_items, worker_count) catch unreachable;
    const spawned_capacity = worker_count - 1;
    const threads = try std.heap.page_allocator.alloc(std.Thread, spawned_capacity);
    defer std.heap.page_allocator.free(threads);

    var start: usize = 0;
    var thread_count: usize = 0;
    while (start < total_items) {
        const end = @min(total_items, start + chunk_size);
        if (end == total_items) {
            State.run(&state, args, start, end);
        } else {
            threads[thread_count] = try std.Thread.spawn(.{}, State.run, .{ &state, args, start, end });
            thread_count += 1;
        }
        start = end;
    }

    for (threads[0..thread_count]) |thread| {
        thread.join();
    }
    if (state.first_error) |err| return err;
}

fn callInParallelContext(comptime func: anytype, args: anytype) @TypeOf(@call(.auto, func, args)) {
    parallel_depth += 1;
    defer parallel_depth -= 1;
    return @call(.auto, func, args);
}

fn runChunk(comptime func: anytype, args: anytype, start: usize, end: usize) void {
    callInParallelContext(func, args ++ .{ start, end });
}

fn chooseWorkerCount(total_items: usize, work_items: usize, min_items_per_chunk: usize) usize {
    if (total_items < min_items_per_chunk * 2) return 1;
    if (work_items < 1_000_000) return 1;

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const chunk_limited = @max(1, total_items / min_items_per_chunk);
    return @min(cpu_count, chunk_limited);
}
