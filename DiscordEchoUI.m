// DiscordEchoUI: قائمة عائمة بخمس تبويبات: الصدى، الموازن، النبرة، المضخّم، الأغاني
// زر 🎙 تسحبه في الشاشة، والضغط عليه يفتح القائمة.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <CoreImage/CoreImage.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <PhotosUI/PhotosUI.h>
#import <Vision/Vision.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// ربط المكتبات تلقائياً بدون تعديل ملف البناء
__asm__(".linker_option \"-framework\", \"CoreImage\"");
__asm__(".linker_option \"-framework\", \"Vision\"");
__asm__(".linker_option \"-framework\", \"CoreMedia\"");
__asm__(".linker_option \"-framework\", \"CoreVideo\"");
__asm__(".linker_option \"-framework\", \"PhotosUI\"");
__asm__(".linker_option \"-framework\", \"QuartzCore\"");
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
extern void DiscordEcho_SetSongPrivate(int on);
extern void DiscordEcho_SetMonitor(int on);
extern void DiscordEcho_SetMonitorVolume(int v);
extern void DiscordEcho_SetGain(int v);
extern void DiscordEcho_SetPitch(int v);
extern void DiscordEcho_SetRobot(int on);
extern void DiscordEcho_SetVoiceMute(int on);
extern void DiscordEcho_SetMicMuteFast(int on); // التحديث الجديد للتحكم الفوري السريع
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

static NSString *const kModeKey  = @"DiscordEchoMode";
static NSString *const kPitchKey = @"DiscordEchoPitch";
static NSString *const kRobotKey = @"DiscordEchoRobot";
static NSString *const kLastURLKey = @"DiscordEchoLastBrowserURL";
static NSString *const kLastTabKey = @"DiscordEchoLastBrowserTab";
static NSString *const kConverterURL = @"https://yt5s.in/ar270/";

static const CGFloat kPanelW = 340;
static const CGFloat kPanelH = 460;
static const CGFloat kTabTop = 56;

enum { TAB_ECHO = 0, TAB_EQ, TAB_PITCH, TAB_AMP, TAB_MUSIC, TAB_CAM };

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

enum { T_CAVE, T_REPEAT, T_LOOP, T_MUTE, T_SONGECHO, T_PRIVATE, T_MONITOR, T_SELFMON, T_MICMUTE, T_COUNT };

#pragma mark - مراقبة الصوت

static AVAudioEngine *gMonEngine;
static int gMonSong, gMonSelf;
static int echo_mon_wanted(void) { return gMonSong || gMonSelf; }
static BOOL gAppReady;
static NSUInteger gMonRestartGen;
static BOOL gMonSuspended;

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
    if (!gAppReady || gMonSuspended) return;
    if (echo_mon_wanted()) echo_monitor_start();
    else echo_monitor_stop();
}

// يوقف المراقبة ويعيد تشغيلها مرة وحدة بعد ما يهدأ تغيير المسار
static void echo_monitor_restart_later(void) {
    NSUInteger gen = ++gMonRestartGen;
    gMonSuspended = YES;
    echo_monitor_stop();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen != gMonRestartGen) return; // جا تغيير أحدث
        gMonSuspended = NO;
        echo_monitor_sync();
    });
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

static void echo_set_micmute_fast(int on) {
    DiscordEcho_SetMicMuteFast(on);
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
    [T_CAVE]     = { @"كهف 👻",                         @"DiscordEchoCave",     1, DiscordEcho_SetCave },
    [T_REPEAT]   = { @"تكرار 🔁",                       @"DiscordEchoRepeat",   1, DiscordEcho_SetRepeat },
    [T_LOOP]     = { @"🔁 تكرار الأغنية",               @"DiscordEchoMusicLoop", 0, DiscordEcho_MusicSetLoop },
    [T_MUTE]     = { @"🔇 كتم صوتي أثناء الأغنية",      @"DiscordEchoVoiceMute", 0, DiscordEcho_SetVoiceMute },
    [T_SONGECHO] = { @"👻 الصدى على الأغنية",           @"DiscordEchoSongEcho", 1, DiscordEcho_SetSongEcho },
    [T_PRIVATE]  = { @"🤫 اسمعها لحالي (لا تطلع بالمايك)", @"DiscordEchoSongPriv", 0, DiscordEcho_SetSongPrivate },
    [T_MONITOR]  = { @"🎧 أنا أسمع الأغنية",            @"DiscordEchoMonitor",  0, echo_set_monitor },
    [T_SELFMON]  = { @"🎧 أسمع صوتي (مع الصدى)",        @"DiscordEchoSelfMon",  0, echo_set_selfmon },
    [T_MICMUTE]  = { @"🎙️ كتم صوتي (الأغنية تكمل)",         @"DiscordEchoMicMute",  0, echo_set_micmute_fast },
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

#pragma mark - متصفح داخلي (مع حفظ الروابط الحالية لكل نافذة وتحديثها تلقائياً)

@interface EchoBrowserController : UIViewController <WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate>
@property (nonatomic, copy) void (^onPick)(NSURL *fileURL, NSString *name);
@property (nonatomic, strong) NSMutableArray<WKWebView *> *tabs;
@property (nonatomic) NSInteger cur;
@property (nonatomic) BOOL isSplitScreen;
@property (nonatomic, strong) UIScrollView *tabBar;
@property (nonatomic, strong) UITextField *addr;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UIButton *backBtn;
@property (nonatomic, strong) UIButton *splitBtn;
@property (nonatomic, strong) UIButton *mp3Btn;
@property (nonatomic, strong) NSArray<UIButton *> *quick;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSURL *> *dests;
@property (nonatomic) BOOL restoring;
@property (nonatomic, copy) NSString *pendingVideo;
@property (nonatomic, weak) WKWebView *pendingWeb;
@property (nonatomic, weak) WKWebView *autoWeb;
@property (nonatomic) NSInteger autoStep;
@property (nonatomic) NSUInteger autoGen;
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
    self.isSplitScreen = YES;

    self.backBtn = [self pill:@"◀︎ رجوع" action:@selector(backTapped) tag:0];
    self.splitBtn = [self pill:@"🪟 فردي" action:@selector(splitTapped) tag:0];
    self.splitBtn.backgroundColor = [UIColor colorWithRed:0.33 green:0.42 blue:1 alpha:0.95];
    self.closeBtn = [self pill:@"✕ إغلاق" action:@selector(closeTapped) tag:0];
    
    [self.view addSubview:self.backBtn];
    [self.view addSubview:self.splitBtn];
    [self.view addSubview:self.closeBtn];
    self.mp3Btn = [self pill:@"⬇️ MP3" action:@selector(mp3Tapped) tag:0];
    [self.view addSubview:self.mp3Btn];

    self.addr = [[UITextField alloc] init];
    self.addr.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.addr.textColor = UIColor.whiteColor;
    self.addr.layer.cornerRadius = 9;
    self.addr.font = [UIFont systemFontOfSize:14];
    self.addr.placeholder = @"اكتب رابط الموقع أو ابحث في قوقل...";
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
    NSArray *names = @[@"YouTube", @"YT5s"];
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
    self.status.text = @"متصفح متعدد النوافذ يدعم الحفظ التلقائي لكل تبويب بكل سلاسة.";
    [self.view addSubview:self.status];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *savedURLs = [defaults arrayForKey:@"DiscordEchoBrowserTabsURLs"];
    
    NSInteger savedIndex = [defaults integerForKey:kLastTabKey];
    self.restoring = YES;

    if (savedURLs.count > 0) {
        for (NSString *urlString in savedURLs) {
            WKWebView *w = [self openTabWithConfig:nil];
            NSURL *u = [NSURL URLWithString:urlString];
            if (u) [w loadRequest:[NSURLRequest requestWithURL:u]];
        }
    } else {
        [self openTabWithConfig:nil];
        [self loadText:@"https://www.youtube.com"];

        [self openTabWithConfig:nil];
        [self loadText:kConverterURL];
        savedIndex = 0;
    }

    self.restoring = NO;
    if (savedIndex < 0 || savedIndex >= (NSInteger)self.tabs.count) savedIndex = 0;
    [self selectTab:savedIndex];
    [self saveCurrentTabsState];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(saveCurrentTabsState)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(silenceTabs)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(resumeAllowed)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)saveCurrentTabsState {
    if (self.restoring) return;
    NSMutableArray *urlsArray = [NSMutableArray array];
    for (WKWebView *w in self.tabs) {
        if (w.URL && w.URL.absoluteString.length > 0) {
            [urlsArray addObject:w.URL.absoluteString];
        } else {
            [urlsArray addObject:@"https://www.google.com"];
        }
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:urlsArray forKey:@"DiscordEchoBrowserTabsURLs"];
    [d setInteger:self.cur forKey:kLastTabKey];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (![keyPath isEqualToString:@"URL"]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (object == self.web && self.web.URL && !self.addr.isFirstResponder)
        self.addr.text = self.web.URL.absoluteString;
    [self saveCurrentTabsState];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)wv {
    [wv reload];
}

#pragma mark - زر MP3

- (BOOL)isVideoURL:(NSURL *)u {
    NSString *h = u.host.lowercaseString;
    if ([h isEqualToString:@"youtu.be"]) return u.path.length > 1;
    if (![h isEqualToString:@"youtube.com"] && ![h hasSuffix:@".youtube.com"]) return NO;
    return [u.path isEqualToString:@"/watch"] || [u.path hasPrefix:@"/shorts/"];
}

- (void)mp3Tapped {
    NSURL *video = [self isVideoURL:self.web.URL] ? self.web.URL : nil;
    for (WKWebView *w in self.tabs) {
        if (!video && [self isVideoURL:w.URL]) video = w.URL;
    }
    if (!video) { self.status.text = @"افتح فيديو في يوتيوب أول، وبعدين اضغط ⬇️ MP3"; return; }

    NSString *host = [NSURL URLWithString:kConverterURL].host;
    NSInteger target = -1;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        if ([self.tabs[i].URL.host isEqualToString:host]) { target = i; break; }
    }
    if (target < 0) [self openTabWithConfig:nil];
    else [self selectTab:target];

    [self stopAuto];
    self.pendingVideo = video.absoluteString;
    self.pendingWeb = self.web;
    UIPasteboard.generalPasteboard.string = self.pendingVideo;
    self.status.text = @"⏳ أفتح موقع التحويل وأحط الرابط…";
    [self loadText:kConverterURL];
}

#pragma mark - التنزيل التلقائي

- (void)stopAuto {
    self.autoGen++;
    self.autoWeb = nil;
    self.autoStep = 0;
}

- (void)startAuto:(WKWebView *)wv video:(NSString *)video {
    [self stopAuto];
    self.autoWeb = wv;
    [self runAuto:video gen:self.autoGen tries:0];
}

- (void)runAuto:(NSString *)video gen:(NSUInteger)gen tries:(int)tries {
    if (gen != self.autoGen || !self.autoWeb) return;
    NSString *host = [NSURL URLWithString:kConverterURL].host;
    if (tries >= 90) {
        self.status.text = @"ما كملت تلقائي. كمّل الباقي بيدك (الرابط منسوخ)";
        [self stopAuto];
        return;
    }
    __weak EchoBrowserController *ws = self;
    void (^again)(void) = ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ws runAuto:video gen:gen tries:tries + 1];
        });
    };
    if (self.autoWeb.loading || ![self.autoWeb.URL.host isEqualToString:host]) { again(); return; }

    NSData *data = [NSJSONSerialization dataWithJSONObject:@[video] options:0 error:nil];
    NSString *arg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"%@(%@[0],%ld)", [self autoScript], arg, (long)self.autoStep];
    [self.autoWeb evaluateJavaScript:js completionHandler:^(id result, NSError *e) {
        EchoBrowserController *me = ws;
        if (!me || gen != me.autoGen) return;
        if ([result isKindOfClass:NSNumber.class]) {
            NSInteger next = [result integerValue];
            if (next != me.autoStep) {
                me.autoStep = next;
                NSArray *msgs = @[@"", @"⏳ ضغطت تنزيل…", @"⏳ اخترت الصوت…", @"⏳ اخترت MP3 320…", @"⏳ ضغطت تحميل، أنتظر الملف…"];
                if (next > 0 && next < (NSInteger)msgs.count) me.status.text = msgs[next];
            }
            if (next >= 4) return;
        }
        again();
    }];
}

- (NSString *)autoScript {
    return
         @"(function(url,step){"
         "var seen=function(e){var r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none';};"
         "var txt=function(e){return (e.innerText||e.value||'').replace(/\\s+/g,' ').trim();};"
         "var all=function(q,root){return Array.prototype.filter.call((root||document).querySelectorAll(q),seen);};"
         "var CLICK='button,a,input[type=button],input[type=submit],[role=button],[role=tab]';"
         "var DL=/download|تحميل|تنزيل|حمل/i;"
         "var GO=/download|convert|get link|تحميل|تنزيل|حمل|تحويل/i;"
         "var mark=function(){all(CLICK).forEach(function(e){e.setAttribute('data-echo-old','1');});};"
         "var find320=function(){"
         "var sels=all('select');"
         "for(var s=0;s<sels.length;s++){"
         "var o=Array.prototype.filter.call(sels[s].options,function(x){return /320/.test(x.text);});"
         "var m=o.filter(function(x){return /mp3/i.test(x.text);})[0]||o[0];"
         "if(!m)continue;"
         "var box=sels[s].parentElement;"
         "for(var u=0;u<4&&box;u++,box=box.parentElement){"
         "var b=all(CLICK,box).filter(function(e){return GO.test(txt(e));})[0];"
         "if(b)return {select:sels[s],value:m.value,button:b};"
         "}"
         "}"
         "var els=all(CLICK);"
         "for(var i=0;i<els.length;i++){"
         "var t=txt(els[i]);"
         "if(/320\\s*k/i.test(t))return {button:els[i]};"
         "if(!GO.test(t))continue;"
         "var row=els[i].closest('tr,li');"
         "if(row&&/320\\s*k/i.test(txt(row)))return {button:els[i]};"
         "}"
         "return null;"
         "};"
         "if(step===0){"
         "var inp=all('input[type=url],input[type=search],input[type=text],input:not([type])')[0];"
         "if(!inp)return 0;"
         "Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(inp,url);"
         "inp.dispatchEvent(new Event('input',{bubbles:true}));"
         "inp.dispatchEvent(new Event('change',{bubbles:true}));"
         "var near=inp.parentElement,go=null;"
         "for(var n=0;n<4&&near&&!go;n++,near=near.parentElement)"
         "go=all(CLICK,near).filter(function(e){return GO.test(txt(e))||e.type==='submit';})[0];"
         "if(!go)return 0;"
         "go.click();return 1;"
         "}"
         "if(step===1){"
         "var tab=all(CLICK+',li,span').filter(function(e){return /^\\W*(audio|mp3|audio mp3|mp3 audio|صوت|الصوت|ملف صوتي)\\W*$/i.test(txt(e));})[0];"
         "if(tab){tab.click();return 2;}"
         "return find320()?2:1;"
         "}"
         "if(step===2){"
         "var hit=find320();"
         "if(!hit)return 2;"
         "mark();"
         "if(hit.select){hit.select.value=hit.value;hit.select.dispatchEvent(new Event('change',{bubbles:true}));}"
         "hit.button.click();return 3;"
         "}"
         "var fin=all(CLICK).filter(function(e){return !e.hasAttribute('data-echo-old')&&DL.test(txt(e));})[0];"
         "if(fin){fin.click();return 4;}"
         "return 3;"
         "})";
}

#pragma mark - إيقاف الصوت عند الخروج من المتصفح

- (void)resumeAllowed {
    if (!self.viewIfLoaded.window) return;
    if (@available(iOS 15.0, *)) {
        for (WKWebView *w in self.tabs) [w setAllMediaPlaybackSuspended:NO completionHandler:nil];
    }
}

- (void)silenceTabs {
    for (WKWebView *w in self.tabs) {
        if (@available(iOS 15.0, *)) {
            [w pauseAllMediaPlaybackWithCompletionHandler:nil];
            [w setAllMediaPlaybackSuspended:YES completionHandler:nil];
        } else {
            [w evaluateJavaScript:@"document.querySelectorAll('video,audio').forEach(function(m){m.pause();})"
                completionHandler:nil];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (@available(iOS 15.0, *)) {
        for (WKWebView *w in self.tabs) [w setAllMediaPlaybackSuspended:NO completionHandler:nil];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.presentingViewController || self.isBeingDismissed) [self silenceTabs];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat top = 10;
    
    self.backBtn.frame = CGRectMake(12, top, 56, 34);
    self.splitBtn.frame = CGRectMake(74, top, 64, 34);
    self.closeBtn.frame = CGRectMake(b.size.width - 72, top, 60, 34);
    
    self.mp3Btn.frame = CGRectMake(144, top, 70, 34);
    CGFloat qx = 220, qw = (b.size.width - 220 - 76 - 6) / 2.0;
    for (NSInteger i = 0; i < 2; i++) {
        self.quick[i].frame = CGRectMake(qx + i * (qw + 4), top, qw, 34);
    }
    
    self.addr.frame = CGRectMake(12, 50, b.size.width - 24, 36);
    self.tabBar.frame = CGRectMake(0, 92, b.size.width, 34);
    
    CGFloat sh = 44;
    CGFloat startY = 130;
    CGFloat totalH = b.size.height - startY - sh;

    if (self.isSplitScreen && self.tabs.count >= 2) {
        CGFloat halfW = b.size.width / 2.0;
        NSInteger right = self.cur >= 2 ? self.cur : 1;
        for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
            self.tabs[i].hidden = (i != 0 && i != right);
        }
        self.tabs[0].frame = CGRectMake(0, startY, halfW - 1, totalH);
        self.tabs[right].frame = CGRectMake(halfW + 1, startY, halfW - 1, totalH);
    } else {
        CGRect wf = CGRectMake(0, startY, b.size.width, totalH);
        for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
            WKWebView *w = self.tabs[i];
            w.hidden = (i != self.cur);
            w.frame = wf;
        }
    }
    
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
    [w addObserver:self forKeyPath:@"URL" options:0 context:NULL];
    [self saveCurrentTabsState];
    [self viewDidLayoutSubviews];
    [self selectTab:(NSInteger)self.tabs.count - 1];
    return w;
}

- (void)selectTab:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.tabs.count) return;
    self.cur = i;
    if (!self.isSplitScreen) {
        for (NSInteger k = 0; k < (NSInteger)self.tabs.count; k++) self.tabs[k].hidden = (k != i);
    }
    NSURL *u = self.web.URL;
    self.addr.text = u ? u.absoluteString : @"";
    [self refreshTabBar];
    [self saveCurrentTabsState];
    [self.view setNeedsLayout];
}

- (void)refreshTabBar {
    for (UIView *v in self.tabBar.subviews) [v removeFromSuperview];
    CGFloat x = 8;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        NSString *t = self.tabs[i].title;
        if (t.length == 0) t = (i == 0) ? @"YouTube" : (i == 1 ? @"YT5s" : @"نافذة");
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

- (void)splitTapped {
    self.isSplitScreen = !self.isSplitScreen;
    [self.splitBtn setTitle:self.isSplitScreen ? @"🪟 فردي" : @"▤ تقسيم" forState:UIControlStateNormal];
    self.splitBtn.backgroundColor = self.isSplitScreen ? [UIColor colorWithRed:0.33 green:0.42 blue:1 alpha:0.95] : [UIColor colorWithWhite:1 alpha:0.14];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)addTabTapped {
    [self openTabWithConfig:nil];
    [self loadText:@"https://www.google.com"];
}

- (void)closeTabTapped {
    if (self.tabs.count <= 1) { self.status.text = @"هذي آخر نافذة. اضغط ✕ إغلاق لو تبغى تطلع"; return; }
    WKWebView *w = self.web;
    if (w == self.autoWeb) [self stopAuto];
    if (w == self.pendingWeb) { self.pendingWeb = nil; self.pendingVideo = nil; }
    [w removeObserver:self forKeyPath:@"URL"];
    [w stopLoading];
    [w removeFromSuperview];
    [self.tabs removeObjectAtIndex:self.cur];
    NSInteger n = self.cur >= (NSInteger)self.tabs.count ? (NSInteger)self.tabs.count - 1 : self.cur;
    [self saveCurrentTabsState];
    [self selectTab:n];
}

- (WKWebView *)webView:(WKWebView *)wv createWebViewWithConfiguration:(WKWebViewConfiguration *)cfg
   forNavigationAction:(WKNavigationAction *)a windowFeatures:(WKWindowFeatures *)f {
    if (wv == self.autoWeb && self.autoStep < 3 &&
        ![a.request.URL.host isEqualToString:[NSURL URLWithString:kConverterURL].host]) return nil;
    if (a.targetFrame == nil || !a.targetFrame.isMainFrame) {
        if (a.request.URL) {
            [wv loadRequest:a.request];
        }
    }
    return nil;
}

- (void)closeTapped {
    [self saveCurrentTabsState];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)backTapped { if (self.web.canGoBack) [self.web goBack]; }

- (void)quickTapped:(UIButton *)b {
    NSArray *urls = @[@"https://www.youtube.com", kConverterURL];
    NSString *host = [NSURL URLWithString:urls[b.tag]].host;
    for (NSInteger i = 0; i < (NSInteger)self.tabs.count; i++) {
        if ([self.tabs[i].URL.host isEqualToString:host]) { [self selectTab:i]; return; }
    }
    [self loadText:urls[b.tag]];
}

- (void)loadText:(NSString *)t {
    t = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (t.length == 0) return;
    NSURL *u = nil;
    if ([t hasPrefix:@"http://"] || [t hasPrefix:@"https://"]) {
        u = [NSURL URLWithString:t];
    } else if ([t containsString:@"."] && ![t containsString:@" "]) {
        u = [NSURL URLWithString:[@"https://" stringByAppendingString:t]];
    } else {
        NSURLComponents *c = [NSURLComponents componentsWithString:@"https://www.google.com/search"];
        c.queryItems = @[ [NSURLQueryItem queryItemWithName:@"q" value:t] ];
        u = c.URL;
    }
    if (u) { 
        self.addr.text = u.absoluteString; 
        [[NSUserDefaults standardUserDefaults] setObject:u.absoluteString forKey:kLastURLKey];
        [self.web loadRequest:[NSURLRequest requestWithURL:u]];
        [self saveCurrentTabsState];
    }
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
        static NSSet *audioExts;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ audioExts = [NSSet setWithObjects:@"mp3", @"m4a", @"wav", @"aac", @"flac", nil]; });
        if (should || [audioExts containsObject:ext.lowercaseString]) { 
            h((WKNavigationActionPolicy)2); 
            return; 
        }
    }
    h(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)wv decidePolicyForNavigationResponse:(WKNavigationResponse *)r
                                                  decisionHandler:(void (^)(WKNavigationResponsePolicy))h {
    if ([self canDownload]) {
        NSString *mime = r.response.MIMEType.lowercaseString ?: @"";
        NSString *ext = r.response.suggestedFilename.pathExtension;
        static NSSet *audioExts;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ audioExts = [NSSet setWithObjects:@"mp3", @"m4a", @"wav", @"aac", @"flac", nil]; });
        BOOL audio = [mime hasPrefix:@"audio/"] || [audioExts containsObject:ext.lowercaseString] || [audioExts containsObject:r.response.URL.pathExtension.lowercaseString];
        if (audio) { 
            h((WKNavigationResponsePolicy)2); 
            return; 
        }
    }
    h(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)wv navigationAction:(WKNavigationAction *)a didBecomeDownload:(id)d {
    [d setDelegate:self];
    [self stopAuto];
    self.status.text = @"⏳ بدأ التنزيل…";
}
- (void)webView:(WKWebView *)wv navigationResponse:(WKNavigationResponse *)r didBecomeDownload:(id)d {
    [d setDelegate:self];
    [self stopAuto];
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
    NSString *name = [[dest.lastPathComponent stringByDeletingPathExtension] copy];
    void (^cb)(NSURL *, NSString *) = self.onPick;
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:^{ if (cb) cb(dest, name); }];
    } else if (cb) {
        cb(dest, name);
    }
}

- (void)download:(id)d didFailWithError:(NSError *__nullable)e resumeData:(NSData *__nullable)rd {
    [self.dests removeObjectForKey:[NSValue valueWithNonretainedObject:d]];
    self.status.text = @"❌ فشل التنزيل. جرّب مرة ثانية أو موقع ثاني";
}

- (void)webView:(WKWebView *)wv didFinishNavigation:(WKNavigation *)n {
    if (wv == self.web && wv.URL) {
        self.addr.text = wv.URL.absoluteString;
        [[NSUserDefaults standardUserDefaults] setObject:wv.URL.absoluteString forKey:kLastURLKey];
    }
    [self saveCurrentTabsState];
    [self refreshTabBar];
    if (self.pendingVideo && wv == self.pendingWeb &&
        [wv.URL.host isEqualToString:[NSURL URLWithString:kConverterURL].host]) {
        NSString *video = self.pendingVideo;
        self.pendingVideo = nil;
        self.pendingWeb = nil;
        [self startAuto:wv video:video];
    }
}

@end

#pragma mark - الكاميرا: فلاتر، أو صورة/فيديو بدل الكام

enum { CAM_LIVE = 0, CAM_IMAGE, CAM_VIDEO };

static NSString *const kCamFilterNames[8] = { @"بدون", @"أبيض وأسود", @"سينمائي", @"قديم", @"بكسل", @"تغبيش", @"كرتون", @"معكوس" };
static NSString *const kCamFilters[8] = { nil, @"CIPhotoEffectNoir", @"CIPhotoEffectChrome", @"CISepiaTone",
                                          @"CIPixellate", @"CIGaussianBlur", @"CIComicEffect", @"CIColorInvert" };

#pragma mark - مؤثرات الوجه

enum { FX_NONE = 0, FX_CAT, FX_CLOWN, FX_SKULL, FX_ROBOT, FX_GLASSES, FX_MUSTACHE, FX_CROWN, FX_HEARTS,
       FX_BIGEYES, FX_BIGMOUTH, FX_PUFFY, FX_THIN, FX_BLURFACE, FX_PIXFACE, FX_CUSTOM, FX_COUNT };

static NSString *const kFxNames[FX_COUNT] = {
    @"بدون", @"🐱 قطو", @"🤡 مهرج", @"💀 مكياج جمجمة", @"🤖 روبوت", @"🕶️ نظارة", @"🥸 شنب", @"👑 تاج", @"😍 قلوب",
    @"👀 عيون كبيرة", @"👄 فم كبير", @"🎈 وجه منفوخ", @"📏 وجه نحيف", @"🌫️ تغبيش الوجه", @"🟦 بكسل الوجه", @"🖼️ قناعي"
};

static void fx_oval(CGRect r, UIColor *c) {
    [c setFill];
    [[UIBezierPath bezierPathWithOvalInRect:r] fill];
}

static void fx_poly(const CGPoint *p, int n, UIColor *c) {
    UIBezierPath *b = [UIBezierPath bezierPath];
    [b moveToPoint:p[0]];
    for (int i = 1; i < n; i++) [b addLineToPoint:p[i]];
    [b closePath];
    [c setFill];
    [b fill];
}

static void fx_line(CGPoint a, CGPoint b, CGFloat width, UIColor *c) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:a];
    [p addLineToPoint:b];
    p.lineWidth = width;
    p.lineCapStyle = kCGLineCapRound;
    [c setStroke];
    [p stroke];
}

static void fx_mask(UIColor *c) {
    UIBezierPath *p = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(170, 150, 660, 790)];
    [p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(285, 365, 130, 110)]];
    [p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(585, 365, 130, 110)]];
    [p appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(390, 675, 220, 95)]];
    p.usesEvenOddFillRule = YES;
    [c setFill];
    [p fill];
}

static void fx_heart(CGFloat cx, CGFloat cy, CGFloat s, UIColor *c) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(cx, cy + s)];
    [p addCurveToPoint:CGPointMake(cx, cy - s * 0.45) controlPoint1:CGPointMake(cx - s * 1.8, cy - s * 0.2)
         controlPoint2:CGPointMake(cx - s * 0.8, cy - s * 1.4)];
    [p addCurveToPoint:CGPointMake(cx, cy + s) controlPoint1:CGPointMake(cx + s * 0.8, cy - s * 1.4)
         controlPoint2:CGPointMake(cx + s * 1.8, cy - s * 0.2)];
    [c setFill];
    [p fill];
}

static void fx_draw(int fx) {
    UIColor *black = UIColor.blackColor, *white = UIColor.whiteColor, *red = [UIColor colorWithRed:0.9 green:0.1 blue:0.15 alpha:1];
    if (fx == FX_CAT) {
        UIColor *fur = [UIColor colorWithRed:0.95 green:0.6 blue:0.2 alpha:1];
        UIColor *pink = [UIColor colorWithRed:1 green:0.55 blue:0.65 alpha:1];
        CGPoint l[3] = { {190, 330}, {200, 20}, {430, 190} }, r[3] = { {810, 330}, {800, 20}, {570, 190} };
        fx_poly(l, 3, fur); fx_poly(r, 3, fur);
        fx_mask([fur colorWithAlphaComponent:0.92]);
        CGPoint li[3] = { {240, 230}, {235, 90}, {350, 180} }, ri[3] = { {760, 230}, {765, 90}, {650, 180} };
        fx_poly(li, 3, pink); fx_poly(ri, 3, pink);
        fx_oval(CGRectMake(350, 570, 300, 150), white);
        CGPoint nose[3] = { {450, 570}, {550, 570}, {500, 625} };
        fx_poly(nose, 3, pink);
        for (int i = -1; i <= 1; i++) {
            fx_line(CGPointMake(360, 620 + i * 30), CGPointMake(110, 600 + i * 75), 9, black);
            fx_line(CGPointMake(640, 620 + i * 30), CGPointMake(890, 600 + i * 75), 9, black);
        }
    } else if (fx == FX_CLOWN) {
        fx_mask([UIColor colorWithWhite:1 alpha:0.88]);
        UIColor *blue = [UIColor colorWithRed:0.1 green:0.35 blue:0.95 alpha:1];
        for (int x = 350; x <= 650; x += 300) {
            CGPoint up[3] = { {x - 35, 355}, {x, 250}, {x + 35, 355} }, dn[3] = { {x - 35, 488}, {x, 590}, {x + 35, 488} };
            fx_poly(up, 3, blue); fx_poly(dn, 3, blue);
        }
        UIBezierPath *smile = [UIBezierPath bezierPath];
        [smile moveToPoint:CGPointMake(300, 680)];
        [smile addQuadCurveToPoint:CGPointMake(700, 680) controlPoint:CGPointMake(500, 940)];
        smile.lineWidth = 45; smile.lineCapStyle = kCGLineCapRound;
        [red setStroke]; [smile stroke];
        fx_oval(CGRectMake(430, 510, 140, 140), red);
        for (int i = 0; i < 5; i++) {
            fx_oval(CGRectMake(90 + i * 45, 330 - i * 70, 180, 180), red);
            fx_oval(CGRectMake(730 - i * 45, 330 - i * 70, 180, 180), red);
        }
    } else if (fx == FX_ROBOT) {
        UIColor *metal = [UIColor colorWithRed:0.55 green:0.6 blue:0.66 alpha:1];
        UIColor *glow = [UIColor colorWithRed:0.1 green:0.95 blue:1 alpha:1];
        fx_line(CGPointMake(500, 150), CGPointMake(500, 50), 22, metal);
        fx_oval(CGRectMake(460, 10, 80, 80), red);
        [metal setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(165, 140, 670, 790) cornerRadius:120] fill];
        [black setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(220, 340, 560, 165) cornerRadius:50] fill];
        fx_oval(CGRectMake(305, 378, 90, 90), glow); fx_oval(CGRectMake(605, 378, 90, 90), glow);
        [black setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(340, 660, 320, 130) cornerRadius:25] fill];
        for (int x = 385; x <= 615; x += 46) fx_line(CGPointMake(x, 685), CGPointMake(x, 765), 14, glow);
        fx_oval(CGRectMake(115, 440, 90, 170), metal); fx_oval(CGRectMake(795, 440, 90, 170), metal);
    } else if (fx == FX_GLASSES) {
        [[UIColor colorWithWhite:0.02 alpha:0.94] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(215, 340, 255, 170) cornerRadius:55] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(530, 340, 255, 170) cornerRadius:55] fill];
        fx_line(CGPointMake(455, 390), CGPointMake(545, 390), 26, black);
        fx_line(CGPointMake(225, 385), CGPointMake(120, 360), 24, black);
        fx_line(CGPointMake(775, 385), CGPointMake(880, 360), 24, black);
        fx_line(CGPointMake(255, 385), CGPointMake(310, 370), 18, [UIColor colorWithWhite:1 alpha:0.55]);
    } else if (fx == FX_MUSTACHE) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(500, 620)];
        [p addCurveToPoint:CGPointMake(235, 625) controlPoint1:CGPointMake(400, 560) controlPoint2:CGPointMake(330, 700)];
        [p addCurveToPoint:CGPointMake(500, 680) controlPoint1:CGPointMake(270, 750) controlPoint2:CGPointMake(430, 745)];
        [p addCurveToPoint:CGPointMake(765, 625) controlPoint1:CGPointMake(570, 745) controlPoint2:CGPointMake(730, 750)];
        [p addCurveToPoint:CGPointMake(500, 620) controlPoint1:CGPointMake(670, 700) controlPoint2:CGPointMake(600, 560)];
        [[UIColor colorWithRed:0.16 green:0.09 blue:0.04 alpha:1] setFill];
        [p fill];
    } else if (fx == FX_CROWN) {
        UIColor *gold = [UIColor colorWithRed:1 green:0.78 blue:0.1 alpha:1];
        CGPoint c[7] = { {240, 210}, {215, 0}, {365, 110}, {500, 0}, {635, 110}, {785, 0}, {760, 210} };
        fx_poly(c, 7, gold);
        fx_oval(CGRectMake(470, 120, 60, 60), red);
        fx_oval(CGRectMake(320, 140, 45, 45), [UIColor systemBlueColor]);
        fx_oval(CGRectMake(635, 140, 45, 45), [UIColor systemGreenColor]);
    } else if (fx == FX_HEARTS) {
        fx_heart(350, 425, 100, red); fx_heart(650, 425, 100, red);
        fx_oval(CGRectMake(220, 570, 150, 90), [UIColor colorWithRed:1 green:0.3 blue:0.45 alpha:0.4]);
        fx_oval(CGRectMake(630, 570, 150, 90), [UIColor colorWithRed:1 green:0.3 blue:0.45 alpha:0.4]);
    }
}

static UIImage *fx_render(void (^draw)(void)) {
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat];
    f.scale = 1;
    f.opaque = NO;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1000, 1000) format:f]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) { draw(); }];
}

#define MAX_PTS 32
typedef struct {
    CGPoint eyes, eyeA, eyeB, mouth;
    CGFloat eyeDist, mouthDist, angle;
    CGPoint contour[MAX_PTS], eyePtsA[MAX_PTS], eyePtsB[MAX_PTS];
    int nContour, nEyeA, nEyeB;
} EchoFace;

static CGPoint fx_center(VNFaceLandmarkRegion2D *r, CGSize size) {
    const CGPoint *p = [r pointsInImageOfSize:size];
    CGFloat x = 0, y = 0;
    for (NSUInteger i = 0; i < r.pointCount; i++) { x += p[i].x; y += p[i].y; }
    return CGPointMake(x / r.pointCount, y / r.pointCount);
}

static int fx_copy(VNFaceLandmarkRegion2D *r, CGSize size, CGPoint *out) {
    const CGPoint *p = [r pointsInImageOfSize:size];
    int n = (int)MIN((NSUInteger)MAX_PTS, r.pointCount);
    for (int i = 0; i < n; i++) out[i] = p[i];
    return n;
}

static CGPoint fx_mix(CGPoint a, CGPoint b, CGFloat k) {
    return CGPointMake(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k);
}

static BOOL fx_find_face(CIImage *img, EchoFace *out) {
    VNDetectFaceLandmarksRequest *req = [[VNDetectFaceLandmarksRequest alloc] init];
    CGSize size = img.extent.size;
    CGFloat shrink = MIN(1.0, 480.0 / MAX(size.width, size.height));
    CIImage *small = shrink < 1.0 ? [img imageByApplyingTransform:CGAffineTransformMakeScale(shrink, shrink)] : img;
    VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCIImage:small options:@{}];
    NSError *e = nil;
    if (![h performRequests:@[req] error:&e]) return NO;
    VNFaceObservation *best = nil;
    for (VNFaceObservation *o in req.results) {
        if (!best || o.boundingBox.size.width > best.boundingBox.size.width) best = o;
    }
    VNFaceLandmarks2D *lm = best.landmarks;
    if (!lm.leftEye.pointCount || !lm.rightEye.pointCount || !lm.outerLips.pointCount) return NO;
    out->eyeA = fx_center(lm.leftEye, size);
    out->eyeB = fx_center(lm.rightEye, size);
    out->mouth = fx_center(lm.outerLips, size);
    out->nContour = fx_copy(lm.faceContour, size, out->contour);
    out->nEyeA = fx_copy(lm.leftEye, size, out->eyePtsA);
    out->nEyeB = fx_copy(lm.rightEye, size, out->eyePtsB);
    return YES;
}

static void fx_measure(EchoFace *f) {
    f->eyes = fx_mix(f->eyeA, f->eyeB, 0.5);
    f->eyeDist = hypot(f->eyeB.x - f->eyeA.x, f->eyeB.y - f->eyeA.y);
    f->mouthDist = hypot(f->mouth.x - f->eyes.x, f->mouth.y - f->eyes.y);
    f->angle = atan2(f->eyes.y - f->mouth.y, f->eyes.x - f->mouth.x) - M_PI_2;
}

#pragma mark - مكياج يلتصق بالوجه

static void paint_smooth(CGContextRef c, const CGPoint *p, int n) {
    if (n < 3) return;
    CGContextMoveToPoint(c, (p[n - 1].x + p[0].x) / 2, (p[n - 1].y + p[0].y) / 2);
    for (int i = 0; i < n; i++) {
        CGPoint a = p[i], b = p[(i + 1) % n];
        CGContextAddQuadCurveToPoint(c, a.x, a.y, (a.x + b.x) / 2, (a.y + b.y) / 2);
    }
    CGContextClosePath(c);
}

static CGPoint paint_local(const EchoFace *f, CGPoint p) {
    CGFloat dx = p.x - f->eyes.x, dy = p.y - f->eyes.y;
    CGFloat c = cos(f->angle), s = sin(f->angle), d = MAX(1.0, f->eyeDist);
    return CGPointMake((dx * c + dy * s) / d, (-dx * s + dy * c) / d);
}

static void paint_eyes_path(CGContextRef c, const EchoFace *f, const CGPoint *eye, int n) {
    if (n < 3) return;
    CGPoint q[MAX_PTS], mid = CGPointZero;
    for (int i = 0; i < n; i++) { q[i] = paint_local(f, eye[i]); mid.x += q[i].x / n; mid.y += q[i].y / n; }
    for (int i = 0; i < n; i++) q[i] = CGPointMake(mid.x + (q[i].x - mid.x) * 1.12, mid.y + (q[i].y - mid.y) * 1.3);
    paint_smooth(c, q, n);
}

static void paint_skull(CGContextRef c, const EchoFace *f, int layer) {
    CGPoint eyeA = paint_local(f, f->eyeA), eyeB = paint_local(f, f->eyeB), mouth = paint_local(f, f->mouth);
    CGFloat md = MAX(0.7, -mouth.y);
    CGContextSetGrayFillColor(c, 1, 1);
    CGContextSetGrayStrokeColor(c, 1, 1);

    if (layer == 0) {
        CGPoint q[MAX_PTS + 8];
        int n = 0, count = f->nContour;
        if (count < 5) return;
        BOOL leftFirst = paint_local(f, f->contour[0]).x < paint_local(f, f->contour[count - 1]).x;
        for (int i = 0; i < count; i++) {
            CGPoint p = paint_local(f, f->contour[leftFirst ? i : count - 1 - i]);
            q[n++] = CGPointMake(p.x * 0.97, p.y * 0.98);
        }
        CGFloat rx = q[n - 1].x, lx = q[0].x;
        q[n++] = CGPointMake(rx * 0.96, 0.45);
        q[n++] = CGPointMake(rx * 0.68, 0.84);
        q[n++] = CGPointMake(0, 0.98);
        q[n++] = CGPointMake(lx * 0.68, 0.84);
        q[n++] = CGPointMake(lx * 0.96, 0.45);
        paint_smooth(c, q, n);
        CGContextFillPath(c);
    } else {
        static const CGFloat kR[12] = { 1.0, 0.95, 1.08, 1.02, 0.94, 1.0, 1.04, 0.93, 1.16, 0.96, 1.03, 0.95 };
        CGPoint eyes[2] = { eyeA, eyeB };
        for (int e = 0; e < 2; e++) {
            CGPoint q[12];
            for (int i = 0; i < 12; i++) {
                CGFloat a = 2 * M_PI * i / 12;
                q[i] = CGPointMake(eyes[e].x + cos(a) * 0.37 * kR[i], eyes[e].y + 0.02 + sin(a) * 0.29 * kR[i]);
            }
            paint_smooth(c, q, 12);
            CGContextFillPath(c);
        }
        CGFloat ny = -md * 0.62;
        CGContextMoveToPoint(c, 0, ny + 0.2);
        CGContextAddCurveToPoint(c, 0.08, ny + 0.08, 0.27, ny - 0.04, 0.17, ny - 0.13);
        CGContextAddQuadCurveToPoint(c, 0.07, ny - 0.17, 0, ny - 0.08);
        CGContextAddQuadCurveToPoint(c, -0.07, ny - 0.17, -0.17, ny - 0.13);
        CGContextAddCurveToPoint(c, -0.27, ny - 0.04, -0.08, ny + 0.08, 0, ny + 0.2);
        CGContextFillPath(c);
        CGFloat half = 0.82, lift = 0.24;
        CGContextSetLineCap(c, kCGLineCapRound);
        CGContextSetLineWidth(c, 0.045);
        CGContextMoveToPoint(c, mouth.x - half, mouth.y + lift);
        CGContextAddQuadCurveToPoint(c, mouth.x, mouth.y - lift, mouth.x + half, mouth.y + lift);
        CGContextStrokePath(c);
        for (int i = 0; i <= 12; i++) {
            CGFloat t = i / 12.0, u = 1 - t;
            CGFloat x = u * u * (mouth.x - half) + 2 * u * t * mouth.x + t * t * (mouth.x + half);
            CGFloat y = u * u * (mouth.y + lift) + 2 * u * t * (mouth.y - lift) + t * t * (mouth.y + lift);
            CGFloat h = 0.07 + 0.08 * sin(M_PI * t);
            CGContextSetLineWidth(c, 0.032);
            CGContextMoveToPoint(c, x - 0.012, y + h);
            CGContextAddLineToPoint(c, x + 0.012, y - h);
            CGContextStrokePath(c);
        }
    }
    CGContextSetGrayFillColor(c, 0, 1);
    paint_eyes_path(c, f, f->eyePtsA, f->nEyeA);
    CGContextFillPath(c);
    paint_eyes_path(c, f, f->eyePtsB, f->nEyeB);
    CGContextFillPath(c);
}

static CIImage *paint_mask(const EchoFace *f, CGSize size, int layer) {
    CGFloat k = MIN(1.0, 640.0 / MAX(size.width, size.height));
    size_t w = MAX(1, (size_t)(size.width * k)), h = MAX(1, (size_t)(size.height * k));
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!c) return nil;
    CGContextSetGrayFillColor(c, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    CGContextScaleCTM(c, k, k);
    CGContextTranslateCTM(c, f->eyes.x, f->eyes.y);
    CGContextRotateCTM(c, f->angle);
    CGContextScaleCTM(c, f->eyeDist, f->eyeDist);
    paint_skull(c, f, layer);
    CGImageRef cg = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    if (!cg) return nil;
    CIImage *m = [CIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    m = [m imageByApplyingTransform:CGAffineTransformMakeScale(size.width / w, size.height / h)];
    CGFloat soft = f->eyeDist * (layer == 0 ? 0.045 : 0.012);
    return [[[m imageByClampingToExtent] imageByApplyingFilter:@"CIGaussianBlur"
                                           withInputParameters:@{ kCIInputRadiusKey: @(soft) }]
            imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];
}

static CIImage *paint_tone(CIImage *img, CGFloat gain, CGFloat r, CGFloat g, CGFloat b) {
    CIImage *mono = [img imageByApplyingFilter:@"CIColorControls" withInputParameters:@{ kCIInputSaturationKey: @0 }];
    return [mono imageByApplyingFilter:@"CIColorMatrix" withInputParameters:@{
        @"inputRVector": [CIVector vectorWithX:gain Y:0 Z:0 W:0],
        @"inputGVector": [CIVector vectorWithX:0 Y:gain Z:0 W:0],
        @"inputBVector": [CIVector vectorWithX:0 Y:0 Z:gain W:0],
        @"inputBiasVector": [CIVector vectorWithX:r Y:g Z:b W:0] }];
}

static CIImage *paint_apply(CIImage *img, const EchoFace *f) {
    CGSize size = img.extent.size;
    CIImage *base = paint_mask(f, size, 0), *ink = paint_mask(f, size, 1);
    if (!base || !ink) return img;
    CIImage *out = [paint_tone(img, 0.55, 0.28, 0.30, 0.34) imageByApplyingFilter:@"CIBlendWithMask"
        withInputParameters:@{ kCIInputBackgroundImageKey: img, kCIInputMaskImageKey: base }];
    out = [paint_tone(img, 0.10, 0.01, 0.01, 0.015) imageByApplyingFilter:@"CIBlendWithMask"
        withInputParameters:@{ kCIInputBackgroundImageKey: out, kCIInputMaskImageKey: ink }];
    return [out imageByCroppingToRect:img.extent];
}

enum { SHAPE_EYES = 0, SHAPE_MOUTH, SHAPE_NOSE, SHAPE_CHIN, SHAPE_FACE, SHAPE_COUNT };
static NSString *const kShapeNames[SHAPE_COUNT] = { @"العيون", @"الفم", @"الأنف", @"الذقن", @"الوجه (نحيف ↔ منفوخ)" };

@interface EchoCam : NSObject
@property (atomic) int effect;
@property (atomic) int liveFlip;
@property (atomic) BOOL faceSeen;
- (void)setShape:(int)index value:(int)v;
- (BOOL)hasShape;
- (void)useCustomMask:(CIImage *)mask;
- (BOOL)hasCustomMask;
@property (atomic) int mode;
@property (atomic) int filter;
@property (atomic) int turns;
@property (atomic) BOOL mirror;
@property (atomic) unsigned frames;
+ (instancetype)shared;
- (void)useImage:(CIImage *)image;
- (BOOL)useVideo:(NSURL *)url;
- (void)useLive;
- (CMSampleBufferRef)copyProcessed:(CMSampleBufferRef)input;
@end

@implementation EchoCam {
    CIContext *_ci;
    CIImage *_still;
    AVURLAsset *_asset;
    AVAssetReader *_reader;
    AVAssetReaderTrackOutput *_track;
    CIImage *_videoFrame;
    CMSampleBufferRef _next;
    CFTimeInterval _videoStart;
    CGAffineTransform _videoTransform;
    CVPixelBufferPoolRef _pool;
    size_t _poolW, _poolH;
    OSType _poolType;
    CIImage *_fxArt[FX_COUNT];
    int _shape[SHAPE_COUNT];
    EchoFace _face;
    BOOL _haveFace;
    CFTimeInterval _faceTime;
    int _searchTurn;
}

- (void)setShape:(int)index value:(int)v {
    if (index < 0 || index >= SHAPE_COUNT) return;
    @synchronized (self) { _shape[index] = v; }
}
- (BOOL)hasShape {
    @synchronized (self) {
        for (int i = 0; i < SHAPE_COUNT; i++) if (_shape[i]) return YES;
        return NO;
    }
}

- (CIImage *)reshape:(CIImage *)img face:(EchoFace)face {
    CGFloat d = face.eyeDist;
    CGPoint nose = fx_mix(face.eyes, face.mouth, 0.6);
    CGPoint chin = fx_mix(face.eyes, face.mouth, 1.65);
    CGPoint middle = fx_mix(face.eyes, face.mouth, 0.5);
    CGFloat v;
    if ((v = _shape[SHAPE_FACE] / 100.0) != 0)
        img = [self warp:img name:@"CIBumpDistortion" at:middle radius:d * 1.9 scale:v * (v > 0 ? 0.4 : 0.25)];
    if ((v = _shape[SHAPE_EYES] / 100.0) != 0) {
        img = [self warp:img name:@"CIBumpDistortion" at:face.eyeA radius:d * 0.55 scale:v * 0.5];
        img = [self warp:img name:@"CIBumpDistortion" at:face.eyeB radius:d * 0.55 scale:v * 0.5];
    }
    if ((v = _shape[SHAPE_NOSE] / 100.0) != 0)
        img = [self warp:img name:@"CIBumpDistortion" at:nose radius:d * 0.55 scale:v * 0.45];
    if ((v = _shape[SHAPE_MOUTH] / 100.0) != 0)
        img = [self warp:img name:@"CIBumpDistortion" at:face.mouth radius:d * 0.75 scale:v * 0.45];
    if ((v = _shape[SHAPE_CHIN] / 100.0) != 0)
        img = [self warp:img name:@"CIBumpDistortion" at:chin radius:d * 0.85 scale:v * 0.4];
    return img;
}

- (void)useCustomMask:(CIImage *)mask {
    @synchronized (self) { _fxArt[FX_CUSTOM] = mask; }
}
- (BOOL)hasCustomMask {
    @synchronized (self) { return _fxArt[FX_CUSTOM] != nil; }
}

// قناع مخصص يلتصق بالوجه، يطابق ميلانه وحجمه، ويفرّغ العيون بحواف ناعمة
- (CIImage *)customFaceMaskForSize:(CGSize)size face:(const EchoFace *)face {
    CGFloat k = MIN(1.0, 640.0 / MAX(size.width, size.height));
    size_t w = MAX(1, (size_t)(size.width * k));
    size_t h = MAX(1, (size_t)(size.height * k));

    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, 0, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!c) return nil;

    CGContextSetGrayFillColor(c, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));

    CGContextScaleCTM(c, k, k);
    CGContextTranslateCTM(c, face->eyes.x, face->eyes.y);
    CGContextRotateCTM(c, face->angle);
    CGContextScaleCTM(c, face->eyeDist, face->eyeDist);

    CGPoint mouthLocal = paint_local(face, face->mouth);
    CGFloat centerY = mouthLocal.y * 0.52;
    CGFloat radiusX = 1.05;
    CGFloat radiusY = MAX(1.05, fabs(mouthLocal.y) * 1.38);

    CGContextSetGrayFillColor(c, 1, 1);
    CGContextFillEllipseInRect(c, CGRectMake(-radiusX, centerY - radiusY, radiusX * 2.0, radiusY * 2.0));

    // تفريغ العينين عشان تبان عيونك الحقيقية
    CGContextSetGrayFillColor(c, 0, 1);
    paint_eyes_path(c, face, face->eyePtsA, face->nEyeA);
    CGContextFillPath(c);
    paint_eyes_path(c, face, face->eyePtsB, face->nEyeB);
    CGContextFillPath(c);

    CGImageRef cg = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    if (!cg) return nil;

    CIImage *m = [CIImage imageWithCGImage:cg];
    CGImageRelease(cg);

    m = [m imageByApplyingTransform:CGAffineTransformMakeScale(size.width / w, size.height / h)];
    CGFloat soft = MAX(4.0, face->eyeDist * 0.055);

    return [[[m imageByClampingToExtent]
             imageByApplyingFilter:@"CIGaussianBlur"
               withInputParameters:@{ kCIInputRadiusKey: @(soft) }]
            imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];
}

- (CIImage *)applyEffect:(CIImage *)img {
    int fx = self.effect;
    if (fx < FX_NONE || fx >= FX_COUNT) fx = FX_NONE;
    if (fx == FX_NONE && ![self hasShape]) { _haveFace = NO; self.faceSeen = NO; return img; }

    static const int kTry[4] = { 1, 6, 8, 3 };
    int o = kTry[_searchTurn & 3];
    int back = o == 6 ? 8 : (o == 8 ? 6 : o);
    CIImage *up = o == 1 ? img : [img imageByApplyingOrientation:o];
    up = [up imageByApplyingTransform:CGAffineTransformMakeTranslation(-up.extent.origin.x, -up.extent.origin.y)];

    CFTimeInterval now = CACurrentMediaTime();
    {
        EchoFace found;
        if (fx_find_face(up, &found)) {
            if (_haveFace) {
                CGPoint was = fx_mix(_face.eyeA, _face.eyeB, 0.5), is = fx_mix(found.eyeA, found.eyeB, 0.5);
                CGFloat move = hypot(is.x - was.x, is.y - was.y);
                CGFloat k = MIN(1.0, 0.3 + move / MAX(1.0, _face.eyeDist * 0.1));
                found.eyeA = fx_mix(_face.eyeA, found.eyeA, k);
                found.eyeB = fx_mix(_face.eyeB, found.eyeB, k);
                found.mouth = fx_mix(_face.mouth, found.mouth, k);
                if (found.nContour == _face.nContour)
                    for (int i = 0; i < found.nContour; i++) found.contour[i] = fx_mix(_face.contour[i], found.contour[i], k);
                if (found.nEyeA == _face.nEyeA)
                    for (int i = 0; i < found.nEyeA; i++) found.eyePtsA[i] = fx_mix(_face.eyePtsA[i], found.eyePtsA[i], k);
                if (found.nEyeB == _face.nEyeB)
                    for (int i = 0; i < found.nEyeB; i++) found.eyePtsB[i] = fx_mix(_face.eyePtsB[i], found.eyePtsB[i], k);
            }
            fx_measure(&found);
            _face = found;
            _haveFace = YES;
            _faceTime = now;
        } else if (!_haveFace || now - _faceTime > 0.5) {
            _haveFace = NO;
            _searchTurn++;
            self.faceSeen = NO;
            return img;
        }
    }
    self.faceSeen = YES;

    CIImage *result = [self reshape:up face:_face];
    if (fx != FX_NONE) result = [self effect:fx on:result face:_face];
    if (o != 1) result = [result imageByApplyingOrientation:back];
    CGRect r = result.extent;
    return [result imageByApplyingTransform:CGAffineTransformMakeTranslation(-r.origin.x, -r.origin.y)];
}

- (CIImage *)warp:(CIImage *)img name:(NSString *)name at:(CGPoint)p radius:(CGFloat)radius scale:(CGFloat)scale {
    CIFilter *f = [CIFilter filterWithName:name];
    if (!f) return img;
    [f setValue:[img imageByClampingToExtent] forKey:kCIInputImageKey];
    [f setValue:[CIVector vectorWithX:p.x Y:p.y] forKey:kCIInputCenterKey];
    [f setValue:@(radius) forKey:kCIInputRadiusKey];
    [f setValue:@(scale) forKey:kCIInputScaleKey];
    return f.outputImage ? [f.outputImage imageByCroppingToRect:img.extent] : img;
}

- (CIImage *)effect:(int)fx on:(CIImage *)img face:(EchoFace)face {
    if (fx == FX_SKULL) return paint_apply(img, &face);
    CGFloat d = face.eyeDist;
    CGPoint middle = fx_mix(face.eyes, face.mouth, 0.5);
    if (fx == FX_BIGEYES) {
        img = [self warp:img name:@"CIBumpDistortion" at:face.eyeA radius:d * 0.55 scale:0.45];
        return [self warp:img name:@"CIBumpDistortion" at:face.eyeB radius:d * 0.55 scale:0.45];
    }
    if (fx == FX_BIGMOUTH) return [self warp:img name:@"CIBumpDistortion" at:face.mouth radius:d * 0.85 scale:0.55];
    if (fx == FX_PUFFY)    return [self warp:img name:@"CIBumpDistortion" at:middle radius:d * 1.9 scale:0.4];
    if (fx == FX_THIN)     return [self warp:img name:@"CIPinchDistortion" at:middle radius:d * 2.0 scale:0.22];

    if (fx == FX_BLURFACE || fx == FX_PIXFACE) {
        CIImage *hidden = [[img imageByClampingToExtent]
            imageByApplyingFilter:(fx == FX_BLURFACE ? @"CIGaussianBlur" : @"CIPixellate")
              withInputParameters:(fx == FX_BLURFACE ? @{ kCIInputRadiusKey: @(d * 0.22) }
                                                     : @{ kCIInputScaleKey: @(MAX(4.0, d * 0.2)) })];
        CIFilter *grad = [CIFilter filterWithName:@"CIRadialGradient" withInputParameters:@{
            kCIInputCenterKey: [CIVector vectorWithX:middle.x Y:middle.y],
            @"inputRadius0": @(d * 1.35), @"inputRadius1": @(d * 1.6),
            @"inputColor0": [CIColor colorWithRed:1 green:1 blue:1],
            @"inputColor1": [CIColor colorWithRed:0 green:0 blue:0] }];
        return [[hidden imageByApplyingFilter:@"CIBlendWithMask" withInputParameters:@{
            kCIInputBackgroundImageKey: img, kCIInputMaskImageKey: grad.outputImage }] imageByCroppingToRect:img.extent];
    }

    if (fx == FX_CUSTOM) {
        CIImage *custom = _fxArt[FX_CUSTOM];
        if (!custom) return img;

        CGFloat scaleX = d / 300.0;
        CGFloat scaleY = MAX(face.mouthDist, d * 0.75) / 300.0;

        CGAffineTransform t = CGAffineTransformMakeTranslation(-500, -580);
        t = CGAffineTransformConcat(t, CGAffineTransformMakeScale(scaleX, scaleY));
        t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(face.angle));
        t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(face.eyes.x, face.eyes.y));

        CIImage *warpedCustom = [[custom imageByApplyingTransform:t] imageByCroppingToRect:img.extent];
        CIImage *faceMask = [self customFaceMaskForSize:img.extent.size face:&face];

        if (faceMask) {
            CIImage *maskedCustom = [warpedCustom imageByApplyingFilter:@"CIBlendWithMask"
                withInputParameters:@{
                    kCIInputBackgroundImageKey: [CIImage imageWithColor:[CIColor clearColor]],
                    kCIInputMaskImageKey: faceMask
                }];
            return [[maskedCustom imageByCompositingOverImage:img] imageByCroppingToRect:img.extent];
        }

        return [[warpedCustom imageByCompositingOverImage:img] imageByCroppingToRect:img.extent];
    }

    if (!_fxArt[fx]) {
        UIImage *art = fx_render(^{ fx_draw(fx); });
        if (art.CGImage) _fxArt[fx] = [CIImage imageWithCGImage:art.CGImage];
    }
    CIImage *art = _fxArt[fx];
    if (!art) return img;
    CGAffineTransform t = CGAffineTransformMakeTranslation(-500, -580);
    t = CGAffineTransformConcat(t, CGAffineTransformMakeScale(d / 300.0, MAX(face.mouthDist, d * 0.7) / 300.0));
    t = CGAffineTransformConcat(t, CGAffineTransformMakeRotation(face.angle));
    t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(face.eyes.x, face.eyes.y));
    return [[[art imageByApplyingTransform:t] imageByCompositingOverImage:img] imageByCroppingToRect:img.extent];
}

+ (instancetype)shared {
    static EchoCam *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [EchoCam new]; });
    return s;
}

- (void)closeVideo {
    [_reader cancelReading];
    _reader = nil;
    _track = nil;
    _videoFrame = nil;
    if (_next) { CFRelease(_next); _next = NULL; }
}

- (void)useImage:(CIImage *)image {
    @synchronized (self) {
        [self closeVideo];
        _asset = nil;
        _still = image;
        self.mode = CAM_IMAGE;
    }
}

- (void)useLive {
    @synchronized (self) {
        [self closeVideo];
        _asset = nil;
        _still = nil;
        self.mode = CAM_LIVE;
    }
}

- (BOOL)startReader {
    [self closeVideo];
    AVAssetTrack *t = [_asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!t) return NO;
    NSError *e = nil;
    AVAssetReader *r = [[AVAssetReader alloc] initWithAsset:_asset error:&e];
    if (!r) return NO;
    NSDictionary *settings = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
    AVAssetReaderTrackOutput *o = [[AVAssetReaderTrackOutput alloc] initWithTrack:t outputSettings:settings];
    if (![r canAddOutput:o]) return NO;
    [r addOutput:o];
    if (![r startReading]) return NO;
    _reader = r;
    _track = o;
    _videoTransform = t.preferredTransform;
    _videoStart = CACurrentMediaTime();
    return YES;
}

- (BOOL)useVideo:(NSURL *)url {
    @synchronized (self) {
        _asset = [AVURLAsset URLAssetWithURL:url options:nil];
        _still = nil;
        BOOL ok = [self startReader];
        self.mode = CAM_VIDEO;
        return ok;
    }
}

- (CIImage *)upright:(CIImage *)img transform:(CGAffineTransform)t {
    int o = 1;
    if (t.a == 0 && t.b == 1 && t.c == -1) o = 6;
    else if (t.a == 0 && t.b == -1 && t.c == 1) o = 8;
    else if (t.a == -1 && t.d == -1) o = 3;
    return o == 1 ? img : [img imageByApplyingOrientation:o];
}

- (CIImage *)currentVideoFrame {
    if (!_reader) return _videoFrame;
    double elapsed = CACurrentMediaTime() - _videoStart;
    for (int i = 0; i < 8; i++) {
        if (!_next) _next = [_track copyNextSampleBuffer];
        if (!_next) {
            CIImage *last = _videoFrame;
            if (![self startReader]) return last;
            _videoFrame = last;
            _next = [_track copyNextSampleBuffer];
            elapsed = 0;
            if (!_next) return last;
        }
        double pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(_next));
        if (_videoFrame && pts > elapsed) break;
        CVImageBufferRef px = CMSampleBufferGetImageBuffer(_next);
        if (px) _videoFrame = [self upright:[CIImage imageWithCVPixelBuffer:px] transform:_videoTransform];
        CFRelease(_next);
        _next = NULL;
    }
    return _videoFrame;
}

- (CIImage *)fit:(CIImage *)img into:(CGSize)size {
    CGRect black = CGRectMake(0, 0, size.width, size.height);
    CIImage *bg = [[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0]] imageByCroppingToRect:black];
    if (!img) return bg;
    static const int kTurn[4] = { 1, 6, 3, 8 };
    img = [img imageByApplyingOrientation:kTurn[self.turns & 3]];
    if (self.mirror) img = [img imageByApplyingOrientation:2];
    CGRect e = img.extent;
    if (e.size.width < 1 || e.size.height < 1) return bg;
    CGFloat k = MIN(size.width / e.size.width, size.height / e.size.height);
    img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(-e.origin.x, -e.origin.y)];
    img = [img imageByApplyingTransform:CGAffineTransformMakeScale(k, k)];
    img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation((size.width - e.size.width * k) / 2,
                                                                        (size.height - e.size.height * k) / 2)];
    return [img imageByCompositingOverImage:bg];
}

- (CIImage *)applyFilter:(CIImage *)img {
    int f = self.filter;
    if (f <= 0 || f >= 8) return img;
    CIFilter *flt = [CIFilter filterWithName:kCamFilters[f]];
    if (!flt) return nil;
    CGRect e = img.extent;
    CIImage *src = (f == 5) ? [img imageByClampingToExtent] : img;
    [flt setValue:src forKey:kCIInputImageKey];
    if (f == 4) [flt setValue:@(MAX(8.0, e.size.width / 60.0)) forKey:kCIInputScaleKey];
    if (f == 5) [flt setValue:@(MAX(8.0, e.size.width / 50.0)) forKey:kCIInputRadiusKey];
    return [flt.outputImage imageByCroppingToRect:e];
}

- (CMSampleBufferRef)copyProcessed:(CMSampleBufferRef)input {
    @synchronized (self) {
        CVImageBufferRef src = CMSampleBufferGetImageBuffer(input);
        if (!src) return NULL;
        size_t w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src);
        OSType type = CVPixelBufferGetPixelFormatType(src);

        if (!_pool || w != _poolW || h != _poolH || type != _poolType) {
            if (_pool) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
            NSDictionary *attrs = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(type),
                                     (id)kCVPixelBufferWidthKey: @(w),
                                     (id)kCVPixelBufferHeightKey: @(h),
                                     (id)kCVPixelBufferIOSurfacePropertiesKey: @{} };
            if (CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)attrs, &_pool) != kCVReturnSuccess) return NULL;
            _poolW = w; _poolH = h; _poolType = type;
        }

        CIImage *img;
        if (self.mode == CAM_LIVE) {
            img = [CIImage imageWithCVPixelBuffer:src];
            int flip = self.liveFlip;
            if (flip) {
                img = [img imageByApplyingOrientation:(flip == 1 ? 2 : 4)];
                img = [img imageByApplyingTransform:CGAffineTransformMakeTranslation(-img.extent.origin.x, -img.extent.origin.y)];
            }
            img = [self applyEffect:img];
        } else img = [self fit:(self.mode == CAM_IMAGE ? _still : [self currentVideoFrame]) into:CGSizeMake(w, h)];
        img = [self applyFilter:img];
        if (!img) return NULL;

        CVPixelBufferRef dst = NULL;
        if (CVPixelBufferPoolCreatePixelBuffer(NULL, _pool, &dst) != kCVReturnSuccess) return NULL;
        CVBufferPropagateAttachments(src, dst);
        if (!_ci) _ci = [CIContext contextWithOptions:nil];
        [_ci render:img toCVPixelBuffer:dst];

        CMSampleTimingInfo timing;
        CMVideoFormatDescriptionRef desc = NULL;
        CMSampleBufferRef out = NULL;
        if (CMSampleBufferGetSampleTimingInfo(input, 0, &timing) == noErr &&
            CMVideoFormatDescriptionCreateForImageBuffer(NULL, dst, &desc) == noErr) {
            CMSampleBufferCreateReadyWithImageBuffer(NULL, dst, desc, &timing, &out);
        }
        if (desc) CFRelease(desc);
        CVPixelBufferRelease(dst);
        return out;
    }
}
@end

typedef void (*EchoFrameIMP)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *);

static void echo_cam_hook_class(Class cls) {
    static NSMutableSet *done;
    static NSMutableSet *ours;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ done = [NSMutableSet set]; ours = [NSMutableSet set]; });
    SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
    @synchronized (done) {
        NSString *name = NSStringFromClass(cls);
        if ([done containsObject:name]) return;
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return;
        IMP current = method_getImplementation(m);
        if ([ours containsObject:[NSValue valueWithPointer:(const void *)current]]) return;
        EchoFrameIMP orig = (EchoFrameIMP)current;
        IMP mine = imp_implementationWithBlock(^(id me, AVCaptureOutput *output, CMSampleBufferRef sb, AVCaptureConnection *conn) {
            if (![output isKindOfClass:AVCaptureVideoDataOutput.class]) { orig(me, sel, output, sb, conn); return; }
            EchoCam *cam = [EchoCam shared];
            cam.frames = cam.frames + 1;
            if (cam.mode == CAM_LIVE && cam.filter == 0 && cam.effect == 0 && cam.liveFlip == 0 && ![cam hasShape]) { orig(me, sel, output, sb, conn); return; }
            @autoreleasepool {
                CMSampleBufferRef out = [cam copyProcessed:sb];
                if (out) {
                    orig(me, sel, output, out, conn);
                    CFRelease(out);
                }
            }
        });
        class_replaceMethod(cls, sel, mine, method_getTypeEncoding(m));
        [ours addObject:[NSValue valueWithPointer:(const void *)mine]];
        [done addObject:name];
    }
}

static void (*orig_setSampleDelegate)(id, SEL, id, dispatch_queue_t);

static void my_setSampleDelegate(id me, SEL sel, id delegate, dispatch_queue_t queue) {
    if (delegate) echo_cam_hook_class(object_getClass(delegate));
    orig_setSampleDelegate(me, sel, delegate, queue);
}

static void echo_cam_install(void) {
    Method m = class_getInstanceMethod(AVCaptureVideoDataOutput.class, @selector(setSampleBufferDelegate:queue:));
    if (!m) return;
    orig_setSampleDelegate = (void (*)(id, SEL, id, dispatch_queue_t))method_getImplementation(m);
    method_setImplementation(m, (IMP)my_setSampleDelegate);
}

#pragma mark - الواجهة الرئيسية

@interface EchoController : UIViewController <UIDocumentPickerDelegate, PHPickerViewControllerDelegate> {
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
@property (nonatomic, strong) EchoBrowserController *browser;
@property (nonatomic) BOOL pickingCam;
@property (nonatomic, strong) UILabel *camStatus;
@property (nonatomic, strong) UILabel *camSource;
@property (nonatomic, strong) NSArray<UIButton *> *camFilterBtns;
@property (nonatomic, strong) NSArray<UIButton *> *camFxBtns;
@property (nonatomic, strong) NSArray<UISlider *> *shapeSliders;
@property (nonatomic, strong) NSArray<UILabel *> *shapeLabels;
@property (nonatomic) BOOL pickingMask;
@property (nonatomic, strong) NSURL *camFile;
@property (nonatomic) unsigned lastCamFrames;
@property (nonatomic) CFTimeInterval lastCamTime;
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

    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:@[@"الصدى", @"الموازن", @"النبرة", @"المايك", @"🎵", @"📷"]];
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
    UIScrollView *tabCam   = [self makeTab];
    self.tabViews = @[tabEcho, tabEq, tabPitch, tabAmp, tabMusic, tabCam];
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

    [self addToggle:T_MICMUTE to:tabAmp x:16 y:y width:w];
    y += 42;

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
    [self addToggle:T_PRIVATE  to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_MONITOR  to:tabMusic x:16 y:y width:w]; y += 40;
    y = [self addSlider:S_MONVOL to:tabMusic y:y];
    [self addToggle:T_LOOP     to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_MUTE     to:tabMusic x:16 y:y width:w]; y += 36;
    [self addToggle:T_SONGECHO to:tabMusic x:16 y:y width:w]; y += 40;
    y = [self addHint:@"🌐 المتصفح: ابحث، تصفح مواقع MP3، وحمّل المقاطع مباشرة."
                   to:tabMusic y:y height:60];
    tabMusic.contentSize = CGSizeMake(kPanelW, y + 10);

    [self buildCamTab:tabCam];

    [self refreshModeButtons];
    [self updatePitchLabel];
}

#pragma mark - تبويب الكاميرا

- (void)buildCamTab:(UIScrollView *)tab {
    CGFloat w = kPanelW - 32, y = 4;
    self.camStatus = [self makeLabelAt:CGRectMake(16, y, w, 20) size:13 bold:YES alpha:1];
    [tab addSubview:self.camStatus];
    y += 28;

    CGFloat bw = (w - 16) / 3.0;
    [tab addSubview:[self makeButton:@"⇋ عكس الكاميرا: طافي" frame:CGRectMake(16, y, w, 36) tag:0 action:@selector(camLiveFlip:)]];
    y += 44;

    y = [self addHeader:@"🧬 غيّر ملامحك" to:tab y:y];
    NSMutableArray *sliders = [NSMutableArray array];
    NSMutableArray *labels = [NSMutableArray array];
    for (NSInteger i = 0; i < SHAPE_COUNT; i++) {
        UILabel *l = [self makeLabelAt:CGRectMake(16, y, w, 20) size:13 bold:YES alpha:1];
        l.text = [NSString stringWithFormat:@"%@: 0", kShapeNames[i]];
        UISlider *sl = [self makeSliderAt:CGRectMake(16, y + 20, w, 28) min:-100 max:100 value:0 action:@selector(shapeChanged:)];
        sl.tag = i;
        [tab addSubview:l];
        [tab addSubview:sl];
        [labels addObject:l];
        [sliders addObject:sl];
        y += 52;
    }
    self.shapeSliders = sliders;
    self.shapeLabels = labels;
    [tab addSubview:[self makeButton:@"↺ رجّع ملامحي" frame:CGRectMake(16, y, w, 34) tag:0 action:@selector(shapeReset)]];
    y += 44;

    y = [self addHeader:@"🎭 مؤثرات الوجه" to:tab y:y];
    NSMutableArray *fxb = [NSMutableArray array];
    for (NSInteger i = 0; i < FX_COUNT; i++) {
        UIButton *b = [self makeButton:kFxNames[i]
                                 frame:CGRectMake(16 + (i % 3) * (bw + 8), y + (i / 3) * 40, bw, 32)
                                   tag:i action:@selector(camFxTapped:)];
        [tab addSubview:b];
        [fxb addObject:b];
    }
    self.camFxBtns = fxb;
    y += ((FX_COUNT + 2) / 3) * 40 + 2;
    [tab addSubview:[self makeButton:@"➕ حط قناعك (صورة PNG شفافة)" frame:CGRectMake(16, y, w, 34) tag:0 action:@selector(camPickMask)]];
    y += 44;

    y = [self addHeader:@"🎨 فلاتر الألوان" to:tab y:y];
    NSMutableArray *btns = [NSMutableArray array];
    for (NSInteger i = 0; i < 8; i++) {
        UIButton *b = [self makeButton:kCamFilterNames[i]
                                 frame:CGRectMake(16 + (i % 3) * (bw + 8), y + (i / 3) * 40, bw, 32)
                                   tag:i action:@selector(camFilterTapped:)];
        [tab addSubview:b];
        [btns addObject:b];
    }
    self.camFilterBtns = btns;
    y += 3 * 40 + 6;

    y = [self addHeader:@"🖼️ صورة أو فيديو بدل الكام" to:tab y:y];
    CGFloat hw = (w - 8) / 2.0;
    [tab addSubview:[self makeButton:@"🖼️ من الصور" frame:CGRectMake(16, y, hw, 36) tag:0 action:@selector(camFromPhotos)]];
    [tab addSubview:[self makeButton:@"📂 من الملفات" frame:CGRectMake(16 + hw + 8, y, hw, 36) tag:0 action:@selector(camFromFiles)]];
    y += 44;
    [tab addSubview:[self makeButton:@"↻ تدوير" frame:CGRectMake(16, y, hw, 34) tag:0 action:@selector(camRotate)]];
    [tab addSubview:[self makeButton:@"⇋ قلب" frame:CGRectMake(16 + hw + 8, y, hw, 34) tag:0 action:@selector(camMirror)]];
    y += 42;
    [tab addSubview:[self makeButton:@"📷 رجّع الكاميرا الحقيقية" frame:CGRectMake(16, y, w, 36) tag:0 action:@selector(camLive)]];
    y += 44;
    self.camSource = [self makeLabelAt:CGRectMake(16, y, w, 36) size:12 bold:YES alpha:0.8];
    self.camSource.text = @"المصدر: الكاميرا الحقيقية";
    [tab addSubview:self.camSource];
    y += 42;
    y = [self addHint:@"اختر الفلتر أو الصورة قبل ما تفتح الكام. وإذا قفلت التطبيق ترجع الكاميرا العادية." to:tab y:y height:44];
    tab.contentSize = CGSizeMake(kPanelW, y + 10);
    [self refreshCamButtons];
    [self refreshCamStatus];
}

- (void)shapeChanged:(UISlider *)sl {
    int v = (int)lroundf(sl.value);
    if (abs(v) < 6) v = 0;
    [[EchoCam shared] setShape:(int)sl.tag value:v];
    self.shapeLabels[sl.tag].text = [NSString stringWithFormat:@"%@: %d", kShapeNames[sl.tag], v];
}

- (void)shapeReset {
    for (UISlider *sl in self.shapeSliders) {
        sl.value = 0;
        [self shapeChanged:sl];
    }
}

- (void)camLiveFlip:(UIButton *)b {
    int v = ([EchoCam shared].liveFlip + 1) % 3;
    [EchoCam shared].liveFlip = v;
    NSArray *titles = @[@"⇋ عكس الكاميرا: طافي", @"⇋ عكس الكاميرا: وضع 1", @"⇋ عكس الكاميرا: وضع 2"];
    [b setTitle:titles[v] forState:UIControlStateNormal];
}

- (void)camFxTapped:(UIButton *)b {
    if (b.tag == FX_CUSTOM && ![[EchoCam shared] hasCustomMask]) { [self camPickMask]; return; }
    [EchoCam shared].effect = (int)b.tag;
    [self refreshCamButtons];
}

- (void)camPickMask {
    self.pickingMask = YES;
    [self openCamFiles];
}

- (void)refreshCamButtons {
    int fx = [EchoCam shared].effect;
    for (UIButton *b in self.camFxBtns) {
        b.backgroundColor = (b.tag == fx) ? [UIColor colorWithRed:0.33 green:0.42 blue:1 alpha:0.95]
                                          : [UIColor colorWithWhite:1 alpha:0.14];
    }
    int f = [EchoCam shared].filter;
    for (UIButton *b in self.camFilterBtns) {
        b.backgroundColor = (b.tag == f) ? [UIColor colorWithRed:0.33 green:0.42 blue:1 alpha:0.95]
                                         : [UIColor colorWithWhite:1 alpha:0.14];
    }
}

- (void)refreshCamStatus {
    unsigned c = [EchoCam shared].frames;
    CFTimeInterval now = CACurrentMediaTime();
    if (c != self.lastCamFrames) { self.lastCamFrames = c; self.lastCamTime = now; }
    BOOL live = c != 0 && (now - self.lastCamTime) < 0.8;
    self.camStatus.text = live ? @"🟢 ملتقط الكاميرا" : @"🔴 ما وصلني شي من الكاميرا";
    EchoCam *cam = [EchoCam shared];
    if (live && (cam.effect != FX_NONE || [cam hasShape]) && cam.mode == CAM_LIVE)
        self.camStatus.text = cam.faceSeen ? @"🟢 ملتقط الكاميرا · 🙂 لقيت وجهك" : @"🟢 ملتقط الكاميرا · 🔍 أدور على وجهك";
    self.camStatus.textColor = live ? [UIColor systemGreenColor] : [UIColor systemOrangeColor];
}

- (void)camFilterTapped:(UIButton *)b {
    [EchoCam shared].filter = (int)b.tag;
    [self refreshCamButtons];
}
- (void)camRotate { [EchoCam shared].turns = ([EchoCam shared].turns + 1) % 4; }
- (void)camMirror { [EchoCam shared].mirror = ![EchoCam shared].mirror; }

- (void)camLive {
    [[EchoCam shared] useLive];
    if (self.camFile) [[NSFileManager defaultManager] removeItemAtURL:self.camFile error:nil];
    self.camFile = nil;
    self.camSource.text = @"المصدر: الكاميرا الحقيقية";
}

- (void)camFromPhotos {
    self.pickingMask = NO;
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        cfg.selectionLimit = 1;
        cfg.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
        PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        p.delegate = self;
        [self presentViewController:p animated:YES completion:nil];
    } else {
        [self camFromFiles];
    }
}

- (void)camFromFiles {
    self.pickingMask = NO;
    [self openCamFiles];
}

- (void)openCamFiles {
    self.pickingCam = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *p =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.image", @"public.movie"]
                                                               inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { self.pickingCam = NO; self.pickingMask = NO; }

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *item = results.firstObject.itemProvider;
    if (!item) return;
    BOOL video = [item hasItemConformingToTypeIdentifier:@"public.movie"];
    self.camSource.text = @"⏳ جاري التحميل…";
    __weak EchoController *ws = self;
    [item loadFileRepresentationForTypeIdentifier:(video ? @"public.movie" : @"public.image")
                                completionHandler:^(NSURL *url, NSError *error) {
        NSURL *copy = nil;
        if (url) {
            NSString *name = [NSString stringWithFormat:@"echo_cam_%u.%@", arc4random(), url.pathExtension];
            copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
            if (![[NSFileManager defaultManager] copyItemAtURL:url toURL:copy error:nil]) copy = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ [ws loadCamFile:copy video:video]; });
    }];
}

- (void)loadCamFile:(NSURL *)url video:(BOOL)video {
    if (!url) { self.camSource.text = @"❌ ما قدرت أقرأ الملف"; return; }
    if (self.pickingMask) {
        self.pickingMask = NO;
        UIImage *img = video ? nil : [UIImage imageWithContentsOfFile:url.path];
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        if (!img || img.size.width < 1 || img.size.height < 1) { self.camSource.text = @"❌ اختر صورة PNG"; return; }
        UIImage *canvas = fx_render(^{
            CGFloat k = MIN(1000.0 / img.size.width, 1000.0 / img.size.height);
            CGSize z = CGSizeMake(img.size.width * k, img.size.height * k);
            [img drawInRect:CGRectMake((1000 - z.width) / 2, (1000 - z.height) / 2, z.width, z.height)];
        });
        if (!canvas.CGImage) return;
        [[EchoCam shared] useCustomMask:[CIImage imageWithCGImage:canvas.CGImage]];
        [EchoCam shared].effect = FX_CUSTOM;
        [self refreshCamButtons];
        return;
    }
    if (video) {
        BOOL ok = [[EchoCam shared] useVideo:url];
        self.camSource.text = ok ? @"المصدر: 🎬 فيديو" : @"❌ ما قدرت أشغل الفيديو (الكام بتطلع سوداء)";
    } else {
        UIImage *img = [UIImage imageWithContentsOfFile:url.path];
        if (!img || img.size.width < 1 || img.size.height < 1) { self.camSource.text = @"❌ ما قدرت أقرأ الصورة"; return; }
        CGFloat k = MIN(1.0, 1920.0 / MAX(img.size.width, img.size.height));
        CGSize size = CGSizeMake(floor(img.size.width * k), floor(img.size.height * k));
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.scale = 1;
        UIImage *flat = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt]
            imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [img drawInRect:CGRectMake(0, 0, size.width, size.height)];
            }];
        if (!flat.CGImage) { self.camSource.text = @"❌ ما قدرت أقرأ الصورة"; return; }
        [[EchoCam shared] useImage:[CIImage imageWithCGImage:flat.CGImage]];
        self.camSource.text = @"المصدر: 🖼️ صورة";
    }
    if (self.camFile && ![self.camFile isEqual:url]) [[NSFileManager defaultManager] removeItemAtURL:self.camFile error:nil];
    self.camFile = url;
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
    if (s.tag == T_PRIVATE && s.on && !_sw[T_MONITOR].on) {
        [self setToggle:T_MONITOR on:YES];
    }
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
    self.pickingCam = NO;
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
    if (self.pickingCam) {
        self.pickingCam = NO;
        NSString *ext = url.pathExtension.lowercaseString;
        BOOL video = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
        if (url) [self loadCamFile:url video:video];
        return;
    }
    if (url) [self loadSongAtURL:url name:url.lastPathComponent cleanup:NO];
}

- (void)browseSong {
    if (!self.browser) self.browser = [EchoBrowserController new];
    EchoBrowserController *vc = self.browser;
    if (vc.presentingViewController || self.presentedViewController) return;
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
            int loaded = DiscordEcho_MusicLoad(buf, count);
            if (loaded && cleanup) DiscordEcho_MusicPlay(1);
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
        } else if (tab == TAB_CAM) {
            [s refreshCamStatus];
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
    echo_cam_install();
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
    
    [nc addObserverForName:AVAudioSessionRouteChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        NSUInteger reason = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
        if (reason == AVAudioSessionRouteChangeReasonRouteConfigurationChange) return;
        DiscordEcho_ResetAll();
        if (echo_mon_wanted()) echo_monitor_restart_later();
    }];

    [nc addObserverForName:AVAudioEngineConfigurationChangeNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        if (echo_mon_wanted() && gMonEngine && n.object == gMonEngine) {
            echo_monitor_restart_later();
        }
    }];
}
