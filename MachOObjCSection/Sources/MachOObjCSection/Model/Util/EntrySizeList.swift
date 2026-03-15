//
//  EntrySizeList.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2025/01/26
//  
//

import Foundation
@_spi(Support) import MachOKit

// https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L707
public struct EntrySizeListHeader: LayoutWrapper {
    public struct Layout {
        public let entsizeAndFlags: UInt32
        public let count: UInt32
    }
    public var layout: Layout
}

public protocol EntrySizeListProtocol {
    associatedtype Entry

    typealias Header = EntrySizeListHeader

    static var flagMask: UInt32 { get }

    var offset: Int { get }
    var header: EntrySizeListHeader { get }
}

extension EntrySizeListProtocol {
    public var entrySize: Int {
        numericCast(header.entsizeAndFlags & ~Self.flagMask)
    }

    public var _flags: UInt32 {
        numericCast(header.entsizeAndFlags & Self.flagMask)
    }

    public var count: Int { numericCast(header.count) }
}

extension EntrySizeListProtocol {
    public static func size(for header: Header) -> Int {
        let entrySize: Int = numericCast(header.entsizeAndFlags & ~Self.flagMask)
        return Header.layoutSize + entrySize * numericCast(header.count)
    }

    public var size: Int {
        Header.layoutSize + entrySize * numericCast(count)
    }
}
