// Prints each fan's current speed in RPM by reading the SMC (reads need no root).
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>
typedef struct { char major, minor, build, reserved[1]; UInt16 release; } Vers;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } PLimit;
typedef struct { UInt32 dataSize, dataType; char dataAttributes; } KeyInfo;
typedef struct { UInt32 key; Vers vers; PLimit pLimitData; KeyInfo keyInfo; char result, status, data8; UInt32 data32; unsigned char bytes[32]; } SMCParam;
static io_connect_t conn;
static UInt32 k(const char *s) { return (UInt32)s[0] << 24 | (UInt32)s[1] << 16 | (UInt32)s[2] << 8 | (UInt32)s[3]; }
static int readKey(const char *key, SMCParam *out) {
  SMCParam in = {0}; size_t sz = sizeof(SMCParam);
  in.key = k(key); in.data8 = 9;
  if (IOConnectCallStructMethod(conn, 2, &in, sizeof in, out, &sz) != kIOReturnSuccess || out->result) return -1;
  KeyInfo info = out->keyInfo; in.keyInfo.dataSize = info.dataSize; in.data8 = 5;
  if (IOConnectCallStructMethod(conn, 2, &in, sizeof in, out, &sz) != kIOReturnSuccess || out->result) return -1;
  out->keyInfo = info; return 0;
}
static double num(SMCParam *p) {
  if (p->keyInfo.dataType == k("flt ")) { float f; memcpy(&f, p->bytes, 4); return f; }
  if (p->keyInfo.dataType == k("fpe2")) return ((p->bytes[0] << 8) | p->bytes[1]) / 4.0;
  if (p->keyInfo.dataType == k("ui8 ")) return p->bytes[0];
  return -1;
}
int main(void) {
  io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn) != kIOReturnSuccess) { puts("no smc"); return 1; }
  SMCParam p; int n = readKey("FNum", &p) == 0 ? (int)num(&p) : 0;
  for (int i = 0; i < n; i++) { char key[5]; snprintf(key, 5, "F%dAc", i); if (readKey(key, &p) == 0) printf("%s%d", i ? " " : "", (int)num(&p)); }
  for (int i = 0; i < n; i++) { char key[5]; snprintf(key, 5, "F%dMn", i); if (readKey(key, &p) == 0) printf(" min%d=%d", i, (int)num(&p)); }
  puts(""); return 0;
}
