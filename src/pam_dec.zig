const std = @import("std");

pub const PAMImage = struct {
    width: usize = 0,
    height: usize = 0,
    depth: u8 = 0,
    maxval: usize = 0,
    data: ?[]u8 = null,

    pub fn readPam(pam: *PAMImage, allocator: std.mem.Allocator, filename: []const u8) !void {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const file_buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(file_buffer);
        _ = try file.readAll(file_buffer);

        const end_header =
            std.mem.indexOf(u8, file_buffer, "ENDHDR\n") orelse
            return error.HeaderNotFound;
        const header_data = file_buffer[0..end_header];
        const data_start = end_header + 7; // "ENDHDR\n" is 7 bytes

        if (!std.mem.startsWith(u8, header_data, "P7"))
            return error.NotAPamFile;

        var lines = std.mem.tokenizeAny(u8, header_data, "\r\n");
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "#")) continue; // skip comments
            if (std.mem.startsWith(u8, line, "WIDTH")) {
                var value_it = std.mem.tokenizeAny(u8, line[5..], " \t");
                if (value_it.next()) |value|
                    pam.width = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.startsWith(u8, line, "HEIGHT")) {
                var value_it = std.mem.tokenizeAny(u8, line[6..], " \t");
                if (value_it.next()) |value|
                    pam.height = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.startsWith(u8, line, "DEPTH")) {
                var value_it = std.mem.tokenizeAny(u8, line[5..], " \t");
                if (value_it.next()) |value|
                    pam.depth = try std.fmt.parseInt(u8, value, 10);
            } else if (std.mem.startsWith(u8, line, "MAXVAL")) {
                var value_it = std.mem.tokenizeAny(u8, line[6..], " \t");
                if (value_it.next()) |value|
                    pam.maxval = try std.fmt.parseInt(usize, value, 10);
            }
        }

        if (pam.width <= 0 or pam.height <= 0 or pam.depth <= 0 or pam.maxval <= 0)
            return error.InvalidPamDimensions;

        const data_size = @as(usize, @intCast(pam.width)) *
            @as(usize, @intCast(pam.height)) *
            @as(usize, @intCast(pam.depth));
        pam.data = try allocator.alloc(u8, data_size);
        errdefer allocator.free(pam.data.?);

        if (data_start + data_size > file_buffer.len)
            return error.InsufficientDataInFile;

        @memcpy(pam.data.?, file_buffer[data_start .. data_start + data_size]);
        return;
    }
};
