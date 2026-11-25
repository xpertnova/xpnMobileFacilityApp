import Foundation

/// A QR code as the grid of modules it is made of, encoded in byte mode at
/// error-correction level M — the same code CoreImage's generator produced.
///
/// The app builds its own codes because CoreImage does not come cheap: the
/// first `CIFilter.qrCodeGenerator()` in a process was measured at 7.5 s on an
/// iPad, and it blocks the main thread from the inside while it happens, so no
/// amount of moving the call to another thread hides it. Encoding here is
/// arithmetic on a few hundred bytes and takes microseconds.
///
/// The grid includes the four-module quiet zone the specification asks for, so
/// a caller can draw it as it is.
struct QRCodeMatrix {
    /// Side of the grid in modules, quiet zone included.
    let size: Int
    /// The QR version, 1...40. The number of modules of the code itself is
    /// `version * 4 + 17`.
    let version: Int
    private let dark: [Bool]

    fileprivate init(size: Int, version: Int, dark: [Bool]) {
        self.size = size
        self.version = version
        self.dark = dark
    }

    /// Whether the module at this position is dark. Positions outside the grid
    /// are light, which keeps drawing code free of bounds checks.
    subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, x < size, y >= 0, y < size else { return false }
        return dark[y * size + x]
    }

    static let quietZone = 4

    /// `nil` for an empty payload, or one that does not fit the largest code
    /// at this level.
    static func encode(_ payload: String) -> QRCodeMatrix? {
        let bytes = Array(payload.utf8)
        guard !bytes.isEmpty else { return nil }
        return QRCodeEncoder.encode(bytes)
    }
}

// MARK: - Encoding

private enum QRCodeEncoder {
    /// Error-correction level M: the number of error-correction codewords per
    /// block, and how the data codewords are split into blocks, for versions
    /// 1...40. Table 9 of ISO/IEC 18004.
    private static let blocks: [(ecCodewords: Int, group1: Int, data1: Int, group2: Int, data2: Int)] = [
        (10, 1, 16, 0, 0), (16, 1, 28, 0, 0), (26, 1, 44, 0, 0), (18, 2, 32, 0, 0),
        (24, 2, 43, 0, 0), (16, 4, 27, 0, 0), (18, 4, 31, 0, 0), (22, 2, 38, 2, 39),
        (22, 3, 36, 2, 37), (26, 4, 43, 1, 44), (30, 1, 50, 4, 51), (22, 6, 36, 2, 37),
        (22, 8, 37, 1, 38), (24, 4, 40, 5, 41), (24, 5, 41, 5, 42), (28, 7, 45, 3, 46),
        (28, 10, 46, 1, 47), (26, 9, 43, 4, 44), (26, 3, 44, 11, 45), (26, 3, 41, 13, 42),
        (26, 17, 42, 0, 0), (28, 17, 46, 0, 0), (28, 4, 47, 14, 48), (28, 6, 45, 14, 46),
        (28, 8, 47, 13, 48), (28, 19, 46, 4, 47), (28, 22, 45, 3, 46), (28, 3, 45, 23, 46),
        (28, 21, 45, 7, 46), (28, 19, 47, 10, 48), (28, 2, 46, 29, 47), (28, 10, 46, 23, 47),
        (28, 14, 46, 21, 47), (28, 14, 46, 23, 47), (28, 12, 47, 26, 48), (28, 6, 47, 34, 48),
        (28, 29, 46, 14, 47), (28, 13, 46, 32, 47), (28, 40, 47, 7, 48), (28, 18, 47, 31, 48)
    ]

    /// Row/column centres of the alignment patterns per version. Annex E.
    private static let alignmentCentres: [[Int]] = [
        [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42],
        [6, 26, 46], [6, 28, 50], [6, 30, 54], [6, 32, 58], [6, 34, 62], [6, 26, 46, 66],
        [6, 26, 48, 70], [6, 26, 50, 74], [6, 30, 54, 78], [6, 30, 56, 82], [6, 30, 58, 86],
        [6, 34, 62, 90], [6, 28, 50, 72, 94], [6, 26, 50, 74, 98], [6, 30, 54, 78, 102],
        [6, 28, 54, 80, 106], [6, 32, 58, 84, 110], [6, 30, 58, 86, 114], [6, 34, 62, 90, 118],
        [6, 26, 50, 74, 98, 122], [6, 30, 54, 78, 102, 126], [6, 26, 52, 78, 104, 130],
        [6, 30, 56, 82, 108, 134], [6, 34, 60, 86, 112, 138], [6, 30, 58, 86, 114, 142],
        [6, 34, 62, 90, 118, 146], [6, 30, 54, 78, 102, 126, 150], [6, 24, 50, 76, 102, 128, 154],
        [6, 28, 54, 80, 106, 132, 158], [6, 32, 58, 84, 110, 136, 162],
        [6, 26, 54, 82, 110, 138, 166], [6, 30, 58, 86, 114, 142, 170]
    ]

    static func encode(_ bytes: [UInt8]) -> QRCodeMatrix? {
        guard let version = version(forByteCount: bytes.count) else { return nil }
        let codewords = interleaved(dataAndErrorCorrectionFor: bytes, version: version)
        let side = version * 4 + 17

        var modules = [Bool](repeating: false, count: side * side)
        var reserved = [Bool](repeating: false, count: side * side)
        placeFunctionPatterns(&modules, &reserved, side: side, version: version)
        placeData(codewords, in: &modules, reserved: reserved, side: side)

        // Every mask is scored and the least penalised one kept, which is what
        // keeps a code readable rather than merely valid.
        var best: (mask: Int, modules: [Bool], penalty: Int)?
        for mask in 0..<8 {
            var candidate = modules
            applyMask(mask, to: &candidate, reserved: reserved, side: side)
            placeFormatInformation(mask: mask, in: &candidate, side: side)
            if version >= 7 { placeVersionInformation(version, in: &candidate, side: side) }
            let penalty = self.penalty(of: candidate, side: side)
            if best == nil || penalty < best!.penalty { best = (mask, candidate, penalty) }
        }
        guard let chosen = best else { return nil }

        let quiet = QRCodeMatrix.quietZone
        let size = side + quiet * 2
        var padded = [Bool](repeating: false, count: size * size)
        for y in 0..<side {
            for x in 0..<side {
                padded[(y + quiet) * size + (x + quiet)] = chosen.modules[y * side + x]
            }
        }
        return QRCodeMatrix(size: size, version: version, dark: padded)
    }

    // MARK: Data

    private static func dataCodewordCount(version: Int) -> Int {
        let block = blocks[version - 1]
        return block.group1 * block.data1 + block.group2 * block.data2
    }

    private static func characterCountBits(version: Int) -> Int {
        version < 10 ? 8 : 16
    }

    private static func version(forByteCount count: Int) -> Int? {
        (1...40).first { version in
            let bits = 4 + characterCountBits(version: version) + count * 8
            return bits <= dataCodewordCount(version: version) * 8
        }
    }

    private static func dataCodewords(_ bytes: [UInt8], version: Int) -> [UInt8] {
        var bits = BitBuffer()
        bits.append(0b0100, bits: 4)                                   // byte mode
        bits.append(bytes.count, bits: characterCountBits(version: version))
        for byte in bytes { bits.append(Int(byte), bits: 8) }

        let capacity = dataCodewordCount(version: version) * 8
        bits.append(0, bits: min(4, capacity - bits.count))            // terminator
        bits.padToByteBoundary()

        var codewords = bits.bytes
        // 0xEC / 0x11 alternating, as the specification prescribes.
        let padding: [UInt8] = [0xEC, 0x11]
        var index = 0
        while codewords.count < dataCodewordCount(version: version) {
            codewords.append(padding[index % 2])
            index += 1
        }
        return codewords
    }

    private static func interleaved(dataAndErrorCorrectionFor bytes: [UInt8], version: Int) -> [UInt8] {
        let block = blocks[version - 1]
        let data = dataCodewords(bytes, version: version)

        var dataBlocks: [[UInt8]] = []
        var offset = 0
        for _ in 0..<block.group1 {
            dataBlocks.append(Array(data[offset..<(offset + block.data1)]))
            offset += block.data1
        }
        for _ in 0..<block.group2 {
            dataBlocks.append(Array(data[offset..<(offset + block.data2)]))
            offset += block.data2
        }
        let errorBlocks = dataBlocks.map {
            ReedSolomon.errorCorrection(for: $0, count: block.ecCodewords)
        }

        var result: [UInt8] = []
        let longestData = dataBlocks.map(\.count).max() ?? 0
        for index in 0..<longestData {
            for dataBlock in dataBlocks where index < dataBlock.count {
                result.append(dataBlock[index])
            }
        }
        for index in 0..<block.ecCodewords {
            for errorBlock in errorBlocks {
                result.append(errorBlock[index])
            }
        }
        return result
    }

    // MARK: Layout

    private static func placeFunctionPatterns(
        _ modules: inout [Bool],
        _ reserved: inout [Bool],
        side: Int,
        version: Int
    ) {
        func set(_ x: Int, _ y: Int, _ dark: Bool) {
            guard x >= 0, x < side, y >= 0, y < side else { return }
            modules[y * side + x] = dark
            reserved[y * side + x] = true
        }

        func finder(atX x: Int, y: Int) {
            for dy in -1...7 {
                for dx in -1...7 {
                    let onRing = (dx == 0 || dx == 6) && (-1...7).contains(dy) && (0...6).contains(dy)
                    let onColumn = (dy == 0 || dy == 6) && (0...6).contains(dx)
                    let inCore = (2...4).contains(dx) && (2...4).contains(dy)
                    let inside = (0...6).contains(dx) && (0...6).contains(dy)
                    set(x + dx, y + dy, inside && (onRing || onColumn || inCore))
                }
            }
        }

        finder(atX: 0, y: 0)
        finder(atX: side - 7, y: 0)
        finder(atX: 0, y: side - 7)

        // Timing patterns.
        for index in 8..<(side - 8) {
            set(index, 6, index % 2 == 0)
            set(6, index, index % 2 == 0)
        }

        // Alignment patterns, which never overlap a finder.
        let centres = alignmentCentres[version - 1]
        for row in centres {
            for column in centres {
                let nearFinder = (row <= 8 && column <= 8)
                    || (row <= 8 && column >= side - 9)
                    || (row >= side - 9 && column <= 8)
                guard !nearFinder else { continue }
                for dy in -2...2 {
                    for dx in -2...2 {
                        let isDark = max(abs(dx), abs(dy)) != 1
                        set(column + dx, row + dy, isDark)
                    }
                }
            }
        }

        // The single module that is always dark.
        set(8, side - 8, true)

        // Format information areas, filled in once a mask is chosen.
        for index in 0...8 where index != 6 {
            reserved[8 * side + index] = true
            reserved[index * side + 8] = true
        }
        for index in 0..<8 {
            reserved[8 * side + (side - 1 - index)] = true
            reserved[(side - 1 - index) * side + 8] = true
        }
        if version >= 7 {
            for index in 0..<18 {
                let row = index / 3
                let column = index % 3
                reserved[row * side + (side - 11 + column)] = true
                reserved[(side - 11 + column) * side + row] = true
            }
        }
    }

    private static func placeData(
        _ codewords: [UInt8],
        in modules: inout [Bool],
        reserved: [Bool],
        side: Int
    ) {
        var bitIndex = 0
        var column = side - 1
        var upward = true
        while column > 0 {
            if column == 6 { column -= 1 }               // the vertical timing pattern
            for step in 0..<side {
                let row = upward ? side - 1 - step : step
                for offset in 0..<2 {
                    let x = column - offset
                    guard !reserved[row * side + x] else { continue }
                    let byte = bitIndex / 8
                    let bit = 7 - (bitIndex % 8)
                    if byte < codewords.count {
                        modules[row * side + x] = (codewords[byte] >> bit) & 1 == 1
                    }
                    bitIndex += 1
                }
            }
            column -= 2
            upward.toggle()
        }
    }

    private static func applyMask(_ mask: Int, to modules: inout [Bool], reserved: [Bool], side: Int) {
        for row in 0..<side {
            for column in 0..<side where !reserved[row * side + column] {
                let flip: Bool
                switch mask {
                case 0: flip = (row + column) % 2 == 0
                case 1: flip = row % 2 == 0
                case 2: flip = column % 3 == 0
                case 3: flip = (row + column) % 3 == 0
                case 4: flip = (row / 2 + column / 3) % 2 == 0
                case 5: flip = (row * column) % 2 + (row * column) % 3 == 0
                case 6: flip = ((row * column) % 2 + (row * column) % 3) % 2 == 0
                default: flip = ((row + column) % 2 + (row * column) % 3) % 2 == 0
                }
                if flip { modules[row * side + column].toggle() }
            }
        }
    }

    private static func placeFormatInformation(mask: Int, in modules: inout [Bool], side: Int) {
        // Level M is 0b00; the 5 data bits carry BCH(15, 5) parity and are
        // then XORed with the pattern the specification fixes.
        let data = (0b00 << 3) | mask
        var value = data << 10
        for _ in 0..<5 where value >= 1 << 10 {
            value ^= 0b10100110111 << (bitLength(value) - 11)
        }
        let format = ((data << 10) | value) ^ 0b101010000010010

        for index in 0..<15 {
            let bit = (format >> index) & 1 == 1
            // Copy one: around the top-left finder.
            if index < 6 {
                modules[index * side + 8] = bit
            } else if index == 6 {
                modules[7 * side + 8] = bit
            } else if index == 7 {
                modules[8 * side + 8] = bit
            } else if index == 8 {
                modules[8 * side + 7] = bit
            } else {
                modules[8 * side + (14 - index)] = bit
            }
            // Copy two: split between the other two finders.
            if index < 8 {
                modules[8 * side + (side - 1 - index)] = bit
            } else {
                modules[(side - 15 + index) * side + 8] = bit
            }
        }
    }

    private static func placeVersionInformation(_ version: Int, in modules: inout [Bool], side: Int) {
        var value = version << 12
        for _ in 0..<6 where value >= 1 << 12 {
            value ^= 0b1111100100101 << (bitLength(value) - 13)
        }
        let information = (version << 12) | value

        for index in 0..<18 {
            let bit = (information >> index) & 1 == 1
            let row = index / 3
            let column = index % 3
            modules[row * side + (side - 11 + column)] = bit
            modules[(side - 11 + column) * side + row] = bit
        }
    }

    private static func bitLength(_ value: Int) -> Int {
        Int.bitWidth - value.leadingZeroBitCount
    }

    // MARK: Masking penalties

    private static func penalty(of modules: [Bool], side: Int) -> Int {
        func isDark(_ row: Int, _ column: Int) -> Bool {
            modules[row * side + column]
        }

        var total = 0

        // Rule 1: runs of five or more of the same colour.
        for line in 0..<side {
            for horizontal in [true, false] {
                var runColour = false
                var runLength = 0
                for index in 0..<side {
                    let dark = horizontal ? isDark(line, index) : isDark(index, line)
                    if dark == runColour {
                        runLength += 1
                    } else {
                        runColour = dark
                        runLength = 1
                    }
                    if runLength == 5 { total += 3 }
                    else if runLength > 5 { total += 1 }
                }
            }
        }

        // Rule 2: 2 x 2 blocks of one colour.
        for row in 0..<(side - 1) {
            for column in 0..<(side - 1) {
                let first = isDark(row, column)
                if first == isDark(row, column + 1),
                   first == isDark(row + 1, column),
                   first == isDark(row + 1, column + 1) {
                    total += 3
                }
            }
        }

        // Rule 3: the 1:1:3:1:1 finder-like pattern with four light modules
        // on either side.
        let pattern: [Bool] = [true, false, true, true, true, false, true]
        let light = [Bool](repeating: false, count: 4)
        for line in 0..<side {
            var row: [Bool] = []
            var column: [Bool] = []
            for index in 0..<side {
                row.append(isDark(line, index))
                column.append(isDark(index, line))
            }
            for sequence in [row, column] {
                for start in 0...(side - 7) where Array(sequence[start..<(start + 7)]) == pattern {
                    let leading = start >= 4 ? Array(sequence[(start - 4)..<start]) : nil
                    let trailing = start + 11 <= side ? Array(sequence[(start + 7)..<(start + 11)]) : nil
                    if leading == light || trailing == light { total += 40 }
                }
            }
        }

        // Rule 4: the balance of dark and light over the whole symbol.
        let darkCount = modules.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        let percentage = darkCount * 100 / modules.count
        let deviation = abs(percentage - 50) / 5
        total += deviation * 10

        return total
    }
}

// MARK: - Arithmetic

/// Reed-Solomon over GF(256) with the primitive polynomial the QR
/// specification fixes, which is all the error correction needs.
private enum ReedSolomon {
    private static let tables: (exponent: [UInt8], logarithm: [Int]) = {
        var exponent = [UInt8](repeating: 0, count: 512)
        var logarithm = [Int](repeating: 0, count: 256)
        var value = 1
        for power in 0..<255 {
            exponent[power] = UInt8(value)
            logarithm[value] = power
            value <<= 1
            if value & 0x100 != 0 { value ^= 0x11D }
        }
        for power in 255..<512 { exponent[power] = exponent[power - 255] }
        return (exponent, logarithm)
    }()

    private static func multiply(_ left: UInt8, _ right: UInt8) -> UInt8 {
        guard left != 0, right != 0 else { return 0 }
        return tables.exponent[tables.logarithm[Int(left)] + tables.logarithm[Int(right)]]
    }

    private static func generator(degree: Int) -> [UInt8] {
        var polynomial: [UInt8] = [1]
        for power in 0..<degree {
            var next = [UInt8](repeating: 0, count: polynomial.count + 1)
            for (index, coefficient) in polynomial.enumerated() {
                // Multiplying by (x + α^power): the shift by one degree, then
                // the constant term.
                next[index] ^= coefficient
                next[index + 1] ^= multiply(coefficient, tables.exponent[power])
            }
            polynomial = next
        }
        return polynomial
    }

    static func errorCorrection(for data: [UInt8], count: Int) -> [UInt8] {
        let polynomial = generator(degree: count)
        var remainder = data + [UInt8](repeating: 0, count: count)
        for index in 0..<data.count {
            let factor = remainder[index]
            guard factor != 0 else { continue }
            for (offset, coefficient) in polynomial.enumerated() {
                remainder[index + offset] ^= multiply(coefficient, factor)
            }
        }
        return Array(remainder.suffix(count))
    }
}

private struct BitBuffer {
    private(set) var bytes: [UInt8] = []
    private(set) var count = 0

    mutating func append(_ value: Int, bits: Int) {
        guard bits > 0 else { return }
        for position in stride(from: bits - 1, through: 0, by: -1) {
            if count % 8 == 0 { bytes.append(0) }
            if (value >> position) & 1 == 1 {
                bytes[count / 8] |= 1 << (7 - (count % 8))
            }
            count += 1
        }
    }

    mutating func padToByteBoundary() {
        while count % 8 != 0 { append(0, bits: 1) }
    }
}
