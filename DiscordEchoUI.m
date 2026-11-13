// DiscordEchoUI: قائمة عائمة بخمس تبويبات: الصدى، الموازن، النبرة، المضخّم، الأغاني
// زر 🎙 تسحبه في الشاشة، والضغط عليه يفتح القائمة.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

extern void DiscordEcho_SetLevel(int v);
extern void DiscordEcho_SetEchoBoost(int v);
extern void DiscordEcho_SetRange(int v);
extern void DiscordEcho_SetCave(int on);
extern void DiscordEcho_SetRepeat(int on);
extern void DiscordEcho_SetCaveAmount(int v);
extern void DiscordEcho_SetRepeatAmount(int v);
extern void DiscordEcho_SetTapSpeed(int v);
extern void DiscordEcho_SetTapFeedback(int v);
extern void DiscordEcho_SetTapScatter(int v);
extern void DiscordEcho_SetDamp(int v);
extern void DiscordEcho_SetMod(int v);
extern void DiscordEcho_SetEqLoFreq(int v);
extern void DiscordEcho_SetEqHiFreq(int v);
extern void DiscordEcho_SetEqLo(int v);
extern void DiscordEcho_SetEqMid(int v);
extern void DiscordEcho_SetEqHi(int v);
extern void DiscordEcho_SetMode(int v);
extern void DiscordEcho_SetSongEcho(int on);
extern void DiscordEcho_SetMonitor(int on);
extern void DiscordEcho_SetMonitorVolume(int v);
extern void DiscordEcho_SetGain(int v);
extern void DiscordEcho_SetPitch(int v);
extern void DiscordEcho_SetRobot(int on);
extern void DiscordEcho_SetVoiceMute(int on);
extern float DiscordEcho_GetPeak(void);
extern int   DiscordEcho_MusicLoad(float *samples, size_t count);
extern void  DiscordEcho_MusicPlay(int play);
extern void  DiscordEcho_MusicStop(void);
extern void  DiscordEcho_MusicSeek(float frac);
extern void  DiscordEcho_MusicSetVolume(int pct);
extern void  DiscordEcho_MusicSetLoop(int on);
extern int   DiscordEcho_MusicIsPlaying(void);
extern float DiscordEcho_MusicProgress(void);
extern float DiscordEcho_MusicDuration(void);
extern void  DiscordEcho_MonitorRead(float *out, unsigned n, double outRate);
extern void  DiscordEcho_SetSelfMonitor(int on);
extern void  DiscordEcho_SetSelfMonitorVolume(int v);
extern unsigned DiscordEcho_RenderCount(void);

static NSString *const kModeKey  = @"DiscordEchoMode";
static NSString *const kPitchKey = @"DiscordEchoPitch";
static NSString *const kRobotKey = @"DiscordEchoRobot";
static NSString *const kLastURLKey = @"DiscordEchoLastBrowserURL";

static const CGFloat kPanelW = 340;
static const CGFloat kPanelH = 460;
static const CGFloat kTabTop = 56;

enum { TAB_ECHO = 0, TAB_EQ, TAB_PITCH, TAB_AMP, TAB_MUSIC };

static int EchoInt(NSString *key, int def) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d objectForKey:key] ? (int)[d integerForKey:key] : def;
}

#pragma mark - جداول الإعدادات

typedef struct {
    NSString *title;
    NSString *unit;
    NSString *key;
    int min, max, def;
    void (*set)(int);
    NSString *zero;
} SliderSpec;

enum {
    S_LEVEL, S_BOOST, S_RANGE,
    S_CAVEAMT, S_DAMP, S_MOD,
    S_REPAMT, S_TAPSPEED, S_TAPFB, S_TAPSCAT,
    S_EQLOF, S_EQHIF, S_EQLO, S_EQMID, S_EQHI,
    S_GAIN, S_MUSVOL, S_MONVOL, S_SELFVOL,
    S_COUNT
};

static const SliderSpec kSliders[S_COUNT] = {
    [S_LEVEL]    = { @"شدة الصدى",             @"",     @"DiscordEchoLevel",   0, 100,  50, DiscordEcho_SetLevel,         @"الصدى: متوقف" },
    [S_BOOST]    = { @"مضخّم الصدى",           @"%",    @"DiscordEchoBoost", 100, 400, 100, DiscordEcho_SetEchoBoost,     nil },
    [S_RANGE]    = { @"مدى الصدى (الأقصى ≈ 40 ث)",             @"",     @"DiscordEchoRange",   0, 100,  60, DiscordEcho_SetRange,         nil },
    [S_CAVEAMT]  = { @"شدة الكهف",             @"",     @"DiscordEchoCaveAmt", 0, 100, 100, DiscordEcho_SetCaveAmount,    nil },
    [S_DAMP]     = { @"تغميق الذيل",           @"",     @"DiscordEchoDamp",    0, 100,  40, DiscordEcho_SetDamp,          nil },
    [S_MOD]      = { @"تنعيم الموجة",          @"",     @"DiscordEchoMod",     0, 100,  50, DiscordEcho_SetMod,           nil },
    [S_REPAMT]   = { @"شدة التكرار",           @"",     @"DiscordEchoRepAmt",  0, 100, 100, DiscordEcho_SetRepeatAmount,  nil },
    [S_TAPSPEED] = { @"تردد التكرار (Multi-Tap)", @"%", @"DiscordEchoTapSpeed", 50, 300, 100, DiscordEcho_SetTapSpeed,     nil },
    [S_TAPFB]    = { @"عدد التكرارات",         @"",     @"DiscordEchoTapFb",   0, 100,  60, DiscordEcho_SetTapFeedback,   nil },
    [S_TAPSCAT]  = { @"التبعثر",               @"",     @"DiscordEchoTapScat", 0, 100, 100, DiscordEcho_SetTapScatter,    nil },
    [S_EQLOF]    = { @"حد الجهير",             @" Hz",  @"DiscordEchoEqLoF",  60, 800, 200, DiscordEcho_SetEqLoFreq,      nil },
    [S_EQHIF]    = { @"حد الحاد",              @" Hz",  @"DiscordEchoEqHiF", 1500, 9000, 3500, DiscordEcho_SetEqHiFreq,   nil },
    [S_EQLO]     = { @"الجهير",                @"%",    @"DiscordEchoEqLo",    0, 200, 100, DiscordEcho_SetEqLo,          nil },
    [S_EQMID]    = { @"الوسط",                 @"%",    @"DiscordEchoEqMid",   0, 200, 100, DiscordEcho_SetEqMid,         nil },
    [S_EQHI]     = { @"الحاد",                 @"%",    @"DiscordEchoEqHi",    0, 200, 100, DiscordEcho_SetEqHi,          nil },
    [S_GAIN]     = { @"تضخيم الصوت",           @"%",    @"DiscordEchoGain",  100, 1600, 100, DiscordEcho_SetGain,          nil },
    [S_MUSVOL]   = { @"مستوى الأغنية",         @"%",    @"DiscordEchoMusicVol", 0, 200, 100, DiscordEcho_MusicSetVolume,  nil },
    [S_MONVOL]   = { @"مستوى سماعك للأغنية",   @"%",    @"DiscordEchoMonVol",  0, 200, 100, DiscordEcho_SetMonitorVolume, nil },
    [S_SELFVOL]  = { @"مستوى سماعك لصوتك",     @"%",    @"DiscordEchoSelfVol", 0, 200, 100, DiscordEcho_SetSelfMonitorVolume, nil },
};

typedef struct {
    NSString *title;
    NSString *key;
    int def;
    void (*set)(int);
} ToggleSpec;

enum { T_CAVE, T_REPEAT, T_LOOP, T_MUTE, T_SONGECHO, T_MONITOR, T_SELFMON, T_COUNT };

#pragma mark - مراقبة الصوت

static AVAudioEngine *gMonEngine;
static int gMonSong, gMonSelf;
static int echo_mon_wanted(void) { return gMonSong || gMonSelf; }
static BOOL gAppReady;

static void echo_monitor_stop(void) {
    if (gMonEngine) {
        [gMonEngine stop];
        gMonEngine = nil;
    }
}

static void echo_monitor_start(void) {
    if (gMonEngine) {
        if (!gMonEngine.isRunning) {
            NSError *e = nil;
            [gMonEngine startAndReturnError:&e];
        }
        return;
    }
    AVAudioEngine *eng = [[AVAudioEngine alloc] init];
    double rate = [eng.outputNode outputFormatForBus:0].sampleRate;
    if (rate < 8000.0) rate = 48000.0;
    AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:2];
    if (!fmt) return;
    AVAudioSourceNode *src = [[AVAudioSourceNode alloc] initWithFormat:fmt
        renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *ts,
                              AVAudioFrameCount frames, AudioBufferList *abl) {
        if (abl->mNumberBuffers == 0) return noErr;
        float *first = (float *)abl->mBuffers[0].mData;
        DiscordEcho_MonitorRead(first, (unsigned)frames, rate);
        for (UInt32 b = 1; b < abl->mNumberBuffers; b++)
            memcpy(abl->mBuffers[b].mData, first, frames * sizeof(float));
        *isSilence = NO;
        return noErr;
    }];
    [eng attachNode:src];
    [eng connect:src to:eng.mainMixerNode format:fmt];
    NSError *err = nil;
    if (![eng startAndReturnError:&err]) return;
    gMonEngine = eng;
}

static void echo_monitor_sync(void) {
    if (!gAppReady) return;
    if (echo_mon_wanted()) echo_monitor_start();
    else echo_monitor_stop();
}

static void echo_set_monitor(int on) {
    gMonSong = on ? 1 : 0;
    DiscordEcho_SetMonitor(on);
    echo_monitor_sync();
}

static void echo_set_selfmon(int on) {
    gMonSelf = on ? 1 : 0;
    DiscordEcho_SetSelfMonitor(on);
    echo_monitor_sync();
}

static BOOL echo_headphones(void) {
    NSArray<AVAudioSessionPortDescription *> *outs = AVAudioSession.sharedInstance.currentRoute.outputs;
    if (outs.count == 0) return YES;
    for (AVAudioSessionPortDescription *o in outs) {
        if ([o.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker] ||
            [o.portType isEqualToString:AVAudioSessionPortBuiltInReceiver]) return NO;
    }
    return YES;
}

static const ToggleSpec kToggles[T_COUNT] = {
    [T_CAVE]     = { @"كهف 👻",                    @"DiscordEchoCave",     1, DiscordEcho_SetCave },
    [T_REPEAT]   = { @"تكرار 🔁",                  @"DiscordEchoRepeat",   1, DiscordEcho_SetRepeat },
    [T_LOOP]     = { @"🔁 تكرار الأغنية",          @"DiscordEchoMusicLoop", 0, DiscordEcho_MusicSetLoop },
    [T_MUTE]     = { @"🔇 كتم صوتي أثناء الأغنية", @"DiscordEchoVoiceMute", 0, DiscordEcho_SetVoiceMute },
    [T_SONGECHO] = { @"👻 الصدى على الأغنية",      @"DiscordEchoSongEcho", 1, DiscordEcho_SetSongEcho },
    [T_MONITOR]  = { @"🎧 أنا أسمع الأغنية",       @"DiscordEchoMonitor",  0, echo_set_monitor },
    [T_SELFMON]  = { @"🎧 أسمع صوتي (مع الصدى)",   @"DiscordEchoSelfMon",  0, echo_set_selfmon },
};

static NSString *const kEqPresetNames[5] = { @"مسطح", @"دافئ", @"ناعم", @"صافي", @"بدون جهير" };
static const int kEqPresets[5][5] = {
    { 200, 3500, 100, 100, 100 },
    { 200, 2500, 130, 100,  55 },
    { 250, 2000, 110,  80,  25 },
    { 300, 4500,  40, 115, 100 },
    { 400, 3500,   0, 100,  90 },
};

#pragma mark - فك ترميز الأغنية إلى عينات أحادية 48kHz

static const double kTargetRate = 48000.0;
static const size_t kMaxSamples = 48000 * 60 * 8;

static float *EchoDecodeFile(NSURL *url, size_t *outCount, BOOL *truncated, void (^progress)(float)) {
    *outCount = 0;
    *truncated = NO;
    NSError *err = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&err];
    if (!file) return NULL;
    AVAudioFormat *src = file.processingFormat;
    AVAudioChannelCount chans = src.channelCount;
    if (chans < 1 || src.sampleRate <= 0) return NULL;
    AVAudioFormat *dst = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                          sampleRate:kTargetRate
                                                            channels:chans
                                                         interleaved:NO];
    if (!dst) return NULL;
    AVAudioConverter *conv = [[AVAudioConverter alloc] initFromFormat:src toFormat:dst];
    if (!conv) return NULL;

    double est = (double)file.length * kTargetRate / src.sampleRate + 8192.0;
    size_t cap = est > (double)kMaxSamples ? kMaxSamples : (size_t)est;
    float *out = (float *)malloc(cap * sizeof(float));
    if (!out) return NULL;
    size_t n = 0;

    const AVAudioFrameCount chunk = 32768;
    AVAudioPCMBuffer *outBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:dst frameCapacity:chunk];
    BOOL finished = NO;
    NSTimeInterval lastProg = 0;
    while (!finished && n < cap) {
        NSError *cerr = nil;
        AVAudioConverterOutputStatus st = [conv convertToBuffer:outBuf
                                                          error:&cerr
                                             withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNum, AVAudioConverterInputStatus *status) {
            AVAudioFramePosition remain = file.length - file.framePosition;
            if (remain <= 0 || inNum == 0) {
                *status = AVAudioConverterInputStatus_EndOfStream;
                return nil;
            }
            AVAudioFrameCount want = inNum;
            if ((AVAudioFramePosition)want > remain) want = (AVAudioFrameCount)remain;
            AVAudioPCMBuffer *inBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:src frameCapacity:want];
            NSError *rerr = nil;
            if (![file readIntoBuffer:inBuf frameCount:want error:&rerr] || inBuf.frameLength == 0) {
                *status = AVAudioConverterInputStatus_EndOfStream;
                return nil;
            }
            *status = AVAudioConverterInputStatus_HaveData;
            return inBuf;
        }];
        if (st == AVAudioConverterOutputStatus_Error) break;
        if (st == AVAudioConverterOutputStatus_EndOfStream) finished = YES;

        AVAudioFrameCount got = outBuf.frameLength;
        float *const *chData = outBuf.floatChannelData;
        for (AVAudioFrameCount i = 0; i < got && n < cap; i++) {
            float s = 0;
            for (AVAudioChannelCount c = 0; c < chans; c++) s += chData[c][i];
            out[n++] = s / (float)chans;
        }
        if (got == 0) finished = YES;
        if (progress && file.length > 0) {
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            if (now - lastProg > 0.25) {
                lastProg = now;
                progress((float)((double)file.framePosition / (double)file.length));
            }
        }
    }
    if (!finished && n >= cap && cap == kMaxSamples) *truncated = YES;
    if (n < 2) { free(out); return NULL; }
    *outCount = n;
    return out;
}

static NSString *EchoTime(float s) {
    int t = (int)lroundf(s < 0 ? 0 : s);
    return [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

#pragma mark - نافذة شفافة تمرر اللمس لديسكورد

@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

#pragma mark - متصفح داخلي (YouTube و Y2Mate مع منع النوافذ المنبثقة وحفظ الصفحة الأخيرة)

static BOOL EchoIsAudioExt(NSString *ext) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSSet setWithObjects:@"mp3", @"m4a", @"wav", @"aac", @"aif", @"aiff", @"caf", @"flac", nil]; });
    return ext.length && [set containsObject:ext.lowercaseString];
}

@interface EchoBrowserController : UIViewController <WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate>
@property (nonatomic, copy) void (^onPick)(NSURL *fileURL, NSString *name);
@property (nonatomic, strong) NSMutableArray<WKWebView *> *tabs;
@property (nonatomic) NSInteger cur;
@property (nonatomic, strong) UIScrollView *tabBar;
@property (nonatomic, strong) UITextField *addr;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) NSArray<UIButton *> *quick;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSURL *> *dests;
@end

@implementation EchoBrowserController

- (WKWebView *)web { return (self.cur >= 0 && self.cur < (NSInteger)self.tabs.count) ? self.tabs[self.cur] : nil; }

- (UIButton *)pill:(NSString *)t action:(SEL)a tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    b.layer.cornerRadius = 9;
    b.tag = tag;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.dests = [NSMutableDictionary dictionary];
    self.tabs = [NSMutableArray array];
    self.cur = -1;

    self.closeBtn = [self pill:@"✕ إغلاق" action:@selector(closeTapped) tag:0];
    self.backBtn = [self pill:@"◀︎ رجوع" action:@selector(backTapped) tag:0];
    [self.view addSubview:self.closeBtn];
    [self.view addSubview:self.backBtn];

    self.addr = [[UITextField alloc] init];
    self.addr.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.addr.textColor = UIColor.whiteColor;
    self.addr.layer.cornerRadius = 9;
    self.addr.font = [UIFont systemFontOfSize:14];
    self.addr.placeholder = @"اكتب موقع أو الصق رابط الفيديو";
    self.addr.keyboardType = UIKeyboardTypeURL;
    self.addr.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.addr.autocorrectionType = UITextAutocorrectionTypeNo;
    self.addr.returnKeyType = UIReturnKeyGo;
    self.addr.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.addr.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    self.addr.leftViewMode = UITextFieldViewModeAlways;
    self.addr.delegate = self;
    [self.view addSubview:self.addr];

    NSMutableArray *q = [NSMutableArray array];
    NSArray *names = @[@"YouTube", @"Y2Mate"];
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *b = [self pill:names[i] action:@selector(quickTapped:) tag:i];
        [self.view addSubview:b];
        [q addObject:b];
    }
    self.quick = q;

    self.tabBar = [[UIScrollView alloc] init];
    self.tabBar.showsHorizontalScrollIndicator = NO;
    [self.view addSubview:self.tabBar];

    self.status = [[UILabel alloc] init];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.font = [UIFont systemFontOfSize:12];
    self.status.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    self.status.numberOfLines = 2;
    self.status.text = @"انسخ رابط الفيديو من YouTube، ثم انتقل لـ Y2Mate للتحميل بصيغة MP3.";
    [self.view addSubview:self.status];

    NSString *savedURL = [[NSUserDefaults standardUserDefaults] stringForKey:kLastURLKey];

    [self openTabWithConfig:nil];
    [self loadText:(savedURL.length > 0 ? savedURL : @"https://www.youtube.com")];

    [self openTabWithConfig:nil];
    [self loadText:@"https://v42.www-y2mate.com/"];

    [self selectTab:0];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat top = 10;
    self.backBtn.frame = CGRectMake(12, top, 84, 34);
    self.closeBtn.frame = CGRectMake(b.size.width - 96, top, 84, 34);
    CGFloat qx = 104, qw = (b.size.width - 104 - 104 - 6) / 2.0;
    for (NSInteger i = 0; i < 2; i++) self.quick[i].frame = CGRectMake(qx + i * (qw + 6), top, qw, 34);
    self.addr.frame = CGRectMake(12, 50, b.size.width - 24, 36);
    self.tabBar.frame = CGRectMake(0, 92, b.size.width, 34);
    CGFloat sh = 44;
    CGRect wf = CGRectMake(0, 130, b.size.width, b.size.height - 130 - sh);
    for (WKWebView *w in self.tabs) w.frame = wf;
    self.status.frame = CGRectMake(12, b.size.height - sh, b.size.width - 24, sh);
}

- (WKWebView *)openTabWithConfig:(WKWebViewConfiguration *)cfg {
    if (!cfg) cfg = [[WKWebViewConfiguration alloc] init];
    WKWebView *w = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
    w.navigationDelegate = self;
    w.UIDelegate = self;
    w.allowsBackForwardNavigationGestures = YES;
    [self.view addSubview:w];
    [self.tabs addObject:w];
    [self viewDidLayoutSubviews];
    [self selectTab:(NSInteger)self.tabs.count - 1];
    return w;
}

- (void)selectTab:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.tabs.count) return;
    self.cur = i;
    for (NSInteger k = 0; k < (NSInteger)self.tabs.count; k++) self.tabs[k].hidden = (k != i);
    NSURL *u = self.web.URL;
    self.addr.text = u ? u.absoluteString : @"";
    [self refreshTabBar];
}

- (void)refreshTabBar {
    for (UIView *v in self.tabBar.subviews) [v removeFromSuperview];
    CGFloat x = 8;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        NSString *t = self.tabs[i].title;
        if (t.length == 0) t = (i == 0) ? @"YouTube" : (i == 1 ? @"Y2Mate" : @"نافذة");
        if (t.length > 14) t = [[t substringToIndex:14] stringByAppendingString:@"…"];
        UIButton *b = [self pill:t action:@selector(tabTapped:) tag:i];
        b.frame = CGRectMake(x, 0, 104, 32);
        if (i == self.cur) b.backgroundColor = [UIColor colorWithRed:0.33 green:0.42 blue:1 alpha:0.95];
        [self.tabBar addSubview:b];
        x += 110;
    }
    UIButton *add = [self pill:@"＋ نافذة" action:@selector(addTabTapped) tag:0];
    add.frame = CGRectMake(x, 0, 78, 32);
    [self.tabBar addSubview:add];
    x += 84;
    UIButton *del = [self pill:@"🗑 شيلها" action:@selector(closeTabTapped) tag:0];
    del.frame = CGRectMake(x, 0, 78, 32);
    [self.tabBar addSubview:del];
    x += 84;
    self.tabBar.contentSize = CGSizeMake(x + 8, 34);
}

- (void)tabTapped:(UIButton *)b { [self selectTab:b.tag]; }

- (void)addTabTapped {
    [self openTabWithConfig:nil];
    [self loadText:@"https://www.youtube.com"];
}

- (void)closeTabTapped {
    if (self.tabs.count <= 1) { self.status.text = @"هذي آخر نافذة. اضغط ✕ إغلاق لو تبغى تطلع"; return; }
    WKWebView *w = self.web;
    [w stopLoading];
    [w removeFromSuperview];
    [self.tabs removeObjectAtIndex:self.cur];
    NSInteger n = self.cur >= (NSInteger)self.tabs.count ? (NSInteger)self.tabs.count - 1 : self.cur;
    [self selectTab:n];
}

- (WKWebView *)webView:(WKWebView *)wv createWebViewWithConfiguration:(WKWebViewConfiguration *)cfg
   forNavigationAction:(WKNavigationAction *)a windowFeatures:(WKWindowFeatures *)f {
    if (a.request.URL) {
        [wv loadRequest:a.request];
    }
    return nil;
}

- (void)closeTapped {
    NSURL *curURL = self.web.URL;
    if (curURL) {
        [[NSUserDefaults standardUserDefaults] setObject:curURL.absoluteString forKey:kLastURLKey];
    }
    for (WKWebView *w in self.tabs) [w stopLoading];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)backTapped { if (self.web.canGoBack) [self.web goBack]; }

- (void)quickTapped:(UIButton *)b {
    NSArray *urls = @[@"https://www.youtube.com", @"https://v42.www-y2mate.com/"];
    [self loadText:urls[b.tag]];
}

- (void)loadText:(NSString *)t {
    t = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.length == 0) return;
    NSURL *u = nil;
    if ([t hasPrefix:@"http://"] || [t hasPrefix:@"https://"]) u = [NSURL URLWithString:t];
    else if ([t containsString:@"."] && ![t containsString:@" "]) u = [NSURL URLWithString:[@"https://" stringByAppendingString:t]];
    else {
        NSURLComponents *c = [NSURLComponents componentsWithString:@"https://www.youtube.com/results"];
        c.queryItems = @[ [NSURLQueryItem queryItemWithName:@"search_query" value:t] ];
        u = c.URL;
    }
    if (u) { self.addr.text = u.absoluteString; [self.web loadRequest:[NSURLRequest requestWithURL:u]]; }
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    [self loadText:tf.text];
    return YES;
}

- (BOOL)canDownload {
    if (@available(iOS 14.5, *)) return YES;
    return NO;
}

- (void)webView:(WKWebView *)wv decidePolicyForNavigationAction:(WKNavigationAction *)a
                                         decisionHandler:(void (^)(WKNavigationActionPolicy))h {
    if ([self canDownload]) {
        BOOL should = NO;
        if ([a respondsToSelector:NSSelectorFromString(@"shouldPerformDownload")])
            should = [[a valueForKey:@"shouldPerformDownload"] boolValue];
        NSString *ext = a.request.URL.pathExtension;
        if (should || EchoIsAudioExt(ext)) { h((WKNavigationActionPolicy)2); return; }
    }
    h(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)wv decidePolicyForNavigationResponse:(WKNavigationResponse *)r
                                                  decisionHandler:(void (^)(WKNavigationResponsePolicy))h {
    if ([self canDownload]) {
        NSString *mime = r.response.MIMEType.lowercaseString ?: @"";
        NSString *ext = r.response.suggestedFilename.pathExtension;
        BOOL audio = [mime hasPrefix:@"audio/"] || EchoIsAudioExt(ext) || EchoIsAudioExt(r.response.URL.pathExtension);
        if (audio) { h((WKNavigationResponsePolicy)2); return; }
    }
    h(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)wv navigationAction:(WKNavigationAction *)a didBecomeDownload:(id)d {
    [d setDelegate:self];
    self.status.text = @"⏳ بدأ التنزيل…";
}
- (void)webView:(WKWebView *)wv navigationResponse:(WKNavigationResponse *)r didBecomeDownload:(id)d {
    [d setDelegate:self];
    self.status.text = @"⏳ بدأ التنزيل…";
}

- (void)download:(id)d decideDestinationUsingResponse:(NSURLResponse *)resp suggestedFilename:(NSString *)name
                                     completionHandler:(void (^)(NSURL *))ch {
    NSString *fn = name.length ? name : @"song";
    fn = [fn stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    if (!fn.pathExtension.length) fn = [fn stringByAppendingString:@".mp3"];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"echo_%u_%@", arc4random(), fn]];
    NSURL *dest = [NSURL fileURLWithPath:path];
    self.dests[[NSValue valueWithNonretainedObject:d]] = dest;
    self.status.text = [NSString stringWithFormat:@"⏳ جاري تنزيل: %@", fn];
    ch(dest);
}

- (void)downloadDidFinish:(id)d {
    NSValue *k = [NSValue valueWithNonretainedObject:d];
    NSURL *dest = self.dests[k];
    [self.dests removeObjectForKey:k];
    if (!dest) return;
    if (!EchoIsAudioExt(dest.pathExtension)) {
        [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
        self.status.text = [NSString stringWithFormat:@"❌ هذا مو ملف صوت (%@)", dest.pathExtension];
        return;
    }
    NSString *name = [[dest.lastPathComponent stringByDeletingPathExtension] copy];
    void (^cb)(NSURL *, NSString *) = self.onPick;
    [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(dest, name); }];
}

- (void)download:(id)d didFailWithError:(NSError *__nullable)e resumeData:(NSData *__nullable)rd {
    [self.dests removeObjectForKey:[NSValue valueWithNonretainedObject:d]];
    self.status.text = @"❌ فشل التنزيل. جرّب مرة ثانية أو موقع ثاني";
}

- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)n {
    if (wv == self.web && wv.URL) self.addr.text = wv.URL.absoluteString;
    [self refreshTabBar];
}

@end

#pragma mark - الواجهة

@interface EchoController : UIViewController <UIDocumentPickerDelegate> {
    UISlider *_sl[S_COUNT];
    UILabel  *_lb[S_COUNT];
    UISwitch *_sw[T_COUNT];
}
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) NSArray<UIView *> *tabViews;
@property (nonatomic, strong) NSArray<UIButton *> *modeBtns;
@property (nonatomic) NSInteger mode;
@property (nonatomic, strong) UILabel *pitchLabel;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic) BOOL robot;
@property (nonatomic, strong) UIProgressView *meter;
@property (nonatomic, strong) UILabel *micStatus;
@property (nonatomic, strong) UILabel *monWarn;
@property (nonatomic) unsigned lastRender;
@property (nonatomic) CFTimeInterval lastRenderTime;
@property (nonatomic, strong) UILabel *songLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UISlider *seekSlider;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic) BOOL seeking;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation EchoController

- (UILabel *)makeLabelAt:(CGRect)frame size:(CGFloat)size bold:(BOOL)bold alpha:(CGFloat)alpha {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)makeButton:(NSString *)title frame:(CGRect)f tag:(NSInteger)tag action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.65;
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    b.layer.cornerRadius = 10;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UISlider *)makeSliderAt:(CGRect)f min:(float)mn max:(float)mx value:(float)v action:(SEL)a {
    UISlider *s = [[UISlider alloc] initWithFrame:f];
    s.minimumValue = mn;
    s.maximumValue = mx;
    s.continuous = YES;
    s.value = v;
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    return s;
}

- (UISwitch *)addToggleTo:(UIView *)parent title:(NSString *)title x:(CGFloat)x y:(CGFloat)y
                    width:(CGFloat)wd on:(BOOL)on action:(SEL)a {
    UILabel *l = [self makeLabelAt:CGRectMake(x, y, wd - 56, 31) size:14 bold:YES alpha:1];
    l.textAlignment = NSTextAlignmentLeft;
    l.numberOfLines = 1;
    l.adjustsFontSizeToFitWidth = YES;
    l.text = title;
    [parent addSubview:l];
    UISwitch *sw = [[UISwitch alloc] init];
    sw.frame = CGRectMake(x + wd - 51, y, 51, 31);
    sw.on = on;
    [sw addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    [parent addSubview:sw];
    return sw;
}

- (UIScrollView *)makeTab {
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, kTabTop, kPanelW, kPanelH - kTabTop)];
    sv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sv.alwaysBounceVertical = YES;
    sv.delaysContentTouches = NO;
    sv.showsHorizontalScrollIndicator = NO;
    return sv;
}

- (CGFloat)addHeader:(NSString *)text to:(UIView *)parent y:(CGFloat)y {
    UILabel *l = [self makeLabelAt:CGRectMake(16, y, kPanelW - 32, 20) size:13 bold:YES alpha:1];
    l.textColor = [UIColor colorWithRed:0.62 green:0.74 blue:1 alpha:1];
    l.text = text;
    [parent addSubview:l];
    return y + 26;
}

- (CGFloat)addHint:(NSString *)text to:(UIView *)parent y:(CGFloat)y height:(CGFloat)h {
    UILabel *l = [self makeLabelAt:CGRectMake(16, y, kPanelW - 32, h) size:12 bold:NO alpha:0.55];
    l.text = text;
    [parent addSubview:l];
    return y + h + 6;
}

- (CGFloat)addSlider:(int)idx to:(UIView *)parent y:(CGFloat)y {
    const SliderSpec *sp = &kSliders[idx];
    CGFloat w = kPanelW - 32;
    UILabel *l = [self makeLabelAt:CGRectMake(16, y, w, 22) size:14 bold:YES alpha:1];
    UISlider *s = [self makeSliderAt:CGRectMake(16, y + 22, w, 28)
                                 min:sp->min max:sp->max
                               value:EchoInt(sp->key, sp->def)
                              action:@selector(specSliderChanged:)];
    s.tag = idx;
    [parent addSubview:l];
    [parent addSubview:s];
    _lb[idx] = l;
    _sl[idx] = s;
    [self updateSpecLabel:idx];
    return y + 54;
}

- (void)addToggle:(int)idx to:(UIView *)parent x:(CGFloat)x y:(CGFloat)y width:(CGFloat)wd {
    const ToggleSpec *t = &kToggles[idx];
    UISwitch *sw = [self addToggleTo:parent title:t->title x:x y:y width:wd
                                  on:EchoInt(t->key, t->def) != 0
                              action:@selector(specToggled:)];
    sw.tag = idx;
    _sw[idx] = sw;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    int pitch = EchoInt(kPitchKey, 0);
    self.robot = EchoInt(kRobotKey, 0) != 0;
    self.mode = EchoInt(kModeKey, 0);
    CGFloat w = kPanelW - 32;

    UIButton *fab = [UIButton buttonWithType:UIButtonTypeCustom];
    fab.frame = CGRectMake(20, 140, 52, 52);
    fab.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    fab.layer.cornerRadius = 26;
    fab.layer.borderWidth = 1;
    fab.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    [fab setTitle:@"🎙" forState:UIControlStateNormal];
    fab.titleLabel.font = [UIFont systemFontOfSize:24];
    [fab addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFab:)];
    [fab addGestureRecognizer:pan];
    [self.view addSubview:fab];
    self.fab = fab;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPanelW, kPanelH)];
    panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.95];
    panel.layer.cornerRadius = 16;
    panel.clipsToBounds = YES;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"الصدى", @"الموازن", @"النبرة", @"المايك", @"🎵"]];
    tabs.frame = CGRectMake(16, 12, kPanelW - 32, 34);
    tabs.selectedSegmentIndex = 0;
    tabs.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    NSDictionary *white = @{ NSForegroundColorAttributeName: UIColor.whiteColor,
                             NSFontAttributeName: [UIFont boldSystemFontOfSize:12] };
    [tabs setTitleTextAttributes:white forState:UIControlStateNormal];
    [tabs setTitleTextAttributes:white forState:UIControlStateSelected];
    [tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:tabs];
    self.tabs = tabs;

    UIScrollView *tabEcho  = [self makeTab];
    UIScrollView *tabEq    = [self makeTab];
    UIScrollView *tabPitch = [self makeTab];
    UIScrollView *tabAmp   = [self makeTab];
    UIScrollView *tabMusic = [self makeTab];
    self.tabViews = @[tabEcho, tabEq, tabPitch, tabAmp, tabMusic];
    for (UIView *v in self.tabViews) { [panel addSubview:v]; v.hidden = (v != tabEcho); }

    CGFloat y;

    // تبويب الصدى
    y = 4;
    y = [self addHeader:@"نوع الصدى (كل واحد لحاله)" to:tabEcho y:y];
    NSArray *modeNames = @[@"👻 كهف مسكون", @"ديلاي", @"ديلاي شريط", @"غرفة", @"قاعة", @"ستاديوم", @"فضاء"];
    CGFloat mbw = (w - 16) / 3.0;
    NSMutableArray *mb = [NSMutableArray array];
    for (NSInteger i = 0; i < 7; i++) {
        NSInteger col = i % 3, row = i / 3;
        UIButton *b = [self makeButton:modeNames[i]
                                 frame:CGRectMake(16 + col * (mbw + 8), y + row * 40, mbw, 32)
                                   tag:i action:@selector(modeTapped:)];
        [tabEcho addSubview:b];
        [mb addObject:b];
    }
    self.modeBtns = mb;
    y += 3 * 40 + 2;
    y = [self addHint:@"«كهف مسكون» = كهف + تكرار مبعثر حسب الأزرار والأشرطة تحت." to:tabEcho y:y height:48];

    CGFloat tw = (w - 12) / 2.0;
    [self addToggle:T_CAVE   to:tabEcho x:16 y:y width:tw];
    [self addToggle:T_REPEAT to:tabEcho x:16 + tw + 12 y:y width:tw];
    y += 40;

    y = [self addHeader:@"🔊 عام" to:tabEcho y:y];
    y = [self addSlider:S_LEVEL to:tabEcho y:y];
    y = [self addSlider:S_BOOST to:tabEcho y:y];
    y = [self addSlider:S_RANGE to:tabEcho y:y];

    y = [self addHeader:@"👻 الكهف" to:tabEcho y:y];
    y = [self addSlider:S_CAVEAMT to:tabEcho y:y];
    y = [self addSlider:S_DAMP to:tabEcho y:y];
    y = [self addSlider:S_MOD to:tabEcho y:y];

    y = [self addHeader:@"🔁 التكرار المبعثر (Multi-Tap)" to:tabEcho y:y];
    y = [self addSlider:S_REPAMT to:tabEcho y:y];
    y = [self addSlider:S_TAPSPEED to:tabEcho y:y];
    y = [self addSlider:S_TAPFB to:tabEcho y:y];
    y = [self addSlider:S_TAPSCAT to:tabEcho y:y];

    y = [self addHint:@"تردد التكرار والتبعثر." to:tabEcho y:y height:48];
    [tabEcho addSubview:[self makeButton:@"↺ رجّع إعدادات الصدى الافتراضية"
                                   frame:CGRectMake(16, y, w, 34) tag:0 action:@selector(resetEcho)]];
    y += 34 + 16;
    tabEcho.contentSize = CGSizeMake(kPanelW, y);

    // تبويب الموازن
    y = 4;
    y = [self addHeader:@"موازن ترددات الصدى" to:tabEq y:y];
    CGFloat ebw = (w - 4 * 6) / 5.0;
    for (NSInteger i = 0; i < 5; i++) {
        [tabEq addSubview:[self makeButton:kEqPresetNames[i]
                                     frame:CGRectMake(16 + i * (ebw + 6), y, ebw, 32)
                                       tag:i action:@selector(eqPresetTapped:)]];
    }
    y += 42;
    [tabEq addSubview:[self makeButton:@"🌊 شيل موجة الذيل"
                                 frame:CGRectMake(16, y, w, 32) tag:0 action:@selector(deWaveTapped)]];
    y += 42;
    y = [self addHeader:@"النطاقات" to:tabEq y:y];
    y = [self addSlider:S_EQLOF to:tabEq y:y];
    y = [self addSlider:S_EQHIF to:tabEq y:y];
    y = [self addSlider:S_EQLO to:tabEq y:y];
    y = [self addSlider:S_EQMID to:tabEq y:y];
    y = [self addSlider:S_EQHI to:tabEq y:y];
    tabEq.contentSize = CGSizeMake(kPanelW, y + 10);

    // تبويب النبرة
    self.pitchLabel = [self makeLabelAt:CGRectMake(16, 4, w, 26) size:16 bold:YES alpha:1];
    [tabPitch addSubview:self.pitchLabel];
    self.pitchSlider = [self makeSliderAt:CGRectMake(16, 32, w, 30) min:-12 max:12 value:pitch action:@selector(pitchChanged:)];
    [tabPitch addSubview:self.pitchSlider];

    NSArray *names = @[@"عادي", @"بنت", @"رجل", @"وحش", @"روبوت", @"🎲 عشوائي"];
    CGFloat pbw = (w - 16) / 3.0;
    for (NSInteger i = 0; i < 6; i++) {
        NSInteger col = i % 3, row = i / 3;
        CGRect f = CGRectMake(16 + col * (pbw + 8), 76 + row * 42, pbw, 34);
        [tabPitch addSubview:[self makeButton:names[i] frame:f tag:i action:@selector(presetTapped:)]];
    }
    [self addHint:@"حرّك الشريط أو اختر نمط جاهز." to:tabPitch y:164 height:40];
    tabPitch.contentSize = CGSizeMake(kPanelW, 230);

    // تبويب المضخّم
    y = 4;
    y = [self addSlider:S_GAIN to:tabAmp y:y];
    NSArray *quickNames = @[@"عادي", @"×2", @"×5", @"×8", @"×12", @"×16"];
    NSArray *quickTags  = @[@100, @200, @500, @800, @1200, @1600];
    CGFloat qbw = (w - 6 * 5) / 6.0;
    for (NSInteger i = 0; i < 6; i++) {
        CGRect f = CGRectMake(16 + i * (qbw + 6), y + 4, qbw, 32);
        [tabAmp addSubview:[self makeButton:quickNames[i] frame:f tag:[quickTags[i] integerValue] action:@selector(gainQuick:)]];
    }
    y += 48;

    UILabel *meterLabel = [self makeLabelAt:CGRectMake(16, y, w, 18) size:13 bold:NO alpha:0.7];
    meterLabel.text = @"مستوى المايك";
    [tabAmp addSubview:meterLabel];
    y += 24;

    UIProgressView *meter = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    meter.frame = CGRectMake(16, y, w, 8);
    meter.trackTintColor = [UIColor colorWithWhite:1 alpha:0.15];
    meter.progressTintColor = [UIColor systemGreenColor];
    [tabAmp addSubview:meter];
    self.meter = meter;
    y += 20;

    self.micStatus = [self makeLabelAt:CGRectMake(16, y, w, 20) size:13 bold:YES alpha:0.9];
    self.micStatus.text = @"🔴 المايك مو شغال";
    self.micStatus.textColor = [UIColor systemOrangeColor];
    [tabAmp addSubview:self.micStatus];
    y += 32;

    y = [self addHeader:@"🎧 أسمع صوتي" to:tabAmp y:y];
    [self addToggle:T_SELFMON to:tabAmp x:16 y:y width:w];
    y += 38;
    y = [self addSlider:S_SELFVOL to:tabAmp y:y];
    self.monWarn = [self makeLabelAt:CGRectMake(16, y, w, 34) size:12 bold:YES alpha:1];
    self.monWarn.textColor = [UIColor systemOrangeColor];
    [tabAmp addSubview:self.monWarn];
    y += 40;

    tabAmp.contentSize = CGSizeMake(kPanelW, y + 10);

    // تبويب الأغاني
    self.songLabel = [self makeLabelAt:CGRectMake(16, 4, w, 34) size:13 bold:YES alpha:1];
    self.songLabel.text = @"ما فيه أغنية. افتح المتصفح أو اختر ملف من جهازك";
    [tabMusic addSubview:self.songLabel];

    CGFloat btnW = (w - 8) / 2.0;
    [tabMusic addSubview:[self makeButton:@"🌐 متصفح" frame:CGRectMake(16, 42, btnW, 36) tag:0 action:@selector(browseSong)]];
    [tabMusic addSubview:[self makeButton:@"📂 ملفات" frame:CGRectMake(16 + btnW + 8, 42, btnW, 36) tag:0 action:@selector(chooseSong)]];

    UISlider *seek = [self makeSliderAt:CGRectMake(16, 86, w, 28) min:0 max:1 value:0 action:@selector(seekChanged:)];
    [seek addTarget:self action:@selector(seekBegan:) forControlEvents:UIControlEventTouchDown];
    [seek addTarget:self action:@selector(seekEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [tabMusic addSubview:seek];
    self.seekSlider = seek;

    self.timeLabel = [self makeLabelAt:CGRectMake(16, 114, w, 18) size:12 bold:NO alpha:0.7];
    self.timeLabel.text = @"0:00 / 0:00";
    [tabMusic addSubview:self.timeLabel];

    CGFloat hb = (w - 8) / 2.0;
    self.playBtn = [self makeButton:@"▶︎ تشغيل" frame:CGRectMake(16, 138, hb, 34) tag:0 action:@selector(playTapped)];
    [tabMusic addSubview:self.playBtn];
    [tabMusic addSubview:[self makeButton:@"⏹ إيقاف" frame:CGRectMake(16 + hb + 8, 138, hb, 34) tag:0 action:@selector(stopTapped)]];

    y = 182;
    y = [self addSlider:S_MUSVOL to:tabMusic y:y];
    [self addToggle:T_LOOP     to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_MUTE     to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_SONGECHO to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_MONITOR  to:tabMusic x:16 y:y width:w]; y += 40;
    y = [self addSlider:S_MONVOL to:tabMusic y:y];
    y = [self addHint:@"🌐 المتصفح: يحتوي على نافذة يوتيوب و Y2Mate لتحميل وتشغيل المقاطع."
                   to:tabMusic y:y height:60];
    tabMusic.contentSize = CGSizeMake(kPanelW, y + 10);

    [self refreshModeButtons];
    [self updatePitchLabel];
}

- (void)updateSpecLabel:(int)idx {
    const SliderSpec *sp = &kSliders[idx];
    int v = (int)lroundf(_sl[idx].value);
    if (v == 0 && sp->zero) _lb[idx].text = sp->zero;
    else _lb[idx].text = [NSString stringWithFormat:@"%@: %d%@", sp->title, v, sp->unit];
}

- (void)updatePitchLabel {
    int st = (int)lroundf(self.pitchSlider.value);
    NSString *t = (st == 0) ? @"النبرة: عادية" : [NSString stringWithFormat:@"النبرة: %+d نغمة", st];
    if (self.robot) t = [t stringByAppendingString:@"  ·  🤖 روبوت"];
    self.pitchLabel.text = t;
}

- (void)tabChanged:(UISegmentedControl *)sender {
    for (NSUInteger i = 0; i < self.tabViews.count; i++)
        self.tabViews[i].hidden = ((NSInteger)i != sender.selectedSegmentIndex);
}

- (void)saveInt:(int)v key:(NSString *)k {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:k];
}

- (void)applySpec:(int)idx value:(int)v {
    const SliderSpec *sp = &kSliders[idx];
    if (v < sp->min) v = sp->min;
    if (v > sp->max) v = sp->max;
    sp->set(v);
    [self saveInt:v key:sp->key];
    [self updateSpecLabel:idx];
}

- (void)specSliderChanged:(UISlider *)s {
    [self applySpec:(int)s.tag value:(int)lroundf(s.value)];
}

- (void)setSpec:(int)idx to:(int)v {
    _sl[idx].value = v;
    [self applySpec:idx value:v];
}

- (void)setToggle:(int)idx on:(BOOL)on {
    const ToggleSpec *t = &kToggles[idx];
    _sw[idx].on = on;
    t->set(on ? 1 : 0);
    [self saveInt:on ? 1 : 0 key:t->key];
}

- (void)specToggled:(UISwitch *)s {
    const ToggleSpec *t = &kToggles[s.tag];
    t->set(s.on ? 1 : 0);
    [self saveInt:s.on ? 1 : 0 key:t->key];
}

- (void)refreshModeButtons {
    for (UIButton *b in self.modeBtns) {
        b.backgroundColor = (b.tag == self.mode)
            ? [UIColor colorWithRed:0.33 green:0.42 blue:1 alpha:0.95]
            : [UIColor colorWithWhite:1 alpha:0.14];
    }
}

- (void)applyMode:(NSInteger)m {
    self.mode = m;
    DiscordEcho_SetMode((int)m);
    [self saveInt:(int)m key:kModeKey];
    [self refreshModeButtons];
}

- (void)modeTapped:(UIButton *)b { [self applyMode:b.tag]; }

- (void)resetEcho {
    for (int i = S_LEVEL; i <= S_EQHI; i++) [self setSpec:i to:kSliders[i].def];
    [self setToggle:T_CAVE on:kToggles[T_CAVE].def != 0];
    [self setToggle:T_REPEAT on:kToggles[T_REPEAT].def != 0];
    [self applyMode:0];
}

- (void)applyEqPreset:(NSInteger)i {
    static const int idx[5] = { S_EQLOF, S_EQHIF, S_EQLO, S_EQMID, S_EQHI };
    for (int k = 0; k < 5; k++) [self setSpec:idx[k] to:kEqPresets[i][k]];
}
- (void)eqPresetTapped:(UIButton *)b { [self applyEqPreset:b.tag]; }
- (void)deWaveTapped {
    [self applyEqPreset:2];
    [self setSpec:S_MOD to:20];
    [self setSpec:S_DAMP to:65];
}

- (void)applyPitch:(int)st robot:(BOOL)robot {
    if (st < -12) st = -12;
    if (st > 12) st = 12;
    self.pitchSlider.value = st;
    self.robot = robot;
    DiscordEcho_SetPitch(st);
    DiscordEcho_SetRobot(robot ? 1 : 0);
    [self saveInt:st key:kPitchKey];
    [self saveInt:robot ? 1 : 0 key:kRobotKey];
    [self updatePitchLabel];
}
- (void)pitchChanged:(UISlider *)s { [self applyPitch:(int)lroundf(s.value) robot:self.robot]; }
- (void)presetTapped:(UIButton *)b {
    switch (b.tag) {
        case 0: [self applyPitch:0  robot:NO];  break;
        case 1: [self applyPitch:5  robot:NO];  break;
        case 2: [self applyPitch:-4 robot:NO];  break;
        case 3: [self applyPitch:-9 robot:NO];  break;
        case 4: [self applyPitch:0  robot:YES]; break;
        default: {
            int st = (int)arc4random_uniform(21) - 10;
            [self applyPitch:st robot:(arc4random_uniform(4) == 0)];
        }
    }
}

- (void)gainQuick:(UIButton *)b { [self setSpec:S_GAIN to:(int)b.tag]; }

- (void)chooseSong {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"]
                                                               inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) [self loadSongAtURL:url name:url.lastPathComponent cleanup:NO];
}

- (void)browseSong {
    EchoBrowserController *vc = [EchoBrowserController new];
    __weak EchoController *ws = self;
    vc.onPick = ^(NSURL *url, NSString *name) { [ws loadSongAtURL:url name:name cleanup:YES]; };
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)loadSongAtURL:(NSURL *)url name:(NSString *)name cleanup:(BOOL)cleanup {
    DiscordEcho_MusicPlay(0);
    self.songLabel.text = [NSString stringWithFormat:@"⏳ جاري التحميل: %@", name];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        size_t count = 0;
        BOOL truncated = NO;
        float *buf = EchoDecodeFile(url, &count, &truncated, ^(float p) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.songLabel.text = [NSString stringWithFormat:@"⏳ فك الأغنية %d%%: %@", (int)(p * 100), name];
            });
        });
        if (cleanup) [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!buf) {
                self.songLabel.text = @"❌ ما قدرت أقرأ الملف. جرّب mp3 أو m4a أو wav";
                return;
            }
            DiscordEcho_MusicLoad(buf, count);
            NSString *t = [NSString stringWithFormat:@"🎵 %@", name];
            if (truncated) t = [t stringByAppendingString:@" (أول 8 دقايق بس)"];
            self.songLabel.text = t;
            [self refreshMusicUI];
        });
    });
}

- (void)refreshMusicUI {
    float dur = DiscordEcho_MusicDuration();
    float prog = DiscordEcho_MusicProgress();
    if (!self.seeking) self.seekSlider.value = prog;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", EchoTime(prog * dur), EchoTime(dur)];
    [self.playBtn setTitle:(DiscordEcho_MusicIsPlaying() ? @"⏸ إيقاف مؤقت" : @"▶︎ تشغيل") forState:UIControlStateNormal];
}

- (void)playTapped {
    DiscordEcho_MusicPlay(DiscordEcho_MusicIsPlaying() ? 0 : 1);
    [self refreshMusicUI];
}
- (void)stopTapped {
    DiscordEcho_MusicStop();
    self.seekSlider.value = 0;
    [self refreshMusicUI];
}
- (void)seekBegan:(UISlider *)s { self.seeking = YES; }
- (void)seekChanged:(UISlider *)s {
    float dur = DiscordEcho_MusicDuration();
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", EchoTime(s.value * dur), EchoTime(dur)];
}
- (void)seekEnded:(UISlider *)s {
    DiscordEcho_MusicSeek(s.value);
    self.seeking = NO;
}

- (void)startTimer {
    if (self.timer) return;
    __weak EchoController *ws = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
        EchoController *s = ws;
        if (!s || s.panel.hidden) return;
        NSInteger tab = s.tabs.selectedSegmentIndex;
        if (tab == TAB_AMP) {
            float pk = DiscordEcho_GetPeak();
            if (pk > 1.0f) pk = 1.0f;
            s.meter.progress = pk;
            s.meter.progressTintColor = (pk > 0.98f) ? [UIColor systemRedColor]
                                      : (pk > 0.8f)  ? [UIColor systemOrangeColor]
                                                     : [UIColor systemGreenColor];
            unsigned c = DiscordEcho_RenderCount();
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            if (c != s.lastRender) { s.lastRender = c; s.lastRenderTime = now; }
            BOOL live = (c != 0) && (now - s.lastRenderTime) < 0.6;
            s.micStatus.text = live ? @"🟢 المايك شغال" : @"🔴 المايك مو شغال";
            s.micStatus.textColor = live ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
            BOOL selfOn = s->_sw[T_SELFMON].on;
            s.monWarn.text = (selfOn && !echo_headphones()) ? @"⚠️ وصّل سماعات لمنع الصفير" : @"";
        } else if (tab == TAB_MUSIC) {
            [s refreshMusicUI];
        }
    }];
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (self.panel.hidden) {
        [self stopTimer];
    } else {
        [self positionPanel];
        [self startTimer];
    }
}

- (void)positionPanel {
    CGRect b = self.view.bounds;
    CGFloat w = kPanelW;
    CGFloat h = MIN(kPanelH, b.size.height - 20);
    CGFloat x = CGRectGetMidX(self.fab.frame) - w / 2;
    x = MAX(10, MIN(x, b.size.width - w - 10));
    CGFloat y = CGRectGetMaxY(self.fab.frame) + 10;
    if (y + h > b.size.height - 10) y = CGRectGetMinY(self.fab.frame) - h - 10;
    y = MAX(10, y);
    self.panel.frame = CGRectMake(x, y, w, h);
}

- (void)dragFab:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.view];
    self.fab.center = CGPointMake(self.fab.center.x + t.x, self.fab.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.view];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

- (void)clampFab {
    CGRect b = self.view.bounds;
    UIEdgeInsets s = self.view.safeAreaInsets;
    CGFloat r = 26;
    CGPoint c = self.fab.center;
    c.x = MAX(r + s.left, MIN(c.x, b.size.width - r - s.right));
    c.y = MAX(r + s.top,  MIN(c.y, b.size.height - r - s.bottom));
    self.fab.center = c;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self clampFab];
    if (!self.panel.hidden) [self positionPanel];
}

@end

static EchoWindow *gWin;

static void echo_setup_window(void) {
    if (gWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;
    gWin = [[EchoWindow alloc] initWithWindowScene:scene];
    gWin.windowLevel = UIWindowLevelAlert + 100;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [EchoController new];
    gWin.hidden = NO;
}

static void echo_apply_saved(void) {
    for (int i = 0; i < S_COUNT; i++)
        kSliders[i].set(EchoInt(kSliders[i].key, kSliders[i].def));
    for (int i = 0; i < T_COUNT; i++)
        kToggles[i].set(EchoInt(kToggles[i].key, kToggles[i].def));
    DiscordEcho_SetMode(EchoInt(kModeKey, 0));
    DiscordEcho_SetPitch(EchoInt(kPitchKey, 0));
    DiscordEcho_SetRobot(EchoInt(kRobotKey, 0));
}

__attribute__((constructor))
static void echo_ui_init(void) {
    echo_apply_saved();

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        gAppReady = YES;
        echo_setup_window();
        echo_monitor_sync();
    }];
    [nc addObserverForName:AVAudioEngineConfigurationChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        if (echo_mon_wanted() && n.object == gMonEngine) {
            echo_monitor_stop();
            echo_monitor_sync();
        }
    }];
}
