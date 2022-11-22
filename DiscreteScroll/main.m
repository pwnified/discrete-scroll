
#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <ApplicationServices/ApplicationServices.h>

#define SIGN(x) (((x) > 0) - ((x) < 0))


double sHostTimeToSeconds = 4.1666666666666666e-08;
double SetTimerScale(void)
{
	mach_timebase_info_data_t info;
	mach_timebase_info(&info);
	sHostTimeToSeconds = (double)info.numer / info.denom * 1e-9;
	return sHostTimeToSeconds;
}
double CurrentTime(void) {
	return (mach_absolute_time() * sHostTimeToSeconds);
}



CGEventRef cgEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
	NSNumber *userInfo = (__bridge NSNumber *)(refcon);
	
	// If the event is not continuous
    if (CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous) == 0) {
        int64_t deltaValue = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
		
		static double lastTime = 0;
		double time = CurrentTime();
		double deltaTime = time - lastTime;
		lastTime = time;

		static int lastSign = 0;
		int sign = SIGN(deltaValue);
		BOOL changedSign = (lastSign != sign);
		lastSign = sign;
		
		static double accel = 0;
		if (deltaTime > 0.4 || changedSign) {
			accel = 0;
		} else {
			accel += 0.25;
		}
		if (accel > 4) {
			accel = 4;
		}
		
		int value = sign * (userInfo.intValue * accel);
		NSLog(@"(value: %d) (deltaTime: %f) (accel: %f)", value, deltaTime, accel);
        CGEventSetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1, value);
    }

    return event;
}

uint64_t Get_HIDMouseScrollAcceleration(void);
BOOL Set_HIDMouseScrollAcceleration(uint64_t x);


int main(void) {

	SetTimerScale();
	
	//"These 8 values are returned for each 'click' of the slider in the system prefs for the mouse 'Scrolling Speed'.
	// They seem to have an arbitrary curve. Just as the acceleration curve is complete dogshit.
	// Map them to a linear integer, which we can use to dial in our own curve that isn't retarded.
	// You'll have to restart this app when you change it, though. But you wont have to recompile it.
	NSDictionary *lookup = @{
		@(0): @(1), // 8192 (diff to next value)
		@(8192): @(2), // 5,898
		@(14090): @(3), // 6,390
		@(20480): @(4), // 12,288
		@(32768): @(5), // 16,384
		@(49152): @(6), // 16,384
		@(65536): @(7), // 262,144
		@(327680): @(8),
	};
	
	uint64_t accel = Get_HIDMouseScrollAcceleration();
	NSNumber *userInfo = lookup[@(accel)];
	
	CFMachPortRef eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0, CGEventMaskBit(kCGEventScrollWheel), cgEventCallback, (__bridge void *)(userInfo));
	if (!eventTap) {
		printf("Failed to create eventTap");
	}
	if (eventTap) {
		CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
		
		CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
		CGEventTapEnable(eventTap, true);
		CFRunLoopRun();
		
		CFRelease(eventTap);
		CFRelease(runLoopSource);
	}

    return 0;
}



// 0, 8192, 14090, 20480, 32768, 49152, 65536, 327680
uint64_t Get_HIDMouseScrollAcceleration(void) {
	
	io_service_t service = IORegistryEntryFromPath(kIOMasterPortDefault, kIOServicePlane ":/IOResources/IOHIDSystem");

	NSDictionary *parameters = (__bridge NSDictionary *)IORegistryEntryCreateCFProperty(service, CFSTR(kIOHIDParametersKey), kCFAllocatorDefault, kNilOptions);
	//NSLog(@"%@", parameters);
	
	return [parameters[@ kIOHIDMouseScrollAccelerationKey] unsignedLongLongValue];
}

BOOL Set_HIDMouseScrollAcceleration(uint64_t x) {
	
	io_service_t service = IORegistryEntryFromPath(kIOMasterPortDefault, kIOServicePlane ":/IOResources/IOHIDSystem");

	NSDictionary *parameters = (__bridge NSDictionary *)IORegistryEntryCreateCFProperty(service, CFSTR(kIOHIDParametersKey), kCFAllocatorDefault, kNilOptions);
	NSLog(@"%@", parameters);

	NSDictionary *dict = @{@ kIOHIDMouseScrollAccelerationKey: @(x)};

	kern_return_t result = IORegistryEntrySetCFProperty(service, CFSTR(kIOHIDParametersKey), (__bridge CFDictionaryRef)dict);
	IOObjectRelease(service);

	NSLog(result == kIOReturnSuccess ? @"Updated" : @"Failed");
	return result == kIOReturnSuccess;
}

