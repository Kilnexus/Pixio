const builtin = @import("builtin");
const std = @import("std");

pub fn forChunks(
    total_items: usize,
    work_items: usize,
    min_items_per_chunk: usize,
    comptime func: anytype,
    args: anytype,
) !void {
    if (total_items == 0) {
        @call(.auto, func, args ++ .{ @as(usize, 0), @as(usize, 0) });
        return;
    }

    const worker_count = chooseWorkerCount(total_items, work_items, min_items_per_chunk);
    if (builtin.single_threaded or worker_count <= 1) {
        @call(.auto, func, args ++ .{ @as(usize, 0), total_items });
        return;
    }

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{
        .allocator = std.heap.page_allocator,
        .n_jobs = worker_count,
    });
    defer pool.deinit();

    var wait_group: std.Thread.WaitGroup = .{};
    const chunk_size = std.math.divCeil(usize, total_items, worker_count) catch unreachable;

    var start: usize = 0;
    while (start < total_items) {
        const end = @min(total_items, start + chunk_size);
        pool.spawnWg(&wait_group, func, args ++ .{ start, end });
        start = end;
    }

    wait_group.wait();
}

fn chooseWorkerCount(total_items: usize, work_items: usize, min_items_per_chunk: usize) usize {
    if (total_items < min_items_per_chunk * 2) return 1;
    if (work_items < 1_000_000) return 1;

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const chunk_limited = @max(1, total_items / min_items_per_chunk);
    return @min(cpu_count, chunk_limited);
}
