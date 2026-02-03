//
//  CGVirtualDisplay.h
//  Macaroni
//
//  Private API declarations for CGVirtualDisplay
//  Based on: https://github.com/w0lfschild/macOS_headers/blob/master/macOS/Frameworks/CoreGraphics/1336/CGVirtualDisplay.h
//  Reference implementations: FluffyDisplay, Chromium virtual_display_mac_util.mm
//

#ifndef CGVirtualDisplay_h
#define CGVirtualDisplay_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Represents a single display mode (resolution + refresh rate)
@interface CGVirtualDisplayMode : NSObject

@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
@property (nonatomic, readonly) double refreshRate;

- (instancetype)initWithWidth:(NSUInteger)width
                       height:(NSUInteger)height
                  refreshRate:(double)refreshRate;

@end

/// Descriptor used to configure a virtual display before creation
@interface CGVirtualDisplayDescriptor : NSObject

/// Vendor ID (use 0 for generic)
@property (nonatomic, assign) uint32_t vendorID;

/// Product ID (use 0 for generic)
@property (nonatomic, assign) uint32_t productID;

/// Serial number
@property (nonatomic, assign) uint32_t serialNum;

/// Display name shown in System Settings
@property (nonatomic, copy, nullable) NSString *name;

/// Physical size in millimeters (used for DPI calculation)
@property (nonatomic, assign) CGSize sizeInMillimeters;

/// Maximum supported width in pixels
@property (nonatomic, assign) NSUInteger maxPixelsWide;

/// Maximum supported height in pixels
@property (nonatomic, assign) NSUInteger maxPixelsHigh;

/// Red primary chromaticity coordinates
@property (nonatomic, assign) CGPoint redPrimary;

/// Green primary chromaticity coordinates
@property (nonatomic, assign) CGPoint greenPrimary;

/// Blue primary chromaticity coordinates
@property (nonatomic, assign) CGPoint bluePrimary;

/// White point chromaticity coordinates
@property (nonatomic, assign) CGPoint whitePoint;

/// Dispatch queue for callbacks
@property (nonatomic, strong, nullable) dispatch_queue_t queue;

/// Called when the virtual display is terminated
@property (nonatomic, copy, nullable) void (^terminationHandler)(CGDirectDisplayID displayID, id _Nullable error);

- (instancetype)init;

@end

/// Settings that can be applied to a virtual display after creation
@interface CGVirtualDisplaySettings : NSObject

/// HiDPI mode flag (1 = HiDPI enabled, 0 = disabled)
@property (nonatomic, assign) NSUInteger hiDPI;

/// Array of CGVirtualDisplayMode objects defining available modes
@property (nonatomic, copy, nullable) NSArray<CGVirtualDisplayMode *> *modes;

- (instancetype)init;

@end

/// A virtual display that appears in System Settings > Displays
@interface CGVirtualDisplay : NSObject

/// The CoreGraphics display ID assigned to this virtual display
@property (nonatomic, readonly) CGDirectDisplayID displayID;

/// Array of available display modes
@property (nonatomic, readonly, nullable) NSArray<CGVirtualDisplayMode *> *modes;

/// Whether HiDPI is enabled
@property (nonatomic, readonly) NSUInteger hiDPI;

/// Create a new virtual display with the given descriptor
/// Returns nil if creation fails
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;

/// Apply new settings to the virtual display
/// Returns YES on success
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;

@end

NS_ASSUME_NONNULL_END

#endif /* CGVirtualDisplay_h */
