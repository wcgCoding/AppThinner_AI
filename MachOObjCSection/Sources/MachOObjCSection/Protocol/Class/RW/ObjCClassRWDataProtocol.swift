//
//  ObjCClassRWDataProtocol.swift
//
//
//  Created by p-x9 on 2024/10/31
//  
//

import Foundation
@_spi(Support) import MachOKit

public protocol ObjCClassRWDataProtocol {
    associatedtype Layout: _ObjCClassRWDataLayoutProtocol
    associatedtype ObjCClassROData: ObjCClassRODataProtocol
    associatedtype ObjCClassRWDataExt: ObjCClassRWDataExtProtocol where ObjCClassRWDataExt.ObjCClassROData == ObjCClassROData

    var layout: Layout { get }
    var offset: Int { get }

    @_spi(Core)
    init(layout: Layout, offset: Int)

    func classROData(in machO: MachOImage) -> ObjCClassROData?
    func ext(in machO: MachOImage) -> ObjCClassRWDataExt?
}

extension ObjCClassRWDataProtocol {
    public var flags: ObjCClassRWDataFlags {
        .init(rawValue: layout.flags)
    }

    public var index: Int {
        numericCast(layout.index)
    }

    public var hasRO: Bool {
        layout.ro_or_rw_ext & 1 == 0
    }

    public var hasExt: Bool {
        layout.ro_or_rw_ext & 1 != 0
    }
}

extension ObjCClassRWDataProtocol {
    public func classROData(in machO: MachOImage) -> ObjCClassROData? {
        guard hasRO else { return nil }

        let address: Int = numericCast(layout.ro_or_rw_ext)
        guard let ptr = UnsafeRawPointer(bitPattern: address) else {
            return nil
        }
        let layout = ptr
            .assumingMemoryBound(to: ObjCClassROData.Layout.self)
            .pointee
        let classData = ObjCClassROData(
            layout: layout,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return classData
    }

    public func ext(in machO: MachOImage) -> ObjCClassRWDataExt? {
        guard hasExt else { return nil }

        let address: Int = numericCast(layout.ro_or_rw_ext)
        guard let ptr = UnsafeRawPointer(bitPattern: address & ~1) else {
            return nil
        }
        let layout = ptr
            .assumingMemoryBound(to: ObjCClassRWDataExt.Layout.self)
            .pointee
        let classData = ObjCClassRWDataExt(
            layout: layout,
            offset: Int(bitPattern: ptr) - Int(bitPattern: machO.ptr)
        )

        return classData
    }
}
