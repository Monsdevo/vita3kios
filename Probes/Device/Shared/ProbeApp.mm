#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#if defined(VITA3KIOS_PROBE_USES_METAL) && VITA3KIOS_PROBE_USES_METAL
#import <QuartzCore/CAMetalLayer.h>
#endif

#include <exception>
#include <string>

#include "ProbeRunner.h"

namespace {

NSString* ProbeKind() {
#if defined(VITA3KIOS_PROBE_USES_METAL) && VITA3KIOS_PROBE_USES_METAL
    return @"MoltenVK / CAMetalLayer";
#else
    return @"Dynarmic JIT";
#endif
}

NSString* ISO8601Timestamp() {
    static NSISO8601DateFormatter* formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      formatter = [[NSISO8601DateFormatter alloc] init];
      formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                                NSISO8601DateFormatWithFractionalSeconds;
    });
    return [formatter stringFromDate:[NSDate date]];
}

NSDictionary* FailureReport(NSString* error, NSString* detail) {
    NSMutableDictionary* report = [@{
        @"schemaVersion" : @1,
        @"probe" : ProbeKind(),
        @"status" : @"failed",
        @"timestamp" : ISO8601Timestamp(),
        @"error" : error,
    } mutableCopy];
    if (detail.length > 0) {
        report[@"detail"] = detail;
    }
    return report;
}

NSData* JSONData(id object) {
    NSError* serializationError = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted |
                                                           NSJSONWritingSortedKeys
                                                     error:&serializationError];
    if (data != nil) {
        return data;
    }

    NSString* message = serializationError.localizedDescription != nil
        ? serializationError.localizedDescription
        : @"Unknown JSON serialization error";
    NSDictionary* fallback = @{
        @"schemaVersion" : @1,
        @"probe" : ProbeKind(),
        @"status" : @"failed",
        @"timestamp" : ISO8601Timestamp(),
        @"error" : @"Shared harness could not serialize the probe report",
        @"detail" : message,
    };
    return [NSJSONSerialization dataWithJSONObject:fallback options:NSJSONWritingPrettyPrinted error:nil];
}

NSData* NormalizedReportData(const std::string& result,
                             BOOL* isValidRunnerReport,
                             BOOL* runnerSucceeded) {
    NSData* rawData = [NSData dataWithBytes:result.data() length:result.size()];
    NSError* parsingError = nil;
    id report = nil;
    if (rawData.length > 0) {
        report = [NSJSONSerialization JSONObjectWithData:rawData options:0 error:&parsingError];
    }

    if ([report isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary* dictionary = [(NSDictionary*)report mutableCopy];
        dictionary[@"harnessTimestamp"] = ISO8601Timestamp();
        BOOL succeeded = NO;
        id passed = dictionary[@"passed"];
        id status = dictionary[@"status"];
        if ([passed isKindOfClass:[NSNumber class]]) {
            succeeded = [passed boolValue];
        } else if ([status isKindOfClass:[NSString class]]) {
            succeeded = [(NSString*)status hasPrefix:@"passed"];
        }
        if (isValidRunnerReport != nullptr) {
            *isValidRunnerReport = YES;
        }
        if (runnerSucceeded != nullptr) {
            *runnerSucceeded = succeeded;
        }
        return JSONData(dictionary);
    }

    if (isValidRunnerReport != nullptr) {
        *isValidRunnerReport = NO;
    }
    if (runnerSucceeded != nullptr) {
        *runnerSucceeded = NO;
    }

    NSMutableDictionary* invalidReport = [FailureReport(
        @"Probe runner returned an invalid JSON object",
        parsingError.localizedDescription != nil
            ? parsingError.localizedDescription
            : @"The report was empty or its top level was not an object") mutableCopy];
    NSString* rawText = [[NSString alloc] initWithData:rawData encoding:NSUTF8StringEncoding];
    if (rawText != nil) {
        invalidReport[@"rawResult"] = rawText;
    } else if (rawData.length > 0) {
        invalidReport[@"rawResultBase64"] = [rawData base64EncodedStringWithOptions:0];
    }
    return JSONData(invalidReport);
}

BOOL WriteLatestReport(NSData* reportData, NSError** writeError) {
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSURL* documentsURL = [[fileManager URLsForDirectory:NSDocumentDirectory
                                               inDomains:NSUserDomainMask] firstObject];
    if (documentsURL == nil) {
        if (writeError != nullptr) {
            *writeError = [NSError errorWithDomain:@"Vita3KiOSProbeHarness"
                                               code:1
                                           userInfo:@{
                                               NSLocalizedDescriptionKey : @"The app Documents directory is unavailable",
                                           }];
        }
        return NO;
    }

    if (![fileManager createDirectoryAtURL:documentsURL
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:writeError]) {
        return NO;
    }

    NSURL* reportURL = [documentsURL URLByAppendingPathComponent:@"latest-report.json"
                                                     isDirectory:NO];
    return [reportData writeToURL:reportURL options:NSDataWritingAtomic error:writeError];
}

NSString* StringFromReportData(NSData* data) {
    NSString* text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text != nil
        ? text
        : @"{\n  \"status\" : \"failed\",\n  \"error\" : \"Report is not valid UTF-8\"\n}";
}

}  // namespace

@interface Vita3KiOSProbeSurfaceView : UIView
@end

@implementation Vita3KiOSProbeSurfaceView

#if defined(VITA3KIOS_PROBE_USES_METAL) && VITA3KIOS_PROBE_USES_METAL
+ (Class)layerClass {
    return [CAMetalLayer class];
}
#endif

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
#if defined(VITA3KIOS_PROBE_USES_METAL) && VITA3KIOS_PROBE_USES_METAL
        self.backgroundColor = [UIColor blackColor];
        self.accessibilityLabel = @"MoltenVK probe presentation surface";
#else
        self.backgroundColor = [UIColor tertiarySystemFillColor];
        self.accessibilityLabel = @"Dynarmic probe status surface";
#endif
        self.isAccessibilityElement = YES;
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
#if defined(VITA3KIOS_PROBE_USES_METAL) && VITA3KIOS_PROBE_USES_METAL
    CAMetalLayer* metalLayer = (CAMetalLayer*)self.layer;
    UIScreen* screen = self.window.screen;
    CGFloat scale = screen != nil ? screen.scale : [UIScreen mainScreen].scale;
    metalLayer.contentsScale = scale;
    metalLayer.drawableSize = CGSizeMake(self.bounds.size.width * scale,
                                          self.bounds.size.height * scale);
#endif
}

@end

@interface Vita3KiOSProbeViewController : UIViewController
@property(nonatomic, strong) Vita3KiOSProbeSurfaceView* surfaceView;
@property(nonatomic, strong) UIButton* runButton;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UITextView* reportTextView;
@property(nonatomic) BOOL didStartAutomaticRun;
@end

@implementation Vita3KiOSProbeViewController {
    dispatch_queue_t _probeQueue;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _probeQueue = dispatch_queue_create("com.vita3kios.device-probe.runner",
                                            DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UILabel* titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"vita3kios Device Probe";
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 0;
    titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;

    UILabel* descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = [NSString stringWithFormat:
        @"%@ feasibility harness. This utility is separate from the product interface.", ProbeKind()];
    descriptionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    descriptionLabel.textColor = [UIColor secondaryLabelColor];
    descriptionLabel.adjustsFontForContentSizeCategory = YES;
    descriptionLabel.numberOfLines = 0;

    self.surfaceView = [[Vita3KiOSProbeSurfaceView alloc] initWithFrame:CGRectZero];
    self.surfaceView.translatesAutoresizingMaskIntoConstraints = NO;

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.runButton setTitle:@"Run Probe" forState:UIControlStateNormal];
    self.runButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.runButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.runButton.accessibilityLabel = @"Run device probe";
    self.runButton.accessibilityHint = @"Runs the probe in the background and saves its latest JSON report";
    [self.runButton addTarget:self
                       action:@selector(runProbe:)
             forControlEvents:UIControlEventTouchUpInside];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"Ready";
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.accessibilityLabel = @"Probe status: Ready";

    self.reportTextView = [[UITextView alloc] init];
    self.reportTextView.editable = NO;
    self.reportTextView.selectable = YES;
    self.reportTextView.alwaysBounceVertical = YES;
    self.reportTextView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.reportTextView.textColor = [UIColor labelColor];
    self.reportTextView.font = [UIFont monospacedSystemFontOfSize:13.0
                                                         weight:UIFontWeightRegular];
    self.reportTextView.adjustsFontForContentSizeCategory = YES;
    self.reportTextView.layer.cornerRadius = 12.0;
    self.reportTextView.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    self.reportTextView.text = @"{\n  \"status\" : \"not-run\"\n}";
    self.reportTextView.accessibilityLabel = @"Probe result report";

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel,
        descriptionLabel,
        self.surfaceView,
        self.runButton,
        self.statusLabel,
        self.reportTextView,
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 16.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:8.0 afterView:titleLabel];
    [stack setCustomSpacing:24.0 afterView:descriptionLabel];

    UIScrollView* scrollView = [[UIScrollView alloc] init];
    scrollView.alwaysBounceVertical = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:stack];
    [self.view addSubview:scrollView];

    UILayoutGuide* safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],

        [stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor
                                            constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor
                                             constant:-20.0],
        [stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor
                                        constant:20.0],
        [stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor
                                           constant:-20.0],
        [stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor
                                          constant:-40.0],

        [self.surfaceView.heightAnchor constraintEqualToAnchor:self.surfaceView.widthAnchor
                                                    multiplier:9.0 / 16.0],
        [self.runButton.heightAnchor constraintGreaterThanOrEqualToConstant:48.0],
        [self.reportTextView.heightAnchor constraintEqualToConstant:260.0],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didStartAutomaticRun) {
        return;
    }
    self.didStartAutomaticRun = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      [self runProbe:self.runButton];
    });
}

- (void)runProbe:(UIButton*)sender {
    sender.enabled = NO;
    self.statusLabel.text = @"Running…";
    self.statusLabel.textColor = [UIColor systemOrangeColor];
    self.statusLabel.accessibilityLabel = @"Probe status: Running";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Device probe started");

    // Resolve and retain the layer on the main thread. The runner may use the
    // opaque pointer on its serial background queue for the duration of RunProbe.
    CALayer* presentationLayer = self.surfaceView.layer;
    dispatch_async(_probeQueue, ^{
      @autoreleasepool {
        NSData* reportData = nil;
        BOOL validRunnerReport = NO;
        BOOL runnerSucceeded = NO;
        try {
            std::string result = Vita3KiOS::Probes::RunProbe((__bridge void*)presentationLayer);
            reportData = NormalizedReportData(result, &validRunnerReport, &runnerSucceeded);
        } catch (const std::exception& exception) {
            NSString* detail = [NSString stringWithUTF8String:exception.what()];
            reportData = JSONData(FailureReport(
                @"Probe runner threw a C++ exception",
                detail != nil ? detail : @"Exception text was not valid UTF-8"));
        } catch (...) {
            reportData = JSONData(FailureReport(@"Probe runner threw an unknown exception", nil));
        }

        NSError* writeError = nil;
        BOOL reportWasWritten = WriteLatestReport(reportData, &writeError);
        NSString* reportText = StringFromReportData(reportData);

        dispatch_async(dispatch_get_main_queue(), ^{
          self.reportTextView.text = reportText;
          self.runButton.enabled = YES;

          if (!reportWasWritten) {
              self.statusLabel.text = [NSString stringWithFormat:
                  @"Finished, but Documents/latest-report.json could not be saved: %@",
                  writeError.localizedDescription != nil
                      ? writeError.localizedDescription
                      : @"unknown error"];
              self.statusLabel.textColor = [UIColor systemRedColor];
          } else if (!validRunnerReport) {
              self.statusLabel.text = @"Finished with an invalid runner report; failure details were saved to Documents/latest-report.json.";
              self.statusLabel.textColor = [UIColor systemRedColor];
          } else if (!runnerSucceeded) {
              self.statusLabel.text = @"Probe failed. Report saved to Documents/latest-report.json.";
              self.statusLabel.textColor = [UIColor systemRedColor];
          } else {
              self.statusLabel.text = @"Finished. Report saved to Documents/latest-report.json.";
              self.statusLabel.textColor = [UIColor systemGreenColor];
          }

          self.statusLabel.accessibilityLabel = [@"Probe status: " stringByAppendingString:self.statusLabel.text];
          UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                                          self.statusLabel.text);
        });
      }
    });
}

@end

@interface Vita3KiOSProbeAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation Vita3KiOSProbeAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id>*)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[Vita3KiOSProbeViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char* argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([Vita3KiOSProbeAppDelegate class]));
    }
}
