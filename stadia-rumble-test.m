// Minimal check that macOS delivers rumble to a Bluetooth Stadia controller.
// Build: clang -fobjc-arc -framework Foundation -framework IOKit stadia-rumble-test.m -o stadia-rumble-test
// Run with the controller connected and awake (press a button first). Exit 0 = report sent; feel for a 1.5 s buzz.
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
static IOHIDDeviceRef dev = NULL;
static void matched(void *c, IOReturn r, void *s, IOHIDDeviceRef d) {
    NSNumber *vid = (__bridge NSNumber *)IOHIDDeviceGetProperty(d, CFSTR(kIOHIDVendorIDKey));
    if (vid.intValue == 0x18d1 && !dev) dev = d;                 // Google
}
int main(void) { @autoreleasepool {
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(m, (__bridge CFDictionaryRef)@{ @kIOHIDVendorIDKey: @(0x18d1) });
    IOHIDManagerRegisterDeviceMatchingCallback(m, matched, NULL);
    IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(m, kIOHIDOptionsTypeNone);                   // shared mode is enough
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
    if (!dev) { fprintf(stderr, "No Stadia controller found (is it connected and awake?)\n"); return 2; }
    int ok = 0;
    for (int i = 0; i < 15; i++) {                                 // ~1.5 s, re-sent every 100 ms
        uint8_t on[5] = { 0x05, 0xff, 0xff, 0xff, 0xff };          // report ID 5 + strong + weak (u16 LE)
        if (IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 5, on, 5) == kIOReturnSuccess) ok++;
        usleep(100000);
    }
    uint8_t off[5] = { 0x05, 0, 0, 0, 0 };
    IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 5, off, 5);
    printf("%d/15 rumble reports accepted. Did it buzz?\n", ok);
    return ok ? 0 : 1;
} }
