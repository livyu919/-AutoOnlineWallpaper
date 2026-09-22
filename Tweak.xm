#import <UIKit/UIKit.h>
#import <rootless.h> // 适配 Roothide 路径

// 声明 SpringBoard 的壁纸控制器私有类
@interface SBWallpaperController
+ (id)sharedInstance;
- (void)setImage:(UIImage *)image forWallpaperLocation:(NSInteger)location wallpaperMode:(NSInteger)mode;
@end

static NSString *gWallpaperURL = nil;
static NSTimer *gWallpaperTimer = nil;

// 1. 修正壁纸设置逻辑
static void setWallpaperImage(UIImage *image) {
    if (!image) return;
    
    // 确保在主线程调用 SpringBoard 的壁纸设置 API
    dispatch_async(dispatch_get_main_queue(), ^{
        Class SBWallpaperControllerClass = %c(SBWallpaperController);
        if (SBWallpaperControllerClass && [SBWallpaperControllerClass respondsToSelector:@selector(sharedInstance)]) {
            id wallpaperController = [SBWallpaperControllerClass sharedInstance];
            // 1 代表主屏幕 (Home)，2 代表锁定屏幕 (Lock)，或者 3 (Both)
            if ([wallpaperController respondsToSelector:@selector(setImage:forWallpaperLocation:wallpaperMode:)]) {
                [wallpaperController setImage:image forWallpaperLocation:1 wallpaperMode:0];
                [wallpaperController setImage:image forWallpaperLocation:2 wallpaperMode:0];
                NSLog(@"[AutoOnlineWallpaper] 在线壁纸设置成功！");
            }
        }
    });
}

// 2. 联网下载壁纸
static void downloadAndSetWallpaper(void) {
    if (!gWallpaperURL || gWallpaperURL.length == 0) return;
    NSURL *url = [NSURL URLWithString:gWallpaperURL];
    if (!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data || err) return;
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
            setWallpaperImage(img);
        }
    }];
    [task resume];
}

// 3. 读取偏好设置（修正 plist 路径以兼容 Roothide）
static void readSettings(void) {
    // 适配 Roothide 的偏好设置读取路径
    NSString *plistPath = jbroot(@"/var/mobile/Library/Preferences/com.user.autoonlinewallpaper.plist");
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    
    if (!cfg) {
        // 如果没有配置文件，赋予默认值或直接返回
        return;
    }
    
    gWallpaperURL = cfg[@"url"];
    NSNumber *intervalNum = cfg[@"interval"];
    BOOL enable = [cfg[@"enable"] ? cfg[@"enable"] : @NO boolValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        // 销毁旧定时器
        if (gWallpaperTimer) {
            [gWallpaperTimer invalidate];
            gWallpaperTimer = nil;
        }
        
        // 如果开启了功能，并且有合法的 URL 和时间间隔
        if (enable && intervalNum && gWallpaperURL.length > 0) {
            NSTimeInterval t = [intervalNum doubleValue];
            if (t < 10) t = 60; // 最小限制防刷爆，比如默认至少 60 秒
            
            // 创建定时器
            gWallpaperTimer = [NSTimer scheduledTimerWithTimeInterval:t repeats:YES block:^(NSTimer * _Nonnull timer) {
                downloadAndSetWallpaper();
            }];
            
            // 立即执行一次
            downloadAndSetWallpaper();
        }
    });
}

// 4. 构造函数与通知监听
%ctor {
    readSettings();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), 
        NULL, 
        ^(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
            readSettings();
        }, 
        CFSTR("com.user.autoonlinewallpaper.settingschanged"), 
        NULL, 
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
