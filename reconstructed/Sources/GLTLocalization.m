#import "GLTLocalization.h"
#import <dispatch/dispatch.h>

NSString *GLTLocalizedString(NSString *english) {
    if (!english) return @"";
    // SpringBoard is the host bundle, not Glint. Resolve system preferences
    // against our supported languages without loading host-bundle resources.
    NSString *language = [NSBundle preferredLocalizationsFromArray:@[@"en", @"zh-Hans"]
                                                   forPreferences:[NSLocale preferredLanguages]].firstObject;
    if (![language isEqualToString:@"zh-Hans"]) return english;

    static NSDictionary<NSString *, NSString *> *chinese;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        chinese = @{
            @"Time": @"时间",
            @"Storage & Memory": @"存储与内存",
            @"Now Playing": @"正在播放",
            @"Alarm & Timer": @"闹钟与计时器",
            @"Quick Message": @"快捷信息",
            @"Weather": @"天气",
            @"Loading the weather…": @"正在加载天气…",
            @"Current Location": @"当前位置",
            @"Feels like %@ · Rain %ld%%": @"体感 %@ · 降雨 %ld%%",
            @"Sunrise %@ · Sunset %@": @"日出 %@ · 日落 %@",
            @"H %@  L %@": @"高 %@  低 %@",
            @"Now": @"现在",
            @"Weather data by Open-Meteo.com": @"天气数据由 Open-Meteo.com 提供",
            @"%@ free of %@": @"可用 %@，共 %@",
            @"Storage": @"存储",
            @"Memory": @"内存",
            @"Not Playing": @"未在播放",
            @"Timer": @"计时器",
            @"Timer · Paused": @"计时器 · 已暂停",
            @"Today": @"今天",
            @"Tomorrow": @"明天",
            @"Alarms": @"闹钟",
            @"No alarms are on.": @"没有已开启的闹钟。",
            @"No alarms": @"无闹钟",
            @"Off": @"已关闭",
            @"Email": @"邮箱",
            @"Number": @"号码",
            @"phone": @"电话",
            @"Name or number": @"姓名或号码",
            @"Message": @"信息",
            @"New Message": @"新建信息",
            @"To: ": @"收件人： ",
            @"Sending…": @"正在发送…",
            @"Sent": @"已发送",
            @"Messaging is disabled in this verification build.": @"此验证版本已禁用信息发送。",
            @"Clear": @"晴",
            @"Mostly Clear": @"大部晴朗",
            @"Partly Cloudy": @"局部多云",
            @"Cloudy": @"多云",
            @"Fog": @"雾",
            @"Drizzle": @"毛毛雨",
            @"Freezing Rain": @"冻雨",
            @"Rain": @"雨",
            @"Heavy Rain": @"大雨",
            @"Snow": @"雪",
            @"Showers": @"阵雨",
            @"Thunderstorms": @"雷暴",
            @"Glint can't find \"%@\".": @"Glint 找不到“%@”。",
            @"Location is not authorized. Type a city in Glint's settings.": @"尚未授权定位。请在 Glint 设置中输入城市。",
            @"Glint can't find where you are. Type a city in Glint's settings.": @"Glint 无法确定你的位置。请在 Glint 设置中输入城市。",
            @"The weather isn't available right now.": @"暂时无法获取天气。",
        };
    });
    return chinese[english] ?: english;
}
