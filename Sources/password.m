#import "EditableAlert.h"
#include <stdio.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 1;
        NSString *prompt = [NSString stringWithUTF8String:argv[1]];
        NSString *trimmed = [prompt stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSDictionary *environment = NSProcessInfo.processInfo.environment;
        NSString *destination = environment[@"UC_WAKE_DESTINATION"];
        NSString *name = environment[@"UC_WAKE_TARGET"];
        if (!destination.length || !name.length || !trimmed.length) return 1;
        NSString *expected = [destination stringByAppendingString:@"'s password:"];
        BOOL passwordPrompt = [trimmed isEqualToString:expected] ||
            [trimmed caseInsensitiveCompare:@"Password:"] == NSOrderedSame;
        BOOL hostPrompt = [trimmed hasPrefix:@"The authenticity of host '"] &&
            [trimmed containsString:@"SHA256:"] &&
            [trimmed containsString:@"Are you sure you want to continue connecting"];
        if (!passwordPrompt && !hostPrompt) return 1;

        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSAlert *alert = [[NSAlert alloc] init];
        if (hostPrompt) {
            NSRange fingerprintRange = [trimmed rangeOfString:@"SHA256:[A-Za-z0-9+/=]+"
                                                      options:NSRegularExpressionSearch];
            if (fingerprintRange.location == NSNotFound) return 1;
            NSString *fingerprint = [trimmed substringWithRange:fingerprintRange];
            alert.messageText = @"验证远程 Mac 身份";
            alert.informativeText = [NSString stringWithFormat:
                @"首次连接 %@（%@）。请对照目标 Mac 的 SSH 主机指纹，一致后再继续。\n\n%@",
                name, destination, fingerprint];
            [alert addButtonWithTitle:@"取消"].keyEquivalent = @"\e";
            [alert addButtonWithTitle:@"指纹一致，继续"];
            [application activateIgnoringOtherApps:YES];
            if ([alert runModal] != NSAlertSecondButtonReturn) return 1;
            puts(fingerprint.UTF8String);
            return 0;
        }
        alert.messageText = @"点亮远程 Mac 屏幕";
        alert.informativeText = [NSString stringWithFormat:@"请输入 %@ 的登录密码。", name];
        NSSecureTextField *password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
        alert.accessoryView = password;
        [alert addButtonWithTitle:@"确认"];
        [alert addButtonWithTitle:@"取消"].keyEquivalent = @"\e";
        alert.window.initialFirstResponder = password;
        [application activateIgnoringOtherApps:YES];
        if (RunEditableAlert(alert, YES) != NSAlertFirstButtonReturn) return 1;
        const char *answer = password.stringValue.UTF8String;
        if (!answer) return 1;
        puts(answer);
    }
    return 0;
}
