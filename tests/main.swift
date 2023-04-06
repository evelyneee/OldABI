
import Foundation
import MachO

let ekhandle = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_NOW);

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

let hookMemory = {
    unsafeBitCast(dlsym(ekhandle, "MSHookMemory"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, size_t) -> Void).self)
}()

let hookFunction = {
    unsafeBitCast(dlsym(ekhandle, "MSHookFunction"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void).self)
}()

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

print("RESULT:", looksLegacy("/Users/charlotte/Downloads/oldABI.dylib") == true)

print("RESULT:", looksLegacy("/Users/charlotte/Downloads/newABI.dylib") == false)

print("ATRIA:", looksLegacy("/Users/charlotte/Downloads/me.lau.atria_1.3-1.3_iphoneos-arm64/var/jb/Library/MobileSubstrate/DynamicLibraries/Atria.dylib") == true)
