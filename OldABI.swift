
import Foundation
import MachO

typealias FileHandleC = UnsafeMutablePointer<FILE>
extension FileHandleC {
    @inline(__always)
    func readData(ofLength count: Int) -> UnsafeMutableRawPointer {
        let alloc = malloc(count)
        fread(alloc, 1, count, self)
        return alloc!
    }
    
    @discardableResult @inline(__always)
    func seek(toFileOffset offset: UInt64) -> UnsafeMutablePointer<FILE> {
        var pos: fpos_t = .init(offset)
        fsetpos(self, &pos)
        return self
    }
    
    @inline(__always)
    var offsetInFile: UInt64 {
        var pos: fpos_t = 0
        fgetpos(self, &pos)
        return .init(pos)
    }
    
    @inline(__always)
    func close() {
        fclose(self)
    }
}

let ekhandle = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);

let hookMemory = {
    unsafeBitCast(dlsym(ekhandle, "MSHookMemory"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, size_t) -> Void).self)
}()

let hookFunction = {
    unsafeBitCast(dlsym(ekhandle, "MSHookFunction"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void).self)
}()

func oneshot_fix_oldabi() {
    
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
                    
                    NSLog("Found patch location")
                    
                    hookMemory(autda, [
                        CFSwapInt32(0xF047C1DA) // xpacd x16
                    ], 4)
                } else {
                    break
                }
            }
        }
    }
}

func looksLegacy(_ path: UnsafePointer<CChar>) -> Bool {
    guard let handle = fopen(path, "r") else {
        print("Failed to open destination file")
        return false
    }
    
    defer { handle.close() }
    
    let machHeaderPointer = handle
        .readData(ofLength: MemoryLayout<mach_header_64>.size)
    
    defer { machHeaderPointer.deallocate() }
    
    if machHeaderPointer.assumingMemoryBound(to: mach_header_64.self).pointee.magic == FAT_CIGAM {
        // we have a fat binary
        // get our current cpu subtype
        let nslices = handle
            .seek(toFileOffset: 0x4)
            .readData(ofLength: MemoryLayout<UInt32>.size)
            .assumingMemoryBound(to: UInt32.self)
            .pointee.bigEndian
                        
        for i in 0..<nslices {
            let slice_ptr = handle
                .seek(toFileOffset: UInt64(8 + (Int(i) * 20)))
                .readData(ofLength: MemoryLayout<fat_arch>.size)
                .assumingMemoryBound(to: fat_arch.self)
            
            let slice = slice_ptr.pointee
            
            defer { slice_ptr.deallocate() }
            
            if slice.cputype.bigEndian == CPU_TYPE_ARM64 {
                                            
                let slice_ptr = handle
                    .seek(toFileOffset: UInt64(8 + (Int(i) * 20)))
                    .readData(ofLength: MemoryLayout<fat_arch>.size)
                    .assumingMemoryBound(to: fat_arch.self)
                
                let slice = slice_ptr.pointee
                
                defer { slice_ptr.deallocate() }
                                
                if slice.cpusubtype == 0x2000080 { // new abi
                    return false
                }
                
                if slice.cpusubtype == 0x2000000 { // old abi
                    return true
                }
            }
        }
    }
    
    return false
}

typealias dlopen_body = @convention(c) (UnsafePointer<CChar>, Int32) -> UnsafeRawPointer

let orig: UnsafeMutablePointer<UnsafeMutableRawPointer?> = .allocate(capacity: 8)

@_cdecl("dlopen_hook")
func dlopen_hook(_ path: UnsafePointer<CChar>, _ loadtype: Int32) -> UnsafeRawPointer {
    if looksLegacy(path) {
        NSLog("looks legacy to me!")
        oneshot_fix_oldabi()
    }
        
    return unsafeBitCast(orig.pointee, to: dlopen_body.self)(path, loadtype)
}

@_cdecl("swift_ctor")
public func ctor() {
    
    let blacklist = [
        "webkit",
        "webcontent",
        "apt",
        "dpkg",
        "mterminal",
        "cloud",
        "druid",
        "dasd",
        "sshd",
        "zsh",
        "jailbreakd"
    ]
        .map {
            ProcessInfo.processInfo.processName.lowercased().contains($0)
        }
        .contains(true)
    
    guard !blacklist else {
        return
    }
    
    let repcl: @convention(c) (UnsafePointer<CChar>, Int32) -> UnsafeRawPointer = dlopen_hook
    let repptr = unsafeBitCast(repcl, to: UnsafeMutableRawPointer.self)
    
    hookFunction(dlsym(dlopen(nil, RTLD_NOW), "dlopen"), repptr, orig)
}
