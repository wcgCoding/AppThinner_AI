//
//  _ObjCStubClassLayoutProtocol.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/18
//  
//

import Foundation

// ref: https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L2714
public protocol _ObjCStubClassLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger

    var isa: Pointer { get }
    var initializer: Pointer { get }
}

public enum ObjCStubClassLayoutField {
    case isa
    case initializer
}
