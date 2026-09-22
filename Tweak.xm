#import <UIKit/UIKit.h>
#import <rootless.h>

@interface SBWallpaperController
+ (id)sharedInstance;
- (void)setImage:(UIImage *)image forWallpaperLocation:(NSInteger)location wallpaperMode:(NSInteger)mode;
@end

static NSString *gWallpaperURL = nil;
static NSTimer *gWallpaperTimer = nil;

static void setWallpaperImage(UIImage *image) {
    if (!image) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        Class SBWallpaperControllerClass = %c(SBWallpaperController);
        if (SBWallpaperControllerClass && [SBWallpaperControllerClass respondsToSelector:@selector(sharedInstance)]) {
            id wallpaperController = [SBWallpaperControllerClass sharedInstance];
            if ([wallpaperController respondsToSelector:@selector(setImage:forWallpaperLocation:wallpaperMode:)]) {
                [wallpaperController setImage:image forWallpaperLocation:1 wallpaperMode:0];
                [wallpaperController setImage:image forWallpaperLocation:2 wallpaperMode:0];
                NSLog(@"[AutoOnlineWallpaper] ✅ 在线壁纸设置成功");
            } else {
                NSLog(@"[AutoOnlineWallpaper] ❌ SBWallpaperController 不支持该方法");
            }
        } else {
            NSLog(@"[AutoOnlineWallpaper] ❌ SBWallpaperController 获取失败");
        }
    });
}

static void downloadAndSetWallpaper(void) {
    if (!gWallpaperURL || gWallpaperURL.length == 0) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️ URL为空");
        return;
    }
    NSURL *url = [NSURL URLWithString:gWallpaperURL];
    if (!url) {
        NSLog(@"[AutoOnlineWallpaper] ⚠️ URL格式错误");
        return;
    }

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) {
            NSLog(@"[AutoOnlineWallpaper] ❌ 下载失败: %@", err.localizedDescription);
            return;
        }
        if (!data) return;
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            setWallpaperImage(img);
        } else {
            NSLog(@"[AutoOnlineWallpaper] ❌ 图片解析失败");
        }
    }];
    [task resume];
}

static void readSettings(void) {
    NSDictionary *cfg = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"com.user.autoonlinewallpaper"];
    if (!cfg) cfg = @{};

    BOOL enable = [cfg[@"enable"] boolValue];
    gWallpaperURL = cfg[@"url"] ?: @"";
    NSTimeInterval interval = [cfg[@"interval"] doubleValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gWallpaperTimer) {
            [gWallpaperTimer invalidate];
            gWallpaperTimer = nil;
        }

        if (enable && gWallpaperURL.length > 0) {
            if (interval < 10) interval = 60;
            gWallpaperTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
                downloadAndSetWallpaper();
            }];
            downloadAndSetWallpaper();
            NSLog(@"[AutoOnlineWallpaper] 🟢 定时器启动，间隔 %.0f秒，url:%@", interval, gWallpaperURL);
        }else{
            NSLog(@"[AutoOnlineWallpaper] 🔴 未开启或URL为空");
        }
    });
}

%ctor {
    readSettings();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        ^(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
            if ([(__bridge NSString *)name isEqualToString:@"com.user.autoonlinewallpaper.settingschanged"]) {
                NSLog(@"[AutoOnlineWallpaper] 📥 收到设置变更通知，重新加载配置");
                readSettings();
            } else if ([(__bridge NSString *)name isEqualToString:@"com.user.autoonlinewallpaper.triggernow"]) {
                NSLog(@"[AutoOnlineWallpaper] 🖱️ 用户点击立即更换壁纸");
                downloadAndSetWallpaper();
            }
        },
        NULL,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    readSettings();
}
%end
