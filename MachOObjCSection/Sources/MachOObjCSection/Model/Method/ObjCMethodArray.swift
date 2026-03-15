//
//  ObjCMethodArray.swift
//
//
//  Created by p-x9 on 2024/11/01
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCMethodArray {
    public let offset: Int
    public let is64Bit: Bool
}

extension ObjCMethodArray {
    var kind: ListArrayKind? {
        .init(rawValue: numericCast(offset) & 3)
    }

    public func lists(in machO: MachOImage) -> [ObjCMethodList] {
        let start = machO.ptr
            .advanced(by: offset & ~3)

        var lists: [ObjCMethodList] = []
        switch kind {
        case .single:
            lists.append(
                ObjCMethodList(
                    ptr: start,
                    offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr),
                    is64Bit: machO.is64Bit
                )
            )
        case .array:
            var currentOffset: Int = 0
            let count = start
                .assumingMemoryBound(to: UInt32.self)
                .pointee
            for _ in 0 ..< Int(count) {
                let address = start
                    .advanced(
                        by: machO.is64Bit ? MemoryLayout<UInt64>.size : 0
                    ) // `count` + align
                    .advanced(by: currentOffset)
                    .assumingMemoryBound(to: UInt.self)
                    .pointee
                guard let ptr = UnsafeRawPointer(bitPattern: address) else {
                    currentOffset += MemoryLayout<UInt>.size
                    continue
                }
                let list = ObjCMethodList(
                    ptr: ptr,
                    offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr),
                    is64Bit: machO.is64Bit
                )
                lists.append(list)
                currentOffset += MemoryLayout<UInt>.size
            }
        case .relative:
            // Use `relativeListList(in:)`
            break
        case ._dummy, .none:
            break
        }

        return lists
    }

    public func relativeListList(in machO: MachOImage) -> ObjCMethodRelativeListList? {
        guard kind == .relative else { return nil }
        let start = machO.ptr
            .advanced(by: offset & ~3)
        return .init(
            ptr: start,
            offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr)
        )
    }
}
