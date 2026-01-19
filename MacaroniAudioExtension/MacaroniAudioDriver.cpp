#include <AudioDriverKit/AudioDriverKit.h>
#include <DriverKit/DriverKit.h>
#include <DriverKit/OSCollections.h>

#include "MacaroniAudioDriver.h"

// Constants
constexpr uint32_t kSampleRate = 48000;
constexpr uint32_t kNumChannels = 2;
constexpr uint32_t kBitsPerChannel = 32;
constexpr uint32_t kBytesPerFrame = (kBitsPerChannel / 8) * kNumChannels;
constexpr uint32_t kBufferFrames = 512;

// Object IDs
constexpr IOUserAudioObjectID kDeviceObjectID = 1;
constexpr IOUserAudioObjectID kInputStreamObjectID = 2;
constexpr IOUserAudioObjectID kOutputStreamObjectID = 3;
constexpr IOUserAudioObjectID kVolumeControlObjectID = 4;
constexpr IOUserAudioObjectID kMuteControlObjectID = 5;

struct MacaroniAudioDriver_IVars
{
    OSSharedPtr<IOUserAudioDevice> audioDevice;
    OSSharedPtr<IOUserAudioStream> inputStream;
    OSSharedPtr<IOUserAudioStream> outputStream;
    OSSharedPtr<IOUserAudioLevelControl> volumeControl;
    OSSharedPtr<IOUserAudioBooleanControl> muteControl;
    OSSharedPtr<IOBufferMemoryDescriptor> inputBuffer;
    OSSharedPtr<IOBufferMemoryDescriptor> outputBuffer;

    float volumeLevel;
    bool isMuted;
    bool isRunning;
};

bool MacaroniAudioDriver::init()
{
    if (!super::init()) {
        return false;
    }

    ivars = IONewZero(MacaroniAudioDriver_IVars, 1);
    if (ivars == nullptr) {
        return false;
    }

    ivars->volumeLevel = 1.0f;
    ivars->isMuted = false;
    ivars->isRunning = false;

    return true;
}

void MacaroniAudioDriver::free()
{
    if (ivars != nullptr) {
        ivars->audioDevice.reset();
        ivars->inputStream.reset();
        ivars->outputStream.reset();
        ivars->volumeControl.reset();
        ivars->muteControl.reset();
        ivars->inputBuffer.reset();
        ivars->outputBuffer.reset();
        IOSafeDeleteNULL(ivars, MacaroniAudioDriver_IVars, 1);
    }
    super::free();
}

kern_return_t MacaroniAudioDriver::Start(IOService* provider)
{
    kern_return_t ret;

    ret = super::Start(provider);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    // Create the audio device
    OSSharedPtr<OSString> deviceName = OSSharedPtr(OSString::withCString("Macaroni Audio"), OSNoRetain);
    OSSharedPtr<OSString> deviceUID = OSSharedPtr(OSString::withCString("com.macaroni.audio.device"), OSNoRetain);
    OSSharedPtr<OSString> modelUID = OSSharedPtr(OSString::withCString("com.macaroni.audio.model"), OSNoRetain);
    OSSharedPtr<OSString> manufacturer = OSSharedPtr(OSString::withCString("Macaroni"), OSNoRetain);

    ivars->audioDevice = OSSharedPtr(IOUserAudioDevice::Create(this, false, deviceUID.get()), OSNoRetain);
    if (!ivars->audioDevice) {
        return kIOReturnNoMemory;
    }

    // Set device properties
    ivars->audioDevice->SetName(deviceName.get());
    ivars->audioDevice->SetModelUID(modelUID.get());
    ivars->audioDevice->SetManufacturer(manufacturer.get());
    ivars->audioDevice->SetCanBeDefault(true);
    ivars->audioDevice->SetCanBeDefaultForSystemSounds(true);
    ivars->audioDevice->SetSampleRate(kSampleRate);
    ivars->audioDevice->SetZeroTimeStampPeriod(kBufferFrames);

    // Create stream format
    IOUserAudioStreamBasicDescription format = {};
    format.mSampleRate = kSampleRate;
    format.mFormatID = kIOUserAudioFormatLinearPCM;
    format.mFormatFlags = kIOUserAudioFormatFlagIsFloat | kIOUserAudioFormatFlagIsPacked;
    format.mBytesPerPacket = kBytesPerFrame;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = kBytesPerFrame;
    format.mChannelsPerFrame = kNumChannels;
    format.mBitsPerChannel = kBitsPerChannel;

    // Create output stream (audio from apps)
    ivars->outputStream = OSSharedPtr(IOUserAudioStream::Create(this,
                                                                 IOUserAudioStreamDirection::Output,
                                                                 kOutputStreamObjectID),
                                      OSNoRetain);
    if (!ivars->outputStream) {
        return kIOReturnNoMemory;
    }

    OSSharedPtr<OSString> outputStreamName = OSSharedPtr(OSString::withCString("Macaroni Output"), OSNoRetain);
    ivars->outputStream->SetName(outputStreamName.get());
    ivars->outputStream->SetAvailableStreamFormats(&format, 1);
    ivars->outputStream->SetCurrentStreamFormat(&format);

    // Create input stream (for loopback to capture processed audio)
    ivars->inputStream = OSSharedPtr(IOUserAudioStream::Create(this,
                                                                IOUserAudioStreamDirection::Input,
                                                                kInputStreamObjectID),
                                     OSNoRetain);
    if (!ivars->inputStream) {
        return kIOReturnNoMemory;
    }

    OSSharedPtr<OSString> inputStreamName = OSSharedPtr(OSString::withCString("Macaroni Input"), OSNoRetain);
    ivars->inputStream->SetName(inputStreamName.get());
    ivars->inputStream->SetAvailableStreamFormats(&format, 1);
    ivars->inputStream->SetCurrentStreamFormat(&format);

    // Create volume control
    IOUserAudioLevelControlRange volumeRange = { -96.0, 0.0, kIOUserAudioObjectPropertyElementMain };
    ivars->volumeControl = OSSharedPtr(IOUserAudioLevelControl::Create(this,
                                                                        true, // is settable
                                                                        0.0,  // initial dB value
                                                                        volumeRange,
                                                                        IOUserAudioLevelControlType::Volume,
                                                                        kVolumeControlObjectID),
                                       OSNoRetain);
    if (!ivars->volumeControl) {
        return kIOReturnNoMemory;
    }

    // Create mute control
    ivars->muteControl = OSSharedPtr(IOUserAudioBooleanControl::Create(this,
                                                                        true, // is settable
                                                                        false, // initial value
                                                                        IOUserAudioBooleanControlType::Mute,
                                                                        kMuteControlObjectID),
                                     OSNoRetain);
    if (!ivars->muteControl) {
        return kIOReturnNoMemory;
    }

    // Add streams and controls to device
    ret = ivars->audioDevice->AddStream(ivars->outputStream.get());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    ret = ivars->audioDevice->AddStream(ivars->inputStream.get());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    ret = ivars->audioDevice->AddControl(ivars->volumeControl.get());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    ret = ivars->audioDevice->AddControl(ivars->muteControl.get());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    // Add device to driver
    ret = AddObject(ivars->audioDevice.get());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    // Create IO buffers
    uint32_t bufferSize = kBufferFrames * kBytesPerFrame;
    ret = IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut,
                                           bufferSize,
                                           0,
                                           ivars->outputBuffer.attach());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    ret = IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut,
                                           bufferSize,
                                           0,
                                           ivars->inputBuffer.attach());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    // Set buffers on streams
    ret = ivars->outputStream->SetIOMemoryDescriptor(ivars->outputBuffer.get());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    ret = ivars->inputStream->SetIOMemoryDescriptor(ivars->inputBuffer.get());
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    // Activate device
    ret = ivars->audioDevice->StartIO(IOUserAudioStartStopFlags::None);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    RegisterService();
    return kIOReturnSuccess;
}

kern_return_t MacaroniAudioDriver::Stop(IOService* provider)
{
    if (ivars->audioDevice) {
        ivars->audioDevice->StopIO(IOUserAudioStartStopFlags::None);
        RemoveObject(ivars->audioDevice.get());
    }
    return super::Stop(provider);
}

kern_return_t MacaroniAudioDriver::NewUserClient(uint32_t type, IOUserClient** userClient)
{
    return super::NewUserClient(type, userClient);
}

kern_return_t MacaroniAudioDriver::StartDevice(IOUserAudioObjectID in_object_id,
                                                IOUserAudioStartStopFlags in_flags)
{
    ivars->isRunning = true;
    return kIOReturnSuccess;
}

kern_return_t MacaroniAudioDriver::StopDevice(IOUserAudioObjectID in_object_id,
                                               IOUserAudioStartStopFlags in_flags)
{
    ivars->isRunning = false;
    return kIOReturnSuccess;
}

kern_return_t MacaroniAudioDriver::PerformDeviceConfigurationChange(IOUserAudioObjectID in_object_id,
                                                                     uint64_t in_change_action,
                                                                     OSObject* in_change_info)
{
    return kIOReturnSuccess;
}

kern_return_t MacaroniAudioDriver::AbortDeviceConfigurationChange(IOUserAudioObjectID in_object_id,
                                                                   uint64_t in_change_action,
                                                                   OSObject* in_change_info)
{
    return kIOReturnSuccess;
}

kern_return_t MacaroniAudioDriver::HandleChangedStreamFormat(IOUserAudioObjectID in_object_id,
                                                              IOUserAudioStream* in_stream,
                                                              const IOUserAudioStreamBasicDescription* in_old_format,
                                                              const IOUserAudioStreamBasicDescription* in_new_format)
{
    return kIOReturnSuccess;
}

IMPL_KERNEL_MAIN()
