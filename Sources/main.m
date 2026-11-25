#import "EditableAlert.h"
#include <unistd.h>

@interface ReconnectApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSMenuItem *message;
@property NSMenuItem *recoverItem;
@end

@implementation ReconnectApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.image = [self menuIcon];
    button.toolTip = @"mac-reconnect-wake";

    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    self.message = [[NSMenuItem alloc] initWithTitle:@"mac-reconnect-wake" action:nil keyEquivalent:@""];
    self.message.enabled = NO;
    [menu addItem:self.message];
    self.recoverItem = [self addItem:@"恢复连接" action:@selector(recover:) toMenu:menu];
    [self addItem:@"点亮远程 Mac 屏幕" action:@selector(wakeMini:) toMenu:menu];
    [self addItem:@"设置唤屏目标…" action:@selector(editWakeTarget:) toMenu:menu];
    [self addItem:@"查看最近断链日志" action:@selector(checkLogs:) toMenu:menu];
    [self addItem:@"打开显示器设置" action:@selector(openDisplays:) toMenu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self addItem:@"退出" action:@selector(quit:) toMenu:menu];
    self.statusItem.menu = menu;
}


- (NSImage *)menuIcon {
    NSImage *image = [NSBundle.mainBundle imageForResource:@"MenuBar"];
    image.size = NSMakeSize(28, 17);
    image.template = YES;
    image.accessibilityDescription = @"mac-reconnect-wake";
    return image;
}

- (void)checkLogs:(NSMenuItem *)sender {
    sender.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/log"];
        task.arguments = @[@"show", @"--last", @"30m", @"--style", @"compact", @"--info",
                           @"--predicate",
                           (@"(process == \"UniversalControl\" OR process == \"rapportd\") AND "
                           @"(eventMessage CONTAINS[c] \"no data connection\" OR "
                           @"eventMessage CONTAINS[c] \"lost AWDL device\" OR "
                           @"eventMessage CONTAINS[c] \"-> Unreachable\" OR "
                           @"(process == \"UniversalControl\" AND eventMessage CONTAINS[c] \"disconnect\"))")];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = NSFileHandle.fileHandleWithNullDevice;
        NSString *summary = @"无法读取系统日志。";
        if ([task launchAndReturnError:NULL]) {
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            if (task.terminationStatus == 0) {
                NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSMutableArray<NSString *> *events = [NSMutableArray array];
                for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                    if ([line rangeOfString:@"^[0-9]{4}-[0-9]{2}-[0-9]{2} " options:NSRegularExpressionSearch].location == 0) {
                        [events addObject:line.length > 220 ? [[line substringToIndex:220] stringByAppendingString:@"…"] : line];
                    }
                }
                if (events.count == 0) {
                    summary = @"最近 30 分钟未找到匹配的断链记录。短暂卡顿可能没有留下这类日志。";
                } else {
                    NSUInteger count = MIN(events.count, 6);
                    NSArray *recent = [events subarrayWithRange:NSMakeRange(events.count - count, count)];
                    summary = [@"以下是最近的候选记录，请对照卡顿时间。\n\n"
                               stringByAppendingString:[recent componentsJoinedByString:@"\n\n"]];
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"最近 30 分钟的断链日志";
            alert.informativeText = summary;
            [alert addButtonWithTitle:@"关闭"];
            [NSApp activateIgnoringOtherApps:YES];
            [alert runModal];
        });
    });
}

- (NSMenuItem *)addItem:(NSString *)title action:(SEL)action toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return item;
}

- (void)recover:(id)sender {
    self.recoverItem.enabled = NO;
    self.message.title = @"正在请求重启通用控制…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pkill"];
        task.arguments = @[@"-TERM", @"-u", [NSString stringWithFormat:@"%u", getuid()],
                           @"-x", @"UniversalControl"];
        NSError *error = nil;
        BOOL launched = [task launchAndReturnError:&error];
        if (launched) [task waitUntilExit];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (launched && task.terminationStatus == 0) {
                self.message.title = @"已请求重启，请稍等后再跨屏";
            } else {
                self.message.title = @"无法重启，请从显示器设置连接";
            }
            self.statusItem.button.toolTip = self.message.title;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                self.recoverItem.enabled = YES;
            });
        });
    });
}

- (NSDictionary *)configureWake:(id)sender {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *saved = [defaults dictionaryForKey:@"WakeTarget"];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"设置唤屏目标";
    alert.informativeText = @"请先在目标 Mac 的共享设置中开启「远程登录」。";
    NSArray *labels = @[@"电脑名称（可选）", @"主机名或 IPv4 地址", @"远程登录用户名"];
    NSArray *keys = @[@"name", @"host", @"user"];
    const CGFloat width = 220;
    const CGFloat rowHeight = 54;
    const CGFloat fieldHeight = 24;
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, rowHeight * keys.count)];
    NSMutableArray<NSTextField *> *fields = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; i++) {
        CGFloat rowBottom = rowHeight * (keys.count - i - 1);
        NSTextField *label = [NSTextField labelWithString:labels[i]];
        label.frame = NSMakeRect(4, rowBottom + fieldHeight + 7, width - 8, 18);
        [form addSubview:label];

        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(4, rowBottom + 3, width - 8, fieldHeight)];
        field.stringValue = saved[keys[i]] ?: @"";
        [form addSubview:field];
        [fields addObject:field];
    }
    for (NSUInteger i = 0; i < fields.count; i++) {
        fields[i].nextKeyView = fields[(i + 1) % fields.count];
    }
    alert.accessoryView = form;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"].keyEquivalent = @"\e";
    alert.window.initialFirstResponder = fields.firstObject;
    [NSApp activateIgnoringOtherApps:YES];
    while (RunEditableAlert(alert, NO) == NSAlertFirstButtonReturn) {
        NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
        NSString *name = [fields[0].stringValue stringByTrimmingCharactersInSet:spaces];
        NSString *host = [fields[1].stringValue stringByTrimmingCharactersInSet:spaces];
        NSString *user = [fields[2].stringValue stringByTrimmingCharactersInSet:spaces];
        BOOL hostOK = [host rangeOfString:@"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$" options:NSRegularExpressionSearch].location != NSNotFound;
        BOOL userOK = [user rangeOfString:@"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$" options:NSRegularExpressionSearch].location != NSNotFound;
        if (hostOK && userOK) {
            NSDictionary *target = @{@"name": name.length ? name : host, @"host": host, @"user": user};
            [defaults setObject:target forKey:@"WakeTarget"];
            return target;
        }
        NSTextField *invalidField = hostOK ? fields[2] : fields[1];
        alert.informativeText = hostOK ? @"请填写远程账户的短用户名。" : @"地址栏只填主机名或 IPv4 地址。";
        alert.window.initialFirstResponder = invalidField;
        [alert.window makeFirstResponder:invalidField];
    }
    return nil;
}

- (void)editWakeTarget:(id)sender {
    [self configureWake:sender];
}

- (void)wakeMini:(NSMenuItem *)sender {
    NSDictionary *target = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"WakeTarget"];
    if (!target) target = [self configureWake:sender];
    if (!target) return;
    NSString *destination = [NSString stringWithFormat:@"%@@%@", target[@"user"], target[@"host"]];
    NSDictionary *connection = target;
    NSURL *askpass = [NSBundle.mainBundle URLForAuxiliaryExecutable:@"MacMiniPassword"];
    if (!askpass) {
        self.message.title = @"缺少密码输入组件，请重新解压应用";
        return;
    }
    sender.enabled = NO;
    self.message.title = @"正在发送唤屏指令…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ssh"];
        NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
        environment[@"SSH_ASKPASS"] = askpass.path;
        environment[@"SSH_ASKPASS_REQUIRE"] = @"force";
        environment[@"UC_WAKE_TARGET"] = connection[@"name"];
        environment[@"UC_WAKE_DESTINATION"] = destination;
        environment[@"LC_ALL"] = @"C";
        task.environment = environment;
        task.standardInput = NSFileHandle.fileHandleWithNullDevice;
        task.arguments = @[@"-T", @"-o", @"BatchMode=no", @"-o", @"ConnectTimeout=5",
                           @"-o", @"StrictHostKeyChecking=ask", @"-o", @"ServerAliveInterval=5",
                           @"-o", @"ServerAliveCountMax=2", @"-o", @"NumberOfPasswordPrompts=1",
                           destination,
                           @"/usr/bin/caffeinate -u -t 5"];
        NSPipe *errors = [NSPipe pipe];
        task.standardError = errors;
        task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
        BOOL launched = [task launchAndReturnError:NULL];
        NSData *details = launched ? [errors.fileHandleForReading readDataToEndOfFile] : nil;
        if (launched) [task waitUntilExit];
        BOOL success = launched && task.terminationStatus == 0;
        NSString *diagnostic = details ? [[NSString alloc] initWithData:details encoding:NSUTF8StringEncoding] : @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            self.message.title = success ? @"唤屏指令已执行" : @"唤屏指令未执行";
            self.statusItem.button.toolTip = success || diagnostic.length == 0
                ? self.message.title
                : [diagnostic stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        });
    });
}

- (void)openDisplays:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:
        [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Displays-Settings.extension"]];
}

- (void)quit:(id)sender {
    [NSApp terminate:sender];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        ReconnectApp *delegate = [[ReconnectApp alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
