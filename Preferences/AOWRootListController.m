#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end


@interface AOWLibraryManagerController : UITableViewController
@property(nonatomic, strong) NSMutableArray<NSString *> *paths;
@property(nonatomic, strong) NSMutableSet<NSString *> *selectedPaths;
@end

@implementation AOWLibraryManagerController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已下载的壁纸";
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
    self.tableView.editing = YES;
    self.paths = [[[NSUserDefaults.alloc initWithSuiteName:@"com.user.autoonlinewallpaper"] stringArrayForKey:@"libraryPaths"] mutableCopy] ?: [NSMutableArray array];
    self.selectedPaths = [NSMutableSet set];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"删除所选" style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];
    self.toolbarItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"全选" style:UIBarButtonItemStylePlain target:self action:@selector(selectAll)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"全部删除" style:UIBarButtonItemStyleDestructive target:self action:@selector(deleteAll)]
    ];
    [self.navigationController setToolbarHidden:NO animated:NO];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.paths.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"AOWWallpaperCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSString *path = self.paths[indexPath.row];
    cell.textLabel.text = path.lastPathComponent;
    cell.detailTextLabel.text = path;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.selectedPaths addObject:self.paths[indexPath.row]];
    [self updateDeleteTitle];
}
- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.selectedPaths removeObject:self.paths[indexPath.row]];
    [self updateDeleteTitle];
}
- (void)updateDeleteTitle { self.navigationItem.rightBarButtonItem.title = self.selectedPaths.count ? [NSString stringWithFormat:@"删除所选(%lu)", (unsigned long)self.selectedPaths.count] : @"删除所选"; }
- (void)selectAll {
    for (NSUInteger i = 0; i < self.paths.count; i++) {
        NSIndexPath *index = [NSIndexPath indexPathForRow:i inSection:0];
        [self.tableView selectRowAtIndexPath:index animated:NO scrollPosition:UITableViewScrollPositionNone];
        [self.selectedPaths addObject:self.paths[i]];
    }
    [self updateDeleteTitle];
}
- (void)removePaths:(NSArray<NSString *> *)paths {
    NSString *libraryDirectory = @"/var/mobile/Library/AutoOnlineWallpaper/Library";
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *remaining = [self.paths mutableCopy];
    for (NSString *path in paths) {
        // 只允许删除插件图库目录内的文件，避免误删用户其他文件。
        NSString *standard = path.stringByStandardizingPath;
        NSString *prefix = [libraryDirectory stringByAppendingString:@"/"];
        if ([standard hasPrefix:prefix]) [fm removeItemAtPath:standard error:nil];
        [remaining removeObject:path];
    }
    self.paths = remaining;
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.user.autoonlinewallpaper"];
    [defaults setObject:self.paths forKey:@"libraryPaths"];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.user.autoonlinewallpaper.settingschanged"), NULL, NULL, YES);
    [self.selectedPaths removeAllObjects];
    [self.tableView reloadData];
    [self updateDeleteTitle];
}
- (void)deleteSelected {
    if (!self.selectedPaths.count) { [self showAlert:@"请先勾选要删除的壁纸。"]; return; }
    NSArray *selected = self.selectedPaths.allObjects;
    [self confirmTitle:@"删除所选壁纸" message:[NSString stringWithFormat:@"确定删除已勾选的 %lu 张壁纸吗？此操作不可撤销。", (unsigned long)selected.count] handler:^{ [self removePaths:selected]; }];
}
- (void)deleteAll {
    if (!self.paths.count) { [self showAlert:@"图库已经是空的。"]; return; }
    NSArray *all = [self.paths copy];
    [self confirmTitle:@"删除全部壁纸" message:[NSString stringWithFormat:@"确定删除图库中的全部 %lu 张壁纸吗？此操作不可撤销。", (unsigned long)all.count] handler:^{ [self removePaths:all]; }];
}
- (void)confirmTitle:(NSString *)title message:(NSString *)message handler:(dispatch_block_t)handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { handler(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AutoOnlineWallpaper" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface AOWRootListController : PSListController <PHPickerViewControllerDelegate>
@end

@implementation AOWRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)selectPhotos:(id)sender {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
        configuration.filter = [PHPickerFilter imagesFilter];
        configuration.selectionLimit = 0; // 0 = 不限数量
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        [self showMessage:@"系统照片选择器需要 iOS 14 或更高版本。"];
    }
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    NSString *directory = @"/var/mobile/Library/AutoOnlineWallpaper/Library";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *dirError = nil;
    [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionNone} error:&dirError];
    if (dirError) { [self showMessage:[NSString stringWithFormat:@"无法创建壁纸目录：%@", dirError.localizedDescription]]; return; }

    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSString *> *newPaths = [NSMutableArray array];
    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        if (![provider canLoadObjectOfClass:UIImage.class]) continue;
        dispatch_group_enter(group);
        [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
            @autoreleasepool {
                UIImage *image = (UIImage *)object;
                NSData *data = UIImageJPEGRepresentation(image, 0.94);
                if (data.length) {
                    NSString *name = [NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString];
                    NSString *path = [directory stringByAppendingPathComponent:name];
                    if ([data writeToFile:path options:NSDataWritingAtomic error:nil]) {
                        @synchronized (newPaths) { [newPaths addObject:path]; }
                    }
                }
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.user.autoonlinewallpaper"];
        NSArray *old = [defaults stringArrayForKey:@"libraryPaths"] ?: @[];
        NSMutableArray *all = [old mutableCopy];
        [all addObjectsFromArray:newPaths];
        [defaults setObject:all forKey:@"libraryPaths"];
        [defaults setObject:@"local" forKey:@"source"];
        [defaults synchronize];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.user.autoonlinewallpaper.settingschanged"), NULL, NULL, YES);
        [self showMessage:[NSString stringWithFormat:@"已导入 %lu 张图片。壁纸来源已切换为本地图库。", (unsigned long)newPaths.count]];
    });
}

- (void)deleteAllLibraryPhotos:(id)sender {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.user.autoonlinewallpaper"];
    NSArray<NSString *> *paths = [defaults stringArrayForKey:@"libraryPaths"] ?: @[];
    if (paths.count == 0) { [self showMessage:@"图库已经是空的。"]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"一键删除全部壁纸" message:[NSString stringWithFormat:@"确定删除图库中的全部 %lu 张已导入壁纸吗？此操作不可撤销。", (unsigned long)paths.count] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"全部删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *directory = @"/var/mobile/Library/AutoOnlineWallpaper/Library";
        NSString *prefix = [directory stringByAppendingString:@"/"];
        NSFileManager *fm = NSFileManager.defaultManager;
        for (NSString *path in paths) {
            NSString *standard = path.stringByStandardizingPath;
            if ([standard hasPrefix:prefix]) [fm removeItemAtPath:standard error:nil];
        }
        [defaults setObject:@[] forKey:@"libraryPaths"];
        [defaults synchronize];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.user.autoonlinewallpaper.settingschanged"), NULL, NULL, YES);
        [self showMessage:@"已删除全部已导入壁纸。"];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)manageLibrary:(id)sender {
    AOWLibraryManagerController *manager = [[AOWLibraryManagerController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:manager];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AutoOnlineWallpaper" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
