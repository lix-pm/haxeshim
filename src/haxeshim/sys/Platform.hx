package haxeshim.sys;

enum abstract Platform(String) to String {
  var Linux32 = "linux32";
  var Linux64 = "linux64";
  var LinuxArm = "linux-arm";
  var LinuxArm64 = "linux-arm64";
  var LinuxRiscV = "linux-riscv";

  var Win32 = "win32";
  var Win64 = "win64";

  var Mac64 = "mac64";
  var MacArm = "mac-arm";
  var MacUniversal = "mac-universal";
  
  var Unknown = "unknown";

  public var isWindows(get, never):Bool;
    inline function get_isWindows() return this.startsWith("win");

  public var isLinux(get, never):Bool;
    inline function get_isLinux() return this.startsWith("linux");

  public var isMac(get, never):Bool;
    inline function get_isMac() return this.startsWith("mac");

  static inline var MACHO_32     = 0xFEEDFACE;
  static inline var MACHO_64     = 0xFEEDFACF;
  static inline var MACHO_32_REV = 0xCEFAEDFE;
  static inline var MACHO_64_REV = 0xCFFAEDFE;
  static inline var FAT          = 0xCAFEBABE;
  static inline var FAT_REV      = 0xBEBAFECA;

  static public function detect(binary:haxe.io.Bytes):Platform {
    final b = binary;

    if (b.length >= 5 && b.get(0) == 0x7F && b.get(1) == 'E'.code && b.get(2) == 'L'.code && b.get(3) == 'F'.code) {

      var eiClass = b.get(4); // 1 = 32-bit, 2 = 64-bit

      // e_machine is at offset 18 (0x12), little endian
      var eMachine = b.get(18) | (b.get(19) << 8);

      return switch (eMachine) {
        case 3:   eiClass == 1 ? Linux32 : Linux64;    // EM_386
        case 62:  Linux64;                             // EM_X86_64
        case 40:  LinuxArm;                            // EM_ARM
        case 183: LinuxArm64;                          // EM_AARCH64
        case 243: LinuxRiscV;                          // EM_RISCV
        default:  eiClass == 1 ? Linux32 : Linux64;
      }
    }

    if (b.length >= 0x40) {
      var peOffset = b.getInt32(0x3C);

      inline function next() return b.get(peOffset++);
      inline function expect(byte) return next() == byte;

      if (expect('P'.code) && expect('E'.code) && expect(0) && expect(0)) {

        // Machine field at PE + 4, little endian
        var machine = next() | (next() << 8);

        return switch (machine) {
          case 0x014C: Win32;   // x86
          case 0x8664: Win64;   // x86_64
          default:     Unknown;
        }
      }
    }

    if (b.length >= 4) {
      // Big-endian read:
      var magic = (b.get(0) << 24) | (b.get(1) << 16) | (b.get(2) << 8) | b.get(3);

      // Thin binaries
      if (magic == MACHO_64 || magic == MACHO_64_REV) 
        return switch (b.get(4) << 24) | (b.get(5) << 16) | (b.get(6) << 8) | b.get(7) {
          case 0x01000007: Mac64;  
          case 0x0100000C: MacArm;
          default: Mac64;
        }                    

      if (magic == MACHO_32 || magic == MACHO_32_REV) return Mac64;

      // Universal / Fat
      if (magic == FAT || magic == FAT_REV) return MacUniversal;
    }

    return Unknown;
  }
}