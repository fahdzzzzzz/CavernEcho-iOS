// DiscordEchoUI: قائمة عائمة + متصفح يوتيوب مباشر يلقط الصوت ويدمجه بالمايك ليديسكورد

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
extern void  DiscordEcho_ResetAll(void);

static NSString *const kEchoAppName = @"DiscordEcho";

static NSString *const kModeKey  = @"DiscordEchoMode";
static NSString *const kPitchKey = @"DiscordEchoPitch";
static NSString *const kRobotKey = @"DiscordEchoRobot";

static const CGFloat kPanelW = 340;
static const CGFloat kPanelH = 460;
static const CGFloat kTabTop = 56;

enum { TAB_ECHO = 0, TAB_EQ, TAB_PITCH, TAB_AMP, TAB_MUSIC };

static int EchoInt(NSString *key, int def) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d objectForKey:key] ? (int)[d integerForKey:key] : def;
}

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
    [S_RANGE]    = { @"مدى الصدى",             @"",     @"DiscordEchoRange",   0, 100,  60, DiscordEcho_SetRange,         nil },
    [S_CAVEAMT]  = { @"شدة الكهف",             @"",     @"DiscordEchoCaveAmt", 0, 100, 100, DiscordEcho_SetCaveAmount,    nil },
    [S_DAMP]     = { @"تغميق الذيل",           @"",     @"DiscordEchoDamp",    0, 100,  40, DiscordEcho_SetDamp,          nil },
    [S_MOD]      = { @"تنعيم الموجة",          @"",     @"DiscordEchoMod",     0, 100,  50, DiscordEcho_SetMod,           nil },
    [S_REPAMT]   = { @"شدة التكرار",           @"",     @"DiscordEchoRepAmt",  0, 100, 100, DiscordEcho_SetRepeatAmount,  nil },
    [S_TAPSPEED] = { @"تردد التكرار",          @"%",    @"DiscordEchoTapSpeed", 50, 300, 100, DiscordEcho_SetTapSpeed,     nil },
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
    NSArray *outs = AVAudioSession.sharedInstance.currentRoute.outputs;
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
        if (st == AVAudioConverterOutputStatus_EndOfStream ||
            st == AVAudioConverterOutputStatus_InputRanDry) finished = YES;

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

#pragma mark - نافذة شفافة

@interface EchoWindow : UIWindow
@end

@implementation EchoWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;
    return v;
}
@end

#pragma mark - متصفح اليوتيوب المباشر (يكتشف الفيديو ويحوله للأداة)

@interface EchoBrowserController : UIViewController <WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate>
@property (nonatomic, copy) void (^onPick)(NSURL *fileURL, NSString *name);
@property (nonatomic, strong) NSMutableArray *tabs;
@property (nonatomic) NSInteger cur;
@property (nonatomic, strong) UIScrollView *tabBar;
@property (nonatomic, strong) UITextField *addr;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) NSArray *quick;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSMutableDictionary *dests;
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
    self.addr.placeholder = @"ابحث في يوتيوب أو الصق الرابط هنا";
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
    NSArray *names = @[@"📺 يوتيوب", @"Pixabay", @"Archive"];
    for (NSInteger i = 0; i < 3; i++) {
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
    self.status.text = @"اضغط أي فيديو في يوتيوب، وبجيبه لك للأداة تلقائياً.";
    [self.view addSubview:self.status];

    [self openTabWithConfig:nil];
    [self loadText:@"https://www.youtube.com"];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat top = 10;
    self.backBtn.frame = CGRectMake(12, top, 84, 34);
    self.closeBtn.frame = CGRectMake(b.size.width - 96, top, 84, 34);
    CGFloat qx = 104, qw = (b.size.width - 104 - 104 - 12) / 3.0;
    for (NSInteger i = 0; i < 3; i++) ((UIView *)self.quick[i]).frame = CGRectMake(qx + i * (qw + 6), top, qw, 34);
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
    for (NSInteger k = 0; k < (NSInteger)self.tabs.count; k++) ((WKWebView *)self.tabs[k]).hidden = (k != i);
    NSURL *u = self.web.URL;
    self.addr.text = u ? u.absoluteString : @"";
    [self refreshTabBar];
}

- (void)refreshTabBar {
    for (UIView *v in self.tabBar.subviews) [v removeFromSuperview];
    CGFloat x = 8;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        NSString *t = ((WKWebView *)self.tabs[i]).title;
        if (t.length == 0) t = @"يوتيوب";
        if (t.length > 14) t = [[t substringToIndex:14] stringByAppendingString:@"…"];
        UIButton *b = [self pill:t action:@selector(tabTapped:) tag:i];
        b.frame = CGRectMake(x, 0, 104, 32);
        if (i == self.cur) b.backgroundColor = [UIColor colorWithRed:0.33 green:0.42 blue:1 alpha:0.95];
        [self.tabBar addSubview:b];
        x += 110;
    }
    UIButton *add = [self pill:@"＋ تبويب" action:@selector(addTabTapped) tag:0];
    add.frame = CGRectMake(x, 0, 78, 32);
    [self.tabBar addSubview:add];
    x += 84;
    UIButton *del = [self pill:@"🗑 إغلاق" action:@selector(closeTabTapped) tag:0];
    del.frame = CGRectMake(x, 0, 78, 32);
    [self.tabBar addSubview:del];
    x += 84;
    self.tabBar.contentSize = CGSizeMake(x + 8, 34);
}

- (void)tabTapped:(UIButton *)b { [self selectTab:b.tag]; }
- (void)addTabTapped { [self openTabWithConfig:nil]; [self loadText:@"https://www.youtube.com"]; }
- (void)closeTabTapped {
    if (self.tabs.count <= 1) { self.status.text = @"هذه آخر نافذة."; return; }
    WKWebView *w = self.web;
    [w stopLoading];
    [w removeFromSuperview];
    [self.tabs removeObjectAtIndex:self.cur];
    NSInteger n = self.cur >= (NSInteger)self.tabs.count ? (NSInteger)self.tabs.count - 1 : self.cur;
    [self selectTab:n];
}

- (WKWebView *)webView:(WKWebView *)wv createWebViewWithConfiguration:(WKWebViewConfiguration *)cfg
   forNavigationAction:(WKNavigationAction *)a windowFeatures:(WKWindowFeatures *)f {
    return [self openTabWithConfig:cfg];
}

- (void)closeTapped {
    for (WKWebView *w in self.tabs) [w stopLoading];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)backTapped { if (self.web.canGoBack) [self.web goBack]; }

- (void)quickTapped:(UIButton *)b {
    NSArray *urls = @[@"https://www.youtube.com", @"https://pixabay.com/music/", @"https://archive.org/details/audio"];
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

// اعتراض روابط يوتيوب وسحب الصوت تلقائياً عند دخول الفيديو
- (void)webView:(WKWebView *)wv decidePolicyForNavigationAction:(WKNavigationAction *)a decisionHandler:(void (^)(WKNavigationActionPolicy))h {
    NSURL *url = a.request.URL;
    NSString *urlString = url.absoluteString;
    
    // إذا دخل المستخدم على فيديو في يوتيوب
    if ([urlString containsString:@"youtube.com/watch?v="] || [urlString containsString:@"youtu.be/"]) {
        NSString *videoId = nil;
        if ([urlString containsString:@"youtu.be/"]) {
            NSArray *parts = [urlString componentsSeparatedByString:@"youtu.be/"];
            if (parts.count > 1) videoId = [[parts[1] componentsSeparatedByString:@"?"] firstObject];
        } else {
            NSArray *parts = [urlString componentsSeparatedByString:@"v="];
            if (parts.count > 1) videoId = [[parts[1] componentsSeparatedByString:@"&"] firstObject];
        }
        
        if (videoId && videoId.length > 0) {
            self.status.text = @"⏳ جاري جلب الصوت من يوتيوب وتشغيله…";
            [self fetchAndPlayYouTubeVideo:videoId];
            h(WKNavigationActionPolicyCancel); // نمنع فتح صفحة الفيديو الثقيلة ونشغل الصوت مباشرة للأداة
            return;
        }
    }
    h(WKNavigationActionPolicyAllow);
}

- (void)fetchAndPlayYouTubeVideo:(NSString *)videoId {
    NSString *api = [NSString stringWithFormat:@"https://pipedapi.kavin.rocks/streams/%@", videoId];
    __weak EchoBrowserController *ws = self;
    NSURLSessionDataTask *t = [NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:api]
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        if (e) return;
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        NSString *streamUrl = nil;
        NSString *title = @"فيديو يوتيوب";
        if ([j isKindOfClass:NSDictionary.class]) {
            title = j[@"title"] ?: @"فيديو يوتيوب";
            NSArray *audioStreams = j[@"audioStreams"];
            if ([audioStreams isKindOfClass:NSArray.class] && audioStreams.count > 0) {
                streamUrl = audioStreams.firstObject[@"url"];
            }
        }
        
        if (!streamUrl) {
            // سيرفر بديل للاستخراج
            dispatch_async(dispatch_get_main_queue(), ^{
                ws.status.text = @"❌ تعذر استخراج الصوت من هذا الفيديو، جرب غيره.";
            });
            return;
        }
        
        NSURL *audioURL = [NSURL URLWithString:streamUrl];
        NSURLSessionDownloadTask *dt = [NSURLSession.sharedSession downloadTaskWithURL:audioURL
            completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *derr) {
            if (!loc || derr) return;
            NSString *fn = [NSString stringWithFormat:@"echo_%u.m4a", arc4random()];
            NSURL *dest = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fn]];
            [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
            if ([[NSFileManager defaultManager] moveItemAtURL:loc toURL:dest error:nil]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    ws.status.text = [NSString stringWithFormat:@"✅ شغال الآن: %@", title];
                    void (^cb)(NSURL *, NSString *) = ws.onPick;
                    [ws dismissViewControllerAnimated:YES completion:^{ if (cb) cb(dest, title); }];
                });
            }
        }];
        [dt resume];
    }];
    [t resume];
}

- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)n {
    if (wv == self.web && wv.URL) self.addr.text = wv.URL.absoluteString;
    [self refreshTabBar];
}
@end

#pragma mark - محرك البحث الاحتياطي

@interface EchoSearchController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, copy) void (^onPick)(NSURL *fileURL, NSString *name);
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) UISegmentedControl *src;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) NSURLSessionTask *task;
@end

@implementation EchoSearchController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeBtn setTitle:@"✕ إغلاق" forState:UIControlStateNormal];
    [self.closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeBtn];
    self.src = [[UISegmentedControl alloc] initWithItems:@[@"🎵 مشاهير", @"🆓 Archive", @"Audius", @"📺 يوتيوب"]];
    self.src.selectedSegmentIndex = 3;
    self.src.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    [self.view addSubview:self.src];
    self.bar = [[UISearchBar alloc] init];
    self.bar.placeholder = @"🔍 ابحث باسم الأغنية";
    self.bar.delegate = self;
    [self.view addSubview:self.bar];
    self.status = [[UILabel alloc] init];
    self.status.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    [self.view addSubview:self.status];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.closeBtn.frame = CGRectMake(b.size.width - 96, 10, 84, 34);
    self.src.frame = CGRectMake(16, 48, b.size.width - 32, 32);
    self.bar.frame = CGRectMake(8, 84, b.size.width - 16, 50);
    self.status.frame = CGRectMake(16, 136, b.size.width - 32, 38);
    self.table.frame = CGRectMake(0, 178, b.size.width, b.size.height - 178);
}
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return 0; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip { return [UITableViewCell new]; }
@end

#pragma mark - الواجهة الرئيسية للأداة

@interface EchoController : UIViewController <UIDocumentPickerDelegate> {
    UISlider *_sl[S_COUNT];
    UILabel  *_lb[S_COUNT];
    UISwitch *_sw[T_COUNT];
}
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) NSArray *tabViews;
@property (nonatomic, strong) NSArray *modeBtns;
@property (nonatomic) NSInteger mode;
@property (nonatomic, strong) UILabel *pitchLabel;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic) BOOL robot;
@property (nonatomic, strong) UIProgressView *meter;
@property (nonatomic, strong) UILabel *micStatus;
@property (nonatomic, strong) UILabel *monWarn;
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
    return l;
}

- (UIButton *)makeButton:(NSString *)title frame:(CGRect)f tag:(NSInteger)tag action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    b.tag = tag;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
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

- (UISwitch *)addToggleTo:(UIView *)parent title:(NSString *)title x:(CGFloat)x y:(CGFloat)y width:(CGFloat)wd on:(BOOL)on action:(SEL)a {
    UILabel *l = [self makeLabelAt:CGRectMake(x, y, wd - 56, 31) size:14 bold:YES alpha:1];
    l.textAlignment = NSTextAlignmentLeft;
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
    sv.alwaysBounceVertical = YES;
    return sv;
}

- (CGFloat)addHeader:(NSString *)text to:(UIView *)parent y:(CGFloat)y {
    UILabel *l = [self makeLabelAt:CGRectMake(16, y, kPanelW - 32, 20) size:13 bold:YES alpha:1];
    l.textColor = [UIColor colorWithRed:0.62 green:0.74 blue:1 alpha:1];
    l.text = text;
    [parent addSubview:l];
    return y + 26;
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
    tabs.selectedSegmentIndex = 4; // نبدأ بتبويب الأغاني مباشرة لسرعة التشغيل
    tabs.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.28];
    [tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:tabs];
    self.tabs = tabs;

    UIScrollView *tabEcho  = [self makeTab];
    UIScrollView *tabEq    = [self makeTab];
    UIScrollView *tabPitch = [self makeTab];
    UIScrollView *tabAmp   = [self makeTab];
    UIScrollView *tabMusic = [self makeTab];
    self.tabViews = @[tabEcho, tabEq, tabPitch, tabAmp, tabMusic];
    for (UIView *v in (NSArray *)self.tabViews) { [panel addSubview:v]; v.hidden = (v != tabMusic); }

    // تبويب الأغاني
    CGFloat y = 4;
    self.songLabel = [self makeLabelAt:CGRectMake(16, y, w, 34) size:13 bold:YES alpha:1];
    self.songLabel.text = @"اختر مقطعاً من متصفح يوتيوب لتشغيله للشباب";
    [tabMusic addSubview:self.songLabel];
    y += 38;

    [tabMusic addSubview:[self makeButton:@"🌐 فتح متصفح يوتيوب" frame:CGRectMake(16, y, w, 38) tag:0 action:@selector(browseSong)]];
    y += 46;

    UISlider *seek = [self makeSliderAt:CGRectMake(16, y, w, 28) min:0 max:1 value:0 action:@selector(seekChanged:)];
    [seek addTarget:self action:@selector(seekBegan:) forControlEvents:UIControlEventTouchDown];
    [seek addTarget:self action:@selector(seekEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [tabMusic addSubview:seek];
    self.seekSlider = seek;
    y += 32;

    self.timeLabel = [self makeLabelAt:CGRectMake(16, y, w, 18) size:12 bold:NO alpha:0.7];
    self.timeLabel.text = @"0:00 / 0:00";
    [tabMusic addSubview:self.timeLabel];
    y += 24;

    CGFloat hb = (w - 8) / 2.0;
    self.playBtn = [self makeButton:@"▶︎ تشغيل" frame:CGRectMake(16, y, hb, 36) tag:0 action:@selector(playTapped)];
    [tabMusic addSubview:self.playBtn];
    [tabMusic addSubview:[self makeButton:@"⏹ إيقاف" frame:CGRectMake(16 + hb + 8, y, hb, 36) tag:0 action:@selector(stopTapped)]];
    y += 44;

    y = [self addSlider:S_MUSVOL to:tabMusic y:y];
    [self addToggle:T_LOOP     to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_MUTE     to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_SONGECHO to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_MONITOR  to:tabMusic x:16 y:y width:w]; y += 40;
    y = [self addSlider:S_MONVOL to:tabMusic y:y];
    tabMusic.contentSize = CGSizeMake(kPanelW, y + 10);
}

- (void)updateSpecLabel:(int)idx {
    const SliderSpec *sp = &kSliders[idx];
    int v = (int)lroundf(_sl[idx].value);
    if (v == 0 && sp->zero) _lb[idx].text = sp->zero;
    else _lb[idx].text = [NSString stringWithFormat:@"%@: %d%@", sp->title, v, sp->unit];
}

- (void)tabChanged:(UISegmentedControl *)sender {
    for (NSUInteger i = 0; i < ((NSArray *)self.tabViews).count; i++)
        ((UIView *)self.tabViews[i]).hidden = ((NSInteger)i != sender.selectedSegmentIndex);
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

- (void)browseSong {
    EchoBrowserController *vc = [EchoBrowserController new];
    __weak EchoController *ws = self;
    vc.onPick = ^(NSURL *url, NSString *name) { [ws loadSongAtURL:url name:name]; };
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)loadSongAtURL:(NSURL *)url name:(NSString *)name {
    DiscordEcho_MusicPlay(0);
    self.songLabel.text = [NSString stringWithFormat:@"⏳ جاري تحويل وتحميل: %@", name];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        size_t count = 0;
        BOOL truncated = NO;
        float *buf = EchoDecodeFile(url, &count, &truncated, nil);
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!buf) {
                self.songLabel.text = @"❌ فشل تحميل المقطع";
                return;
            }
            DiscordEcho_MusicLoad(buf, count);
            self.songLabel.text = [NSString stringWithFormat:@"🎵 شغال: %@", name];
            [self refreshMusicUI];
        });
    });
}

- (void)refreshMusicUI {
    float dur = DiscordEcho_MusicDuration();
    float prog = DiscordEcho_MusicProgress();
    if (!self.seeking) self.seekSlider.value = prog;
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", EchoTime(prog * dur), EchoTime(dur)];
    [self.playBtn setTitle:(DiscordEcho_MusicIsPlaying() ? @"⏸ إيقاف" : @"▶︎ تشغيل") forState:UIControlStateNormal];
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

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    if (!self.panel.hidden) {
        CGRect b = self.view.bounds;
        CGFloat w = kPanelW, h = MIN(kPanelH, b.size.height - 20);
        self.panel.frame = CGRectMake((b.size.width - w)/2, (b.size.height - h)/2, w, h);
    }
}
@end

static EchoWindow *gWin;
static void echo_setup_window(void) {
    if (gWin) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    }
    if (!scene) return;
    gWin = [[EchoWindow alloc] initWithWindowScene:scene];
    gWin.windowLevel = UIWindowLevelAlert + 100;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [EchoController new];
    gWin.hidden = NO;
}

__attribute__((constructor))
static void echo_ui_init(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        gAppReady = YES; echo_setup_window(); echo_monitor_sync();
    }];
}
