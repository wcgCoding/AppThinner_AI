//
//  MachOFile+MethodList.swift
//
//
//  Created by p-x9 on 2024/05/23
//  
//

import Foundation
import MachOKit

extension MachOFile {
    public struct ObjCMethodLists: Sequence {
        public let data: Data
        public let offset: Int
        public let align: Int // 2^align
        public let is64Bit: Bool

        public func makeIterator() -> Iterator {
            .init(
                data: data,
                offset: offset,
                align: align,
                is64Bit: is64Bit
            )
        }
    }
}

extension MachOFile.ObjCMethodLists {
    public struct Iterator: IteratorProtocol {
        public typealias Element = ObjCMethodList

        private let tableStartOffset: Int
        private let data: Data
        private let align: Int
        private let is64Bit: Bool

        private var nextOffset: Int = 0

        init(
            data: Data,
            offset: Int,
            align: Int,
            is64Bit: Bool
        ) {
            self.data = data
            self.tableStartOffset = offset
            self.align = align
            self.is64Bit = is64Bit
        }

        public mutating func next() -> Element? {
            guard nextOffset < data.count else {
                return nil
            }
            let data = data.advanced(by: nextOffset)

            guard let header: Element.Header = data.withUnsafeBytes({
                guard let baseAddress = $0.baseAddress else {
                    return nil
                }
                return baseAddress
                    .assumingMemoryBound(to: Element.Header.self)
                    .pointee
            }) else { return nil }
            let listSize = Element.size(for: header)

            guard nextOffset + listSize <= data.count else {
                return nil
            }

            guard let list: Element = data.withUnsafeBytes({
                guard let ptr = $0.baseAddress else {
                    return nil
                }
                return Element(
                    ptr: ptr,
                    offset: tableStartOffset + nextOffset,
                    is64Bit: is64Bit
                )
            }) else { return nil }

            guard list.isValidEntrySize(is64Bit: is64Bit) else {
                preconditionFailure()
            }

            defer {
                nextOffset += list.size
                nextOffset += nextOffset % numericCast(power(2, align))
            }

            return list
        }
    }
}
