//
//  ObjCProtocolArrayProtocol.swift
//
//
//  Created by p-x9 on 2024/11/01
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCProtocolArrayProtocol {
    associatedtype ObjCProtocolList: ObjCProtocolListProtocol
    associatedtype ObjCProtocolRelativeListList: ObjCProtocolRelativeListListProtocol where ObjCProtocolRelativeListList.List == ObjCProtocolList

    var offset: Int { get }

    @_spi(Core)
    init(offset: Int)

    func lists(in machO: MachOImage) -> [ObjCProtocolList]
}

extension ObjCProtocolArrayProtocol {
    var kind: ListArrayKind? {
        .init(rawValue: numericCast(offset) & 3)
    }

    public func lists(in machO: MachOImage) -> [ObjCProtocolList] {
        let start = machO.ptr
            .advanced(by: offset & ~3)

        var lists: [ObjCProtocolList] = []
        switch kind {
        case .single:
            lists.append(
                ObjCProtocolList(
                    ptr: start,
                    offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr)
                )
            )
        case .array:
            let count = start
                .assumingMemoryBound(to: UInt32.self)
                .pointee
            let sequnece = MemorySequence(
                basePointer: start
                    .advanced(
                        by: machO.is64Bit ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
                    ) // `count` + align
                    .assumingMemoryBound(to: UInt64.self),
                numberOfElements: numericCast(count)
            )

            lists = sequnece
                .map {
                    let ptr = UnsafeRawPointer(bitPattern: UInt($0))!
                    return ObjCProtocolList(
                        ptr: ptr,
                        offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
                    )
                }
        case .relative:
            // Use `relativeListList(in:)`
            break
        case ._dummy, .none:
            break
        }

        return lists
    }

    public func relativeListList(in machO: MachOImage) -> ObjCProtocolRelativeListList? {
        guard kind == .relative else { return nil }
        let start = machO.ptr
            .advanced(by: offset & ~3)
        return .init(
            ptr: start,
            offset: Int(bitPattern: start) - Int(bitPattern: machO.ptr)
        )
    }
}
