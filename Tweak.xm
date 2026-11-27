#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <notify.h>

static NSString * const kDomain = @"com.user.autoonlinewallpaper";
static NSString * const kChanged = @"com.user.autoonlinewallpaper.settingschanged";
static NSString * const kTrigger = @"com.user.autoonlinewallpaper.triggernow";
static NSString * const kLog = @"[AutoOnlineWallpaper]";

static BOOL gEnabled = YES;
static BOOL gUnlockEnabled = YES;
static BOOL gLockEnabled = YES;
static BOOL gHomeEnabled = YES;
static BOOL gBusy = NO;
static NSString *gSource = @"bing";
static NSString *gURL = @"";
static NSString *gAPIKey = @"";
static NSString *gQuery = @"";
static NSString *gLocalPath = @"";
static NSTimeInterval gInterval = 0;
static NSTimeInterval gUnlockDelay = 2.0;
static NSTimeInterval gCooldown = 5.0;
static NSDate *gLastUnlockTrigger = nil;
static NSDate *gLastChange = nil;
static dispatch_source_t gTimer = nil;

static NSUserDefaults *AOWDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kDomain];
}

static void AOWPostLog(NSString *message) {
    NSLog(@"%@ %@", kLog, message);
}

static void AOWLoadSettings(void) {
    NSUserDefaults *d = AOWDefaults();
    [d synchronize];
    gEnabled = [d objectForKey:@"enable"] ? [d boolForKey:@"enable"] : YES;
    gUnlockEnabled = [d objectForKey:@"unlockEnable"] ? [d boolForKey:@"unlockEnable"] : YES;
    gLockEnabled = [d objectForKey:@"lockScreen"] ? [d boolForKey:@"lockScreen"] : YES;
    gHomeEnabled = [d objectForKey:@"homeScreen"] ? [d boolForKey:@"homeScreen"] : YES;
    gSource = [d stringForKey:@"source"] ?: @"bing";
    gURL = [d stringForKey:@"url"] ?: @"";
    gAPIKey = [d stringForKey:@"apiKey"] ?: @"";
    gQuery = [d stringForKey:@"query"] ?: @"";
    gLocalPath = [d stringForKey:@"localPath"] ?: @"";
    gInterval = [d doubleForKey:@"interval"];
    if (gInterval < 0) gInterval = 0;
    gUnlockDelay = [d objectForKey:@"unlockDelay"] ? [d doubleForKey:@"unlockDelay"] : 2.0;
    if (gUnlockDelay < 0) gUnlockDelay = 0;
    if (gUnlockDelay > 30) gUnlockDelay = 30;
    gCooldown = [d objectForKey:@"unlockCooldown"] ? [d doubleForKey:@"unlockCooldown"] : 5.0;
    if (gCooldown < 3) gCooldown = 3;
    if (gCooldown > 120) gCooldown = 120;
    AOWPostLog([NSString stringWithFormat:@"配置已加载：enabled=%d source=%@ interval=%.0f unlockDelay=%.1f cooldown=%.1f", gEnabled, gSource, gInterval, gUnlockDelay, gCooldown]);
}

static NSURLSession *AOWSession(void) {
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    c.timeoutIntervalForRequest = 25;
    c.timeoutIntervalForResource = 40;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    return [NSURLSession sessionWithConfiguration:c];
}

static void AOWSetWallpaper(UIImage *image) {
    if (!image) { AOWPostLog(@"图片为空，取消设置"); return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"SBWallpaperController");
        id controller = nil;
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if (cls && [cls respondsToSelector:sharedSel]) controller = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSel);
        if (!controller) {
            AOWPostLog(@"无法取得 SBWallpaperController；当前系统可能使用不同的私有壁纸接口");
            return;
        }
        NSInteger locations = (gLockEnabled ? 1 : 0) | (gHomeEnabled ? 2 : 0);
        if (locations == 0) { AOWPostLog(@"锁屏和主屏幕均未启用"); return; }

        SEL modern = NSSelectorFromString(@"setWallpaperImage:forLocations:completionHandler:");
        SEL legacy = NSSelectorFromString(@"setImage:forWallpaperLocation:wallpaperMode:");
        if ([controller respondsToSelector:modern]) {
            void (^completion)(void) = ^{ AOWPostLog(@"系统壁纸接口已返回完成回调"); };
            ((void (*)(id, SEL, id, NSInteger, id))objc_msgSend)(controller, modern, image, locations, completion);
            AOWPostLog([NSString stringWithFormat:@"已调用现代壁纸接口，locations=%ld", (long)locations]);
        } else if ([controller respondsToSelector:legacy]) {
            if (gLockEnabled) ((void (*)(id, SEL, id, NSInteger, NSInteger))objc_msgSend)(controller, legacy, image, 1, 0);
            if (gHomeEnabled) ((void (*)(id, SEL, id, NSInteger, NSInteger))objc_msgSend)(controller, legacy, image, 2, 0);
            AOWPostLog(@"已调用旧版壁纸接口");
        } else {
            AOWPostLog(@"当前系统未找到已知壁纸设置方法；需要针对该 iOS 版本适配私有 API");
        }
    });
}

static void AOWDownloadImageURL(NSURL *url, void (^completion)(UIImage *image, NSError *error)) {
    if (!url || !url.scheme.length) {
        NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:10 userInfo:@{NSLocalizedDescriptionKey:@"图片网址无效"}];
        completion(nil, e); return;
    }
    [[AOWSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (![response isKindOfClass:[NSHTTPURLResponse class]] || ((NSHTTPURLResponse *)response).statusCode < 200 || ((NSHTTPURLResponse *)response).statusCode >= 300) {
            NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:11 userInfo:@{NSLocalizedDescriptionKey:@"服务器返回非 2xx 状态"}];
            completion(nil, e); return;
        }
        UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
        if (!image) {
            NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:12 userInfo:@{NSLocalizedDescriptionKey:@"响应内容不是有效图片"}];
            completion(nil, e); return;
        }
        completion(image, nil);
    }] resume];
}

static void AOWFetchBing(void (^completion)(UIImage *, NSError *)) {
    NSURL *api = [NSURL URLWithString:@"https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-CN"];
    [[AOWSession() dataTaskWithURL:api completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *path = [json[@"images"] isKindOfClass:[NSArray class]] ? json[@"images"].firstObject[@"url"] : nil;
        if (![path isKindOfClass:[NSString class]] || !path.length) {
            NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:20 userInfo:@{NSLocalizedDescriptionKey:@"无法解析 Bing 每日壁纸地址"}]; completion(nil, e); return;
        }
        NSString *full = [path hasPrefix:@"http"] ? path : [@"https://www.bing.com" stringByAppendingString:path];
        AOWDownloadImageURL([NSURL URLWithString:full], completion);
    }] resume];
}

static void AOWFetchUnsplash(void (^completion)(UIImage *, NSError *)) {
    if (!gAPIKey.length) {
        NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:30 userInfo:@{NSLocalizedDescriptionKey:@"Unsplash 需要填写 Access Key"}]; completion(nil, e); return;
    }
    NSString *query = gQuery.length ? gQuery : @"nature landscape";
    NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *s = [NSString stringWithFormat:@"https://api.unsplash.com/photos/random?orientation=landscape&query=%@&client_id=%@", encoded, [gAPIKey stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:s]];
    request.timeoutInterval = 25;
    [[AOWSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *imageURL = [json[@"urls"] isKindOfClass:[NSDictionary class]] ? json[@"urls"][@"regular"] : nil;
        if (![imageURL isKindOfClass:[NSString class]]) {
            NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:31 userInfo:@{NSLocalizedDescriptionKey:@"Unsplash 响应中没有图片地址"}]; completion(nil, e); return;
        }
        AOWDownloadImageURL([NSURL URLWithString:imageURL], completion);
    }] resume];
}

static void AOWFetchCustom(void (^completion)(UIImage *, NSError *)) {
    NSURL *url = [NSURL URLWithString:gURL];
    if (!url || !url.scheme.length) {
        NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:39 userInfo:@{NSLocalizedDescriptionKey:@"自定义 API 地址无效"}]; completion(nil, e); return;
    }
    if ([[url.pathExtension lowercaseString] isEqualToString:@"jpg"] || [[url.pathExtension lowercaseString] isEqualToString:@"jpeg"] || [[url.pathExtension lowercaseString] isEqualToString:@"png"] || [[url.pathExtension lowercaseString] isEqualToString:@"webp"]) {
        AOWDownloadImageURL(url, completion); return;
    }
    [[AOWSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        UIImage *direct = data ? [UIImage imageWithData:data] : nil;
        if (direct) { completion(direct, nil); return; }
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *imageURL = json[@"url"] ?: json[@"image_url"] ?: json[@"image"];
        if (![imageURL isKindOfClass:[NSString class]]) {
            NSError *e = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:40 userInfo:@{NSLocalizedDescriptionKey:@"自定义 API 需返回图片，或 JSON 的 url/image_url/image 字段"}]; completion(nil, e); return;
        }
        AOWDownloadImageURL([NSURL URLWithString:imageURL], completion);
    }] resume];
}

static void AOWChangeWallpaper(void) {
    if (!gEnabled || gBusy) return;
    if (!gLockEnabled && !gHomeEnabled) return;
    gBusy = YES;
    void (^done)(UIImage *, NSError *) = ^(UIImage *image, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            gBusy = NO;
            if (error || !image) { AOWPostLog([NSString stringWithFormat:@"获取壁纸失败：%@", error.localizedDescription ?: @"未知错误"]); return; }
            AOWSetWallpaper(image);
            gLastChange = [NSDate date];
        });
    };
    if ([gSource isEqualToString:@"bing"]) AOWFetchBing(done);
    else if ([gSource isEqualToString:@"unsplash"]) AOWFetchUnsplash(done);
    else if ([gSource isEqualToString:@"local"]) {
        NSArray *library = [AOWDefaults() stringArrayForKey:@"libraryPaths"];
        NSString *selectedPath = gLocalPath;
        if (library.count > 0) {
            // 从相册导入的图片每次随机选择一张。
            NSUInteger index = arc4random_uniform((uint32_t)library.count);
            selectedPath = [library[index] isKindOfClass:NSString.class] ? library[index] : gLocalPath;
        }
        UIImage *image = selectedPath.length ? [UIImage imageWithContentsOfFile:selectedPath] : nil;
        NSError *error = image ? nil : [NSError errorWithDomain:@"AutoOnlineWallpaper" code:50 userInfo:@{NSLocalizedDescriptionKey:@"本地图库为空或图片无法读取，请先从相册导入图片"}];
        done(image, error);
    } else if ([gSource isEqualToString:@"custom"]) AOWFetchCustom(done);
    else {
        NSError *error = [NSError errorWithDomain:@"AutoOnlineWallpaper" code:51 userInfo:@{NSLocalizedDescriptionKey:@"未知壁纸来源，请选择 bing/unsplash/custom/local"}];
        done(nil, error);
    }
}

static void AOWScheduleUnlockChange(void) {
    if (!gEnabled || !gUnlockEnabled) return;

    // 仅由 UIApplicationProtectedDataDidBecomeAvailable 触发：避免锁屏通知
    // 在“锁定”和“解锁”两个方向都发送时，把锁屏误判为解锁。
    NSDate *now = [NSDate date];
    if (gLastUnlockTrigger && [now timeIntervalSinceDate:gLastUnlockTrigger] < gCooldown) {
        AOWPostLog(@"解锁事件处于冷却时间，忽略重复触发");
        return;
    }
    gLastUnlockTrigger = now;

    NSTimeInterval delay = gUnlockDelay;
    AOWPostLog([NSString stringWithFormat:@"检测到数据保护解除，%.1f 秒后检查桌面状态", delay]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        // SpringBoard 是宿主进程；只有数据保护已解除且 SpringBoard 已回到 active，
        // 才执行壁纸更换。若仍在过渡/后台状态，本次跳过，不在稍后补执行。
        if (!app.protectedDataAvailable || app.applicationState != UIApplicationStateActive) {
            AOWPostLog(@"设备尚未回到可交互桌面状态，本次解锁更换已跳过");
            return;
        }
        if (gLastChange && [[NSDate date] timeIntervalSinceDate:gLastChange] < gCooldown) {
            AOWPostLog(@"刚刚已更换过壁纸，忽略重复请求");
            return;
        }
        AOWPostLog(@"解锁后桌面状态确认，开始更换壁纸");
        AOWChangeWallpaper();
    });
}

static void AOWStartIntervalTimer(void) {
    if (gTimer) { dispatch_source_cancel(gTimer); gTimer = nil; }
    if (!gEnabled || gInterval < 10) return;
    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(gInterval * NSEC_PER_SEC)), (uint64_t)(gInterval * NSEC_PER_SEC), NSEC_PER_SEC);
    dispatch_source_set_event_handler(gTimer, ^{ AOWChangeWallpaper(); });
    dispatch_resume(gTimer);
}

static void AOWSettingsChanged(void) {
    AOWLoadSettings();
    AOWStartIntervalTimer();
}

static void AOWDarwinCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *n = (__bridge NSString *)name;
    if ([n isEqualToString:kChanged]) AOWSettingsChanged();
    else if ([n isEqualToString:kTrigger]) AOWChangeWallpaper();
}

%ctor {
    @autoreleasepool {
        AOWSettingsChanged();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AOWDarwinCallback, (__bridge CFStringRef)kChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, AOWDarwinCallback, (__bridge CFStringRef)kTrigger, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        // Protected-data becomes available after a successful unlock on iOS.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            AOWScheduleUnlockChange();
        }];
        AOWPostLog(@"Tweak 已加载；智能解锁触发采用数据保护解除通知，并检查 SpringBoard active 状态。私有壁纸 API 仍需真机验证");
    }
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    AOWSettingsChanged();
}
%end
