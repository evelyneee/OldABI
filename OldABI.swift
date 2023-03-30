
import Foundation
import MachO

@_cdecl("swift_ctor")
public func ctor() {
    let ekhandle = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
    let hookFunction = unsafeBitCast(dlsym(ekhandle, "MSHookMemory"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, size_t) -> Void).self);
    for image in 0..<_dyld_image_count() {
        if String(cString: _dyld_get_image_name(image)) == "/usr/lib/libobjc.A.dylib" ||
            String(cString: _dyld_get_image_name(image)) == "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation" {
            let bytes: [[UInt8]] = [
                [
                    0x30, 0x1A, 0xC1, 0xDA // autda x16, x17 (most calls)
                ],
                [
                    0x90, 0x1B, 0xC1, 0xDA // autda x16, x28
                ],
                [
                    0x50, 0x19, 0xC1, 0xDA // autda x16, x10 (objc_msgSend...)
                ]
            ]
            
            for byteArray in bytes {
                while true {
                    var byteArray = byteArray
                    let autda = patchfind_find(Int32(image), &byteArray, nil, 4)
                    if let autda {
                        hookFunction(autda, [
                            CFSwapInt32(0xF047C1DA) // xpacd x16
                        ], 4)
                    } else {
                        break
                    }
                }
            }
        }
    }
}
