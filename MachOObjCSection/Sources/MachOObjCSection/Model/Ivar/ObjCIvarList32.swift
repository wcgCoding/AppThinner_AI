//
//  ObjCIvarList32.swift
//
//
//  Created by p-x9 on 2024/08/25
//  
//

import Foundation
@_spi(Support) import MachOKit

public struct ObjCIvarList32: ObjCIvarListProtocol {
    public typealias ObjCIvar = ObjCIvar32
    public typealias Entry = ObjCIvar

    /// Offset from machO header start
    public let offset: Int
    public let header: Header

    @_spi(Core)
    public init(
        header: Header,
        offset: Int
    ) {
        self.header = header
        self.offset = offset
    }
}

extension ObjCIvarList32 {
    public func ivars(in machO: MachOFile) -> [ObjCIvar]? {
        guard let (fileHandle, fileOffset) = machO.fileHandleAndOffset(forOffset: numericCast(offset)) else {
            return []
        }

        let size = MemoryLayout<ObjCIvar.Layout>.size
        let sequence: DataSequence<ObjCIvar.Layout> = fileHandle
            .readDataSequence(
                offset: fileOffset + numericCast(MemoryLayout<Header>.size),
                numberOfElements: count
            )
        return sequence.enumerated()
            .map {
                .init(
                    layout: $1,
                    offset: offset + MemoryLayout<Header>.size + size * $0
                )
            }
    }
}
