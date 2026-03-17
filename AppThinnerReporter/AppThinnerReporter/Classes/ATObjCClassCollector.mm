//
//  ATObjCClassCollector.mm
//  AppThinnerReporter
//
//  遍历所有 dyld 已加载镜像的 __objc_classlist，采集全量类并判断 RW_REALIZED。
//

#import "ATObjCClassCollector.h"
#import <dlfcn.h>
#import <mach-o/getsect.h>
#import <mach-o/dyld.h>
#import <objc/objc.h>
#import <stdint.h>
#import <Foundation/NSObjCRuntime.h>
#import <objc/NSObject.h>
#import <objc/runtime.h>

#if __LP64__

typedef uint32_t at_mask_t;

struct at_class_rw_t {
    uint32_t flags;
};

#ifndef FAST_DATA_MASK
#define FAST_DATA_MASK        0x00007ffffffffff8UL
#endif

struct at_class_data_bits_t {
    uintptr_t bits;
    at_class_rw_t* data() {
        return (at_class_rw_t *)(bits & FAST_DATA_MASK);
    }
};

struct at_cache_t {
    void *_buckets;
    at_mask_t _mask;
    at_mask_t _occupied;
};

#ifndef RW_REALIZED
#define RW_REALIZED           (1<<31)
#endif

struct at_objc_class : objc_object {
    Class superclass;
    at_cache_t cache;
    at_class_data_bits_t bits;
    at_class_rw_t *data() {
        return bits.data();
    }
    bool isRealized() {
        return data()->flags & RW_REALIZED;
    }
};

bool at_objc_isClassRealized(Class cls) {
#if !__LP64__
    (void)cls;
    return false;
#else
    if (!cls) return false;
    at_objc_class *oc = (__bridge at_objc_class *)cls;
    return oc->isRealized();
#endif
}

const uintptr_t at_getCurSectionHeader(void)
{
    Dl_info info;
    dladdr((const void *)&at_getCurSectionHeader, &info);
    const uintptr_t mach_header = (uintptr_t)info.dli_fbase;
    return mach_header;
}

const struct section_64* at_getCurClassListSection(const uintptr_t mach_header)
{
    const struct section_64 *section = getsectbynamefromheader_64((const struct mach_header_64 *)mach_header, "__DATA", "__objc_classlist");
    if (section == NULL) {
        section = getsectbynamefromheader_64((const struct mach_header_64 *)mach_header, "__DATA_CONST", "__objc_classlist");
    }
    if (section == NULL) {
        section = getsectbynamefromheader_64((const struct mach_header_64 *)mach_header, "__DATA_DIRTY", "__objc_classlist");
    }
    
    if (section == NULL) {
        return 0;
    }
    
    return section;
}

int at_objc_allClassCount(void) {
#if !__LP64__
    return 0;
#else
    const uintptr_t mach_header = at_getCurSectionHeader();
    const struct section_64 *section = at_getCurClassListSection(mach_header);
    if (section == NULL) {
        return 0;
    }
    return (int)(section->size / sizeof(void *));
#endif
}

int at_objc_getRealizedClasses(Class *buffer, int bufferLen)
{
    const uintptr_t mach_header = at_getCurSectionHeader();
    const struct section_64 *section = at_getCurClassListSection(mach_header);
    if (section == NULL) {
        return 0;
    }
    int count = 0;
    for (uint64_t addr = section->offset; addr < section->offset + section->size; addr += sizeof(void *)) {
        Class cls = (__bridge Class)(*(void **)(mach_header + addr));
        if (at_objc_isClassRealized(cls)) {
            if (buffer && count < bufferLen) {
                buffer[count] = cls;
            }
            count ++;
        }
    }
    return count;
}

int at_objc_getAllClasses(Class * _Nullable buffer, int bufferLen) {
#if !__LP64__
    (void)buffer;
    (void)bufferLen;
    return 0;
#else
    const uintptr_t mach_header = at_getCurSectionHeader();
    const struct section_64 *section = at_getCurClassListSection(mach_header);
    if (section == NULL) {
        return 0;
    }
    int count = 0;
    for (uint64_t addr = section->offset; addr < section->offset + section->size; addr += sizeof(void *)) {
        Class cls = (__bridge Class)(*(void **)(mach_header + addr));
        if (buffer && count < bufferLen) {
            buffer[count] = cls;
        }
        count ++;
    }
    return count;
#endif
}

int at_compareClassesByName(const void *a, const void *b) {
    Class cls1 = *(Class *)a;
    Class cls2 = *(Class *)b;
    const char *n1 = class_getName(cls1);
    const char *n2 = class_getName(cls2);
    if (!n1) return n2 ? -1 : 0;
    if (!n2) return 1;
    return strcmp(n1, n2);
}
#endif // __LP64__

