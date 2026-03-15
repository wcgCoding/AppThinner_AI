//
//  ListArrayKind.swift
//
//
//  Created by p-x9 on 2024/11/01
//
//

import Foundation

// https://github.com/apple-oss-distributions/objc4/blob/89543e2c0f67d38ca5211cea33f42c51500287d5/runtime/objc-runtime-new.h#L2014
// PointerUnion4
enum ListArrayKind: Int {
    case single
    case array
    case relative
    case _dummy
}

protocol ListArray {
    associatedtype List

    var listArrayKind: ListArrayKind { get }
    func lists(in machO: MachOImage)
}
