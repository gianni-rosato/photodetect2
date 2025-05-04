const std = @import("std");

const p = @import("./pam_dec.zig");
const PAMImage = p.PAMImage;

const ScreenContentClass = enum {
    OUT_SC_PHOTO,
    OUT_SC_BASIC,
    OUT_SC_HIVAR,
    OUT_SC_MED,
    OUT_SC_HIGH,
};

const InputImage = struct {
    width: usize = 0,
    height: usize = 0,
    y: ?[]u8 = null,
    y_stride: usize = 0,

    fn lumaFromRgb(
        img: *InputImage,
        pam: *const PAMImage,
    ) void {
        var dst_idx: usize = 0;
        var src_idx: usize = 0;
        while (dst_idx < img.width * img.height) : (dst_idx += 1) {
            const y: f64 =
                @as(f64, @floatFromInt(pam.data.?[src_idx])) * 0.299 +
                @as(f64, @floatFromInt(pam.data.?[src_idx + 1])) * 0.587 +
                @as(f64, @floatFromInt(pam.data.?[src_idx + 2])) * 0.114;
            img.y.?[dst_idx] = @intFromFloat(y);
            src_idx += pam.depth;
        }
    }

    fn detectScreenContent(img: *const InputImage) ScreenContentClass {
        const scc = ScreenContentClass;
        if (img.width < 1 or img.height < 1 or img.y == null)
            return scc.OUT_SC_PHOTO;

        const blk_w: usize = 16;
        const blk_h: usize = 16;

        const simple_color_thresh = 4;
        const complex_final_color_thresh = 6;
        const var_thresh = 5;

        var counts_1: usize = 0;
        var counts_2: usize = 0;
        var counts_photo: usize = 0;

        var dilated_blk: [blk_w * blk_h]u8 = undefined;
        const dilated_blk_ptr: [*]u8 = &dilated_blk;

        var r: usize = 0;
        while (r + blk_h <= img.height) : (r += blk_h) {
            var c: usize = 0;
            while (c + blk_w <= img.width) : (c += blk_w) {
                const src_stride: usize = img.y_stride;
                var number_of_colors: usize = 0;
                const src_block_ptr: [*]const u8 = img.y.?.ptr + r * img.y_stride + c;

                const counted_distinct_colors: bool =
                    countDistinctColors(src_block_ptr, src_stride, blk_w, blk_h, complex_final_color_thresh, &number_of_colors);
                if (counted_distinct_colors) {
                    if (number_of_colors <= simple_color_thresh) {
                        counts_1 += 1;
                        const variance: usize =
                            calculateVariance(src_block_ptr, src_stride, blk_w, blk_h);
                        if (variance > var_thresh) counts_2 += 1;
                    } else {
                        dilateBlock(src_block_ptr, dilated_blk_ptr, src_stride, blk_w, blk_h);
                        const counted_distinct_colors_2: bool =
                            countDistinctColors(dilated_blk_ptr, blk_w, blk_w, blk_h, complex_final_color_thresh, &number_of_colors);
                        if (counted_distinct_colors_2) {
                            counts_1 += 1;
                            const variance: usize = calculateVariance(src_block_ptr, src_stride, blk_w, blk_h);
                            if (variance > var_thresh) counts_2 += 1;
                        }
                    }
                } else {
                    counts_photo += 1;
                }
            }
        }

        const tot_px_area: usize = img.width * img.height;
        const blk_area: usize = blk_w * blk_h;
        const photo_penalty: usize = counts_photo / 24;

        const score1_base: isize = @as(isize, @intCast(counts_1)) - @as(isize, @intCast(photo_penalty));
        const score2_base: isize = @as(isize, @intCast(counts_2)) - @as(isize, @intCast(photo_penalty));
        const score1: usize = if (score1_base < 0) 0 else @intCast(score1_base);
        const score2: usize = if (score2_base < 0) 0 else @intCast(score2_base);

        const score1_check = score1 * blk_area * 10 > tot_px_area;
        const score2_check1 = score2 * blk_area * 12 > tot_px_area;

        const sc_class0: bool = score1_check;
        const sc_class1: bool = sc_class0 and score2_check1;

        const score1_check_alt2 = counts_1 * blk_area * 15 > tot_px_area * 4;
        const score2_check_alt2 = counts_2 * blk_area * 30 > tot_px_area;
        const score1_check_alt3 = counts_1 * blk_area * 8 > tot_px_area;
        const score2_check_alt3 = counts_2 * blk_area * 50 > tot_px_area;

        const sc_class2_alt: bool = score1_check_alt2 and score2_check_alt2;
        const sc_class3_alt: bool = score1_check_alt3 and score2_check_alt3;

        const sc_class2: bool = sc_class1 or sc_class2_alt;
        const sc_class3: bool = sc_class1 or sc_class3_alt;

        if (sc_class3) return scc.OUT_SC_HIGH;
        if (sc_class2) return scc.OUT_SC_MED;
        if (sc_class1) return scc.OUT_SC_HIVAR;
        if (sc_class0) return scc.OUT_SC_BASIC;
        return scc.OUT_SC_PHOTO;
    }
};

fn countDistinctColors(
    data: [*]const u8,
    stride: usize,
    w: usize,
    h: usize,
    max_colors_allowed: usize,
    num_colors: *usize,
) bool {
    var seen: [256]u8 = [_]u8{0} ** 256;
    var count: usize = 0;

    for (0..h) |r| {
        const row: [*]const u8 = data + r * stride;
        for (0..w) |c| {
            if (seen[row[c]] == 0) {
                seen[row[c]] = 1;
                count += 1;
                if (count > max_colors_allowed) {
                    num_colors.* = count;
                    return false;
                }
            }
        }
    }
    num_colors.* = count;
    return true;
}

fn calculateVariance(
    data: [*]const u8,
    stride: usize,
    w: usize,
    h: usize,
) usize {
    var sum: usize = 0;
    var sum_sq: usize = 0;
    const num_pixels: usize = w * h;
    if (num_pixels == 0) return 0;

    for (0..h) |r| {
        const row: [*]const u8 = data + r * stride;
        for (0..w) |c| {
            const val: u8 = row[c];
            sum += @intCast(val);
            sum_sq += @as(usize, @intCast(val)) * @as(usize, @intCast(val));
        }
    }

    const variance_x_n_sq: usize = num_pixels * sum_sq - sum * sum;
    const n_sq: usize = num_pixels * num_pixels;
    if (n_sq == 0) return 0;
    return @intCast((variance_x_n_sq + (n_sq / 2)) / n_sq);
}

fn findDominantColor(
    data: [*]const u8,
    stride: usize,
    w: usize,
    h: usize,
) u8 {
    var counts: [256]u16 = [_]u16{0} ** 256;
    var dominant_color: u8 = 0;
    var max_count: u16 = 0;

    for (0..h) |r| {
        const row: [*]const u8 = data + r * stride;
        for (0..w) |c| counts[row[c]] += 1;
    }
    for (0..256) |c| {
        if (counts[c] > max_count) {
            max_count = counts[c];
            dominant_color = @intCast(c);
        }
    }
    return dominant_color;
}

fn dilateBlock(
    src: [*]const u8,
    dst: [*]u8,
    src_stride: usize,
    w: usize,
    h: usize,
) void {
    const dominant_color: u8 = findDominantColor(src, src_stride, w, h);

    for (0..h) |r|
        @memcpy(dst[r * w .. r * w + w], src[r * src_stride .. r * src_stride + w]);

    for (0..h) |r| {
        for (0..w) |c| {
            if (dst[r * w + c] != dominant_color) {
                var is_neighbor_dominant: bool = false;
                var dr: isize = -1;
                while (dr < 2) : (dr += 1) {
                    var dc: isize = -1;
                    while (dc < 2) : (dc += 1) {
                        if (dr == 0 and dc == 0) continue;
                        const nr: isize = @as(isize, @intCast(r)) + dr;
                        const nc: isize = @as(isize, @intCast(c)) + dc;
                        if (nr >= 0 and nr < h and nc >= 0 and nc < w) {
                            const src_nr: usize = @intCast(nr);
                            const src_nc: usize = @intCast(nc);
                            const src_idx: usize = src_nr * src_stride + src_nc;
                            if (src[src_idx] == dominant_color) {
                                is_neighbor_dominant = true;
                                break;
                            }
                        }
                    }
                    if (is_neighbor_dominant) break;
                }
                if (is_neighbor_dominant)
                    dst[r * w + c] = dominant_color;
            }
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: sccdetect <input.pam>\n", .{});
        return error.MissingInput;
    }

    const input_file: []const u8 = args[1];

    var pam: PAMImage = undefined;
    try pam.readPam(allocator, input_file);
    defer allocator.free(pam.data.?);

    var img: InputImage = .{
        .width = pam.width,
        .height = pam.height,
        .y_stride = pam.width,
        .y = null,
    };
    img.y = try allocator.alloc(u8, img.width * img.height);
    defer allocator.free(img.y.?);

    img.lumaFromRgb(&pam);

    const result: ScreenContentClass = img.detectScreenContent();
    std.debug.print("{any}\n", .{result});
}
