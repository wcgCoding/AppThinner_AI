//
//  ATObjCClassCollector.mm
//  AppThinnerReporter
//
//  遍历所有 dyld 已加载镜像的 __objc_classlist，采集全量类并判断 RW_REALIZED。
//

#import "ATObjCClassCollector.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/getsect.h>
#import <mach-o/dyld.h>
#import <stdint.h>

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

static const struct section_64 *at_getClassListSection(const struct mach_header_64 *header) {
    const struct section_64 *sec = getsectbynamefromheader_64(header, "__DATA", "__objc_classlist");
    if (!sec) sec = getsectbynamefromheader_64(header, "__DATA_CONST", "__objc_classlist");
    if (!sec) sec = getsectbynamefromheader_64(header, "__DATA_DIRTY", "__objc_classlist");
    return sec;
}

static void at_collectClassesFromHeader(const struct mach_header_64 *header, int64_t slide,
                                        Class * _Nullable buffer, int bufferLen, int *outCount) {
    const struct section_64 *sec = at_getClassListSection(header);
    if (!sec) return;
    uint64_t addr = sec->offset;
    uint64_t end = addr + sec->size;
    uintptr_t base = (uintptr_t)header + slide;
    while (addr < end && (buffer == NULL || *outCount < bufferLen)) {
        Class cls = (__bridge Class)(*(void **)(base + addr));
        if (cls) {
            if (buffer) buffer[*outCount] = cls;
            (*outCount)++;
        }
        addr += sizeof(void *);
    }
}

int at_objc_allClassCount(void) {
#if !__LP64__
    return 0;
#else
    int n = 0;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *h = _dyld_get_image_header(i);
        if (h->magic != MH_MAGIC_64 && h->magic != MH_CIGAM_64) continue;
        const struct section_64 *sec = at_getClassListSection((const struct mach_header_64 *)h);
        if (sec) n += (int)(sec->size / sizeof(void *));
    }
    return n;
#endif
}

int at_objc_getAllClasses(Class * _Nullable buffer, int bufferLen) {
#if !__LP64__
    (void)buffer;
    (void)bufferLen;
    return 0;
#else
    int total = 0;
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const struct mach_header *h = _dyld_get_image_header(i);
        if (h->magic != MH_MAGIC_64 && h->magic != MH_CIGAM_64) continue;
        int64_t slide = _dyld_get_image_vmaddr_slide(i);
        at_collectClassesFromHeader((const struct mach_header_64 *)h, slide, buffer, bufferLen, &total);
        if (buffer && total >= bufferLen) break;
    }
    return total;
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
