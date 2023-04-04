
import Foundation
import MachO

@_cdecl("swift_ctor")
public func ctor() {
        
    let blacklist = [
        "webkit",
        "webcontent",
        "apt",
        "dpkg",
        "mterminal",
        "icloud",
        "sh"
    ]
        .map {
            ProcessInfo.processInfo.processName.lowercased().contains($0)
        }
        .contains(true)
    
    if blacklist {
        NSLog("Blacklist for OldABI")
        return
    }
    
    let ekhandle = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);
    let hookFunction = unsafeBitCast(dlsym(ekhandle, "MSHookMemory"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, size_t) -> Void).self);
    
    for image in 0..<_dyld_image_count() {
        if String(cString: _dyld_get_image_name(image)) == "/usr/lib/libobjc.A.dylib" ||
            String(cString: _dyld_get_image_name(image)) == "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation" {
            var bytes: [UInt8] = [
                0x00, 0x18, 0xC1, 0xDA
            ]
            
            var mask: [UInt8] = [
                0x00, 0xFC, 0xFF, 0xFF
            ]
            
            while true {
                let autda = patchfind_find(Int32(image), &bytes, &mask, 4)
                                
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
