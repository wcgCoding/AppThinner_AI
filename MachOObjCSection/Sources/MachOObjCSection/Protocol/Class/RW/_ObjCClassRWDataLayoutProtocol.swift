//
//  _ObjCClassRWDataLayoutProtocol.swift
//
//
//  Created by p-x9 on 2024/10/31
//  
//

import Foundation

public protocol _ObjCClassRWDataLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var flags: UInt32 { get }
    var witness: UInt16 { get }
    var index: UInt16 { get }
    var ro_or_rw_ext: Pointer { get }
    var firstSubclass: Pointer { get }
    var nextSiblingClass: Pointer { get }
}
