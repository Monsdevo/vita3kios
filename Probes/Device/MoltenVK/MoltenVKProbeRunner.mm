#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include <sys/utsname.h>

#include "ProbeRunner.h"

#ifndef VITA3KIOS_APP_COMMIT
#define VITA3KIOS_APP_COMMIT "unknown"
#endif
#ifndef VITA3KIOS_UPSTREAM_COMMIT
#define VITA3KIOS_UPSTREAM_COMMIT "unknown"
#endif

namespace Vita3KiOS::Probes {
namespace {

class VulkanError final : public std::runtime_error {
public:
    VulkanError(const char* stage, VkResult result)
        : std::runtime_error(std::string(stage) + " failed with VkResult " +
                             std::to_string(static_cast<int>(result)))
        , stage(stage)
        , result(result) {}

    std::string stage;
    VkResult result;
};

void Check(VkResult result, const char* stage) {
    if (result != VK_SUCCESS) {
        throw VulkanError(stage, result);
    }
}

NSString* String(const char* value) {
    if (value == nullptr) {
        return @"";
    }
    NSString* string = [NSString stringWithUTF8String:value];
    return string != nil ? string : @"<invalid UTF-8>";
}

NSString* Timestamp() {
    NSISO8601DateFormatter* formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                              NSISO8601DateFormatWithFractionalSeconds;
    return [formatter stringFromDate:[NSDate date]];
}

std::string Serialize(NSDictionary* report) {
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted |
                                                           NSJSONWritingSortedKeys
                                                     error:&error];
    if (data == nil) {
        std::string message = "JSON serialization failed";
        if (error.localizedDescription != nil) {
            message += ": ";
            message += error.localizedDescription.UTF8String;
        }
        throw std::runtime_error(message);
    }
    return std::string(static_cast<const char*>(data.bytes), data.length);
}

template<typename ExtensionProperty>
NSArray<NSString*>* ExtensionNames(const std::vector<ExtensionProperty>& properties) {
    NSMutableArray<NSString*>* result = [NSMutableArray arrayWithCapacity:properties.size()];
    for (const auto& property : properties) {
        [result addObject:String(property.extensionName)];
    }
    return result;
}

template<typename ExtensionProperty>
bool HasExtension(const std::vector<ExtensionProperty>& properties, const char* name) {
    return std::any_of(properties.begin(), properties.end(), [name](const auto& property) {
        return std::string_view(property.extensionName) == name;
    });
}

template<typename Structure>
Structure VulkanStructure(VkStructureType structureType) {
    Structure structure{};
    structure.sType = structureType;
    return structure;
}

NSString* FormatName(VkFormat format) {
    switch (format) {
    case VK_FORMAT_R8_UNORM: return @"R8_UNORM";
    case VK_FORMAT_R8G8_UNORM: return @"R8G8_UNORM";
    case VK_FORMAT_R8G8B8A8_UNORM: return @"R8G8B8A8_UNORM";
    case VK_FORMAT_B8G8R8A8_UNORM: return @"B8G8R8A8_UNORM";
    case VK_FORMAT_R5G6B5_UNORM_PACK16: return @"R5G6B5_UNORM_PACK16";
    case VK_FORMAT_R4G4B4A4_UNORM_PACK16: return @"R4G4B4A4_UNORM_PACK16";
    case VK_FORMAT_A2R10G10B10_UNORM_PACK32: return @"A2R10G10B10_UNORM_PACK32";
    case VK_FORMAT_A2B10G10R10_UNORM_PACK32: return @"A2B10G10R10_UNORM_PACK32";
    case VK_FORMAT_D24_UNORM_S8_UINT: return @"D24_UNORM_S8_UINT";
    case VK_FORMAT_D32_SFLOAT_S8_UINT: return @"D32_SFLOAT_S8_UINT";
    case VK_FORMAT_BC1_RGBA_UNORM_BLOCK: return @"BC1_RGBA_UNORM_BLOCK";
    case VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK: return @"ETC2_R8G8B8A8_UNORM_BLOCK";
    case VK_FORMAT_ASTC_4x4_UNORM_BLOCK: return @"ASTC_4x4_UNORM_BLOCK";
#ifdef VK_IMG_format_pvrtc
    case VK_FORMAT_PVRTC1_4BPP_UNORM_BLOCK_IMG: return @"PVRTC1_4BPP_UNORM_BLOCK_IMG";
#endif
    default: return [NSString stringWithFormat:@"VkFormat(%d)", static_cast<int>(format)];
    }
}

NSDictionary* FormatReport(VkPhysicalDevice physicalDevice, VkFormat format) {
    VkFormatProperties2 properties =
        VulkanStructure<VkFormatProperties2>(VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2);
    vkGetPhysicalDeviceFormatProperties2(physicalDevice, format, &properties);
    const VkFormatFeatureFlags optimal = properties.formatProperties.optimalTilingFeatures;
    return @{
        @"format" : FormatName(format),
        @"enum" : @(static_cast<int>(format)),
        @"optimalTilingFlags" : @((static_cast<unsigned long long>(optimal))),
        @"sampled" : @((optimal & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT) != 0),
        @"colorAttachment" : @((optimal & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT) != 0),
        @"depthStencilAttachment" : @((optimal & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) != 0),
        @"storage" : @((optimal & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT) != 0),
        @"transferSource" : @((optimal & VK_FORMAT_FEATURE_TRANSFER_SRC_BIT) != 0),
        @"transferDestination" : @((optimal & VK_FORMAT_FEATURE_TRANSFER_DST_BIT) != 0),
    };
}

struct VulkanState {
    VkInstance instance = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkRenderPass renderPass = VK_NULL_HANDLE;
    VkCommandPool commandPool = VK_NULL_HANDLE;
    VkSemaphore imageAvailable = VK_NULL_HANDLE;
    VkSemaphore renderFinished = VK_NULL_HANDLE;
    VkFence frameFence = VK_NULL_HANDLE;
    std::vector<VkImageView> imageViews;
    std::vector<VkFramebuffer> framebuffers;

    ~VulkanState() {
        if (device != VK_NULL_HANDLE) {
            vkDeviceWaitIdle(device);
            if (frameFence != VK_NULL_HANDLE) vkDestroyFence(device, frameFence, nullptr);
            if (renderFinished != VK_NULL_HANDLE) vkDestroySemaphore(device, renderFinished, nullptr);
            if (imageAvailable != VK_NULL_HANDLE) vkDestroySemaphore(device, imageAvailable, nullptr);
            if (commandPool != VK_NULL_HANDLE) vkDestroyCommandPool(device, commandPool, nullptr);
            for (VkFramebuffer framebuffer : framebuffers) {
                vkDestroyFramebuffer(device, framebuffer, nullptr);
            }
            if (renderPass != VK_NULL_HANDLE) vkDestroyRenderPass(device, renderPass, nullptr);
            for (VkImageView imageView : imageViews) {
                vkDestroyImageView(device, imageView, nullptr);
            }
            if (swapchain != VK_NULL_HANDLE) vkDestroySwapchainKHR(device, swapchain, nullptr);
            vkDestroyDevice(device, nullptr);
        }
        if (surface != VK_NULL_HANDLE && instance != VK_NULL_HANDLE) {
            vkDestroySurfaceKHR(instance, surface, nullptr);
        }
        if (instance != VK_NULL_HANDLE) {
            vkDestroyInstance(instance, nullptr);
        }
    }
};

VkCompositeAlphaFlagBitsKHR ChooseCompositeAlpha(VkCompositeAlphaFlagsKHR supported) {
    constexpr std::array<VkCompositeAlphaFlagBitsKHR, 4> candidates = {
        VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    };
    for (VkCompositeAlphaFlagBitsKHR candidate : candidates) {
        if ((supported & candidate) != 0) {
            return candidate;
        }
    }
    throw std::runtime_error("surface reports no supported composite-alpha mode");
}

void PopulateRuntimeIdentity(NSMutableDictionary* report) {
    struct utsname systemInfo {};
    NSString* model = @"unknown";
    if (uname(&systemInfo) == 0) {
        model = String(systemInfo.machine);
    }
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    report[@"runtime"] = @{
        @"hardwareModel" : model,
        @"physicalMemoryBytes" : @(NSProcessInfo.processInfo.physicalMemory),
        @"osVersion" : [NSString stringWithFormat:@"%ld.%ld.%ld",
                                                  static_cast<long>(version.majorVersion),
                                                  static_cast<long>(version.minorVersion),
                                                  static_cast<long>(version.patchVersion)],
        @"processorCount" : @(NSProcessInfo.processInfo.processorCount),
    };
}

void RunVulkan(CAMetalLayer* metalLayer, NSMutableDictionary* report) {
    if (metalLayer == nil) {
        throw std::runtime_error("shared harness did not provide a CAMetalLayer");
    }
    const CGSize drawableSize = metalLayer.drawableSize;
    if (drawableSize.width < 1.0 || drawableSize.height < 1.0) {
        throw std::runtime_error("CAMetalLayer drawableSize is zero; wait for view layout and run again");
    }
    report[@"layer"] = @{
        @"width" : @(drawableSize.width),
        @"height" : @(drawableSize.height),
        @"contentsScale" : @(metalLayer.contentsScale),
    };

    VulkanState state;

    uint32_t instanceExtensionCount = 0;
    Check(vkEnumerateInstanceExtensionProperties(nullptr, &instanceExtensionCount, nullptr),
          "vkEnumerateInstanceExtensionProperties(count)");
    std::vector<VkExtensionProperties> instanceExtensions(instanceExtensionCount);
    Check(vkEnumerateInstanceExtensionProperties(nullptr, &instanceExtensionCount,
                                                 instanceExtensions.data()),
          "vkEnumerateInstanceExtensionProperties(data)");
    report[@"instanceExtensions"] = ExtensionNames(instanceExtensions);

    if (!HasExtension(instanceExtensions, VK_KHR_SURFACE_EXTENSION_NAME)) {
        throw std::runtime_error("VK_KHR_surface is unavailable");
    }
    if (!HasExtension(instanceExtensions, VK_EXT_METAL_SURFACE_EXTENSION_NAME)) {
        throw std::runtime_error("VK_EXT_metal_surface is unavailable");
    }

    std::vector<const char*> enabledInstanceExtensions = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
    };
    VkInstanceCreateFlags instanceFlags = 0;
    const bool hasPortabilityEnumeration =
        HasExtension(instanceExtensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    if (hasPortabilityEnumeration) {
        enabledInstanceExtensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        instanceFlags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    VkApplicationInfo appInfo =
        VulkanStructure<VkApplicationInfo>(VK_STRUCTURE_TYPE_APPLICATION_INFO);
    appInfo.pApplicationName = "vita3kios MoltenVK Probe";
    appInfo.applicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);
    appInfo.pEngineName = "none";
    appInfo.engineVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo instanceInfo =
        VulkanStructure<VkInstanceCreateInfo>(VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO);
    instanceInfo.flags = instanceFlags;
    instanceInfo.pApplicationInfo = &appInfo;
    instanceInfo.enabledExtensionCount = static_cast<uint32_t>(enabledInstanceExtensions.size());
    instanceInfo.ppEnabledExtensionNames = enabledInstanceExtensions.data();
    Check(vkCreateInstance(&instanceInfo, nullptr, &state.instance), "vkCreateInstance");

    VkMetalSurfaceCreateInfoEXT surfaceInfo =
        VulkanStructure<VkMetalSurfaceCreateInfoEXT>(VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT);
    surfaceInfo.pLayer = metalLayer;
    Check(vkCreateMetalSurfaceEXT(state.instance, &surfaceInfo, nullptr, &state.surface),
          "vkCreateMetalSurfaceEXT");

    uint32_t physicalDeviceCount = 0;
    Check(vkEnumeratePhysicalDevices(state.instance, &physicalDeviceCount, nullptr),
          "vkEnumeratePhysicalDevices(count)");
    if (physicalDeviceCount == 0) {
        throw std::runtime_error("MoltenVK enumerated no physical device");
    }
    std::vector<VkPhysicalDevice> physicalDevices(physicalDeviceCount);
    Check(vkEnumeratePhysicalDevices(state.instance, &physicalDeviceCount, physicalDevices.data()),
          "vkEnumeratePhysicalDevices(data)");

    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    uint32_t queueFamilyIndex = std::numeric_limits<uint32_t>::max();
    for (VkPhysicalDevice candidate : physicalDevices) {
        uint32_t queueFamilyCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queueFamilyCount, nullptr);
        std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queueFamilyCount, queueFamilies.data());
        for (uint32_t index = 0; index < queueFamilyCount; ++index) {
            VkBool32 presentSupported = VK_FALSE;
            Check(vkGetPhysicalDeviceSurfaceSupportKHR(candidate, index, state.surface,
                                                       &presentSupported),
                  "vkGetPhysicalDeviceSurfaceSupportKHR");
            if ((queueFamilies[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && presentSupported) {
                physicalDevice = candidate;
                queueFamilyIndex = index;
                break;
            }
        }
        if (physicalDevice != VK_NULL_HANDLE) break;
    }
    if (physicalDevice == VK_NULL_HANDLE) {
        throw std::runtime_error("no graphics queue can present to the CAMetalLayer surface");
    }

    VkPhysicalDeviceProperties deviceProperties{};
    VkPhysicalDeviceMemoryProperties memoryProperties{};
    vkGetPhysicalDeviceProperties(physicalDevice, &deviceProperties);
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memoryProperties);

    uint32_t deviceExtensionCount = 0;
    Check(vkEnumerateDeviceExtensionProperties(physicalDevice, nullptr, &deviceExtensionCount, nullptr),
          "vkEnumerateDeviceExtensionProperties(count)");
    std::vector<VkExtensionProperties> deviceExtensions(deviceExtensionCount);
    Check(vkEnumerateDeviceExtensionProperties(physicalDevice, nullptr, &deviceExtensionCount,
                                               deviceExtensions.data()),
          "vkEnumerateDeviceExtensionProperties(data)");
    report[@"deviceExtensions"] = ExtensionNames(deviceExtensions);
    if (!HasExtension(deviceExtensions, VK_KHR_SWAPCHAIN_EXTENSION_NAME)) {
        throw std::runtime_error("VK_KHR_swapchain is unavailable");
    }

    const bool hasPortabilitySubset =
        HasExtension(deviceExtensions, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);
    const bool hasInterlock =
        HasExtension(deviceExtensions, VK_EXT_FRAGMENT_SHADER_INTERLOCK_EXTENSION_NAME);
    const bool hasRasterOrder =
        HasExtension(deviceExtensions, VK_EXT_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_EXTENSION_NAME);

    VkPhysicalDeviceFeatures2 features =
        VulkanStructure<VkPhysicalDeviceFeatures2>(VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2);
    VkPhysicalDevicePortabilitySubsetFeaturesKHR portability =
        VulkanStructure<VkPhysicalDevicePortabilitySubsetFeaturesKHR>(
            VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PORTABILITY_SUBSET_FEATURES_KHR);
    VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT interlock =
        VulkanStructure<VkPhysicalDeviceFragmentShaderInterlockFeaturesEXT>(
            VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FRAGMENT_SHADER_INTERLOCK_FEATURES_EXT);
    VkPhysicalDeviceRasterizationOrderAttachmentAccessFeaturesEXT rasterOrder =
        VulkanStructure<VkPhysicalDeviceRasterizationOrderAttachmentAccessFeaturesEXT>(
            VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RASTERIZATION_ORDER_ATTACHMENT_ACCESS_FEATURES_EXT);
    void* featureChain = nullptr;
    if (hasPortabilitySubset) {
        portability.pNext = featureChain;
        featureChain = &portability;
    }
    if (hasInterlock) {
        interlock.pNext = featureChain;
        featureChain = &interlock;
    }
    if (hasRasterOrder) {
        rasterOrder.pNext = featureChain;
        featureChain = &rasterOrder;
    }
    features.pNext = featureChain;
    vkGetPhysicalDeviceFeatures2(physicalDevice, &features);

    const uint32_t apiMajor = VK_API_VERSION_MAJOR(deviceProperties.apiVersion);
    const uint32_t apiMinor = VK_API_VERSION_MINOR(deviceProperties.apiVersion);
    const bool apiAtLeast11 = apiMajor > 1 || (apiMajor == 1 && apiMinor >= 1);
    report[@"physicalDevice"] = @{
        @"name" : String(deviceProperties.deviceName),
        @"apiVersion" : [NSString stringWithFormat:@"%u.%u.%u", apiMajor, apiMinor,
                                                  VK_API_VERSION_PATCH(deviceProperties.apiVersion)],
        @"driverVersion" : @(deviceProperties.driverVersion),
        @"vendorID" : @(deviceProperties.vendorID),
        @"deviceID" : @(deviceProperties.deviceID),
        @"queueFamilyIndex" : @(queueFamilyIndex),
        @"memoryHeapCount" : @(memoryProperties.memoryHeapCount),
    };
    report[@"capabilities"] = @{
        @"portabilityEnumeration" : @(hasPortabilityEnumeration),
        @"portabilitySubset" : @(hasPortabilitySubset),
        @"imageViewFormatReinterpretation" : @(hasPortabilitySubset && portability.imageViewFormatReinterpretation),
        @"imageViewFormatSwizzle" : @(hasPortabilitySubset && portability.imageViewFormatSwizzle),
        @"fragmentStoresAndAtomics" : @(features.features.fragmentStoresAndAtomics),
        @"fragmentShaderSampleInterlock" : @(hasInterlock && interlock.fragmentShaderSampleInterlock),
        @"fragmentShaderPixelInterlock" : @(hasInterlock && interlock.fragmentShaderPixelInterlock),
        @"rasterizationOrderColorAttachmentAccess" :
            @(hasRasterOrder && rasterOrder.rasterizationOrderColorAttachmentAccess),
        @"maintenance1" : @(apiAtLeast11 || HasExtension(deviceExtensions, VK_KHR_MAINTENANCE_1_EXTENSION_NAME)),
        @"storageBufferStorageClass" :
            @(apiAtLeast11 || HasExtension(deviceExtensions, VK_KHR_STORAGE_BUFFER_STORAGE_CLASS_EXTENSION_NAME)),
    };

    constexpr std::array<VkFormat, 13
#ifdef VK_IMG_format_pvrtc
        + 1
#endif
    > formats = {
        VK_FORMAT_R8_UNORM,
        VK_FORMAT_R8G8_UNORM,
        VK_FORMAT_R8G8B8A8_UNORM,
        VK_FORMAT_B8G8R8A8_UNORM,
        VK_FORMAT_R5G6B5_UNORM_PACK16,
        VK_FORMAT_R4G4B4A4_UNORM_PACK16,
        VK_FORMAT_A2R10G10B10_UNORM_PACK32,
        VK_FORMAT_A2B10G10R10_UNORM_PACK32,
        VK_FORMAT_D24_UNORM_S8_UINT,
        VK_FORMAT_D32_SFLOAT_S8_UINT,
        VK_FORMAT_BC1_RGBA_UNORM_BLOCK,
        VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK,
        VK_FORMAT_ASTC_4x4_UNORM_BLOCK,
#ifdef VK_IMG_format_pvrtc
        VK_FORMAT_PVRTC1_4BPP_UNORM_BLOCK_IMG,
#endif
    };
    NSMutableArray<NSDictionary*>* formatReports = [NSMutableArray arrayWithCapacity:formats.size()];
    for (VkFormat format : formats) {
        [formatReports addObject:FormatReport(physicalDevice, format)];
    }
    report[@"formatMatrix"] = formatReports;

    std::vector<const char*> enabledDeviceExtensions = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    if (hasPortabilitySubset) {
        enabledDeviceExtensions.push_back(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);
    }
    const float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueInfo =
        VulkanStructure<VkDeviceQueueCreateInfo>(VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO);
    queueInfo.queueFamilyIndex = queueFamilyIndex;
    queueInfo.queueCount = 1;
    queueInfo.pQueuePriorities = &queuePriority;
    VkDeviceCreateInfo deviceInfo =
        VulkanStructure<VkDeviceCreateInfo>(VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO);
    deviceInfo.queueCreateInfoCount = 1;
    deviceInfo.pQueueCreateInfos = &queueInfo;
    deviceInfo.enabledExtensionCount = static_cast<uint32_t>(enabledDeviceExtensions.size());
    deviceInfo.ppEnabledExtensionNames = enabledDeviceExtensions.data();
    Check(vkCreateDevice(physicalDevice, &deviceInfo, nullptr, &state.device), "vkCreateDevice");
    VkQueue queue = VK_NULL_HANDLE;
    vkGetDeviceQueue(state.device, queueFamilyIndex, 0, &queue);

    VkSurfaceCapabilitiesKHR surfaceCapabilities{};
    Check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, state.surface,
                                                    &surfaceCapabilities),
          "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    if ((surfaceCapabilities.supportedUsageFlags & VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) == 0) {
        throw std::runtime_error("surface swapchain images cannot be color attachments");
    }

    uint32_t surfaceFormatCount = 0;
    Check(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, state.surface,
                                              &surfaceFormatCount, nullptr),
          "vkGetPhysicalDeviceSurfaceFormatsKHR(count)");
    if (surfaceFormatCount == 0) throw std::runtime_error("surface reports no formats");
    std::vector<VkSurfaceFormatKHR> surfaceFormats(surfaceFormatCount);
    Check(vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, state.surface,
                                              &surfaceFormatCount, surfaceFormats.data()),
          "vkGetPhysicalDeviceSurfaceFormatsKHR(data)");

    uint32_t presentModeCount = 0;
    Check(vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, state.surface,
                                                   &presentModeCount, nullptr),
          "vkGetPhysicalDeviceSurfacePresentModesKHR(count)");
    std::vector<VkPresentModeKHR> presentModes(presentModeCount);
    Check(vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, state.surface,
                                                   &presentModeCount, presentModes.data()),
          "vkGetPhysicalDeviceSurfacePresentModesKHR(data)");

    VkSurfaceFormatKHR selectedFormat = surfaceFormats.front();
    for (const VkSurfaceFormatKHR& candidate : surfaceFormats) {
        if (candidate.format == VK_FORMAT_B8G8R8A8_UNORM &&
            candidate.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            selectedFormat = candidate;
            break;
        }
    }

    VkExtent2D extent = surfaceCapabilities.currentExtent;
    if (extent.width == std::numeric_limits<uint32_t>::max()) {
        extent.width = std::clamp(static_cast<uint32_t>(drawableSize.width),
                                  surfaceCapabilities.minImageExtent.width,
                                  surfaceCapabilities.maxImageExtent.width);
        extent.height = std::clamp(static_cast<uint32_t>(drawableSize.height),
                                   surfaceCapabilities.minImageExtent.height,
                                   surfaceCapabilities.maxImageExtent.height);
    }
    uint32_t imageCount = surfaceCapabilities.minImageCount + 1;
    if (surfaceCapabilities.maxImageCount > 0) {
        imageCount = std::min(imageCount, surfaceCapabilities.maxImageCount);
    }

    NSMutableArray<NSDictionary*>* surfaceFormatReports =
        [NSMutableArray arrayWithCapacity:surfaceFormats.size()];
    for (const VkSurfaceFormatKHR& format : surfaceFormats) {
        [surfaceFormatReports addObject:@{
            @"format" : FormatName(format.format),
            @"colorSpace" : @(static_cast<int>(format.colorSpace)),
        }];
    }
    NSMutableArray<NSNumber*>* presentModeReports = [NSMutableArray arrayWithCapacity:presentModes.size()];
    for (VkPresentModeKHR mode : presentModes) {
        [presentModeReports addObject:@(static_cast<int>(mode))];
    }
    report[@"surface"] = @{
        @"minImageCount" : @(surfaceCapabilities.minImageCount),
        @"maxImageCount" : @(surfaceCapabilities.maxImageCount),
        @"supportedUsageFlags" : @(surfaceCapabilities.supportedUsageFlags),
        @"formats" : surfaceFormatReports,
        @"presentModes" : presentModeReports,
        @"selectedFormat" : FormatName(selectedFormat.format),
        @"selectedWidth" : @(extent.width),
        @"selectedHeight" : @(extent.height),
    };

    VkSwapchainCreateInfoKHR swapchainInfo =
        VulkanStructure<VkSwapchainCreateInfoKHR>(VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR);
    swapchainInfo.surface = state.surface;
    swapchainInfo.minImageCount = imageCount;
    swapchainInfo.imageFormat = selectedFormat.format;
    swapchainInfo.imageColorSpace = selectedFormat.colorSpace;
    swapchainInfo.imageExtent = extent;
    swapchainInfo.imageArrayLayers = 1;
    swapchainInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    swapchainInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    swapchainInfo.preTransform = surfaceCapabilities.currentTransform;
    swapchainInfo.compositeAlpha = ChooseCompositeAlpha(surfaceCapabilities.supportedCompositeAlpha);
    swapchainInfo.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    swapchainInfo.clipped = VK_TRUE;
    Check(vkCreateSwapchainKHR(state.device, &swapchainInfo, nullptr, &state.swapchain),
          "vkCreateSwapchainKHR");

    uint32_t swapchainImageCount = 0;
    Check(vkGetSwapchainImagesKHR(state.device, state.swapchain, &swapchainImageCount, nullptr),
          "vkGetSwapchainImagesKHR(count)");
    std::vector<VkImage> swapchainImages(swapchainImageCount);
    Check(vkGetSwapchainImagesKHR(state.device, state.swapchain, &swapchainImageCount,
                                  swapchainImages.data()),
          "vkGetSwapchainImagesKHR(data)");
    state.imageViews.reserve(swapchainImages.size());
    for (VkImage image : swapchainImages) {
        VkImageViewCreateInfo imageViewInfo =
            VulkanStructure<VkImageViewCreateInfo>(VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO);
        imageViewInfo.image = image;
        imageViewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        imageViewInfo.format = selectedFormat.format;
        imageViewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        imageViewInfo.subresourceRange.levelCount = 1;
        imageViewInfo.subresourceRange.layerCount = 1;
        VkImageView imageView = VK_NULL_HANDLE;
        Check(vkCreateImageView(state.device, &imageViewInfo, nullptr, &imageView),
              "vkCreateImageView");
        state.imageViews.push_back(imageView);
    }

    VkAttachmentDescription colorAttachment{};
    colorAttachment.format = selectedFormat.format;
    colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
    colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    VkAttachmentReference colorReference{0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorReference;
    VkSubpassDependency dependency{};
    dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
    dependency.dstSubpass = 0;
    dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    VkRenderPassCreateInfo renderPassInfo =
        VulkanStructure<VkRenderPassCreateInfo>(VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO);
    renderPassInfo.attachmentCount = 1;
    renderPassInfo.pAttachments = &colorAttachment;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;
    renderPassInfo.dependencyCount = 1;
    renderPassInfo.pDependencies = &dependency;
    Check(vkCreateRenderPass(state.device, &renderPassInfo, nullptr, &state.renderPass),
          "vkCreateRenderPass");

    state.framebuffers.reserve(state.imageViews.size());
    for (VkImageView imageView : state.imageViews) {
        VkFramebufferCreateInfo framebufferInfo =
            VulkanStructure<VkFramebufferCreateInfo>(VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO);
        framebufferInfo.renderPass = state.renderPass;
        framebufferInfo.attachmentCount = 1;
        framebufferInfo.pAttachments = &imageView;
        framebufferInfo.width = extent.width;
        framebufferInfo.height = extent.height;
        framebufferInfo.layers = 1;
        VkFramebuffer framebuffer = VK_NULL_HANDLE;
        Check(vkCreateFramebuffer(state.device, &framebufferInfo, nullptr, &framebuffer),
              "vkCreateFramebuffer");
        state.framebuffers.push_back(framebuffer);
    }

    VkCommandPoolCreateInfo commandPoolInfo =
        VulkanStructure<VkCommandPoolCreateInfo>(VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO);
    commandPoolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    commandPoolInfo.queueFamilyIndex = queueFamilyIndex;
    Check(vkCreateCommandPool(state.device, &commandPoolInfo, nullptr, &state.commandPool),
          "vkCreateCommandPool");
    VkCommandBufferAllocateInfo commandBufferInfo =
        VulkanStructure<VkCommandBufferAllocateInfo>(VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO);
    commandBufferInfo.commandPool = state.commandPool;
    commandBufferInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    commandBufferInfo.commandBufferCount = 1;
    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    Check(vkAllocateCommandBuffers(state.device, &commandBufferInfo, &commandBuffer),
          "vkAllocateCommandBuffers");
    VkSemaphoreCreateInfo semaphoreInfo =
        VulkanStructure<VkSemaphoreCreateInfo>(VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO);
    Check(vkCreateSemaphore(state.device, &semaphoreInfo, nullptr, &state.imageAvailable),
          "vkCreateSemaphore(imageAvailable)");
    Check(vkCreateSemaphore(state.device, &semaphoreInfo, nullptr, &state.renderFinished),
          "vkCreateSemaphore(renderFinished)");
    VkFenceCreateInfo fenceInfo =
        VulkanStructure<VkFenceCreateInfo>(VK_STRUCTURE_TYPE_FENCE_CREATE_INFO);
    Check(vkCreateFence(state.device, &fenceInfo, nullptr, &state.frameFence), "vkCreateFence");

    uint32_t imageIndex = 0;
    VkResult acquireResult = vkAcquireNextImageKHR(state.device, state.swapchain,
                                                   std::numeric_limits<uint64_t>::max(),
                                                   state.imageAvailable, VK_NULL_HANDLE,
                                                   &imageIndex);
    if (acquireResult != VK_SUCCESS && acquireResult != VK_SUBOPTIMAL_KHR) {
        throw VulkanError("vkAcquireNextImageKHR", acquireResult);
    }
    VkCommandBufferBeginInfo beginInfo =
        VulkanStructure<VkCommandBufferBeginInfo>(VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO);
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    Check(vkBeginCommandBuffer(commandBuffer, &beginInfo), "vkBeginCommandBuffer");
    const VkClearValue clearColor{{{0.05f, 0.55f, 0.48f, 1.0f}}};
    VkRenderPassBeginInfo renderBegin =
        VulkanStructure<VkRenderPassBeginInfo>(VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO);
    renderBegin.renderPass = state.renderPass;
    renderBegin.framebuffer = state.framebuffers.at(imageIndex);
    renderBegin.renderArea.extent = extent;
    renderBegin.clearValueCount = 1;
    renderBegin.pClearValues = &clearColor;
    vkCmdBeginRenderPass(commandBuffer, &renderBegin, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdEndRenderPass(commandBuffer);
    Check(vkEndCommandBuffer(commandBuffer), "vkEndCommandBuffer");

    const VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submitInfo = VulkanStructure<VkSubmitInfo>(VK_STRUCTURE_TYPE_SUBMIT_INFO);
    submitInfo.waitSemaphoreCount = 1;
    submitInfo.pWaitSemaphores = &state.imageAvailable;
    submitInfo.pWaitDstStageMask = &waitStage;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;
    submitInfo.signalSemaphoreCount = 1;
    submitInfo.pSignalSemaphores = &state.renderFinished;
    Check(vkQueueSubmit(queue, 1, &submitInfo, state.frameFence), "vkQueueSubmit");

    VkPresentInfoKHR presentInfo =
        VulkanStructure<VkPresentInfoKHR>(VK_STRUCTURE_TYPE_PRESENT_INFO_KHR);
    presentInfo.waitSemaphoreCount = 1;
    presentInfo.pWaitSemaphores = &state.renderFinished;
    presentInfo.swapchainCount = 1;
    presentInfo.pSwapchains = &state.swapchain;
    presentInfo.pImageIndices = &imageIndex;
    VkResult presentResult = vkQueuePresentKHR(queue, &presentInfo);
    if (presentResult != VK_SUCCESS && presentResult != VK_SUBOPTIMAL_KHR) {
        throw VulkanError("vkQueuePresentKHR", presentResult);
    }
    Check(vkWaitForFences(state.device, 1, &state.frameFence, VK_TRUE,
                          std::numeric_limits<uint64_t>::max()),
          "vkWaitForFences");
    Check(vkQueueWaitIdle(queue), "vkQueueWaitIdle");

    report[@"presentation"] = @{
        @"clearFramePresented" : @YES,
        @"triangleFramePresented" : @NO,
        @"triangleStatus" : @"pending committed SPIR-V fixtures",
        @"acquireResult" : @(static_cast<int>(acquireResult)),
        @"presentResult" : @(static_cast<int>(presentResult)),
        @"deviceLostCount" : @0,
    };
}

}  // namespace

std::string RunProbe(void* presentationLayer) {
    @autoreleasepool {
        NSMutableDictionary* report = [@{
            @"schemaVersion" : @1,
            @"probe" : @"moltenvk-cametal-layer",
            @"status" : @"running",
            @"timestamp" : Timestamp(),
            @"appCommit" : @VITA3KIOS_APP_COMMIT,
            @"upstreamCommit" : @VITA3KIOS_UPSTREAM_COMMIT,
            @"moltenVKVersion" : @"1.4.1",
            @"moltenVKArtifactSHA256" :
                @"54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701",
        } mutableCopy];
        PopulateRuntimeIdentity(report);

        try {
            CAMetalLayer* metalLayer = (__bridge CAMetalLayer*)presentationLayer;
            RunVulkan(metalLayer, report);
            report[@"status"] = @"passed-clear-frame";
        } catch (const VulkanError& error) {
            report[@"status"] = @"failed";
            report[@"error"] = String(error.what());
            report[@"failedStage"] = String(error.stage.c_str());
            report[@"vkResult"] = @(static_cast<int>(error.result));
        } catch (const std::exception& error) {
            report[@"status"] = @"failed";
            report[@"error"] = String(error.what());
        }
        return Serialize(report);
    }
}

}  // namespace Vita3KiOS::Probes
