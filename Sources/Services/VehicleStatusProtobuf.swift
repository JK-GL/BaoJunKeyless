import Foundation

// MARK: - Protobuf Wire Format Parser
// 手动解析 Protobuf wire format，不需要 swift-protobuf 依赖
// 只处理 VehicleStatus 用到的字段类型：varint (int64) 和 length-delimited (string)

enum ProtobufWireType: UInt8 {
    case varint = 0
    case lengthDelimited = 2
}

struct ProtobufField {
    let fieldNumber: Int
    let wireType: ProtobufWireType
    let data: Data
}

enum ProtobufDecoder {
    /// 解码所有字段（不处理嵌套消息，够用）
    static func decode(_ data: Data) -> [ProtobufField] {
        var fields: [ProtobufField] = []
        var offset = 0

        while offset < data.count {
            // 1. 读 tag (fieldNumber << 3 | wireType)
            guard let tag = readVarint(data, &offset) else { break }
            let wireType = UInt8(tag & 0x07)
            let fieldNumber = Int(tag >> 3)

            guard let type = ProtobufWireType(rawValue: wireType) else {
                // 未知 wire type，跳过
                break
            }

            switch type {
            case .varint:
                guard let value = readVarint(data, &offset) else { break }
                // 把 varint 编码回 Data 以便后续按类型解码
                var encoded = Data()
                encodeVarint(value, into: &encoded)
                fields.append(ProtobufField(fieldNumber: fieldNumber, wireType: .varint, data: encoded))

            case .lengthDelimited:
                guard let length = readVarint(data, &offset),
                      offset + Int(length) <= data.count else { break }
                let fieldData = data[offset..<(offset + Int(length))]
                fields.append(ProtobufField(fieldNumber: fieldNumber, wireType: .lengthDelimited, data: Data(fieldData)))
                offset += Int(length)
            }
        }

        return fields
    }

    // MARK: - 值提取

    static func string(_ field: ProtobufField?) -> String? {
        guard let field, field.wireType == .lengthDelimited else { return nil }
        return String(data: field.data, encoding: .utf8)
    }

    static func int64(_ field: ProtobufField?) -> Int64? {
        guard let field, field.wireType == .varint else { return nil }
        return Int64(bitPattern: readVarintFromData(field.data) ?? 0)
    }

    // MARK: - 内部

    private static func readVarint(_ data: Data, _ offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    private static func readVarintFromData(_ data: Data) -> UInt64? {
        var offset = 0
        return readVarint(data, &offset)
    }

    private static func encodeVarint(_ value: UInt64, into data: inout Data) {
        var v = value
        while v > 0x7F {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
    }
}
