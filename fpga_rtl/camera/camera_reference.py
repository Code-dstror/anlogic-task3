"""Independent byte/crop contracts used by camera self-checking benches."""


def sensor_write(address, value):
    return bytes((0x34, address >> 8, address & 255, value))


def crop_frame(rows, first_row, first_group, width, height):
    """Rows contain 4-pixel groups, preserving the original Bayer samples."""
    assert width % 4 == 0
    return [row[first_group:first_group + width // 4]
            for row in rows[first_row:first_row + height]]


def rgb_bytes(pixels):
    return bytes(channel for pixel in pixels for channel in pixel)


if __name__ == "__main__":
    assert sensor_write(0x3000, 1) == bytes((0x34, 0x30, 0, 1))
    assert crop_frame([[10 * y + x for x in range(6)] for y in range(5)],
                      1, 1, 8, 2) == [[11, 12], [21, 22]]
    assert rgb_bytes([(1, 2, 3), (4, 5, 6)]) == bytes(range(1, 7))
    print("camera reference contracts PASS")
