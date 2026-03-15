//
//  ObjCProperty.swift
//
//
//  Created by p-x9 on 2024/05/25
//
//

import Foundation

// https://github.com/apple-oss-distributions/dyld/blob/25174f1accc4d352d9e7e6294835f9e6e9b3c7bf/common/ObjCVisitor.h#L408

// https://github.com/apple-oss-distributions/objc4/blob/01edf1705fbc3ff78a423cd21e03dfc21eb4d780/runtime/objc-runtime-new.h#L1318

public struct ObjCProperty {
    public let name: String
    public let attributes: String
}

extension ObjCProperty {
    struct Property {
        let name: UnsafePointer<CChar>
        let attributes: UnsafePointer<CChar>
    }

    init(_ property: Property) {
        self.init(
            name: .init(cString: property.name),
            attributes: .init(cString: property.attributes)
        )
    }
}

extension ObjCProperty {
    struct Property64 {
        let name: UInt64
        let attributes: UInt64
    }
}

extension ObjCProperty {
    struct Property32 {
        let name: UInt32
        let attributes: UInt32
    }
}

extension ObjCProperty {
    struct UnresolvedProperty {
        let name: UnresolvedValue
        let attributes: UnresolvedValue
    }

    struct ResolvedProperty {
        let name: ResolvedValue
        let attributes: ResolvedValue
    }
}
