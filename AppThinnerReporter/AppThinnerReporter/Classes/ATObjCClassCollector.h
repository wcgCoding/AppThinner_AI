//
//  ATObjCClassCollector.h
//  AppThinnerReporter
//
//  从已加载 Mach-O 镜像中采集全量 OC 类，并判断是否已 Realized（+initialize 已触发）。
//  参考 doc/UnuseClassDetector 中 JXRealizeCalss 思路，支持多 image 遍历。
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 类是否已在运行时 Realized（metaClass flags & RW_REALIZED）
bool at_objc_isClassRealized(Class cls);

/// 当前进程已加载镜像中的全量 OC 类数量（去重、按类名排序后的数量需另算）
int at_objc_allClassCount(void);

int at_objc_getRealizedClasses(Class *buffer, int bufferLen);

/// 将全量 OC 类写入 buffer，返回写入数量。建议先 at_objc_allClassCount 再分配 buffer。
/// 类顺序为各镜像 __objc_classlist 顺序的并集，未排序；调用方若需稳定顺序请按类名排序。
int at_objc_getAllClasses(Class * _Nullable buffer, int bufferLen);

/// 按类名字典序比较，用于 qsort。保证与看板端解析顺序一致。
int at_compareClassesByName(const void *a, const void *b);

#ifdef __cplusplus
}
#endif
