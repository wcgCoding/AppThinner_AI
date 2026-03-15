//
//  SegmentCommandProtocol+.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/12/06
//  
//

import MachOKit

extension SegmentCommandProtocol {
    func __objc_imageinfo(in machO: MachOFile) -> SectionType? {
        _section(for: "__objc_imageinfo", in: machO)
    }

    func __objc_imageinfo(in machO: MachOImage) -> SectionType? {
        _section(for: "__objc_imageinfo", in: machO)
    }

    func __objc_methlist(in machO: MachOFile) -> SectionType? {
        _section(for: "__objc_methlist", in: machO)
    }

    func __objc_methlist(in machO: MachOImage) -> SectionType? {
        _section(for: "__objc_methlist", in: machO)
    }

    func __objc_protolist(in machO: MachOFile) -> SectionType? {
        _section(for: "__objc_protolist", in: machO)
    }

    func __objc_protolist(in machO: MachOImage) -> SectionType? {
        _section(for: "__objc_protolist", in: machO)
    }

    func __objc_classlist(in machO: MachOFile) -> SectionType? {
        _section(for: "__objc_classlist", in: machO)
    }

    func __objc_classlist(in machO: MachOImage) -> SectionType? {
        _section(for: "__objc_classlist", in: machO)
    }

    func __objc_catlist(in machO: MachOFile) -> SectionType? {
        _section(for: "__objc_catlist", in: machO)
    }

    func __objc_catlist(in machO: MachOImage) -> SectionType? {
        _section(for: "__objc_catlist", in: machO)
    }

    func __objc_catlist2(in machO: MachOFile) -> SectionType? {
        _section(for: "__objc_catlist2", in: machO)
    }

    func __objc_catlist2(in machO: MachOImage) -> SectionType? {
        _section(for: "__objc_catlist2", in: machO)
    }
}

extension SegmentCommandProtocol {
    func _section(for name: String, in machO: MachOFile) -> SectionType? {
        sections(in: machO).first(
            where: {
                $0.sectionName == name
            }
        )
    }

    func _section(for name: String, in machO: MachOImage) -> SectionType? {
        sections(cmdsStart: machO.cmdsStartPtr).first(
            where: {
                $0.sectionName == name
            }
        )
    }
}
