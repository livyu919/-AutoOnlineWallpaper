#import <substrate.h>
#import <UIKit/UIKit.h>

static NSString *gWallpaperURL = nil;
static NSTimer *gWallpaperTimer = nil;

static void setWallpaperImage(UIImage *image) {
    if(!image) return;
    UIScreen *screen = [UIScreen mainScreen];
    SEL setWallpaperSel = NSSelectorFromString(@"_setWallpaperForLocations:");
    if([screen respondsToSelector:setWallpaperSel]){
        ((void(*)(id,SEL,id))objc_msgSend)(screen, setWallpaperSel, @(1));
    }
}

static void downloadAndSetWallpaper(void) {
    if(!gWallpaperURL || gWallpaperURL.length == 0) return;
    NSURL *url = [NSURL URLWithString:gWallpaperURL];
    if(!url) return;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err){
        if(!data || err) return;
        UIImage *img = [UIImage imageWithData:data];
        if(img){
            dispatch_async(dispatch_get_main_queue(), ^{
                setWallpaperImage(img);
            });
        }
    }];
    [task resume];
}

static void readSettings(void){
    NSDictionary *cfg = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"AutoOnlineWallpaperConfig"];
    if(!cfg) return;
    gWallpaperURL = cfg[@"url"];
    NSNumber *intervalNum = cfg[@"interval"];
    BOOL enable = [cfg[@"enable"] boolValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        if(gWallpaperTimer){
            [gWallpaperTimer invalidate];
            gWallpaperTimer = nil;
        }
        if(enable && intervalNum && gWallpaperURL.length>0){
            NSTimeInterval t = [intervalNum doubleValue];
            gWallpaperTimer = [NSTimer scheduledTimerWithTimeInterval:t target:[NSBlockOperation blockOperationWithBlock:^{
                downloadAndSetWallpaper();
            }] selector:@selector(main) userInfo:nil repeats:YES];
            downloadAndSetWallpaper();
        }
    });
}

%ctor {
    readSettings();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, ^(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo){
        readSettings();
    }, CFSTR("com.user.autoonlinewallpaper.settingschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
